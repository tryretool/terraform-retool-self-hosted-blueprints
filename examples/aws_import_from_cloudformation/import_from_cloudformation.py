#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "boto3>=1.34",
#     "click>=8.1",
#     "questionary>=2.0",
#     "rich>=13.7",
#     "pyyaml>=6.0",
# ]
# ///
"""Adopt a Retool CloudFormation deployment's databases into this Terraform stack.

Reads an existing `retool-onpremise` CloudFormation stack, traverses to the
resources it references, and produces the two things needed to bring its
databases under Terraform's control without interrupting the running deployment:

  describe-cf-stack   what's there, and whether it can be imported cleanly
  import-tfvars       imported.tfvars — every value derivable from the stack
  import-state        terraform import for each resource, dry-run by default

The Terraform addresses written here are specific to the
aws_import_from_cloudformation example; run it from that directory.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import boto3
import click
import questionary
import yaml
from botocore.exceptions import ClientError
from rich.console import Console
from rich.table import Table

console = Console()
err_console = Console(stderr=True)

TFVARS_FILENAME = "imported.tfvars"

# CloudFormation logical IDs used by the Retool templates. The stacks are
# routinely forked, so every lookup falls back to discovery by resource type.
LOGICAL_RETOOL_DB = "RetoolRDSInstance"
LOGICAL_RETOOL_DB_SECRET = "RetoolRDSSecret"
LOGICAL_TEMPORAL_DB = "RetoolTemporalRDSInstance"
LOGICAL_TEMPORAL_CLUSTER = "RetoolTemporalRDSCluster"
LOGICAL_TEMPORAL_DB_SECRET = "RetoolTemporalRDSSecret"
LOGICAL_ENCRYPTION_KEY_SECRET = "RetoolEncryptionKeySecret"
LOGICAL_JWT_SECRET = "RetoolJWTSecret"

# CloudFormation's GenerateSecretString nests the generated value under a key
# rather than storing a bare string; these are the templates' choices.
CF_GENERATED_SECRET_PROPERTY = "password"
CF_LICENSE_KEY_PROPERTY = "licenseKey"


# ---------------------------------------------------------------------------
# CloudFormation template parsing
# ---------------------------------------------------------------------------


class _CfnLoader(yaml.SafeLoader):
    """YAML loader that tolerates CloudFormation's short-form tags.

    Templates are full of `!Ref`, `!GetAtt`, `!Sub` and friends, which SafeLoader
    rejects outright. Nothing here needs to resolve them — only the Mappings
    block is read — so they collapse to a placeholder.
    """


def _ignore_unknown_tag(loader: yaml.Loader, tag_suffix: str, node: yaml.Node) -> Any:
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    return loader.construct_mapping(node)


_CfnLoader.add_multi_constructor("!", _ignore_unknown_tag)


def parse_template(body: str) -> dict[str, Any]:
    """Parse a CloudFormation template body, JSON or YAML."""
    try:
        return json.loads(body)
    except (json.JSONDecodeError, TypeError):
        pass
    try:
        parsed = yaml.load(body, Loader=_CfnLoader)
        return parsed if isinstance(parsed, dict) else {}
    except yaml.YAMLError:
        return {}


# ---------------------------------------------------------------------------
# Discovered facts
# ---------------------------------------------------------------------------


@dataclass
class SecurityGroupRule:
    """One rule on a security group, as AWS reports it.

    Keyed by its own `sgr-` ID, which is also its Terraform import ID — the
    reason these are modelled as `aws_vpc_security_group_{ingress,egress}_rule`
    rather than the older composite-ID resource.
    """

    rule_id: str
    is_egress: bool
    ip_protocol: str
    from_port: int | None
    to_port: int | None
    cidr_ipv4: str | None
    cidr_ipv6: str | None
    referenced_security_group_id: str | None
    prefix_list_id: str | None
    description: str | None

    @classmethod
    def from_api(cls, raw: dict[str, Any]) -> "SecurityGroupRule":
        referenced = (raw.get("ReferencedGroupInfo") or {}).get("GroupId")
        # AWS reports -1/-1 for all-traffic rules; Terraform wants them unset.
        from_port = raw.get("FromPort")
        to_port = raw.get("ToPort")
        if raw.get("IpProtocol") == "-1":
            from_port = to_port = None
        return cls(
            rule_id=raw["SecurityGroupRuleId"],
            is_egress=raw.get("IsEgress", False),
            ip_protocol=raw.get("IpProtocol", "-1"),
            from_port=from_port,
            to_port=to_port,
            cidr_ipv4=raw.get("CidrIpv4"),
            cidr_ipv6=raw.get("CidrIpv6"),
            referenced_security_group_id=referenced,
            prefix_list_id=raw.get("PrefixListId"),
            description=raw.get("Description") or None,
        )

    def target(self) -> str:
        """Human-readable source/destination, for the summary tables."""
        for value in (
            self.cidr_ipv4,
            self.cidr_ipv6,
            self.referenced_security_group_id,
            self.prefix_list_id,
        ):
            if value:
                return value
        return "?"

    def ports(self) -> str:
        if self.ip_protocol == "-1":
            return "all"
        if self.from_port == self.to_port:
            return str(self.from_port)
        return f"{self.from_port}-{self.to_port}"

    def to_tfvars(self) -> dict[str, Any]:
        out: dict[str, Any] = {"ip_protocol": self.ip_protocol}
        if self.from_port is not None:
            out["from_port"] = self.from_port
        if self.to_port is not None:
            out["to_port"] = self.to_port
        for key, value in (
            ("cidr_ipv4", self.cidr_ipv4),
            ("cidr_ipv6", self.cidr_ipv6),
            ("referenced_security_group_id", self.referenced_security_group_id),
            ("prefix_list_id", self.prefix_list_id),
            ("description", self.description),
        ):
            if value:
                out[key] = value
        return out


@dataclass
class Database:
    """An RDS database referenced by the stack, with everything import needs."""

    identifier: str
    kind: str  # "instance" or "aurora"
    address: str | None
    port: int
    engine: str
    engine_version: str
    instance_class: str
    allocated_storage: int
    max_allocated_storage: int
    storage_type: str
    iops: int | None
    storage_encrypted: bool
    multi_az: bool
    database_name: str | None
    master_username: str | None
    manages_master_password: bool
    rds_managed_secret_arn: str | None
    deletion_protection: bool
    parameter_group_name: str | None
    db_subnet_group_name: str | None
    subnet_ids: list[str]
    security_group_ids: list[str]
    rules: list[SecurityGroupRule] = field(default_factory=list)
    credentials_secret_arn: str | None = None
    cluster_identifier: str | None = None

    @property
    def importable(self) -> bool:
        """Aurora members are aws_rds_cluster_instance, which aws-database is not."""
        return self.kind == "instance"

    @property
    def family(self) -> str:
        major = self.engine_version.split(".")[0]
        return f"{self.engine}{major}"

    @property
    def major_engine_version(self) -> str:
        return self.engine_version.split(".")[0]

    @property
    def security_group_id(self) -> str | None:
        return self.security_group_ids[0] if self.security_group_ids else None


@dataclass
class Secret:
    """A Secrets Manager secret, and the shape of what's inside it."""

    arn: str
    name: str
    json_keys: list[str] | None  # None when the value is a bare string
    readable: bool

    def property_for(self, preferred: str) -> str | None:
        """Which JSON key holds the value, or None if it's a bare string."""
        if self.json_keys is None:
            return None
        if preferred in self.json_keys:
            return preferred
        # A single-key object is unambiguous whatever the key is called.
        if len(self.json_keys) == 1:
            return self.json_keys[0]
        return preferred


@dataclass
class StackFacts:
    """Everything discovered about the CloudFormation deployment."""

    stack_name: str
    region: str
    parameters: dict[str, str]
    resources: dict[str, str]  # logical ID -> physical ID
    resource_types: dict[str, str]  # logical ID -> AWS type
    mappings: dict[str, Any]
    retool_db: Database | None = None
    temporal_db: Database | None = None
    secrets: dict[str, Secret] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)

    def param(self, name: str) -> str | None:
        value = self.parameters.get(name)
        return value or None


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------


class Discoverer:
    def __init__(self, session: boto3.Session, stack_name: str, region: str):
        self.session = session
        self.stack_name = stack_name
        self.region = region
        self.cfn = session.client("cloudformation", region_name=region)
        self.rds = session.client("rds", region_name=region)
        self.ec2 = session.client("ec2", region_name=region)
        self.sm = session.client("secretsmanager", region_name=region)

    def run(self) -> StackFacts:
        facts = self._read_stack()
        self._discover_databases(facts)
        self._discover_secrets(facts)
        return facts

    def _read_stack(self) -> StackFacts:
        try:
            stacks = self.cfn.describe_stacks(StackName=self.stack_name)["Stacks"]
        except ClientError as exc:
            raise click.ClickException(
                f"Could not read CloudFormation stack {self.stack_name!r} in {self.region}: {exc}"
            ) from exc

        stack = stacks[0]
        parameters = {
            p["ParameterKey"]: p.get("ParameterValue", "")
            for p in stack.get("Parameters", [])
        }

        resources: dict[str, str] = {}
        resource_types: dict[str, str] = {}
        paginator = self.cfn.get_paginator("list_stack_resources")
        for page in paginator.paginate(StackName=self.stack_name):
            for res in page["StackResourceSummaries"]:
                logical = res["LogicalResourceId"]
                resources[logical] = res.get("PhysicalResourceId", "")
                resource_types[logical] = res["ResourceType"]

        mappings: dict[str, Any] = {}
        try:
            body = self.cfn.get_template(StackName=self.stack_name)["TemplateBody"]
            if not isinstance(body, str):
                body = json.dumps(body)
            mappings = parse_template(body).get("Mappings") or {}
        except ClientError:
            pass  # Mappings are a bonus; CloudAuth config can be supplied by hand.

        return StackFacts(
            stack_name=self.stack_name,
            region=self.region,
            parameters=parameters,
            resources=resources,
            resource_types=resource_types,
            mappings=mappings,
        )

    # -- databases ----------------------------------------------------------

    def _logical_ids_of_type(self, facts: StackFacts, aws_type: str) -> list[str]:
        return [lid for lid, t in facts.resource_types.items() if t == aws_type]

    def _discover_databases(self, facts: StackFacts) -> None:
        instance_ids = self._logical_ids_of_type(facts, "AWS::RDS::DBInstance")

        retool_logical = (
            LOGICAL_RETOOL_DB
            if LOGICAL_RETOOL_DB in facts.resources
            else next((i for i in instance_ids if "temporal" not in i.lower()), None)
        )
        if retool_logical:
            facts.retool_db = self._load_instance(facts.resources[retool_logical])
        else:
            facts.warnings.append(
                "No Retool RDS instance found in the stack. Nothing to import for the main database."
            )

        temporal_logical = (
            LOGICAL_TEMPORAL_DB
            if LOGICAL_TEMPORAL_DB in facts.resources
            else next((i for i in instance_ids if "temporal" in i.lower()), None)
        )
        if temporal_logical:
            facts.temporal_db = self._load_instance(facts.resources[temporal_logical])
        elif LOGICAL_TEMPORAL_CLUSTER in facts.resources or self._logical_ids_of_type(
            facts, "AWS::RDS::DBCluster"
        ):
            facts.temporal_db = self._load_cluster_for(facts)

        # The Temporal database is sometimes created outside the stack. If the
        # stack didn't name one, look for it in the same VPC.
        if facts.temporal_db is None and facts.retool_db is not None:
            facts.temporal_db = self._search_temporal_instance(facts)

        # Credentials secrets, by logical ID where the templates provide one.
        if facts.retool_db is not None:
            facts.retool_db.credentials_secret_arn = facts.resources.get(
                LOGICAL_RETOOL_DB_SECRET
            )
        if facts.temporal_db is not None:
            facts.temporal_db.credentials_secret_arn = facts.resources.get(
                LOGICAL_TEMPORAL_DB_SECRET
            ) or (
                facts.temporal_db.rds_managed_secret_arn
                if facts.temporal_db.manages_master_password
                else None
            )

        for db in (facts.retool_db, facts.temporal_db):
            if db is not None:
                db.rules = self._load_rules(db.security_group_ids)

    def _load_instance(self, identifier: str) -> Database | None:
        try:
            raw = self.rds.describe_db_instances(DBInstanceIdentifier=identifier)[
                "DBInstances"
            ][0]
        except ClientError:
            return None
        return self._instance_from_api(raw)

    def _instance_from_api(self, raw: dict[str, Any]) -> Database:
        subnet_group = raw.get("DBSubnetGroup") or {}
        param_groups = raw.get("DBParameterGroups") or []
        is_cluster_member = bool(raw.get("DBClusterIdentifier"))
        return Database(
            identifier=raw["DBInstanceIdentifier"],
            kind="aurora" if is_cluster_member else "instance",
            address=(raw.get("Endpoint") or {}).get("Address"),
            port=(raw.get("Endpoint") or {}).get("Port") or 5432,
            engine=raw.get("Engine", "postgres"),
            engine_version=raw.get("EngineVersion", ""),
            instance_class=raw.get("DBInstanceClass", ""),
            allocated_storage=raw.get("AllocatedStorage") or 0,
            max_allocated_storage=raw.get("MaxAllocatedStorage") or 0,
            storage_type=raw.get("StorageType") or "gp2",
            iops=raw.get("Iops"),
            storage_encrypted=raw.get("StorageEncrypted", False),
            multi_az=raw.get("MultiAZ", False),
            database_name=raw.get("DBName"),
            master_username=raw.get("MasterUsername"),
            manages_master_password=bool(raw.get("MasterUserSecret")),
            rds_managed_secret_arn=(raw.get("MasterUserSecret") or {}).get("SecretArn"),
            deletion_protection=raw.get("DeletionProtection", False),
            parameter_group_name=(
                param_groups[0].get("DBParameterGroupName") if param_groups else None
            ),
            db_subnet_group_name=subnet_group.get("DBSubnetGroupName"),
            subnet_ids=[
                s["SubnetIdentifier"] for s in subnet_group.get("Subnets", []) or []
            ],
            security_group_ids=[
                sg["VpcSecurityGroupId"]
                for sg in raw.get("VpcSecurityGroups", []) or []
                if sg.get("Status") == "active"
            ],
            cluster_identifier=raw.get("DBClusterIdentifier"),
        )

    def _load_cluster_for(self, facts: StackFacts) -> Database | None:
        cluster_id = facts.resources.get(LOGICAL_TEMPORAL_CLUSTER)
        if not cluster_id:
            clusters = self._logical_ids_of_type(facts, "AWS::RDS::DBCluster")
            cluster_id = facts.resources.get(clusters[0]) if clusters else None
        if not cluster_id:
            return None
        try:
            raw = self.rds.describe_db_clusters(DBClusterIdentifier=cluster_id)[
                "DBClusters"
            ][0]
        except ClientError:
            return None
        return Database(
            identifier=raw["DBClusterIdentifier"],
            kind="aurora",
            address=raw.get("Endpoint"),
            port=raw.get("Port") or 5432,
            engine=raw.get("Engine", "aurora-postgresql"),
            engine_version=raw.get("EngineVersion", ""),
            instance_class="db.serverless",
            allocated_storage=0,
            max_allocated_storage=0,
            storage_type=raw.get("StorageType") or "aurora",
            iops=None,
            storage_encrypted=raw.get("StorageEncrypted", False),
            multi_az=raw.get("MultiAZ", False),
            database_name=raw.get("DatabaseName"),
            master_username=raw.get("MasterUsername"),
            manages_master_password=bool(raw.get("MasterUserSecret")),
            rds_managed_secret_arn=(raw.get("MasterUserSecret") or {}).get("SecretArn"),
            deletion_protection=raw.get("DeletionProtection", False),
            parameter_group_name=raw.get("DBClusterParameterGroup"),
            db_subnet_group_name=raw.get("DBSubnetGroup"),
            subnet_ids=[],
            security_group_ids=[
                sg["VpcSecurityGroupId"]
                for sg in raw.get("VpcSecurityGroups", []) or []
                if sg.get("Status") == "active"
            ],
            cluster_identifier=raw["DBClusterIdentifier"],
        )

    def _search_temporal_instance(self, facts: StackFacts) -> Database | None:
        """Find a Temporal database created outside the stack.

        Matches on identifier, then on the database name Temporal uses, scoped to
        databases sharing the Retool instance's subnet group so unrelated
        databases in the account are never picked up.
        """
        assert facts.retool_db is not None
        subnet_group = facts.retool_db.db_subnet_group_name
        candidates: list[Database] = []
        paginator = self.rds.get_paginator("describe_db_instances")
        for page in paginator.paginate():
            for raw in page["DBInstances"]:
                if raw["DBInstanceIdentifier"] == facts.retool_db.identifier:
                    continue
                db = self._instance_from_api(raw)
                if db.db_subnet_group_name != subnet_group:
                    continue
                if "temporal" in db.identifier.lower() or (
                    db.database_name or ""
                ).lower().startswith("temporal"):
                    candidates.append(db)
        if not candidates:
            return None
        if len(candidates) > 1:
            facts.warnings.append(
                "Found more than one candidate Temporal database "
                f"({', '.join(c.identifier for c in candidates)}); using "
                f"{candidates[0].identifier}. Override temporal_db in terraform.tfvars "
                "if that is the wrong one."
            )
        return candidates[0]

    def _load_rules(self, security_group_ids: list[str]) -> list[SecurityGroupRule]:
        if not security_group_ids:
            return []
        rules: list[SecurityGroupRule] = []
        paginator = self.ec2.get_paginator("describe_security_group_rules")
        for page in paginator.paginate(
            Filters=[{"Name": "group-id", "Values": security_group_ids}]
        ):
            for raw in page["SecurityGroupRules"]:
                rules.append(SecurityGroupRule.from_api(raw))
        return rules

    def security_group_name(self, group_id: str) -> str | None:
        try:
            groups = self.ec2.describe_security_groups(GroupIds=[group_id])[
                "SecurityGroups"
            ]
        except ClientError:
            return None
        return groups[0]["GroupName"] if groups else None

    # -- secrets ------------------------------------------------------------

    def _discover_secrets(self, facts: StackFacts) -> None:
        wanted = {
            "encryption_key": facts.resources.get(LOGICAL_ENCRYPTION_KEY_SECRET),
            "jwt": facts.resources.get(LOGICAL_JWT_SECRET),
            "license_key": facts.param("LicenseKeyARN"),
            "alb_oidc": facts.param("AlbOAuthARN"),
        }
        if facts.retool_db and facts.retool_db.credentials_secret_arn:
            wanted["retool_db"] = facts.retool_db.credentials_secret_arn
        if facts.temporal_db and facts.temporal_db.credentials_secret_arn:
            wanted["temporal_db"] = facts.temporal_db.credentials_secret_arn

        for key, arn in wanted.items():
            if arn:
                facts.secrets[key] = self._load_secret(arn)

    def _load_secret(self, secret_id: str) -> Secret:
        try:
            meta = self.sm.describe_secret(SecretId=secret_id)
            arn, name = meta["ARN"], meta["Name"]
        except ClientError:
            return Secret(arn=secret_id, name=secret_id, json_keys=None, readable=False)

        try:
            value = self.sm.get_secret_value(SecretId=secret_id).get("SecretString")
        except ClientError:
            return Secret(arn=arn, name=name, json_keys=None, readable=False)

        keys: list[str] | None = None
        if value:
            try:
                parsed = json.loads(value)
                if isinstance(parsed, dict):
                    keys = sorted(parsed.keys())
            except json.JSONDecodeError:
                keys = None
        return Secret(arn=arn, name=name, json_keys=keys, readable=True)

    def secret_field(self, secret_id: str, key: str) -> str | None:
        try:
            value = self.sm.get_secret_value(SecretId=secret_id).get("SecretString")
        except ClientError:
            return None
        if not value:
            return None
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return value
        return parsed.get(key) if isinstance(parsed, dict) else None

    def create_secret(self, name: str, value: str, description: str) -> str:
        resp = self.sm.create_secret(
            Name=name, SecretString=value, Description=description
        )
        return resp["ARN"]


# ---------------------------------------------------------------------------
# Import operations
# ---------------------------------------------------------------------------


@dataclass
class ImportOp:
    """One `terraform import`: a source in AWS and a target address in state.

    Holding these as objects is what makes dry-run trivially honest — the same
    list is what gets printed and what gets executed, so the preview cannot
    drift from the action.
    """

    tf_address: str
    physical_id: str
    source: str
    description: str

    def command(self, var_files: list[str]) -> list[str]:
        cmd = ["terraform", "import"]
        for var_file in var_files:
            cmd.append(f"-var-file={var_file}")
        cmd += [self.tf_address, self.physical_id]
        return cmd


def build_import_ops(facts: StackFacts) -> list[ImportOp]:
    ops: list[ImportOp] = []

    for module, db, logical in (
        ("db-main", facts.retool_db, LOGICAL_RETOOL_DB),
        ("db-temporal", facts.temporal_db, LOGICAL_TEMPORAL_DB),
    ):
        if db is None or not db.importable:
            continue

        prefix = f"module.{module}" if module == "db-main" else f"module.{module}[0]"

        ops.append(
            ImportOp(
                tf_address=f"{prefix}.module.rds_cluster.module.db_instance.aws_db_instance.this[0]",
                physical_id=db.identifier,
                source=f"{logical} / {db.identifier}",
                description="RDS instance",
            )
        )

        if db.db_subnet_group_name:
            ops.append(
                ImportOp(
                    tf_address=f"{prefix}.module.rds_cluster.module.db_subnet_group.aws_db_subnet_group.this[0]",
                    physical_id=db.db_subnet_group_name,
                    source=f"subnet group of {db.identifier}",
                    description="DB subnet group",
                )
            )

        if db.security_group_id:
            ops.append(
                ImportOp(
                    tf_address=f"{prefix}.module.main_rds_sg.aws_security_group.this[0]",
                    physical_id=db.security_group_id,
                    source=f"security group of {db.identifier}",
                    description="Security group",
                )
            )

        for rule in db.rules:
            kind = "egress" if rule.is_egress else "ingress"
            ops.append(
                ImportOp(
                    tf_address=f'aws_vpc_security_group_{kind}_rule.preserved["{rule.rule_id}"]',
                    physical_id=rule.rule_id,
                    source=f"{rule.ports()} {kind} from {rule.target()}",
                    description=f"Existing {kind} rule",
                )
            )

    return ops


# ---------------------------------------------------------------------------
# tfvars rendering
# ---------------------------------------------------------------------------


_BARE_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


def render_key(key: str) -> str:
    """Quote a map key unless it is a bare HCL identifier.

    Rule IDs like `sgr-0abc` contain hyphens; unquoted, HCL reads them as
    subtraction rather than a key.
    """
    if _BARE_IDENTIFIER.match(key) and "-" not in key:
        return key
    escaped = key.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_value(value: Any, indent: int = 0) -> str:
    pad = "  " * indent
    inner_pad = "  " * (indent + 1)

    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(value, list):
        if not value:
            return "[]"
        items = ",\n".join(f"{inner_pad}{render_value(v, indent + 1)}" for v in value)
        return f"[\n{items}\n{pad}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        keys = {k: render_key(k) for k in value}
        width = max(len(k) for k in keys.values())
        lines = [
            f"{inner_pad}{keys[k].ljust(width)} = {render_value(v, indent + 1)}"
            for k, v in value.items()
        ]
        body = "\n".join(lines)
        return f"{{\n{body}\n{pad}}}"
    raise TypeError(f"cannot render {type(value)!r} as HCL")


def render_tfvars(values: dict[str, Any]) -> str:
    """Render a tfvars document.

    Deliberately comment-free: this file is regenerated and layered into later
    applies, so anything explanatory would be lost or go stale.
    """
    lines = [f"{key} = {render_value(value)}" for key, value in values.items()]
    return "\n".join(lines) + "\n"


def db_to_tfvars(db: Database, security_group_name: str | None) -> dict[str, Any]:
    return {
        "identifier": db.identifier,
        "credentials_secret_id": db.credentials_secret_arn,
        "password_property": CF_GENERATED_SECRET_PROPERTY,
        "security_group_name": security_group_name,
        "db_subnet_group_name": db.db_subnet_group_name,
        "parameter_group_name": db.parameter_group_name,
        "database_name": db.database_name,
        "master_username": db.master_username,
        "port": db.port,
        "engine_version": db.engine_version,
        "instance_class": db.instance_class,
        "allocated_storage": db.allocated_storage,
        "max_allocated_storage": db.max_allocated_storage,
        "storage_type": db.storage_type,
        "iops": db.iops,
        "storage_encrypted": db.storage_encrypted,
        "multi_az": db.multi_az,
        "family": db.family,
        "major_engine_version": db.major_engine_version,
        "deletion_protection": db.deletion_protection,
    }


def rules_to_tfvars(rules: list[SecurityGroupRule], egress: bool) -> dict[str, Any]:
    return {
        rule.rule_id: rule.to_tfvars()
        for rule in rules
        if rule.is_egress == egress
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.option("--stack-name", required=True, help="CloudFormation stack name.")
@click.option("--region", required=True, help="AWS region the stack is deployed in.")
@click.option("--profile", default=None, help="AWS CLI profile to use.")
@click.option(
    "--chdir",
    "workdir",
    default=".",
    type=click.Path(file_okay=False, exists=True),
    help="Terraform working directory (default: current directory).",
)
@click.pass_context
def cli(
    ctx: click.Context, stack_name: str, region: str, profile: str | None, workdir: str
) -> None:
    """Adopt a Retool CloudFormation deployment's databases into Terraform."""
    ctx.ensure_object(dict)
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    ctx.obj["discoverer"] = Discoverer(session, stack_name, region)
    ctx.obj["workdir"] = workdir


def _discover(ctx: click.Context) -> tuple[StackFacts, Discoverer]:
    discoverer: Discoverer = ctx.obj["discoverer"]
    with console.status("Reading CloudFormation stack..."):
        facts = discoverer.run()
    return facts, discoverer


@cli.command("describe-cf-stack")
@click.pass_context
def describe_cf_stack(ctx: click.Context) -> None:
    """Summarize what the stack contains and whether it imports cleanly."""
    facts, discoverer = _discover(ctx)

    console.print(
        f"\n[bold]{facts.stack_name}[/bold] in [bold]{facts.region}[/bold]\n"
    )

    if facts.parameters:
        table = Table(title="Stack parameters", title_justify="left", show_lines=False)
        table.add_column("Parameter", style="cyan")
        table.add_column("Value", overflow="fold")
        for key in sorted(facts.parameters):
            value = facts.parameters[key]
            if len(value) > 80:
                value = value[:77] + "..."
            table.add_row(key, value)
        console.print(table)

    blockers: list[str] = []

    for label, db in (("Retool", facts.retool_db), ("Temporal", facts.temporal_db)):
        console.print()
        if db is None:
            console.print(f"[yellow]{label} database: not found[/yellow]")
            continue

        table = Table(title=f"{label} database", title_justify="left")
        table.add_column("Attribute", style="cyan")
        table.add_column("Value", overflow="fold")
        table.add_row("Identifier", db.identifier)
        table.add_row(
            "Kind",
            "standalone RDS instance"
            if db.kind == "instance"
            else "[yellow]Aurora cluster[/yellow]",
        )
        table.add_row("Endpoint", db.address or "-")
        table.add_row("Engine", f"{db.engine} {db.engine_version}")
        table.add_row("Instance class", db.instance_class)
        table.add_row("Storage", f"{db.allocated_storage} GB {db.storage_type}")
        table.add_row("Multi-AZ", str(db.multi_az))
        table.add_row("Encrypted", str(db.storage_encrypted))
        table.add_row("Database name", db.database_name or "-")
        table.add_row("Master username", db.master_username or "-")
        table.add_row(
            "Master password",
            "[yellow]RDS-managed[/yellow]"
            if db.manages_master_password
            else "self-managed (Secrets Manager)",
        )
        table.add_row("Credentials secret", db.credentials_secret_arn or "[red]not found[/red]")
        table.add_row("Parameter group", db.parameter_group_name or "-")
        table.add_row("Subnet group", db.db_subnet_group_name or "-")
        table.add_row("Security groups", ", ".join(db.security_group_ids) or "-")
        console.print(table)

        if db.rules:
            rules_table = Table(
                title=f"{label} security group rules — all preserved on import",
                title_justify="left",
            )
            rules_table.add_column("Rule ID", style="dim")
            rules_table.add_column("Dir")
            rules_table.add_column("Ports")
            rules_table.add_column("Source/dest", overflow="fold")
            rules_table.add_column("Description", overflow="fold")
            for rule in sorted(db.rules, key=lambda r: (r.is_egress, r.rule_id)):
                rules_table.add_row(
                    rule.rule_id,
                    "egress" if rule.is_egress else "ingress",
                    rule.ports(),
                    rule.target(),
                    rule.description or "-",
                )
            console.print(rules_table)

        if not db.importable:
            blockers.append(
                f"{label} database is an Aurora cluster. The aws-database module builds a "
                "standalone RDS instance, so it cannot be imported. import-tfvars will "
                'emit it as temporal_db_mode = "external" instead, leaving it where it is.'
            )
        if db.manages_master_password:
            blockers.append(
                f"{label} database has an RDS-managed master password. This example expects a "
                "self-managed one so the running ECS deployment keeps its credentials; review "
                "before importing."
            )

    if facts.secrets:
        console.print()
        table = Table(title="Secrets", title_justify="left")
        table.add_column("Purpose", style="cyan")
        table.add_column("Name", overflow="fold")
        table.add_column("Shape")
        for key in sorted(facts.secrets):
            secret = facts.secrets[key]
            if not secret.readable:
                shape = "[yellow]unreadable[/yellow]"
            elif secret.json_keys is None:
                shape = "bare string"
            else:
                shape = f"JSON: {', '.join(secret.json_keys)}"
            table.add_row(key, secret.name, shape)
        console.print(table)

    if facts.mappings:
        console.print()
        console.print("[bold]Template mappings[/bold] (CloudAuth configuration)")
        console.print_json(json.dumps(facts.mappings))

    console.print()
    if facts.warnings or blockers:
        for item in facts.warnings:
            console.print(f"[yellow]![/yellow] {item}")
        for item in blockers:
            console.print(f"[yellow]![/yellow] {item}")
    else:
        console.print("[green]No blockers found.[/green]")

    console.print(
        "\nNext: [bold]import-tfvars[/bold] to write "
        f"{TFVARS_FILENAME}, then [bold]import-state[/bold] to import.\n"
    )


@cli.command("import-state")
@click.option(
    "--apply",
    "do_apply",
    is_flag=True,
    default=False,
    help="Actually run terraform import. Without this the run is read-only.",
)
@click.option(
    "--var-file",
    "var_files",
    multiple=True,
    default=(TFVARS_FILENAME, "terraform.tfvars"),
    show_default=True,
    help="Var files passed to terraform import; repeatable.",
)
@click.pass_context
def import_state(
    ctx: click.Context, do_apply: bool, var_files: tuple[str, ...]
) -> None:
    """Import the stack's databases into Terraform state."""
    facts, _ = _discover(ctx)
    workdir: str = ctx.obj["workdir"]

    ops = build_import_ops(facts)
    if not ops:
        raise click.ClickException(
            "Nothing to import. Run describe-cf-stack to see what was found."
        )

    existing = _terraform_state_list(workdir)
    pending = [op for op in ops if op.tf_address not in existing]
    skipped = len(ops) - len(pending)

    table = Table(
        title=f"{'Importing' if do_apply else 'Would import'} {len(pending)} resource(s)",
        title_justify="left",
    )
    table.add_column("Source (AWS)", style="cyan", overflow="fold")
    table.add_column("ID", overflow="fold")
    table.add_column("Target (Terraform address)", overflow="fold")
    for op in pending:
        table.add_row(op.source, op.physical_id, op.tf_address)
    console.print(table)

    if skipped:
        console.print(f"[dim]{skipped} already in state; skipping.[/dim]")

    if facts.temporal_db is not None and not facts.temporal_db.importable:
        console.print(
            "\n[yellow]![/yellow] The Temporal database is an Aurora cluster and cannot be "
            "imported into the aws-database module.\n"
            '    Use temporal_db_mode = "external" — import-tfvars writes that for you — '
            "which leaves it\n    in place and connects Retool to it as an external database."
        )

    if not pending:
        console.print("\n[green]Nothing left to import.[/green]")
        return

    if not do_apply:
        console.print(
            "\n[dim]Read-only run. Re-run with --apply to perform these imports.[/dim]"
        )
        return

    missing = [v for v in var_files if not (_path(workdir, v)).exists()]
    if missing:
        raise click.ClickException(
            f"Missing var file(s): {', '.join(missing)}. Run import-tfvars first, "
            "and copy vars.tf.example to terraform.tfvars."
        )

    if not questionary.confirm(
        f"Run terraform import for {len(pending)} resource(s) in {workdir}?",
        default=False,
    ).ask():
        console.print("Aborted.")
        return

    failures = 0
    for op in pending:
        console.print(f"[cyan]import[/cyan] {op.tf_address}")
        result = subprocess.run(
            op.command(list(var_files)), cwd=workdir, text=True, capture_output=True
        )
        if result.returncode != 0:
            failures += 1
            err_console.print(f"[red]failed:[/red] {op.tf_address}")
            err_console.print(result.stderr.strip())
    if failures:
        raise click.ClickException(
            f"{failures} import(s) failed. Fix the cause and re-run — imports already "
            "done are skipped."
        )

    console.print(
        "\n[green]Imports complete.[/green] Now run terraform plan and confirm it shows "
        "no replacement\nor deletion of the databases, subnet groups, security groups, "
        "or any preserved rule."
    )


@cli.command("import-tfvars")
@click.option(
    "--output",
    default=TFVARS_FILENAME,
    show_default=True,
    help="File to write, relative to --chdir.",
)
@click.option(
    "--prefix",
    default=None,
    help="Deployment prefix, used when offering to create derived secrets.",
)
@click.option(
    "--yes",
    "assume_yes",
    is_flag=True,
    default=False,
    help="Skip confirmation prompts. Never creates secrets; declines those offers.",
)
@click.pass_context
def import_tfvars(
    ctx: click.Context, output: str, prefix: str | None, assume_yes: bool
) -> None:
    """Write imported.tfvars from the CloudFormation stack."""
    facts, discoverer = _discover(ctx)
    workdir: str = ctx.obj["workdir"]
    out_path = _path(workdir, output)

    values: dict[str, Any] = {}

    # -- network ---------------------------------------------------------
    if vpc_id := facts.param("VpcId"):
        values["vpc_id"] = vpc_id
    if subnets := facts.param("SubnetId"):
        values["private_subnet_ids"] = [s.strip() for s in subnets.split(",") if s.strip()]
    if lb_subnets := facts.param("LoadBalancerSubnetId"):
        values["public_subnet_ids"] = [
            s.strip() for s in lb_subnets.split(",") if s.strip()
        ]

    # -- application -----------------------------------------------------
    if base_domain := facts.param("BaseDomain"):
        values["domain_name"] = base_domain.split("://", 1)[-1].rstrip("/")
    if image := (facts.param("RetoolImage") or facts.param("Image")):
        values["retool_image_tag"] = image.rsplit(":", 1)[-1] if ":" in image else image
    if cert := facts.param("CertificateARN"):
        values["acm_certificate_arn"] = cert

    replica_counts = {}
    for key, param in (
        ("backend", "DesiredCount"),
        ("workflows_backend", "DesiredWorkflowsCount"),
        ("workflows_worker", "DesiredWorkflowsCount"),
        ("code_executor", "DesiredCodeExecutorCount"),
    ):
        if raw := facts.param(param):
            try:
                replica_counts[key] = int(raw)
            except ValueError:
                pass
    if replica_counts:
        values["replica_counts"] = replica_counts

    if token := facts.param("UsageAPIToken"):
        values["usage_api_token"] = token
    if mapping := facts.param("LDAPRoleMapping"):
        values["ldap_role_mapping"] = mapping

    # -- databases -------------------------------------------------------
    if facts.retool_db is None:
        raise click.ClickException(
            "No Retool database found in the stack; nothing to write. "
            "Run describe-cf-stack to see what was discovered."
        )

    retool_sg_name = (
        discoverer.security_group_name(facts.retool_db.security_group_id)
        if facts.retool_db.security_group_id
        else None
    )
    values["retool_db"] = db_to_tfvars(facts.retool_db, retool_sg_name)
    values["retool_db_preserved_ingress_rules"] = rules_to_tfvars(
        facts.retool_db.rules, egress=False
    )
    values["retool_db_preserved_egress_rules"] = rules_to_tfvars(
        facts.retool_db.rules, egress=True
    )

    temporal = facts.temporal_db
    if temporal is None:
        values["temporal_db_mode"] = "none"
    elif temporal.importable:
        temporal_sg_name = (
            discoverer.security_group_name(temporal.security_group_id)
            if temporal.security_group_id
            else None
        )
        values["temporal_db_mode"] = "imported"
        values["temporal_db"] = db_to_tfvars(temporal, temporal_sg_name)
        values["temporal_db_preserved_ingress_rules"] = rules_to_tfvars(
            temporal.rules, egress=False
        )
        values["temporal_db_preserved_egress_rules"] = rules_to_tfvars(
            temporal.rules, egress=True
        )
    else:
        values["temporal_db_mode"] = "external"
        values["temporal_db_external"] = {
            "host": temporal.address,
            "port": temporal.port,
            "username": temporal.master_username,
            "credentials_secret_id": temporal.credentials_secret_arn,
            "password_property": CF_GENERATED_SECRET_PROPERTY,
            "security_group_id": temporal.security_group_id,
        }

    # -- secrets ---------------------------------------------------------
    values.update(
        _secret_values(facts, discoverer, prefix=prefix, assume_yes=assume_yes)
    )

    # -- CloudAuth -------------------------------------------------------
    if cloudauth := _cloudauth_values(facts):
        values["cloudauth"] = cloudauth

    # -- ALB OIDC --------------------------------------------------------
    if alb_oidc := _alb_oidc_values(facts):
        values["alb_oidc"] = alb_oidc

    rendered = render_tfvars(values)

    if out_path.exists() and not assume_yes:
        if not questionary.confirm(
            f"{output} already exists. Overwrite it?", default=False
        ).ask():
            console.print("Aborted; nothing written.")
            console.print(rendered)
            return

    out_path.write_text(rendered)
    console.print(f"[green]Wrote {out_path}[/green] ({len(values)} values)")
    console.print(
        "\nReview it, then copy vars.tf.example to terraform.tfvars for the values that "
        "are your\nown choices (prefix, region, profile). Apply with both:\n"
        f"\n  terraform apply -var-file={output} -var-file=terraform.tfvars\n"
    )


def _secret_values(
    facts: StackFacts,
    discoverer: Discoverer,
    prefix: str | None,
    assume_yes: bool,
) -> dict[str, Any]:
    """Build the secret-referencing tfvars, offering to reshape where useful.

    The blueprint reads a secret's value either whole or from a named JSON
    property, so a CloudFormation secret can be referenced exactly as it is —
    that is the default and it mutates nothing. Creating a derived, bare-string
    secret is offered only as an alternative, and only with consent.
    """
    out: dict[str, Any] = {}

    specs = [
        ("encryption_key", "encryption_key_secret", CF_GENERATED_SECRET_PROPERTY, True),
        ("jwt", "jwt_secret", CF_GENERATED_SECRET_PROPERTY, False),
        ("license_key", "license_key_secret", CF_LICENSE_KEY_PROPERTY, False),
    ]

    for key, var_name, preferred, offer_derived in specs:
        secret = facts.secrets.get(key)
        if secret is None:
            continue

        prop = secret.property_for(preferred)
        entry: dict[str, Any] = {"secret_id": secret.arn, "property": prop}

        if (
            offer_derived
            and prop is not None
            and secret.readable
            and not assume_yes
            and prefix
        ):
            console.print(
                f"\n[bold]{var_name}[/bold] is JSON with the value under "
                f"[cyan]{prop}[/cyan].\n"
                "Terraform can read it in place — no change needed. Alternatively a "
                "derived secret\nholding just the raw value can be created, if you "
                "prefer that shape."
            )
            derived_name = f"retool/{prefix}/{var_name.replace('_secret', '').replace('_', '-')}"
            if questionary.confirm(
                f"Create derived secret {derived_name}?", default=False
            ).ask():
                value = discoverer.secret_field(secret.arn, prop)
                if value is None:
                    console.print("[yellow]Could not read the value; leaving as is.[/yellow]")
                else:
                    try:
                        arn = discoverer.create_secret(
                            derived_name,
                            value,
                            f"Raw {var_name} derived from {secret.name}",
                        )
                        entry = {"secret_id": arn, "property": None}
                        console.print(f"[green]Created {arn}[/green]")
                    except ClientError as exc:
                        console.print(f"[yellow]Could not create it: {exc}[/yellow]")

        out[var_name] = entry

    return out


def _cloudauth_values(facts: StackFacts) -> dict[str, Any] | None:
    """Pull the CloudAuth configuration out of the template's Mappings block."""
    endpoints = facts.mappings.get("CloudAuthVpcEndpointServices") or {}
    fqens = facts.mappings.get("CloudAuthSuperStarFQENs") or {}
    constants = facts.mappings.get("Constants") or {}

    service = (endpoints.get(facts.region) or {}).get("vpces")
    fqen = (fqens.get(facts.region) or {}).get("fqen")
    if not service or not fqen:
        return None

    out: dict[str, Any] = {
        "vpc_endpoint_service_name": service,
        "fqen": fqen,
    }
    if subdomain := (constants.get("cloudauth") or {}).get("subdomain"):
        out["subdomain"] = subdomain
    # The execute-api account IDs live in an IAM policy in the template, not in
    # Mappings; the operator supplies them.
    out["api_gateway_account_ids"] = []
    return out


def _alb_oidc_values(facts: StackFacts) -> dict[str, Any] | None:
    secret_arn = facts.param("AlbOAuthARN")
    environment = facts.param("FederateEnvironment")
    if not secret_arn or not environment:
        return None
    base = f"https://idp-{environment}.federate.amazon.com"
    return {
        "issuer": base,
        "authorization_endpoint": f"{base}/api/oauth2/v1/authorize",
        "token_endpoint": f"{base}/api/oauth2/v2/token",
        "user_info_endpoint": f"{base}/api/oauth2/v1/userinfo",
        "credentials_secret_id": secret_arn,
    }


# ---------------------------------------------------------------------------
# Terraform helpers
# ---------------------------------------------------------------------------


def _path(workdir: str, name: str) -> Path:
    return Path(workdir) / name


def _terraform_state_list(workdir: str) -> set[str]:
    """Addresses already in state, so imports can be re-run safely."""
    if shutil.which("terraform") is None:
        raise click.ClickException("terraform not found on PATH.")
    result = subprocess.run(
        ["terraform", "state", "list"], cwd=workdir, text=True, capture_output=True
    )
    if result.returncode != 0:
        # No state yet is the normal case on a first run.
        return set()
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def main() -> None:
    try:
        cli(obj={})
    except KeyboardInterrupt:
        err_console.print("\nInterrupted.")
        sys.exit(130)


if __name__ == "__main__":
    main()
