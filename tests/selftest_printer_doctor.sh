#!/usr/bin/env bash
set -euo pipefail

SCRIPT="bin/printer-doctor"

[[ -x "$SCRIPT" ]] || {
  echo "FAIL: $SCRIPT is not executable" >&2
  exit 1
}

"$SCRIPT" --help >/tmp/printer-doctor-help.txt
grep -q "printer-doctor" /tmp/printer-doctor-help.txt
grep -q "status" /tmp/printer-doctor-help.txt
grep -q "repair" /tmp/printer-doctor-help.txt

"$SCRIPT" --help-md >/tmp/printer-doctor-help-md.txt
grep -q "# printer-doctor" /tmp/printer-doctor-help-md.txt
grep -q "vendor-agnostic" /tmp/printer-doctor-help-md.txt
grep -q "No cartridge cleaning" /tmp/printer-doctor-help-md.txt

set +e
"$SCRIPT" >/tmp/printer-doctor-empty.txt 2>/tmp/printer-doctor-empty.err
rc=$?
set -e
[[ "$rc" -eq 2 ]] || {
  echo "FAIL: empty invocation should exit 2, got $rc" >&2
  exit 1
}

echo "OK: printer-doctor selftest passed"
