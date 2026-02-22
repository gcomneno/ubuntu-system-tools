#!/usr/bin/env bash
set -euo pipefail

TOOL="$(cd "$(dirname -- "$0")/.." && pwd)/bin/hdd_cleanup"

echo "== Test: --help"
"$TOOL" --help >/dev/null

echo "== Test: --help-md"
"$TOOL" --help-md | head -n 5 >/dev/null

echo "== Test: refuse without --apply"
set +e
"$TOOL" purge-junk --root /tmp >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "Expected exit=2, got $rc" >&2
  exit 1
fi

echo "== Test: E2E tmp workspace"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p       "$TMP/repoA/target"       "$TMP/repoA/.venv/lib/python3.12/site-packages/__pycache__"       "$TMP/repoA/src/__pycache__"       "$TMP/repoB/node_modules"       "$TMP/repoB/.pytest_cache"

dd if=/dev/zero of="$TMP/repoA/target/blob" bs=1M count=5 status=none
dd if=/dev/zero of="$TMP/repoB/node_modules/blob" bs=1M count=3 status=none

"$TOOL" report-junk --root "$TMP" --summary >/dev/null
"$TOOL" purge-junk --root "$TMP" --apply --summary >/dev/null

test ! -d "$TMP/repoA/target"
test ! -d "$TMP/repoA/.venv"
test ! -d "$TMP/repoB/node_modules"
test ! -d "$TMP/repoB/.pytest_cache"

echo "== Test: --exclude"
TMP2="$(mktemp -d)"
trap 'rm -rf "$TMP2"' EXIT
mkdir -p "$TMP2/keepme/.venv" "$TMP2/deleteme/.venv"
"$TOOL" purge-junk --root "$TMP2" --exclude keepme --apply >/dev/null
test -d "$TMP2/keepme/.venv"
test ! -d "$TMP2/deleteme/.venv"

echo "OK ✅"
