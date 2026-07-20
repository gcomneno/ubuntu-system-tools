#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/safe-uninstall"
REAL_UID="$EUID"
REAL_USER="$(/usr/bin/id -un)"
REAL_HOME="$(/usr/bin/getent passwd "$REAL_UID" | awk -F: 'NF >= 6 { print $6; exit }')"
[[ -n "$REAL_HOME" && "$REAL_HOME" == /* ]] || { printf 'FAIL: cannot resolve real home\n' >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -F -- "$2" "$1" >/dev/null || fail "missing '$2' in $1"; }
assert_no_mutations() { [[ ! -s "$MUTATIONS" ]] || fail "unexpected mutation: $(<"$MUTATIONS")"; }

FAKEBIN="$TMP/bin"
FAKEROOT="$TMP/root"
STATE="$TMP/package-state"
MUTATIONS="$TMP/mutations"
mkdir -p "$FAKEBIN" "$FAKEROOT/etc/apt/sources.list.d" "$FAKEROOT/etc/anydesk" \
  "$FAKEROOT/etc/systemd/system/multi-user.target.wants" "$FAKEROOT/etc/xdg/autostart" \
  "$FAKEROOT/var/lib/gdm3" "$FAKEROOT/var/log" "$FAKEROOT/home/alice/.config/anydesk" \
  "$FAKEROOT/home/alice/.cache/anydesk" "$FAKEROOT/home/alice/.local/share/anydesk" \
  "$FAKEROOT/home/alice/.anydesk" "$FAKEROOT$REAL_HOME" \
  "$FAKEROOT/usr/bin" "$FAKEROOT/usr/lib/systemd/system"
printf 'installed\n' > "$STATE"
printf 'deb example anydesk\n' > "$FAKEROOT/etc/apt/sources.list.d/anydesk.list"
touch "$FAKEROOT/etc/systemd/system/anydesk.service" \
  "$FAKEROOT/etc/systemd/system/multi-user.target.wants/anydesk.service" \
  "$FAKEROOT/etc/xdg/autostart/anydesk_global_tray.desktop" \
  "$FAKEROOT/var/lib/gdm3/.anydesk" "$FAKEROOT/var/log/anydesk.trace" \
  "$FAKEROOT/usr/bin/anydesk" "$FAKEROOT/usr/lib/systemd/system/anydesk.service"
chmod +x "$FAKEROOT/usr/bin/anydesk"

cat > "$FAKEBIN/dpkg-query" <<'EOF'
#!/usr/bin/env bash
[[ "$(<"$SAFE_TEST_STATE")" == installed ]] || exit 1
printf 'ii  1.2.3\n'
EOF
cat > "$FAKEBIN/dpkg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' /usr/bin/anydesk /usr/lib/systemd/system/anydesk.service /usr/share/doc/anydesk
EOF
cat > "$FAKEBIN/systemctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  is-active)
    if [[ "${2:-}" == --quiet ]]; then
      exit 3
    fi
    printf 'inactive\n'
    exit 3
    ;;
  *) printf 'systemctl %s\n' "$*" >> "$SAFE_TEST_MUTATIONS";;
esac
EOF
cat > "$FAKEBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >> "$SAFE_TEST_PGREP_CALLS"
[[ "$*" == '-a -x -- anydesk' ]] || exit 1
printf '%s\n' \
  '5151 anydesk --service' \
  '5151 anydesk --service'
EOF
cat > "$FAKEBIN/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-u' ]] || exit 2
printf '0\n'
EOF
cat > "$FAKEBIN/pkill" <<'EOF'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >> "$SAFE_TEST_MUTATIONS"
EOF
cat > "$FAKEBIN/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$SAFE_TEST_MUTATIONS"
printf 'absent\n' > "$SAFE_TEST_STATE"
EOF
cat > "$FAKEBIN/getent" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
  alice) printf 'alice:x:1000:1000::/home/alice:/bin/bash\n';;
  root) printf 'root:x:0:0::/root:/bin/bash\n';;
  "$SAFE_TEST_REAL_USER") printf '%s:x:%s:%s::%s:/bin/bash\n' "$SAFE_TEST_REAL_USER" "$SAFE_TEST_REAL_UID" "$SAFE_TEST_REAL_UID" "${SAFE_TEST_SPOOF_HOME:-$SAFE_TEST_REAL_HOME}";;
  *) exit 2;;
esac
EOF
cat > "$FAKEBIN/find" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  */etc) printf '%s/etc/anydesk\n' "$SAFE_UNINSTALL_ROOT_PREFIX";;
esac
EOF
cat > "$FAKEBIN/rm" <<'EOF'
#!/usr/bin/env bash
printf 'rm %s\n' "$*" >> "$SAFE_TEST_MUTATIONS"
target="${!#}"
[[ "${SAFE_TEST_KEEP_PATH:-}" == "$target" ]] && exit 0
mkdir -p "$SAFE_TEST_TRASH"
mv -- "$target" "$SAFE_TEST_TRASH/item.$RANDOM" 2>/dev/null || true
EOF
chmod +x "$FAKEBIN"/*

export PATH="$FAKEBIN:/usr/bin:/bin"
export SAFE_UNINSTALL_ROOT_PREFIX="$FAKEROOT"
export SAFE_TEST_REAL_UID="$REAL_UID"
export SAFE_TEST_REAL_USER="$REAL_USER"
export SAFE_TEST_REAL_HOME="$REAL_HOME"
export SAFE_TEST_STATE="$STATE"
export SAFE_TEST_MUTATIONS="$MUTATIONS"
export SAFE_TEST_TRASH="$TMP/trash"
export SAFE_TEST_PGREP_CALLS="$TMP/pgrep-calls"

printf '%s\n' 'TEST: help and strict package validation'
"$TOOL" --help > "$TMP/help"
assert_contains "$TMP/help" 'safe-uninstall inspect PACKAGE'
if "$TOOL" inspect 'bad;name' > /dev/null 2>&1; then fail 'invalid package name accepted'; fi

printf '%s\n' 'TEST: inspection is deterministic and read-only'
: > "$MUTATIONS"
"$TOOL" inspect anydesk > "$TMP/inspect-1"
"$TOOL" inspect anydesk > "$TMP/inspect-2"
cmp -s "$TMP/inspect-1" "$TMP/inspect-2" || fail 'inspection output changed'
assert_contains "$TMP/inspect-1" 'Trusted profile: anydesk'
assert_contains "$TMP/inspect-1" '/usr/lib/systemd/system/anydesk.service: inactive'
if grep -Fx 'unknown' "$TMP/inspect-1"; then
  fail 'inactive systemd unit was also reported as unknown'
fi
assert_contains "$SAFE_TEST_PGREP_CALLS" 'pgrep -a -x -- anydesk'
if grep -F -- '-f' "$SAFE_TEST_PGREP_CALLS"; then fail 'process inspection searched its own command line'; fi
if grep -F 'safe-uninstall inspect anydesk' "$TMP/inspect-1"; then fail 'inspection command reported as a package process'; fi
[[ "$(grep -Fc '5151 anydesk --service' "$TMP/inspect-1")" == 1 ]] || fail 'process report was not deduplicated'
assert_no_mutations

printf '%s\n' 'TEST: purge preview is complete and read-only'
"$TOOL" purge anydesk --target-user alice > "$TMP/plan"
assert_contains "$TMP/plan" 'stop and disable service: anydesk.service'
assert_contains "$TMP/plan" 'terminate exact process name: anydesk'
assert_contains "$TMP/plan" '/home/alice/.config/anydesk'
assert_contains "$TMP/plan" 'do not run apt autoremove'
assert_no_mutations

printf '%s\n' 'TEST: direct preview uses real process identity'
env -u SUDO_USER USER=spoofed LOGNAME=spoofed "$TOOL" purge anydesk > "$TMP/direct-user-plan"
assert_contains "$TMP/direct-user-plan" "Target user: $REAL_USER ($REAL_HOME)"
[[ "$(bash -c 'source "$1"; select_target_user "" 0 ""' _ "$TOOL")" == root ]] || fail 'direct-root default was not root'
assert_no_mutations

printf '%s\n' 'TEST: production home resolution ignores PATH-injected getent'
env -u SAFE_UNINSTALL_ROOT_PREFIX SAFE_TEST_SPOOF_HOME=/tmp/spoofed-home \
  "$TOOL" purge anydesk --target-user "$REAL_USER" > "$TMP/trusted-home-plan"
assert_contains "$TMP/trusted-home-plan" "Target user: $REAL_USER ($REAL_HOME)"
if grep -F '/tmp/spoofed-home' "$TMP/trusted-home-plan"; then fail 'production home resolution used fake getent'; fi
assert_no_mutations

printf '%s\n' 'TEST: mutation without root is rejected before mutations'
if SAFE_UNINSTALL_TESTING=1 SAFE_UNINSTALL_TEST_EUID=0 SUDO_USER=alice "$TOOL" purge anydesk --apply > "$TMP/nonroot" 2>&1; then fail 'non-root apply succeeded with fake id in PATH'; fi
assert_contains "$TMP/nonroot" 'requires root privileges'
assert_no_mutations

printf '%s\n' 'TEST: automatically selected target user is validated'
if bash -c 'source "$1"; select_target_user "" 0 "bad;user"' _ "$TOOL" > "$TMP/invalid-sudo-user" 2>&1; then fail 'invalid SUDO_USER accepted'; fi
assert_contains "$TMP/invalid-sudo-user" 'invalid target user: bad;user'
assert_no_mutations

printf '%s\n' 'TEST: generic purge never guesses process or residual removals'
bash -c 'source "$1"; apply_purge example none ""' _ "$TOOL" > "$TMP/generic"
assert_contains "$MUTATIONS" 'apt-get -y purge -- example'
if grep -Eq '^(pkill|rm) ' "$MUTATIONS"; then fail 'generic purge made guessed mutations'; fi

printf '%s\n' 'TEST: AnyDesk apply uses allowlisted mutations and SUDO_USER home'
printf 'installed\n' > "$STATE"
: > "$MUTATIONS"
bash -c 'source "$1"; apply_purge anydesk anydesk /home/alice' _ "$TOOL" > "$TMP/apply"
assert_contains "$MUTATIONS" 'systemctl stop anydesk.service'
assert_contains "$MUTATIONS" 'systemctl disable anydesk.service'
assert_contains "$MUTATIONS" 'pkill -x -- anydesk'
assert_contains "$MUTATIONS" 'apt-get -y purge -- anydesk'
assert_contains "$MUTATIONS" "rm -rf -- $FAKEROOT/home/alice/.config/anydesk"
if grep -F '/home/root/' "$MUTATIONS"; then fail 'selected root home instead of SUDO_USER'; fi
while IFS= read -r mutation; do
  case "$mutation" in
    'systemctl stop anydesk.service'|\
    'systemctl disable anydesk.service'|\
    'systemctl daemon-reload'|\
    'systemctl reset-failed anydesk.service'|\
    'pkill -x -- anydesk'|\
    'apt-get -y purge -- anydesk'|\
    "rm -f -- $FAKEROOT/etc/systemd/system/anydesk.service"|\
    "rm -f -- $FAKEROOT/etc/systemd/system/multi-user.target.wants/anydesk.service"|\
    "rm -f -- $FAKEROOT/etc/xdg/autostart/anydesk_global_tray.desktop"|\
    "rm -f -- $FAKEROOT/var/lib/gdm3/.anydesk"|\
    "rm -f -- $FAKEROOT/var/log/anydesk.trace"|\
    "rm -rf -- $FAKEROOT/etc/anydesk"|\
    "rm -rf -- $FAKEROOT/home/alice/.anydesk"|\
    "rm -rf -- $FAKEROOT/home/alice/.config/anydesk"|\
    "rm -rf -- $FAKEROOT/home/alice/.cache/anydesk"|\
    "rm -rf -- $FAKEROOT/home/alice/.local/share/anydesk") ;;
    *) fail "non-allowlisted mutation: $mutation" ;;
  esac
done < "$MUTATIONS"

printf '%s\n' 'TEST: dangerous and empty removal paths are refused'
if bash -c 'source "$1"; validate_removal_path ""' _ "$TOOL" >/dev/null 2>&1; then fail 'empty path accepted'; fi
if bash -c 'source "$1"; validate_removal_path "/"' _ "$TOOL" >/dev/null 2>&1; then fail 'root path accepted'; fi
if bash -c 'source "$1"; validate_removal_path "/home/alice" "/home/alice"' _ "$TOOL" >/dev/null 2>&1; then fail 'home root accepted'; fi

printf '%s\n' 'TEST: symlinked user-profile parents are refused before mutation'
mkdir -p "$TMP/external-anydesk" "$FAKEROOT/home/alice"
rm -rf -- "$FAKEROOT/home/alice/.config"
ln -s -- "$TMP/external-anydesk" "$FAKEROOT/home/alice/.config"
printf 'installed\n' > "$STATE"
: > "$MUTATIONS"
if bash -c 'source "$1"; apply_purge anydesk anydesk /home/alice' _ "$TOOL" > "$TMP/symlink-parent" 2>&1; then fail 'symlinked profile parent was accepted'; fi
assert_contains "$TMP/symlink-parent" 'refusing symlinked parent in target-user path'
[[ -d "$TMP/external-anydesk" ]] || fail 'external directory was deleted through symlinked parent'
assert_no_mutations
rm -f -- "$FAKEROOT/home/alice/.config"
mkdir -p "$FAKEROOT/home/alice/.config/anydesk"

printf '%s\n' 'TEST: final verification detects a surviving profile path'
mkdir -p "$FAKEROOT/etc/anydesk"
printf 'installed\n' > "$STATE"
: > "$MUTATIONS"
export SAFE_TEST_KEEP_PATH="$FAKEROOT/etc/anydesk"
if bash -c 'source "$1"; apply_purge anydesk anydesk /home/alice' _ "$TOOL" > "$TMP/survivor" 2>&1; then fail 'surviving path was not fatal'; fi
assert_contains "$TMP/survivor" 'VERIFY FAIL: path remains: /etc/anydesk'
unset SAFE_TEST_KEEP_PATH

printf '%s\n' 'OK: safe-uninstall safety contract'
