#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "boto3>=1.40",
#     "click>=8.1",
#     "httpx>=0.27",
#     "pyyaml>=6.0",
#     "rich>=13.7",
# ]
# ///
"""Keep pinned component versions in the Terraform sources current.

Every version literal in this repo is pinned on purpose, so an apply never
silently picks up a new upstream release. A literal opts in to being bumped by
carrying a marker comment directly above it:

    # AUTOUPDATE: external-secrets-chart 2.x.x
    version    = optional(string, "2.8.0")

The component name selects a version source (see COMPONENTS); the constraint
says how far the version is allowed to move. Nothing without a marker is ever
touched.

  report    print what would change, write nothing
  update    rewrite the literals in place

Both subcommands run exactly the same scan and the same upstream lookups; only
the final write differs.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Literal, Protocol

import boto3
import click
import httpx
import yaml
from botocore.exceptions import BotoCoreError, ClientError
from rich.console import Console
from rich.table import Table

# emoji=False so version strings and registry paths are never reinterpreted as
# emoji shortcodes — ":sig", ":stable" and friends would otherwise be mangled.
console = Console(emoji=False)
err_console = Console(stderr=True, emoji=False)


# ---------------------------------------------------------------------------
# Version shapes
#
# The literals here come in a dozen spellings: v1.21.0, 2.8.0, 1.34, 16.13, 16,
# postgres16, POSTGRES_16, 3.334.0-stable, retool-temporal-1.1.6. Rather than
# special-case each, every literal is split into prefix + numeric segments +
# suffix, and the replacement is rendered back into the same shape. One source
# returning "17.11" can then drive "16.13", "postgres16" and "16" correctly.
# ---------------------------------------------------------------------------

# The prefix charset excludes digits and dots deliberately. A lenient [^0-9]*
# backtracks and parses "retool-temporal-1.1.6" as prefix "retool-temporal-1.1."
# plus nums "6"; excluding digits forces the split at the first digit.
LITERAL_RE = re.compile(
    r"^(?P<prefix>(?:[A-Za-z_][A-Za-z_-]*)?)"
    r"(?P<nums>\d+(?:\.\d+)*)"
    r"(?P<suffix>(?:[-.][A-Za-z0-9][A-Za-z0-9._-]*)?)$"
)

CONSTRAINT_RE = re.compile(
    r"^(?P<segs>(?:x|\d+)(?:\.(?:x|\d+))*)"
    r"(?P<suffix>(?:[-.][A-Za-z0-9][A-Za-z0-9._-]*)?)$"
)


class ShapeError(Exception):
    """A chosen version cannot be rendered into the literal's shape."""


@dataclass(frozen=True)
class ParsedVersion:
    """An upstream version string split into its comparable parts."""

    raw: str
    prefix: str
    nums: tuple[int, ...]
    suffix: str


@dataclass(frozen=True)
class Shape:
    """The lexical shape of an existing literal, used to render its successor."""

    prefix: str
    segments: int
    suffix: str


@dataclass(frozen=True)
class Constraint:
    """A parsed marker constraint.

    `pins` holds one entry per segment: an int to pin it, or None for `x`.
    """

    raw: str
    pins: tuple[int | None, ...]
    suffix: str


def parse_version(text: str) -> ParsedVersion | None:
    """Split a version string, or return None if it is not version-shaped."""
    m = LITERAL_RE.match(text)
    if m is None:
        return None
    return ParsedVersion(
        raw=text,
        prefix=m.group("prefix"),
        nums=tuple(int(n) for n in m.group("nums").split(".")),
        suffix=m.group("suffix"),
    )


def parse_constraint(text: str) -> Constraint | None:
    """Parse `6.x.x`, `1.x`, `x`, or `4.34.x-stable`."""
    m = CONSTRAINT_RE.match(text)
    if m is None:
        return None
    pins = tuple(None if s == "x" else int(s) for s in m.group("segs").split("."))
    return Constraint(raw=text, pins=pins, suffix=m.group("suffix"))


def shape_of(version: ParsedVersion) -> Shape:
    return Shape(
        prefix=version.prefix, segments=len(version.nums), suffix=version.suffix
    )


def matches(constraint: Constraint, candidate: ParsedVersion) -> bool:
    """Whether a candidate satisfies a constraint.

    The suffix rule carries most of the weight: a constraint's suffix must equal
    the candidate's, where absent is "". That single comparison excludes
    prereleases (3.0.0-beta.1), ECR Public's signature and digest tags
    (sha256-<hex>.sig, v0-<sha40>), RDS Extended Support builds
    (11.22-rds.20250508), and keeps `4.34.x-stable` from ever crossing into
    `-edge` or `-stable-hardened` — with no filter lists to maintain.

    The prefix is ignored here and used only when rendering, which is what lets
    the ALB controller's "v1.13.2" be bumped from upstream's unprefixed "1.13.2".
    """
    if candidate.suffix != constraint.suffix:
        return False
    # A candidate may be more precise than the constraint (1.x matches 1.36.4),
    # but never less — "16.x" must not be satisfied by a bare "16".
    if len(candidate.nums) < len(constraint.pins):
        return False
    return all(
        pin is None or pin == num for pin, num in zip(constraint.pins, candidate.nums)
    )


def select_best(constraint: Constraint, candidates: list[str]) -> ParsedVersion:
    """Highest candidate satisfying the constraint.

    Upstream order is never trusted: stakater's index.yaml lists 3.0.0-beta.1
    first, and registries sort tags lexicographically (where 1.34.9 sorts
    above 1.34.11). Everything is parsed and compared as a tuple of ints.

    packaging.version is deliberately not used — postgres16, POSTGRES_16,
    retool-temporal-1.1.6 and 3.334.0-stable are not PEP 440, and
    Version("3.334.0-stable") raises.
    """
    viable = [
        parsed
        for parsed in (parse_version(c) for c in candidates)
        if parsed is not None and matches(constraint, parsed)
    ]
    if not viable:
        raise VersionFetchError(
            f"no available version matches {constraint.raw!r}",
            hint=f"{len(candidates)} candidates were offered upstream",
        )
    return max(viable, key=lambda p: p.nums)


def render(shape: Shape, chosen: ParsedVersion) -> str:
    """Render a chosen version into an existing literal's shape."""
    if len(chosen.nums) < shape.segments:
        raise ShapeError(
            f"upstream offers {chosen.raw!r} ({len(chosen.nums)} segment(s)) but the "
            f"literal needs {shape.segments}; zero-padding would assert a release "
            f"that may not exist"
        )
    # Truncating from the right is safe: in each of these namespaces every dotted
    # prefix of a version is itself a valid coarser identifier — 17.11 -> 17 is
    # the true Postgres major, 1.36.4 -> 1.36 the true Kubernetes minor.
    nums = chosen.nums[: shape.segments]
    return shape.prefix + ".".join(str(n) for n in nums) + shape.suffix


# ---------------------------------------------------------------------------
# Version sources
# ---------------------------------------------------------------------------


class VersionFetchError(Exception):
    """A source could not answer.

    Always reported as a row and counted toward the exit code; never aborts the
    scan, so one set of missing credentials cannot hide every other bump.
    """

    def __init__(self, message: str, *, hint: str | None = None) -> None:
        super().__init__(message)
        self.hint = hint


@dataclass
class SourceEnv:
    """Context a source may need, supplied by the CLI at call time."""

    aws_region: str
    aws_profile: str | None
    timeout: int
    _session: Any = field(default=None, repr=False)

    def boto3_client(self, service: str) -> Any:
        if self._session is None:
            try:
                self._session = boto3.Session(
                    profile_name=self.aws_profile, region_name=self.aws_region
                )
            except BotoCoreError as exc:
                raise VersionFetchError(
                    str(exc), hint="check --aws-profile / AWS_PROFILE"
                ) from exc
        return self._session.client(service)


class VersionSource(Protocol):
    """Where the available versions of one component come from."""

    # A read-only property, not a plain attribute: every source is a frozen
    # dataclass, whose attributes are read-only, and a read-only
    # implementation cannot satisfy a protocol attribute declared writable.
    @property
    def needs(self) -> str:
        """Prerequisite named in error rows, e.g. "AWS credentials"."""
        ...

    def fetch(self, env: SourceEnv) -> list[str]:
        """Every candidate version, spelled exactly as upstream spells it.

        Order is not significant — selection happens downstream. Raise
        VersionFetchError for anything that prevents answering.
        """
        ...


def _http_get(url: str, env: SourceEnv, **kwargs: Any) -> httpx.Response:
    try:
        response = httpx.get(url, timeout=env.timeout, follow_redirects=True, **kwargs)
        response.raise_for_status()
        return response
    except httpx.HTTPError as exc:
        raise VersionFetchError(f"{type(exc).__name__}: {exc}", hint=url) from exc


@dataclass(frozen=True)
class HelmChart:
    """Chart versions from a classic HTTP Helm repository's index.yaml."""

    index_url: str
    chart: str
    # "version" is the chart version; "appVersion" is the application image it
    # ships. The GCP modules pin both, and reading them from the same document
    # is what keeps a chart and its image_tag from drifting apart.
    field: str = "version"
    needs: str = "network access"

    def fetch(self, env: SourceEnv) -> list[str]:
        response = _http_get(f"{self.index_url.rstrip('/')}/index.yaml", env)
        try:
            document = yaml.safe_load(response.text)
        except yaml.YAMLError as exc:
            raise VersionFetchError(f"unparseable index.yaml: {exc}") from exc
        entries = (document or {}).get("entries", {}).get(self.chart)
        if not entries:
            raise VersionFetchError(
                f"chart {self.chart!r} not found in {self.index_url}"
            )
        return [e[self.field] for e in entries if e.get(self.field)]


@dataclass(frozen=True)
class OciTags:
    """Tags from an OCI registry, used for both OCI-hosted charts and images."""

    registry: str
    repository: str
    max_pages: int = 10
    needs: str = "network access"

    def fetch(self, env: SourceEnv) -> list[str]:
        client = httpx.Client(timeout=env.timeout, follow_redirects=True)
        try:
            return self._fetch(client)
        except httpx.HTTPError as exc:
            raise VersionFetchError(f"{type(exc).__name__}: {exc}") from exc
        finally:
            client.close()

    def _fetch(self, client: httpx.Client) -> list[str]:
        url = f"https://{self.registry}/v2/{self.repository}/tags/list"
        headers: dict[str, str] = {}
        tags: list[str] = []
        for _ in range(self.max_pages):
            response = client.get(url, headers=headers)
            if response.status_code == 401 and "Authorization" not in headers:
                headers["Authorization"] = (
                    f"Bearer {self._anonymous_token(client, response)}"
                )
                continue
            response.raise_for_status()
            tags.extend(response.json().get("tags") or [])
            # ECR Public and MCR paginate with a Link: <...>; rel="next" header
            # rather than a body field.
            next_link = _next_link(response.headers.get("link"))
            if not next_link:
                break
            url = httpx.URL(f"https://{self.registry}").join(next_link).__str__()
        if not tags:
            raise VersionFetchError(f"no tags for {self.registry}/{self.repository}")
        return tags

    def _anonymous_token(self, client: httpx.Client, challenge: httpx.Response) -> str:
        header = challenge.headers.get("www-authenticate", "")
        realm = re.search(r'realm="([^"]+)"', header)
        if realm is None:
            raise VersionFetchError(
                f"{self.registry} demanded auth without a realm", hint=header
            )
        params = {"scope": f"repository:{self.repository}:pull"}
        service = re.search(r'service="([^"]+)"', header)
        if service is not None:
            params["service"] = service.group(1)
        payload = client.get(realm.group(1), params=params).json()
        token = payload.get("token") or payload.get("access_token")
        if not token:
            raise VersionFetchError(f"{self.registry} issued no anonymous token")
        return token


def _next_link(link_header: str | None) -> str | None:
    if not link_header:
        return None
    match = re.search(r'<([^>]+)>\s*;\s*rel="?next"?', link_header)
    return match.group(1) if match else None


@dataclass(frozen=True)
class DockerHubTags:
    """Tags from Docker Hub's public repository API."""

    repository: str
    # tryretool/backend carries ~2400 tags. Ordering by last_updated puts every
    # live release train's newest tag near the front, so a bounded walk is both
    # sufficient and far cheaper than paging the lot.
    max_pages: int = 10
    needs: str = "network access"

    def fetch(self, env: SourceEnv) -> list[str]:
        url = f"https://hub.docker.com/v2/repositories/{self.repository}/tags"
        params: dict[str, Any] | None = {"page_size": 100, "ordering": "last_updated"}
        tags: list[str] = []
        for _ in range(self.max_pages):
            response = _http_get(url, env, params=params)
            payload = response.json()
            tags.extend(result["name"] for result in payload.get("results", []))
            if not payload.get("next"):
                break
            url, params = payload["next"], None
        if not tags:
            raise VersionFetchError(f"no tags for {self.repository}")
        return tags


@dataclass(frozen=True)
class RdsPostgres:
    """Postgres engine versions RDS will actually accept, for this region."""

    needs: str = "AWS credentials"

    def fetch(self, env: SourceEnv) -> list[str]:
        client = env.boto3_client("rds")
        versions: list[str] = []
        try:
            # No IncludeAll: the default already returns only available engines.
            # Passing it would add ~200 deprecated versions that RDS refuses.
            for page in client.get_paginator("describe_db_engine_versions").paginate(
                Engine="postgres"
            ):
                versions.extend(
                    v["EngineVersion"]
                    for v in page.get("DBEngineVersions", [])
                    if v.get("Status", "available") == "available"
                )
        except (ClientError, BotoCoreError) as exc:
            raise VersionFetchError(str(exc), hint=_aws_hint(exc)) from exc
        return versions


@dataclass(frozen=True)
class EksCluster:
    """Kubernetes versions EKS offers under standard support."""

    needs: str = "AWS credentials"

    def fetch(self, env: SourceEnv) -> list[str]:
        client = env.boto3_client("eks")
        if not hasattr(client, "describe_cluster_versions"):
            raise VersionFetchError(
                "this botocore has no eks:DescribeClusterVersions",
                hint="uv will fetch a current boto3; check the PEP 723 pin",
            )
        versions: list[str] = []
        token: str | None = None
        try:
            while True:
                kwargs = {"nextToken": token} if token else {}
                page = client.describe_cluster_versions(**kwargs)
                versions.extend(
                    v["clusterVersion"]
                    for v in page.get("clusterVersions", [])
                    # Never propose a move onto extended support.
                    if v.get("versionStatus") == "STANDARD_SUPPORT"
                )
                token = page.get("nextToken")
                if not token:
                    break
        except (ClientError, BotoCoreError) as exc:
            raise VersionFetchError(str(exc), hint=_aws_hint(exc)) from exc
        return versions


def _aws_hint(exc: Exception) -> str:
    text = str(exc)
    if "credential" in text.lower() or "ProfileNotFound" in type(exc).__name__:
        return "configure AWS credentials (aws sso login / --aws-profile)"
    if "AccessDenied" in text or "UnauthorizedOperation" in text:
        return "the caller lacks the required Describe* permission"
    return "check --aws-region and credentials"


def _parse_iso_date(value: Any) -> date | None:
    """Parse an endoflife.date date field; None for absent or malformed."""
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


@dataclass(frozen=True)
class EndOfLife:
    """Cycles endoflife.date currently lists as released and not retired.

    Unofficial on purpose. Reading ARM for these instead would mean an Entra
    app registration or managed identity, a federated credential, Reader at
    subscription scope, and two registered resource providers — real
    ceremony for two lookups — so these components take the community-data
    tradeoff documented in COMPONENTS, and the nightly job stays Azure-free.
    """

    product: str
    # Days a release must be old before it is proposed. endoflife.date is
    # global while availability is regional, and a Kubernetes minor reaches
    # every AKS region over roughly the weeks after GA. The buffer trades
    # bump latency for bump safety.
    min_age_days: int = 30
    needs: str = "network access"

    def fetch(self, env: SourceEnv) -> list[str]:
        response = _http_get(f"https://endoflife.date/api/{self.product}.json", env)
        try:
            cycles = response.json()
        except json.JSONDecodeError as exc:
            raise VersionFetchError(
                f"unparseable JSON from endoflife.date: {exc}"
            ) from exc
        if not isinstance(cycles, list):
            raise VersionFetchError("unexpected payload from endoflife.date")

        today = date.today()
        floor = today - timedelta(days=self.min_age_days)
        versions: list[str] = []
        for cycle in cycles:
            name = cycle.get("cycle")
            release = _parse_iso_date(cycle.get("releaseDate"))
            eol = _parse_iso_date(cycle.get("eol"))
            # Not released yet, or released too recently to trust everywhere.
            if release is None or release > floor:
                continue
            # A null eol means the tracker has no date yet, not that the
            # cycle is gone; a past eol means retired.
            if eol is not None and eol <= today:
                continue
            if isinstance(name, str) and name:
                versions.append(name)
        if not versions:
            raise VersionFetchError(
                f"no live cycles for {self.product} on endoflife.date",
                hint=f"https://endoflife.date/api/{self.product}.json",
            )
        return versions


# ---------------------------------------------------------------------------
# Component registry
#
# The keys are the tokens written in the marker comments.
# ---------------------------------------------------------------------------

COMPONENTS: dict[str, VersionSource] = {
    # Helm charts.
    "cert-manager-chart": HelmChart("https://charts.jetstack.io", "cert-manager"),
    "external-secrets-chart": HelmChart(
        "https://charts.external-secrets.io", "external-secrets"
    ),
    "reloader-chart": HelmChart(
        "https://stakater.github.io/stakater-charts", "reloader"
    ),
    "alb-controller-chart": HelmChart(
        "https://aws.github.io/eks-charts", "aws-load-balancer-controller"
    ),
    "external-dns-chart": HelmChart(
        "https://kubernetes-sigs.github.io/external-dns/", "external-dns"
    ),
    "retool-chart": HelmChart("https://charts.retool.com", "retool"),
    "karpenter-chart": OciTags("public.ecr.aws", "karpenter/karpenter"),
    "agic-chart": OciTags(
        "mcr.microsoft.com", "azure-application-gateway/charts/ingress-azure"
    ),
    # Images. The *-image entries read the chart's appVersion from the same
    # index.yaml as the corresponding *-chart entry, so both lines carry the
    # chart constraint and cannot drift apart.
    "external-secrets-image": HelmChart(
        "https://charts.external-secrets.io", "external-secrets", field="appVersion"
    ),
    "reloader-image": HelmChart(
        "https://stakater.github.io/stakater-charts", "reloader", field="appVersion"
    ),
    "external-dns-image": HelmChart(
        "https://kubernetes-sigs.github.io/external-dns/",
        "external-dns",
        field="appVersion",
    ),
    "retool-image": DockerHubTags("tryretool/backend"),
    # Cloud platform versions.
    "eks-cluster": EksCluster(),
    "rds-postgres": RdsPostgres(),
    # Azure platform versions read endoflife.date's community API rather than
    # ARM, so the nightly job needs no Azure credentials at all. The costs,
    # accepted knowingly:
    #
    # aks-cluster — the data is global, not per-region; min_age_days holds a
    #   new minor back until every AKS region should have it. Only GA cycles
    #   are listed, so the isPreview filter the old az source needed has no
    #   counterpart here.
    # azure-postgres — the marker pins a bare major that advances by hand, so
    #   this mostly answers "is that major still offered"; once the cycle is
    #   retired the marker fails loudly and the major bump stays a human
    #   decision, as it should be.
    "aks-cluster": EndOfLife("azure-kubernetes-service"),
    "azure-postgres": EndOfLife("azure-database-for-postgresql"),
    # Deliberately absent:
    #
    # gke-cluster — there is no literal to bump. modules/gcp-gke pins via
    #   release_channel = "REGULAR" with cluster_version defaulting to "", and
    #   the two are mutually exclusive. The release channel already delegates
    #   version selection to Google; this would be a worse reimplementation.
    #
    # gcp-cloudsql-postgres — the Cloud SQL databaseVersion enum is a
    #   reservation list, not an availability list. It advertises POSTGRES_19
    #   and POSTGRES_20 with deprecated: false; neither exists. A source reading
    #   it would confidently write a version that fails at create time.
}


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

MARKER_RE = re.compile(
    r"^\s*#\s*AUTOUPDATE:\s*(?P<component>\S+)\s+(?P<constraint>\S+)\s*$"
)

# Matches one double-quoted HCL string, honouring backslash escapes.
QUOTED_RE = re.compile(r'"(?:[^"\\]|\\.)*"')


def _display(path: Path) -> str:
    """Path as the operator would type it, falling back to absolute."""
    try:
        return str(path.relative_to(Path.cwd()))
    except ValueError:
        return str(path)


@dataclass(frozen=True)
class Marker:
    """A resolved marker and the exact byte span its literal occupies."""

    path: Path
    line_number: int
    component: str
    constraint: Constraint
    literal: str
    start: int
    end: int

    @property
    def location(self) -> str:
        return f"{_display(self.path)}:{self.line_number}"


@dataclass(frozen=True)
class Problem:
    """A marker that could not even be read well enough to look up."""

    path: Path
    line_number: int
    component: str
    message: str

    @property
    def location(self) -> str:
        return f"{_display(self.path)}:{self.line_number}"


def iter_source_files(root: Path) -> list[Path]:
    """Every tracked .tf file under root.

    Deferring to git means the vendored .terraform/ trees and the scratch
    deployments/ directory are skipped for free, because both are gitignored.
    """
    try:
        completed = subprocess.run(
            ["git", "ls-files", "-z", "--", "*.tf"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError as exc:
        raise click.ClickException("git not found on PATH") from exc
    except subprocess.CalledProcessError as exc:
        raise click.ClickException(
            f"git ls-files failed in {root}: {exc.stderr.strip()}"
        ) from exc
    return [root / name for name in completed.stdout.split("\0") if name]


def scan_file(path: Path) -> tuple[list[Marker], list[Problem]]:
    text = path.read_text()
    lines = text.splitlines(keepends=True)

    offsets: list[int] = []
    running = 0
    for line in lines:
        offsets.append(running)
        running += len(line)

    markers: list[Marker] = []
    problems: list[Problem] = []
    claimed: dict[int, int] = {}

    for index, line in enumerate(lines):
        match = MARKER_RE.match(line)
        if match is None:
            continue
        number = index + 1
        component = match.group("component")

        # Bind the loop variables by default. fail is only ever called within
        # the iteration that defines it, but a closure that outlived its
        # iteration would read the loop's final values (B023).
        def fail(
            message: str, *, number: int = number, component: str = component
        ) -> None:
            problems.append(Problem(path, number, component, message))

        raw_constraint = match.group("constraint")
        constraint = parse_constraint(raw_constraint)
        if constraint is None:
            hint = ""
            if LITERAL_RE.match(raw_constraint) and raw_constraint[0].isalpha():
                # Easy mistake: writing "v1.x.x" because the literal reads
                # "v1.21.0". Constraints are numeric because matching ignores the
                # prefix; the literal's own prefix is reapplied when rendering.
                stripped = raw_constraint.lstrip(
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"
                )
                hint = f" (constraints carry no prefix — did you mean {stripped!r}?)"
            fail(f"unparseable constraint {raw_constraint!r}{hint}")
            continue

        target = _target_line(lines, index)
        if target is None:
            fail("no version literal follows this marker")
            continue
        if MARKER_RE.match(lines[target]):
            fail("stacked markers: another marker follows immediately")
            continue
        if target in claimed:
            fail(
                f"line {target + 1} is already claimed by the marker on "
                f"line {claimed[target]}"
            )
            continue

        # Exactly one quoted string is required. This holds for every version
        # literal in the repo, including `optional(string, "2.8.0")` — `string`
        # there is a bare HCL type keyword, not a quoted string. Do not relax
        # this to "the last quoted string"; the single-match rule is what stops
        # a misplaced marker from rewriting a description.
        quoted = list(QUOTED_RE.finditer(lines[target]))
        if len(quoted) != 1:
            fail(
                f"expected exactly one quoted string on line {target + 1}, "
                f"found {len(quoted)}"
            )
            continue

        literal = quoted[0].group()[1:-1]
        if parse_version(literal) is None:
            fail(f"{literal!r} on line {target + 1} is not a version literal")
            continue

        claimed[target] = number
        markers.append(
            Marker(
                path=path,
                line_number=target + 1,
                component=component,
                constraint=constraint,
                literal=literal,
                start=offsets[target] + quoted[0].start() + 1,
                end=offsets[target] + quoted[0].end() - 1,
            )
        )

    return markers, problems


def _target_line(lines: list[str], marker_index: int) -> int | None:
    """Index of the first following line that is neither blank nor a comment."""
    for index in range(marker_index + 1, len(lines)):
        stripped = lines[index].strip()
        if not stripped:
            continue
        if stripped.startswith("#") and not MARKER_RE.match(lines[index]):
            continue
        return index
    return None


def scan(root: Path) -> tuple[list[Marker], list[Problem]]:
    markers: list[Marker] = []
    problems: list[Problem] = []
    for path in iter_source_files(root):
        found, failed = scan_file(path)
        markers.extend(found)
        problems.extend(failed)
    return markers, problems


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

Status = Literal["current", "update", "error"]


@dataclass(frozen=True)
class Resolution:
    marker: Marker
    status: Status
    proposed: str | None = None
    note: str = ""


class Resolver:
    """Looks components up once, caching successes and failures alike.

    N markers on one component cost one request, and a broken source poisons
    only its own markers rather than aborting the run.
    """

    def __init__(self, env: SourceEnv) -> None:
        self.env = env
        self._cache: dict[str, list[str] | VersionFetchError] = {}

    def versions_for(self, component: str) -> list[str]:
        cached = self._cache.get(component)
        if cached is not None:
            if isinstance(cached, VersionFetchError):
                raise cached
            return cached

        source = COMPONENTS.get(component)
        if source is None:
            error = VersionFetchError(
                f"unknown component {component!r}",
                hint=f"known components: {', '.join(sorted(COMPONENTS))}",
            )
            self._cache[component] = error
            raise error

        try:
            versions = source.fetch(self.env)
        except VersionFetchError as exc:
            if exc.hint is None:
                exc.hint = f"needs {source.needs}"
            self._cache[component] = exc
            raise
        # Exception, not BaseException: a buggy source must not swallow Ctrl-C.
        except Exception as exc:
            wrapped = VersionFetchError(
                f"{type(exc).__name__}: {exc}", hint=f"needs {source.needs}"
            )
            self._cache[component] = wrapped
            raise wrapped from exc

        self._cache[component] = versions
        return versions


def resolve(markers: list[Marker], resolver: Resolver) -> list[Resolution]:
    resolutions: list[Resolution] = []
    for marker in markers:
        try:
            candidates = resolver.versions_for(marker.component)
            chosen = select_best(marker.constraint, candidates)
            # parse_version cannot return None here: scan_file drops any
            # marker whose literal is not version-shaped, so every marker
            # reaching this point carries a parseable literal.
            literal = parse_version(marker.literal)
            assert literal is not None
            proposed = render(shape_of(literal), chosen)
        except VersionFetchError as exc:
            note = str(exc) + (f" ({exc.hint})" if exc.hint else "")
            resolutions.append(Resolution(marker, "error", note=note))
            continue
        except ShapeError as exc:
            resolutions.append(Resolution(marker, "error", note=str(exc)))
            continue

        # Truncation can make a real upstream bump render identically — 16.13 to
        # upstream 16.14 is still "16" in a one-segment literal. Compare the
        # rendered string, so the table never promises a change we won't write.
        truncated = chosen.raw != proposed
        if proposed == marker.literal:
            note = (
                f"upstream {chosen.raw}, truncated to {proposed}" if truncated else ""
            )
            resolutions.append(Resolution(marker, "current", note=note))
        else:
            note = f"from upstream {chosen.raw}" if truncated else ""
            resolutions.append(
                Resolution(marker, "update", proposed=proposed, note=note)
            )
    return resolutions


# ---------------------------------------------------------------------------
# Rewriting
# ---------------------------------------------------------------------------


def apply_updates(resolutions: list[Resolution]) -> tuple[int, list[Problem]]:
    """Rewrite every literal marked for update. Returns (files written, failures).

    Edits are byte spans applied in descending offset order, one read and one
    write per file, so indentation, `=` alignment, trailing comments, line
    endings and a missing final newline all survive untouched.
    """
    by_file: dict[Path, list[Resolution]] = {}
    for resolution in resolutions:
        if resolution.status == "update":
            by_file.setdefault(resolution.marker.path, []).append(resolution)

    written = 0
    failures: list[Problem] = []
    for path, pending in by_file.items():
        try:
            text = path.read_text()
            for resolution in sorted(
                pending, key=lambda r: r.marker.start, reverse=True
            ):
                marker = resolution.marker
                assert resolution.proposed is not None
                if text[marker.start : marker.end] != marker.literal:
                    raise RuntimeError(
                        f"line {marker.line_number} changed since it was scanned"
                    )
                text = text[: marker.start] + resolution.proposed + text[marker.end :]
            temporary = path.with_name(f".{path.name}.autoupdate")
            temporary.write_text(text)
            os.replace(temporary, path)
            written += 1
        except (OSError, RuntimeError) as exc:
            failures.append(Problem(path, 0, "-", f"write failed: {exc}"))
    return written, failures


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

STATUS_STYLE: dict[Status, str] = {"current": "dim", "update": "green", "error": "red"}


def build_table(resolutions: list[Resolution], problems: list[Problem]) -> Table:
    table = Table(box=None, pad_edge=False, header_style="bold")
    for column in ("Component", "Location", "Current", "Proposed", "Note"):
        table.add_column(column, overflow="fold")

    for resolution in sorted(
        resolutions, key=lambda r: (r.marker.component, str(r.marker.path))
    ):
        marker = resolution.marker
        table.add_row(
            marker.component,
            marker.location,
            marker.literal,
            resolution.proposed or "-",
            resolution.note,
            style=STATUS_STYLE[resolution.status],
        )
    for problem in sorted(problems, key=lambda p: (str(p.path), p.line_number)):
        table.add_row(
            problem.component, problem.location, "-", "-", problem.message, style="red"
        )
    return table


def as_json(resolutions: list[Resolution], problems: list[Problem]) -> str:
    return json.dumps(
        {
            "updates": [
                {
                    "component": r.marker.component,
                    "path": str(r.marker.path),
                    "line": r.marker.line_number,
                    "current": r.marker.literal,
                    "proposed": r.proposed,
                    "status": r.status,
                    "note": r.note,
                }
                for r in resolutions
            ],
            "problems": [
                {
                    "component": p.component,
                    "path": str(p.path),
                    "line": p.line_number,
                    "message": p.message,
                }
                for p in problems
            ],
        },
        indent=2,
    )


def _md_cell(text: str) -> str:
    """Escape a value for a Markdown table cell."""
    # A pipe would end the cell, and notes carry free text and error messages
    # that can contain anything.
    return text.replace("|", "\\|").replace("\n", " ")


def as_markdown(resolutions: list[Resolution], problems: list[Problem]) -> str:
    """Render the outcome as Markdown, for a pull request body.

    Built with plain string joins rather than rich: rich sizes a table to the
    terminal, or to 80 columns when there is no terminal as in CI, and would
    fold a Markdown table into unparseable fragments.
    """
    updates = [r for r in resolutions if r.status == "update"]
    errors = [r for r in resolutions if r.status == "error"]
    current = [r for r in resolutions if r.status == "current"]
    out: list[str] = []

    if updates:
        out += [
            "### Bumped",
            "",
            "| Component | Location | From | To | Note |",
            "| --- | --- | --- | --- | --- |",
        ]
        for r in sorted(
            updates, key=lambda r: (r.marker.component, str(r.marker.path))
        ):
            out.append(
                f"| `{r.marker.component}` | `{r.marker.location}` "
                f"| `{r.marker.literal}` | `{r.proposed}` | {_md_cell(r.note)} |"
            )
        out.append("")

    if errors or problems:
        out += [
            "### Failed",
            "",
            "| Component | Location | Current | Error |",
            "| --- | --- | --- | --- |",
        ]
        for r in sorted(errors, key=lambda r: (r.marker.component, str(r.marker.path))):
            out.append(
                f"| `{r.marker.component}` | `{r.marker.location}` "
                f"| `{r.marker.literal}` | {_md_cell(r.note)} |"
            )
        for pr in sorted(problems, key=lambda p: (str(p.path), p.line_number)):
            out.append(
                f"| `{pr.component}` | `{pr.location}` | - | {_md_cell(pr.message)} |"
            )
        out.append("")

    if current:
        out += [
            f"<details><summary>{len(current)} marker(s) already current</summary>",
            "",
            "| Component | Location | Version | Note |",
            "| --- | --- | --- | --- |",
        ]
        for r in sorted(
            current, key=lambda r: (r.marker.component, str(r.marker.path))
        ):
            out.append(
                f"| `{r.marker.component}` | `{r.marker.location}` "
                f"| `{r.marker.literal}` | {_md_cell(r.note)} |"
            )
        out += ["", "</details>"]

    if not resolutions and not problems:
        out.append("No `# AUTOUPDATE:` markers were found.")
    else:
        counts = [
            f"{len(resolutions) + len(problems)} marker(s)",
            f"{len(updates)} changed",
        ]
        if errors or problems:
            counts.append(f"**{len(errors) + len(problems)} failed**")
        out += ["", ", ".join(counts) + "."]
    return "\n".join(out).rstrip() + "\n"


def as_commit_message(resolutions: list[Resolution], problems: list[Problem]) -> str:
    """Render the bumped markers as a plain-text git commit message.

    Derived from the same Outcome as the Markdown report, so a workflow that
    writes one into a commit and the other into the PR body can never show
    them disagreeing. Kept deliberately plain — no Markdown tables or
    emphasis — since this is what lands in the commit history. Identical
    (component, from → to) bumps that recur across several locations are
    grouped onto one line so a component pinned in many example files does
    not swamp the message.
    """
    updates = [r for r in resolutions if r.status == "update"]
    if not updates:
        return ""

    # Group by the version move, preserving first-seen order. Bumps that
    # share component/from/to but live in different files (the retool chart
    # and image pinned in every example) collapse to one line each.
    # r.note is optional, so None normalizes to "" for the dict key; a bump
    # always has a concrete proposed version, but the field is typed optional.
    groups: dict[tuple[str, str, str | None, str], list[Resolution]] = {}
    for r in updates:
        key = (r.marker.component, r.marker.literal, r.proposed, r.note or "")
        groups.setdefault(key, []).append(r)

    out: list[str] = []
    for (component, from_v, to_v, note), rs in sorted(
        groups.items(), key=lambda kv: (kv[0][0], str(kv[1][0].marker.path))
    ):
        locations = sorted(r.marker.location for r in rs)
        if len(locations) == 1:
            where = f" ({locations[0]})"
        elif len(locations) == 2:
            where = f" ({locations[0]}; {locations[1]})"
        else:
            where = f" ({len(locations)} locations: {locations[0]}, …)"
        line = f"- {component}: {from_v} → {to_v}{where}"
        if note:
            line += f" — {note}"
        out.append(line)
    out.append("")
    out.append("Components: " + ", ".join(sorted({r.marker.component for r in updates})))
    failures = len([r for r in resolutions if r.status == "error"]) + len(problems)
    if failures:
        out.append(f"\n({failures} marker(s) failed to resolve this run — see the job log.)")
    return "\n".join(out).rstrip() + "\n"


# Named render_report, not render: render() above is the version-shape renderer,
# and a second module-level render() would shadow it at call time.
def render_report(outcome: Outcome, output_format: str) -> str:
    """The outcome in one of the file formats. `table` is rendered by rich."""
    if output_format == "json":
        return as_json(outcome.resolutions, outcome.problems)
    if output_format == "markdown":
        return as_markdown(outcome.resolutions, outcome.problems)
    if output_format == "commit":
        return as_commit_message(outcome.resolutions, outcome.problems)
    raise ValueError(f"not a file format: {output_format!r}")


@dataclass(frozen=True)
class Outcome:
    resolutions: list[Resolution]
    problems: list[Problem]

    @property
    def updates(self) -> list[Resolution]:
        return [r for r in self.resolutions if r.status == "update"]

    @property
    def failures(self) -> int:
        return len([r for r in self.resolutions if r.status == "error"]) + len(
            self.problems
        )


def run(root: Path, env: SourceEnv) -> Outcome:
    markers, problems = scan(root)
    return Outcome(resolve(markers, Resolver(env)), problems)


def summarize(outcome: Outcome, *, verb: str) -> str:
    parts = [
        f"{len(outcome.resolutions)} marker(s)",
        f"{len(outcome.updates)} {verb}",
    ]
    if outcome.failures:
        parts.append(f"[red]{outcome.failures} failed[/red]")
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent


@click.group(
    context_settings={"help_option_names": ["-h", "--help"]},
    invoke_without_command=True,
)
@click.option(
    "--root",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    default=REPO_ROOT,
    show_default="the repository root",
    help="Directory to scan for AUTOUPDATE markers.",
)
@click.option(
    "--aws-region",
    default="us-east-1",
    show_default=True,
    help="Region for the RDS and EKS lookups.",
)
@click.option("--aws-profile", default=None, help="AWS CLI profile to use.")
@click.option(
    "--timeout", default=60, show_default=True, help="Per-request timeout in seconds."
)
@click.pass_context
def cli(
    ctx: click.Context,
    root: Path,
    aws_region: str,
    aws_profile: str | None,
    timeout: int,
) -> None:
    """Bump the version literals carrying an AUTOUPDATE marker."""
    ctx.obj = {
        "root": root,
        "env": SourceEnv(
            aws_region=aws_region,
            aws_profile=aws_profile,
            timeout=timeout,
        ),
    }
    if ctx.invoked_subcommand is None:
        ctx.invoke(update)


# Shared by both subcommands. --format picks what goes to stdout; --report-path
# additionally writes that rendering to a file, which is how the CI workflow gets
# a pull request body out of the same single pass that does the writing.
FORMAT_OPTION = click.option(
    "--format",
    "output_format",
    type=click.Choice(["table", "json", "markdown"]),
    default="table",
    show_default=True,
    help="Output format.",
)
REPORT_PATH_OPTION = click.option(
    "--report-path",
    type=click.Path(dir_okay=False, writable=True, path_type=Path),
    default=None,
    help=(
        "Also write the report to this file, in --format (markdown when "
        "--format is table, since a rich table is not a file format)."
    ),
)


# Internal format choices for the CI workflow, not for the interactive
# --format flag: `commit` produces a plain-text commit message from the same
# pass that produces the Markdown PR body, so the bumps land in the commit
# history without a second run (which would double every upstream call and
# could disagree with the body if a release landed between runs). Keyed by
# output path so the two are orthogonal to --format.
COMMIT_MESSAGE_PATH_OPTION = click.option(
    "--commit-message-path",
    type=click.Path(dir_okay=False, writable=True, path_type=Path),
    default=None,
    help=(
        "Also write a plain-text commit message listing the bumped versions "
        "to this file, for the workflow to feed to create-pull-request's "
        "commit-message-path."
    ),
)


def emit(
    outcome: Outcome,
    output_format: str,
    report_path: Path | None,
    *,
    verb: str,
    commit_message_path: Path | None = None,
) -> None:
    """Print the outcome, and write the files the optional paths name."""
    if output_format == "table":
        console.print(build_table(outcome.resolutions, outcome.problems))
        console.print()
        console.print(summarize(outcome, verb=verb))
    else:
        # click.echo, not console.print: rich would wrap and style JSON and
        # Markdown to the terminal width, corrupting both.
        click.echo(render_report(outcome, output_format))
    if report_path is not None:
        report_path.write_text(
            render_report(
                outcome, "markdown" if output_format == "table" else output_format
            )
        )
    if commit_message_path is not None:
        commit_message_path.write_text(
            as_commit_message(outcome.resolutions, outcome.problems)
        )


@cli.command("report")
@FORMAT_OPTION
@REPORT_PATH_OPTION
@click.pass_context
def report(ctx: click.Context, output_format: str, report_path: Path | None) -> None:
    """Show what would change, without writing anything."""
    outcome = run(ctx.obj["root"], ctx.obj["env"])
    emit(outcome, output_format, report_path, verb="would change")
    # The report has already said which markers failed and why, so exit bare
    # rather than via ClickException, whose "Error: ..." line would add nothing.
    if outcome.failures:
        raise SystemExit(1)


@cli.command("update")
@FORMAT_OPTION
@REPORT_PATH_OPTION
@COMMIT_MESSAGE_PATH_OPTION
@click.pass_context
def update(
    ctx: click.Context,
    output_format: str,
    report_path: Path | None,
    commit_message_path: Path | None,
) -> None:
    """Rewrite every out-of-date literal in place."""
    outcome = run(ctx.obj["root"], ctx.obj["env"])
    # Report before writing, so an interrupted run still leaves a full report,
    # and so --report-path describes the change even if a write then fails.
    emit(
        outcome,
        output_format,
        report_path,
        verb="changed",
        commit_message_path=commit_message_path,
    )

    written, write_failures = apply_updates(outcome.resolutions)
    for failure in write_failures:
        err_console.print(f"[red]{failure.location}: {failure.message}[/red]")

    console.print(f"Wrote {written} file(s)." if written else "Nothing to change.")
    if outcome.failures or write_failures:
        raise SystemExit(1)


def main() -> None:
    try:
        cli(obj={})
    except KeyboardInterrupt:
        err_console.print("\nInterrupted.")
        sys.exit(130)


if __name__ == "__main__":
    main()
