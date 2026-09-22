#!/usr/bin/env bash

# Assemble a Marketplace Terraform zip: root files at the zip root (no wrapping
# folder) plus the GCP / retool-helm modules. Rewrites module sources from
# ../../modules/... to ./modules/... so the zip is self-contained.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/marketplace/gcp"
OUT="${1:-$SRC/retool-blueprints-tf.zip}"
# zip runs from STAGE; make OUT absolute so relative paths still land under the repo.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp "$SRC"/versions.tf "$SRC"/providers.tf "$SRC"/variables.tf \
  "$SRC"/main.tf "$SRC"/helm.tf "$SRC"/outputs.tf \
  "$SRC"/schema.yaml "$SRC"/marketplace_test.tfvars \
  "$SRC"/metadata.yaml "$SRC"/metadata.display.yaml \
  "$SRC"/README.md \
  "$STAGE/"

mkdir -p "$STAGE/modules"
for module in gcp-vpc gcp-gke gcp-database gcp-retool-services gcp-user-ingress retool-helm; do
  cp -R "$ROOT/modules/$module" "$STAGE/modules/"
done

find "$STAGE" -type d -name '.terraform' -exec rm -rf {} +
find "$STAGE" -name '.terraform.lock.hcl' -delete
find "$STAGE" -name '.DS_Store' -delete

perl -pi -e 's|source = "../../modules/|source = "./modules/|g' \
  "$STAGE/main.tf" "$STAGE/helm.tf"

rm -f "$OUT"
(cd "$STAGE" && zip -r "$OUT" .)
echo "Wrote $OUT"
unzip -l "$OUT" | head -40
