#!/usr/bin/env bash
set -euo pipefail

SCRIPT="bin/printer-doctor"

[[ -x "$SCRIPT" ]] || {
  echo "FAIL: $SCRIPT is not executable" >&2
  exit 1
}

"$SCRIPT" --help >/tmp/printer-doctor-help.txt
grep -q "printer-doctor" /tmp/printer-doctor-help.txt
grep -q "list" /tmp/printer-doctor-help.txt
grep -q "status" /tmp/printer-doctor-help.txt
grep -q "repair" /tmp/printer-doctor-help.txt

"$SCRIPT" --help-md >/tmp/printer-doctor-help-md.txt
grep -q "# printer-doctor" /tmp/printer-doctor-help-md.txt
grep -q "vendor-agnostic" /tmp/printer-doctor-help-md.txt
grep -q "List configured printers" /tmp/printer-doctor-help-md.txt
grep -q "No cartridge cleaning" /tmp/printer-doctor-help-md.txt

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/lpstat" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -r)
    echo "scheduler is running"
    ;;
  -d)
    echo "system default destination: Office_Printer"
    ;;
  -p)
    echo "printer Office_Printer is idle. enabled since Fri 01 Jan 2000"
    echo "printer Canon_TS3500_IP is idle. enabled since Fri 01 Jan 2000"
    ;;
  -v)
    echo "device for Office_Printer: ipp://office/printer"
    echo "device for Canon_TS3500_IP: ipp://canon/printer"
    ;;
  *)
    echo "unexpected lpstat call: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$tmpdir/lpstat"

PATH="$tmpdir:$PATH" "$SCRIPT" list >/tmp/printer-doctor-list.txt
grep -q "PRINTER DOCTOR: LIST" /tmp/printer-doctor-list.txt
grep -q "Default printer: Office_Printer" /tmp/printer-doctor-list.txt
grep -q "Canon_TS3500_IP" /tmp/printer-doctor-list.txt

set +e
"$SCRIPT" >/tmp/printer-doctor-empty.txt 2>/tmp/printer-doctor-empty.err
rc=$?
set -e
[[ "$rc" -eq 2 ]] || {
  echo "FAIL: empty invocation should exit 2, got $rc" >&2
  exit 1
}

echo "OK: printer-doctor selftest passed"
