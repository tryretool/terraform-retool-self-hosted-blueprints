#!/usr/bin/env python3
"""Create or delete a Cloud SQL instance, waiting out transient INTERNAL_ERROR.

The google Terraform provider treats a SQL operation that is still RUNNING but
carries error.code=INTERNAL_ERROR as fatal (empty "Error waiting for Create
Instance:"). GCP often keeps building the instance and marks the same operation
DONE a few minutes later. This script keeps polling in that situation, and
treats an already-existing instance as success so a Marketplace retry can adopt
an orphan left by a failed provider wait.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://sqladmin.googleapis.com/sql/v1beta4"
POLL_SECONDS = 10
WAIT_SECONDS = 30 * 60


def token() -> str:
    env = os.environ.get("SQL_TOKEN", "").strip()
    if env:
        return env
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.load(resp)["access_token"]
    except Exception as meta_err:
        # Last resort when not on GCE/Cloud Build (local apply with ADC/gcloud).
        import subprocess

        try:
            return subprocess.check_output(
                ["gcloud", "auth", "print-access-token"],
                text=True,
            ).strip()
        except Exception as gcloud_err:
            raise SystemExit(
                f"no access token (SQL_TOKEN unset, metadata: {meta_err}, gcloud: {gcloud_err})"
            )


def request(method: str, url: str, body: dict | None = None) -> tuple[int, dict]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"error": {"message": raw.decode("utf-8", "replace")}}
        return err.code, payload


def project() -> str:
    value = os.environ.get("SQL_PROJECT", "").strip()
    if not value:
        raise SystemExit("SQL_PROJECT is required")
    return value


def name() -> str:
    value = os.environ.get("SQL_NAME", "").strip()
    if not value:
        raise SystemExit("SQL_NAME is required")
    return value


def get_instance(proj: str, inst: str) -> tuple[int, dict]:
    return request("GET", f"{API}/projects/{proj}/instances/{inst}")


def wait_until_runnable(proj: str, inst: str) -> dict:
    deadline = time.time() + WAIT_SECONDS
    last = {}
    while time.time() < deadline:
        status, body = get_instance(proj, inst)
        last = body
        if status == 200 and body.get("state") == "RUNNABLE":
            print(f"instance {inst} is RUNNABLE", flush=True)
            return body
        if status == 200:
            print(f"instance {inst} state={body.get('state')}", flush=True)
        elif status == 404:
            print(f"instance {inst} not found yet", flush=True)
        else:
            print(f"get instance HTTP {status}: {body}", flush=True)
        time.sleep(POLL_SECONDS)
    raise SystemExit(f"timed out waiting for {inst} to become RUNNABLE: {last}")


def wait_operation(proj: str, op_name: str) -> dict:
    deadline = time.time() + WAIT_SECONDS
    url = f"{API}/projects/{proj}/operations/{op_name}"
    last = {}
    while time.time() < deadline:
        status, body = request("GET", url)
        last = body
        if status != 200:
            print(f"get operation HTTP {status}: {body}", flush=True)
            time.sleep(POLL_SECONDS)
            continue
        op_status = body.get("status")
        errors = (body.get("error") or {}).get("errors") or []
        codes = [e.get("code") for e in errors]
        print(f"operation {op_name} status={op_status} errors={codes}", flush=True)
        if op_status == "DONE":
            if errors and not _only_transient(codes):
                raise SystemExit(f"operation failed: {body}")
            return body
        # RUNNING (or UNKNOWN) with INTERNAL_ERROR is the provider bug: keep polling.
        time.sleep(POLL_SECONDS)
    raise SystemExit(f"timed out waiting for operation {op_name}: {last}")


def _only_transient(codes: list) -> bool:
    return bool(codes) and all(c in ("INTERNAL_ERROR", None, "") for c in codes)


def upsert() -> None:
    proj, inst = project(), name()
    status, body = get_instance(proj, inst)
    if status == 200:
        print(f"instance {inst} already exists (state={body.get('state')})", flush=True)
        wait_until_runnable(proj, inst)
        return
    if status not in (404,):
        raise SystemExit(f"get instance HTTP {status}: {body}")

    spec = json.loads(os.environ.get("SQL_BODY", "{}"))
    spec["name"] = inst
    print(f"creating instance {inst}", flush=True)
    status, body = request("POST", f"{API}/projects/{proj}/instances", spec)
    if status in (200, 201):
        op_name = body.get("name")
        if not op_name:
            raise SystemExit(f"insert returned no operation: {body}")
        wait_operation(proj, op_name)
        wait_until_runnable(proj, inst)
        return
    if status == 409:
        print(f"instance {inst} appeared during insert (409); waiting", flush=True)
        wait_until_runnable(proj, inst)
        return
    raise SystemExit(f"insert HTTP {status}: {body}")


def delete() -> None:
    proj, inst = project(), name()
    status, body = get_instance(proj, inst)
    if status == 404:
        print(f"instance {inst} already gone", flush=True)
        return
    if status != 200:
        raise SystemExit(f"get instance HTTP {status}: {body}")
    print(f"deleting instance {inst}", flush=True)
    status, body = request("DELETE", f"{API}/projects/{proj}/instances/{inst}")
    if status in (200, 201):
        op_name = body.get("name")
        if op_name:
            wait_operation(proj, op_name)
        return
    if status == 404:
        print(f"instance {inst} already gone", flush=True)
        return
    raise SystemExit(f"delete HTTP {status}: {body}")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("upsert", "delete"):
        raise SystemExit(f"usage: {sys.argv[0]} upsert|delete")
    {"upsert": upsert, "delete": delete}[sys.argv[1]]()


if __name__ == "__main__":
    main()
