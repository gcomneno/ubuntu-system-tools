#!/usr/bin/env bash
set -euo pipefail

TOOL="$(cd "$(dirname -- "$0")/.." && pwd)/bin/garbage-collector"

echo "== Test: --help"
"$TOOL" --help >/dev/null

echo "== Test: E2E tmp workspace"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/repoA/.venv/lib/python3.12/site-packages" \
  "$TMP/repoA/src/__pycache__" \
  "$TMP/repoB/node_modules" \
  "$TMP/repoC/target" \
  "$TMP/repoD/.pytest_cache" \
  "$TMP/repoE/dist" \
  "$TMP/repoF/pkg.egg-info"

dd if=/dev/zero of="$TMP/repoA/.venv/blob" bs=1M count=2 status=none
dd if=/dev/zero of="$TMP/repoB/node_modules/blob" bs=1M count=1 status=none
dd if=/dev/zero of="$TMP/repoC/target/blob" bs=1M count=1 status=none

OUT="$("$TOOL" "$TMP" --max-depth 4)"

echo "$OUT" | grep -F ".venv" >/dev/null
echo "$OUT" | grep -F "node_modules" >/dev/null
echo "$OUT" | grep -F "target" >/dev/null
echo "$OUT" | grep -F "__pycache__" >/dev/null
echo "$OUT" | grep -F ".pytest_cache" >/dev/null
echo "$OUT" | grep -F "dist" >/dev/null
echo "$OUT" | grep -F "pkg.egg-info" >/dev/null
echo "$OUT" | grep -F "Potentially reclaimable:" >/dev/null

test -d "$TMP/repoA/.venv"
test -d "$TMP/repoB/node_modules"
test -d "$TMP/repoC/target"

echo "== Test: --min-bytes"
OUT_MIN="$("$TOOL" "$TMP" --max-depth 4 --min-bytes 1500000)"

echo "$OUT_MIN" | grep -F ".venv" >/dev/null

if echo "$OUT_MIN" | grep -F "node_modules" >/dev/null; then
  echo "Expected node_modules to be filtered out by --min-bytes" >&2
  exit 1
fi

echo "OK ✅"
