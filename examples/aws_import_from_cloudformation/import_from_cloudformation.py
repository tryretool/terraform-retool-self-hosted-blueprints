#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "boto3>=1.34",
#     "click>=8.1",
#     "questionary>=2.0",
#     "rich>=13.7",
# ]
# ///
"""Derive this Terraform stack's configuration from a Retool CloudFormation deployment.

Reads an existing `retool-onpremise` CloudFormation stack, traverses to the
resources it references, and writes out everything the Terraform stack needs to
stand up alongside it:

  describe-cf-stack   what's there, and anything that needs attention
  import-tfvars       imported.auto.tfvars — every value derivable from the stack

Nothing here modifies the CloudFormation deployment. The one action that writes
to AWS — creating a derived secret — is offered explicitly and never implied.

The variable names written here match the aws_import_from_cloudformation
example; run it from that directory.
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
from botocore.exceptions import ClientError
from rich.console import Console
from rich.table import Table

# emoji=False because ARNs contain ":secret:", which rich would otherwise
# render as ㊙ — corrupting every ARN printed.
console = Console(emoji=False)
err_console = Console(stderr=True, emoji=False)

# *.auto.tfvars is loaded automatically by Terraform, so no -var-file flag is
# needed on any command. Files load in lexical order, so anything the operator
# puts in overrides.auto.tfvars wins over what is generated here.
TFVARS_FILENAME = "imported.auto.tfvars"

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
# Discovered facts
# ---------------------------------------------------------------------------


@dataclass
class Database:
    """An RDS database referenced by the stack, as the Terraform stack needs it."""

    identifier: str
    kind: str  # "instance" or "aurora"
    address: str | None
    port: int
    engine: str
    engine_version: str
    instance_class: str
    allocated_storage: int
    storage_encrypted: bool
    multi_az: bool
    database_name: str | None
    master_username: str | None
    manages_master_password: bool
    rds_managed_secret_arn: str | None
    db_subnet_group_name: str | None
    security_group_ids: list[str]
    credentials_secret_arn: str | None = None
    cluster_identifier: str | None = None

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

        return StackFacts(
            stack_name=self.stack_name,
            region=self.region,
            parameters=parameters,
            resources=resources,
            resource_types=resource_types,
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
                "No Retool RDS instance found in the stack. There is nothing to point "
                "the new deployment at."
            )

        temporal_logical = (
            LOGICAL_TEMPORAL_DB
            if LOGICAL_TEMPORAL_DB in facts.resources
            else next((i for i in instance_ids if "temporal" in i.lower()), None)
        )
        if temporal_logical:
            facts.temporal_db = self._load_instance(facts.resources[temporal_logical])
            # An Aurora member instance has its own endpoint, but connections
            # belong on the cluster's writer endpoint — that one follows
            # failover and survives the instance being replaced.
            if facts.temporal_db and facts.temporal_db.cluster_identifier:
                cluster = self._load_cluster(facts.temporal_db.cluster_identifier)
                if cluster:
                    facts.temporal_db = cluster
        elif LOGICAL_TEMPORAL_CLUSTER in facts.resources or self._logical_ids_of_type(
            facts, "AWS::RDS::DBCluster"
        ):
            facts.temporal_db = self._load_cluster_for(facts)

        # The Temporal database is sometimes created outside the stack. If the
        # stack didn't name one, look for it in the same subnet group.
        if facts.temporal_db is None and facts.retool_db is not None:
            facts.temporal_db = self._search_temporal_instance(facts)

        # Credentials secrets, by logical ID where the templates provide one.
        if facts.retool_db is not None:
            facts.retool_db.credentials_secret_arn = facts.resources.get(
                LOGICAL_RETOOL_DB_SECRET
            ) or facts.retool_db.rds_managed_secret_arn
        if facts.temporal_db is not None:
            facts.temporal_db.credentials_secret_arn = (
                facts.resources.get(LOGICAL_TEMPORAL_DB_SECRET)
                or facts.temporal_db.rds_managed_secret_arn
            )

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
            storage_encrypted=raw.get("StorageEncrypted", False),
            multi_az=raw.get("MultiAZ", False),
            database_name=raw.get("DBName"),
            master_username=raw.get("MasterUsername"),
            manages_master_password=bool(raw.get("MasterUserSecret")),
            rds_managed_secret_arn=(raw.get("MasterUserSecret") or {}).get("SecretArn"),
            db_subnet_group_name=subnet_group.get("DBSubnetGroupName"),
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
        return self._load_cluster(cluster_id)

    def _load_cluster(self, cluster_id: str) -> Database | None:
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
            storage_encrypted=raw.get("StorageEncrypted", False),
            multi_az=raw.get("MultiAZ", False),
            database_name=raw.get("DatabaseName"),
            master_username=raw.get("MasterUsername"),
            manages_master_password=bool(raw.get("MasterUserSecret")),
            rds_managed_secret_arn=(raw.get("MasterUserSecret") or {}).get("SecretArn"),
            db_subnet_group_name=raw.get("DBSubnetGroup"),
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
                f"{candidates[0].identifier}. Override temporal_db in overrides.auto.tfvars "
                "if that is the wrong one."
            )
        return candidates[0]

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
# tfvars rendering
# ---------------------------------------------------------------------------

_BARE_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def render_key(key: str) -> str:
    """Quote a map key unless it is a bare HCL identifier.

    A key containing a hyphen reads as subtraction if left unquoted.
    """
    if _BARE_IDENTIFIER.match(key):
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
    """Derive Terraform configuration from a Retool CloudFormation deployment."""
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
    """Summarize what the stack contains."""
    facts, _ = _discover(ctx)

    console.print(f"\n[bold]{facts.stack_name}[/bold] in [bold]{facts.region}[/bold]\n")

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

    notes: list[str] = []

    for label, db in (("Retool", facts.retool_db), ("Temporal", facts.temporal_db)):
        console.print()
        if db is None:
            console.print(f"[yellow]{label} database: not found[/yellow]")
            if label == "Temporal":
                notes.append(
                    "No Temporal database found. import-tfvars will leave temporal_db "
                    "unset, which disables Retool Workflows."
                )
            continue

        table = Table(title=f"{label} database", title_justify="left")
        table.add_column("Attribute", style="cyan")
        table.add_column("Value", overflow="fold")
        table.add_row("Identifier", db.identifier)
        table.add_row(
            "Kind",
            "standalone RDS instance" if db.kind == "instance" else "Aurora cluster",
        )
        table.add_row("Endpoint", db.address or "-")
        table.add_row("Engine", f"{db.engine} {db.engine_version}")
        table.add_row("Instance class", db.instance_class)
        table.add_row("Database name", db.database_name or "-")
        table.add_row("Master username", db.master_username or "-")
        table.add_row(
            "Master password",
            "RDS-managed"
            if db.manages_master_password
            else "self-managed (Secrets Manager)",
        )
        table.add_row(
            "Credentials secret", db.credentials_secret_arn or "[red]not found[/red]"
        )
        table.add_row("Subnet group", db.db_subnet_group_name or "-")
        table.add_row("Security groups", ", ".join(db.security_group_ids) or "-")
        console.print(table)

        if not db.credentials_secret_arn:
            notes.append(
                f"{label} database has no discoverable credentials secret. Set its "
                "credentials_secret_id by hand, or the new deployment cannot "
                "authenticate."
            )
        if not db.security_group_ids:
            notes.append(
                f"{label} database has no active security group. This stack adds an "
                "ingress rule for the EKS nodes to one; without it you must open "
                "access yourself."
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

    if "encryption_key" not in facts.secrets:
        notes.append(
            "No encryption key secret found. It MUST be carried over — every "
            "credential stored in the Retool database is encrypted with it."
        )

    console.print()
    if facts.warnings or notes:
        for item in facts.warnings + notes:
            console.print(f"[yellow]![/yellow] {item}")
    else:
        console.print("[green]Nothing needing attention.[/green]")

    console.print(
        f"\nNext: [bold]import-tfvars[/bold] to write {TFVARS_FILENAME}.\n"
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
    """Write imported.auto.tfvars from the CloudFormation stack."""
    facts, discoverer = _discover(ctx)
    workdir: str = ctx.obj["workdir"]
    out_path = Path(workdir) / output

    values: dict[str, Any] = {}

    # -- network ---------------------------------------------------------
    if vpc_id := facts.param("VpcId"):
        values["vpc_id"] = vpc_id
    if subnets := facts.param("SubnetId"):
        values["private_subnet_ids"] = [
            s.strip() for s in subnets.split(",") if s.strip()
        ]
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

    values["retool_db"] = {
        "instance_identifier": facts.retool_db.identifier,
        "credentials_secret_id": facts.retool_db.credentials_secret_arn,
        "password_property": CF_GENERATED_SECRET_PROPERTY,
        "security_group_id": facts.retool_db.security_group_id,
    }

    if facts.temporal_db is not None:
        values["temporal_db"] = {
            "host": facts.temporal_db.address,
            "port": facts.temporal_db.port,
            "username": facts.temporal_db.master_username,
            "database": facts.temporal_db.database_name or "temporal",
            "credentials_secret_id": facts.temporal_db.credentials_secret_arn,
            "password_property": CF_GENERATED_SECRET_PROPERTY,
            "security_group_id": facts.temporal_db.security_group_id,
        }
    else:
        values["temporal_db"] = None

    # -- secrets ---------------------------------------------------------
    values.update(
        _secret_values(facts, discoverer, prefix=prefix, assume_yes=assume_yes)
    )

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
    _terraform_fmt(out_path)
    console.print(f"[green]Wrote {out_path}[/green] ({len(values)} values)")
    console.print(
        "\nReview it, then copy vars.tf.example to overrides.auto.tfvars for the "
        "values that are\nyour own choices (prefix, region, profile). Both are loaded "
        "automatically:\n"
        "\n  terraform plan\n  terraform apply\n"
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
            derived_name = (
                f"retool/{prefix}/{var_name.replace('_secret', '').replace('_', '-')}"
            )
            if questionary.confirm(
                f"Create derived secret {derived_name}?", default=False
            ).ask():
                value = discoverer.secret_field(secret.arn, prop)
                if value is None:
                    console.print(
                        "[yellow]Could not read the value; leaving as is.[/yellow]"
                    )
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


def _terraform_fmt(path: Path) -> None:
    """Canonicalize the rendered file with `terraform fmt`, if it's available.

    The renderer emits valid HCL but doesn't reproduce Terraform's alignment of
    consecutive assignments. Rather than reimplement that, hand it to the tool
    that defines it. Best-effort: the file is already correct without this.
    """
    if shutil.which("terraform") is None:
        return
    subprocess.run(
        ["terraform", "fmt", path.name],
        cwd=path.parent,
        capture_output=True,
        text=True,
    )


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


def main() -> None:
    try:
        cli(obj={})
    except KeyboardInterrupt:
        err_console.print("\nInterrupted.")
        sys.exit(130)


if __name__ == "__main__":
    main()
