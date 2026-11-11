#!/usr/bin/env bash
set -euo pipefail

USAGE="Usage: scripts/version-compare.sh <version-a> <version-b>

Compares two semver versions (leading 'v' optional) and prints:
  -1  if a < b
   0  if a == b
   1  if a > b

Example: scripts/version-compare.sh v0.5.3 0.6.0  # prints -1"

A="${1:?$USAGE}"
B="${2:?$USAGE}"
A="${A#v}"
B="${B#v}"

if [ "$A" = "$B" ]; then
  echo 0
  exit 0
fi

# GNU sort -V (version sort) orders semver correctly; the lower of the two
# comes first.
lowest="$(printf '%s\n%s\n' "$A" "$B" | sort -V | head -1)"
if [ "$lowest" = "$A" ]; then
  echo -1
else
  echo 1
fi
