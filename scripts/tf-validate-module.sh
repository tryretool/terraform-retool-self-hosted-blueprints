#!/usr/bin/env bash
# Validate a single Terraform module directory.
#
# Invoked once per directory by `make validate` via GNU parallel, which supplies
# the per-line `<dir>:` prefix (--tagstring) and keeps each module's output
# contiguous and in order (--group --keep-order).
#
# Output contract: print nothing when the module is valid, and the failing
# command's full output when it is not. Each stage's output is captured
# so that a validate failure is not buried under init's success chatter.
set -uo pipefail

dir="${1%/}"
: "${TF:=terraform}"
: "${TF_PLUGIN_CACHE_DIR:?must be set (make validate sets it)}"

# Serialize `terraform init` across modules by locking the shared provider
# cache. Terraform's plugin cache is not concurrency-safe: parallel inits race
# writing it and hand back truncated provider binaries, which surface as
# "Failed to load plugin schemas", "Unrecognized remote plugin message", or
# dependency-lock checksum mismatches. Only init writes the cache, so
# `validate` below stays parallel and overlaps with other modules' inits.
if ! out=$(flock -x "$TF_PLUGIN_CACHE_DIR" \
  "$TF" -chdir="$dir" init -backend=false -input=false -no-color 2>&1); then
  printf '%s\n' "$out"
  exit 1
fi

if ! out=$("$TF" -chdir="$dir" validate -no-color 2>&1); then
  printf '%s\n' "$out"
  exit 1
fi

# On success, print nothing, to keep logs as clean as possible.
