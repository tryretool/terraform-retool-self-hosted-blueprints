#!/usr/bin/env bash
set -euo pipefail

USAGE="Usage: scripts/update-example-versions.sh <new-version>

Bumps the \`version = \"...\"\` constraint on every module block in examples/
whose \`source\` references tryretool/self-hosted-blueprints, preserving
whatever constraint operator (~>, =, or none) was already there.

Example: scripts/update-example-versions.sh 0.4"

NEW_VERSION="${1:?$USAGE}"
EXAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/examples"

find "$EXAMPLES_DIR" -type f -name '*.tf' | while IFS= read -r file; do
  tmp="$(mktemp)"
  awk -v new_version="$NEW_VERSION" '
    BEGIN { in_module = 0; is_retool = 0 }
    {
      line = $0

      if (!in_module) {
        if (line ~ /^[[:space:]]*module[[:space:]]+"[^"]+"[[:space:]]*\{/) {
          in_module = 1
          is_retool = 0
        }
        print line
        next
      }

      if (line ~ /^\}[[:space:]]*$/) {
        in_module = 0
        is_retool = 0
        print line
        next
      }

      if (line ~ /^[[:space:]]*source[[:space:]]*=[[:space:]]*"tryretool\/self-hosted-blueprints/) {
        is_retool = 1
      }

      if (is_retool && line ~ /^[[:space:]]*version[[:space:]]*=/) {
        if (match(line, /[0-9]+\.[0-9]+(\.[0-9]+)?/)) {
          line = substr(line, 1, RSTART - 1) new_version substr(line, RSTART + RLENGTH)
        }
      }

      print line
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
done

echo "Bumped tryretool/self-hosted-blueprints module versions to ${NEW_VERSION} under ${EXAMPLES_DIR}"
