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
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
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
    first, and AKS orders patch versions lexicographically (where 1.34.9 sorts
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
    azure_location: str
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

    needs: str
    """Prerequisite named in error rows, e.g. "AWS credentials"."""

    def fetch(self, env: SourceEnv) -> list[str]:
        """Every candidate version, spelled exactly as upstream spells it.

        Order is not significant — selection happens downstream. Raise
        VersionFetchError for anything that prevents answering.
        """


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


def _az(args: list[str], env: SourceEnv) -> Any:
    """Run an `az` command and return its parsed JSON stdout.

    stdout and stderr are kept separate on purpose: az writes WARNING: lines to
    stderr on several of these commands, and merging would corrupt the JSON.
    """
    if shutil.which("az") is None:
        raise VersionFetchError("az not found on PATH", hint="brew install azure-cli")
    try:
        completed = subprocess.run(
            ["az", *args, "-o", "json", "--only-show-errors"],
            capture_output=True,
            text=True,
            timeout=env.timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise VersionFetchError(f"az timed out after {env.timeout}s") from exc
    if completed.returncode != 0:
        lines = [ln for ln in completed.stderr.strip().splitlines() if ln.strip()]
        raise VersionFetchError(
            lines[-1] if lines else f"az exited {completed.returncode}",
            hint="az login, and check --azure-location",
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise VersionFetchError(f"unparseable JSON from az: {exc}") from exc


@dataclass(frozen=True)
class AksCluster:
    """Kubernetes versions AKS offers in a location, excluding previews."""

    needs: str = "az login"

    def fetch(self, env: SourceEnv) -> list[str]:
        payload = _az(["aks", "get-versions", "--location", env.azure_location], env)
        return [
            entry["version"]
            for entry in payload.get("values", [])
            if not entry.get("isPreview")
        ]


@dataclass(frozen=True)
class AzurePostgres:
    """Postgres major versions Flexible Server offers in a location."""

    needs: str = "az login"

    def fetch(self, env: SourceEnv) -> list[str]:
        payload = _az(
            [
                "postgres",
                "flexible-server",
                "list-skus",
                "--location",
                env.azure_location,
            ],
            env,
        )
        versions = [
            supported["name"]
            for entry in payload
            for supported in entry.get("supportedServerVersions", [])
        ]
        if not versions:
            # An empty list here means the region is restricted for provisioning,
            # not that Postgres has no versions. Failing loudly beats a no-op.
            raise VersionFetchError(
                f"no server versions offered in {env.azure_location}",
                hint="provisioning may be restricted in this region; try another",
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
    "aks-cluster": AksCluster(),
    "rds-postgres": RdsPostgres(),
    "azure-postgres": AzurePostgres(),
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

        def fail(message: str) -> None:
            problems.append(Problem(path, number, component, message))

        raw_constraint = match.group("constraint")
        constraint = parse_constraint(raw_constraint)
        if constraint is None:
            hint = ""
            if LITERAL_RE.match(raw_constraint) and raw_constraint[0].isalpha():
                # Easy mistake: writing "v1.x.x" because the literal reads
                # "v1.21.0". Constraints are numeric because matching ignores the
                # prefix; the literal's own prefix is reapplied when rendering.
                hint = f" (constraints carry no prefix — did you mean {raw_constraint.lstrip('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-')!r}?)"
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
                f"line {target + 1} is already claimed by the marker on line {claimed[target]}"
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
                f"expected exactly one quoted string on line {target + 1}, found {len(quoted)}"
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
            proposed = render(shape_of(parse_version(marker.literal)), chosen)
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
    "--azure-location",
    default="eastus2",
    show_default=True,
    help="Location for the AKS and Azure Postgres lookups.",
)
@click.option(
    "--timeout", default=60, show_default=True, help="Per-request timeout in seconds."
)
@click.pass_context
def cli(
    ctx: click.Context,
    root: Path,
    aws_region: str,
    aws_profile: str | None,
    azure_location: str,
    timeout: int,
) -> None:
    """Bump the version literals carrying an AUTOUPDATE marker."""
    ctx.obj = {
        "root": root,
        "env": SourceEnv(
            aws_region=aws_region,
            aws_profile=aws_profile,
            azure_location=azure_location,
            timeout=timeout,
        ),
    }
    if ctx.invoked_subcommand is None:
        ctx.invoke(update)


@cli.command("report")
@click.option(
    "--format",
    "output_format",
    type=click.Choice(["table", "json"]),
    default="table",
    show_default=True,
    help="Output format.",
)
@click.pass_context
def report(ctx: click.Context, output_format: str) -> None:
    """Show what would change, without writing anything."""
    outcome = run(ctx.obj["root"], ctx.obj["env"])
    if output_format == "json":
        console.print_json(as_json(outcome.resolutions, outcome.problems))
    else:
        console.print(build_table(outcome.resolutions, outcome.problems))
        console.print()
        console.print(summarize(outcome, verb="would change"))
    # The table has already said which markers failed and why, so exit bare
    # rather than via ClickException, whose "Error: ..." line would add nothing.
    if outcome.failures:
        raise SystemExit(1)


@cli.command("update")
@click.pass_context
def update(ctx: click.Context) -> None:
    """Rewrite every out-of-date literal in place."""
    outcome = run(ctx.obj["root"], ctx.obj["env"])
    # Print before writing, so an interrupted run still leaves a full report.
    console.print(build_table(outcome.resolutions, outcome.problems))
    console.print()

    written, write_failures = apply_updates(outcome.resolutions)
    for failure in write_failures:
        err_console.print(f"[red]{failure.location}: {failure.message}[/red]")

    console.print(summarize(outcome, verb="changed"))
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
