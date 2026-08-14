#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$repo_root/bin/weekly-health"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local expected="$2"
  local message="$3"

  grep -Fq -- "$expected" "$path" || {
    printf 'MISSING TEXT: %s\n' "$expected" >&2
    printf '%s\n' '----- file content -----' >&2
    cat -- "$path" >&2
    printf '%s\n' '------------------------' >&2
    fail "$message"
  }
}

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq -- "$unexpected" "$path"; then
    printf 'UNEXPECTED TEXT: %s\n' "$unexpected" >&2
    printf '%s\n' '----- file content -----' >&2
    cat -- "$path" >&2
    printf '%s\n' '------------------------' >&2
    fail "$message"
  fi
}

run_expect_status() {
  local expected="$1"
  shift

  set +e
  "$@"
  local actual=$?
  set -e

  [[ "$actual" -eq "$expected" ]] || fail "expected exit status $expected, got $actual"
}

make_helper_template() {
  local path="$1"

  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'exit 130' INT
trap 'exit 143' TERM

name="$(basename -- "$0")"
case "$name" in
  security-health) prefix="SECURITY_HEALTH" ;;
  kernel-health) prefix="KERNEL_HEALTH" ;;
  security-clamav-scan) prefix="SECURITY_CLAMAV_SCAN" ;;
  *) echo "unexpected helper name: $name" >&2; exit 2 ;;
esac

if [[ -n "${FAKE_WEEKLY_CALLS:-}" ]]; then
  printf '%s\t%s\n' "$name" "$*" >> "$FAKE_WEEKLY_CALLS"
fi

pid_var="FAKE_${prefix}_PID_FILE"
if [[ -n "${!pid_var:-}" ]]; then
  printf '%s\n' "$$" > "${!pid_var}"
fi

self_status_var="FAKE_${prefix}_SIGNAL_STATUS"
if [[ -n "${!self_status_var:-}" ]]; then
  exit "${!self_status_var}"
fi

status_var="FAKE_${prefix}_STATUS"
stdout_var="FAKE_${prefix}_STDOUT"
stderr_var="FAKE_${prefix}_STDERR"
sleep_var="FAKE_${prefix}_SLEEP"
busy_var="FAKE_${prefix}_BUSY"

if [[ -n "${!busy_var:-}" ]]; then
  while :; do
    :
  done
fi

if [[ -n "${!sleep_var:-}" ]]; then
  sleep "${!sleep_var}"
fi

if [[ -n "${!stdout_var:-}" ]]; then
  printf '%s\n' "${!stdout_var}"
fi

if [[ -n "${!stderr_var:-}" ]]; then
  printf '%s\n' "${!stderr_var}" >&2
fi

exit "${!status_var:-0}"
EOF
  chmod 0755 "$path"
}

populate_helper_dir() {
  local dir="$1"
  local helper_template="$2"

  mkdir -p "$dir"
  ln -s -- "$helper_template" "$dir/security-health"
  ln -s -- "$helper_template" "$dir/kernel-health"
  ln -s -- "$helper_template" "$dir/security-clamav-scan"
}

make_sysbin() {
  local dir="$1"
  local include_flock="${2:-1}"

  mkdir -p "$dir"
  for cmd in bash mkdir dirname sed date cat mktemp grep sleep basename rm; do
    ln -s -- "$(command -v "$cmd")" "$dir/$cmd"
  done
  if [[ "$include_flock" == "1" ]]; then
    ln -s -- "$(command -v flock)" "$dir/flock"
  fi
}

run_with_env() {
  local out="$1"
  local err="$2"
  shift 2

  set +e
  "$@" >"$out" 2>"$err"
  local actual=$?
  set -e
  printf '%s' "$actual"
}

wait_for_file() {
  local path="$1"
  local attempts="${2:-50}"
  local i

  for ((i = 0; i < attempts; i++)); do
    [[ -e "$path" ]] && return 0
    sleep 0.1
  done

  return 1
}

wait_for_pid_exit() {
  local pid="$1"
  local label="$2"
  local attempts="${3:-50}"
  local i

  for ((i = 0; i < attempts; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done

  kill -KILL "$pid" 2>/dev/null || true
  sleep 0.1
  kill -0 "$pid" 2>/dev/null && fail "$label is still alive after the bounded wait"
}

make_fake_mktemp() {
  local dir="$1"
  local path_file="$2"

  mkdir -p "$dir"
  cat > "$dir/mktemp" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

out="$(__REAL_MKTEMP__ "$@")"
printf '%s\n' "$out" > "__PATH_FILE__"
printf '%s\n' "$out"
EOF
  local escaped_real_mktemp="${REAL_MKTEMP//\\/\\\\}"
  escaped_real_mktemp="${escaped_real_mktemp//&/\\&}"
  local escaped_path_file="${path_file//\\/\\\\}"
  escaped_path_file="${escaped_path_file//&/\\&}"
  sed -i \
    -e "s#__REAL_MKTEMP__#$escaped_real_mktemp#g" \
    -e "s#__PATH_FILE__#$escaped_path_file#g" \
    "$dir/mktemp"
  chmod 0755 "$dir/mktemp"
}

run_group_signal_case() {
  local signal_name="$1"
  local tool_pid_file="$2"
  local child_pid_file="$3"
  local out_file="$4"
  local err_file="$5"
  shift 5

  python3 - "$signal_name" "$tool_pid_file" "$child_pid_file" "$out_file" "$err_file" "$@" <<'PY'
import os
import signal
import subprocess
import sys
import time

signal_name = sys.argv[1]
tool_pid_file = sys.argv[2]
child_pid_file = sys.argv[3]
out_file = sys.argv[4]
err_file = sys.argv[5]
cmd = sys.argv[6:]

if not cmd:
    raise SystemExit('missing command to execute')

signal_number = getattr(signal, f'SIG{signal_name}', None)
if signal_number is None:
    raise SystemExit(f'invalid signal name: {signal_name}')

def reset_signals():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGQUIT, signal.SIG_DFL)

proc = subprocess.Popen(
    cmd,
    start_new_session=True,
    restore_signals=True,
    preexec_fn=reset_signals,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    encoding='utf-8',
    errors='replace',
)

with open(tool_pid_file, 'w', encoding='utf-8') as handle:
    handle.write(f'{proc.pid}\n')

if os.getpgid(proc.pid) != proc.pid:
    proc.kill()
    stdout, stderr = proc.communicate(timeout=5)
    with open(out_file, 'w', encoding='utf-8') as handle:
        handle.write(stdout)
    with open(err_file, 'w', encoding='utf-8') as handle:
        handle.write(stderr)
    raise SystemExit('tool did not start in its own process group')

deadline = time.monotonic() + 5
while time.monotonic() < deadline:
    if os.path.exists(child_pid_file):
        break
    if proc.poll() is not None:
        stdout, stderr = proc.communicate(timeout=5)
        with open(out_file, 'w', encoding='utf-8') as handle:
            handle.write(stdout)
        with open(err_file, 'w', encoding='utf-8') as handle:
            handle.write(stderr)
        raise SystemExit('tool exited before the helper pid file appeared')
    time.sleep(0.05)
else:
    os.killpg(proc.pid, signal.SIGKILL)
    stdout, stderr = proc.communicate(timeout=5)
    with open(out_file, 'w', encoding='utf-8') as handle:
        handle.write(stdout)
    with open(err_file, 'w', encoding='utf-8') as handle:
        handle.write(stderr)
    raise SystemExit('timed out waiting for the helper pid file')

os.killpg(proc.pid, signal_number)
try:
    stdout, stderr = proc.communicate(timeout=5)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGKILL)
    stdout, stderr = proc.communicate(timeout=5)

with open(out_file, 'w', encoding='utf-8') as handle:
    handle.write(stdout)
with open(err_file, 'w', encoding='utf-8') as handle:
    handle.write(stderr)

sys.exit(proc.returncode if proc.returncode is not None else 2)
PY
}

call_log_order() {
  local log="$1"
  local expected1="$2"
  local expected2="$3"
  local expected3="$4"

  mapfile -t lines < "$log"
  [[ "${#lines[@]}" -eq 3 ]] || fail "expected 3 helper invocations, got ${#lines[@]}"
  [[ "${lines[0]}" == "$expected1"* ]] || fail "first helper invocation differs: ${lines[0]}"
  [[ "${lines[1]}" == "$expected2"* ]] || fail "second helper invocation differs: ${lines[1]}"
  [[ "${lines[2]}" == "$expected3"* ]] || fail "third helper invocation differs: ${lines[2]}"
}

ENV_CMD="$(command -v env)"
REAL_MKTEMP="$(command -v mktemp)"
SYSBIN="$tmp/sysbin"
FAKE_MKTEMP_DIR="$tmp/fake-mktemp"
HELPER_TEMPLATE="$tmp/fake-helper.sh"
HELPER_BUNDLE="$tmp/helper-bundle"
FALLBACK_LAUNCHER="$tmp/fallback-launcher"
PATH_BUNDLE="$tmp/path-bundle"
PATH_AMBIG_A="$tmp/path-ambig-a"
PATH_AMBIG_B="$tmp/path-ambig-b"
PATH_AMBIG_C="$tmp/path-ambig-c"

make_sysbin "$SYSBIN"
make_fake_mktemp "$FAKE_MKTEMP_DIR" "$tmp/mktemp.path"
make_helper_template "$HELPER_TEMPLATE"
populate_helper_dir "$HELPER_BUNDLE" "$HELPER_TEMPLATE"
populate_helper_dir "$PATH_BUNDLE" "$HELPER_TEMPLATE"
populate_helper_dir "$PATH_AMBIG_A" "$HELPER_TEMPLATE"
populate_helper_dir "$PATH_AMBIG_B" "$HELPER_TEMPLATE"
populate_helper_dir "$PATH_AMBIG_C" "$HELPER_TEMPLATE"
rm -f -- "$PATH_AMBIG_A/kernel-health" "$PATH_AMBIG_A/security-clamav-scan"
rm -f -- "$PATH_AMBIG_B/security-health" "$PATH_AMBIG_B/security-clamav-scan"
rm -f -- "$PATH_AMBIG_C/security-health" "$PATH_AMBIG_C/kernel-health"

PATH_MISSING="$tmp/path-missing"
populate_helper_dir "$PATH_MISSING" "$HELPER_TEMPLATE"
rm -f -- "$PATH_MISSING/security-clamav-scan"

mkdir -p "$FALLBACK_LAUNCHER"
ln -s -- "$repo_root/bin/weekly-health" "$FALLBACK_LAUNCHER/weekly-health"

bundle_tool="$HELPER_BUNDLE/weekly-health"
ln -s -- "$repo_root/bin/weekly-health" "$bundle_tool"

printf '%s\n' 'TEST: help is stable'
help_out="$tmp/help.out"
help_err="$tmp/help.err"
run_expect_status 0 \
  "$ENV_CMD" PATH="$SYSBIN" "$tool" --help >"$help_out" 2>"$help_err"
assert_contains "$help_out" 'weekly-health: local read-only weekly security health orchestration' 'help title missing'
assert_contains "$help_out" 'security-clamav-scan --yes' 'help does not document the scan command'
assert_contains "$help_out" '130' 'help does not document signal exit codes'

printf '%s\n' 'TEST: same-directory symlink installation resolution and success'
calls="$tmp/calls-symlink.log"
out="$tmp/symlink.out"
err="$tmp/symlink.err"
run_status="$(run_with_env "$out" "$err" \
  "$ENV_CMD" PATH="$HELPER_BUNDLE:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$calls" \
  FAKE_SECURITY_HEALTH_STDOUT='security-health ok' FAKE_SECURITY_HEALTH_STATUS=0 \
  FAKE_KERNEL_HEALTH_STDOUT='kernel-health ok' FAKE_KERNEL_HEALTH_STATUS=0 \
  FAKE_SECURITY_CLAMAV_SCAN_STDOUT='clamav ok' FAKE_SECURITY_CLAMAV_SCAN_STATUS=0 \
  "$bundle_tool")"
[[ "$run_status" -eq 0 ]] || fail "symlink bundle run returned $run_status"
assert_contains "$out" "Helper directory: $HELPER_BUNDLE" 'symlink bundle helper directory differs'
assert_contains "$out" 'aggregate: 0 (clean)' 'symlink bundle did not complete cleanly'
assert_contains "$out" 'security-health ok' 'security-health output missing from symlink bundle'
assert_contains "$out" 'kernel-health ok' 'kernel-health output missing from symlink bundle'
assert_contains "$out" 'clamav ok' 'clamav output missing from symlink bundle'
call_log_order "$calls" \
  "security-health" \
  "kernel-health" \
  "security-clamav-scan"
assert_contains "$calls" $'security-clamav-scan\t--yes' 'weekly-health did not pass --yes to the ClamAV helper'

printf '%s\n' 'TEST: PATH fallback resolution and finding preservation'
calls="$tmp/calls-path.log"
out="$tmp/path.out"
err="$tmp/path.err"
run_status="$(run_with_env "$out" "$err" \
  "$ENV_CMD" PATH="$PATH_BUNDLE:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$calls" \
  FAKE_SECURITY_HEALTH_STDOUT='security-health finding' FAKE_SECURITY_HEALTH_STATUS=1 \
  FAKE_KERNEL_HEALTH_STDOUT='kernel-health ok' FAKE_KERNEL_HEALTH_STATUS=0 \
  FAKE_SECURITY_CLAMAV_SCAN_STDOUT='clamav ok' FAKE_SECURITY_CLAMAV_SCAN_STATUS=0 \
  "$FALLBACK_LAUNCHER/weekly-health")"
[[ "$run_status" -eq 1 ]] || fail "PATH fallback run returned $run_status"
assert_contains "$out" "Helper directory: $PATH_BUNDLE" 'PATH fallback helper directory differs'
assert_contains "$out" 'security-health: 1 (findings)' 'finding status was not preserved'
assert_contains "$out" 'aggregate: 1 (findings)' 'aggregate finding status was not reported'
call_log_order "$calls" \
  "security-health" \
  "kernel-health" \
  "security-clamav-scan"

printf '%s\n' 'TEST: operational error takes precedence but does not hide later checks'
calls="$tmp/calls-operational.log"
out="$tmp/operational.out"
err="$tmp/operational.err"
run_status="$(run_with_env "$out" "$err" \
  "$ENV_CMD" PATH="$PATH_BUNDLE:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$calls" \
  FAKE_SECURITY_HEALTH_STDOUT='security-health broken' FAKE_SECURITY_HEALTH_STATUS=2 \
  FAKE_KERNEL_HEALTH_STDOUT='kernel-health findings' FAKE_KERNEL_HEALTH_STATUS=1 \
  FAKE_SECURITY_CLAMAV_SCAN_STDOUT='clamav findings' FAKE_SECURITY_CLAMAV_SCAN_STATUS=1 \
  "$FALLBACK_LAUNCHER/weekly-health")"
[[ "$run_status" -eq 2 ]] || fail "operational error run returned $run_status"
assert_contains "$out" 'security-health: 2 (operational error)' 'security-health operational error missing'
assert_contains "$out" 'kernel-health: 1 (findings)' 'kernel-health findings missing'
assert_contains "$out" 'security-clamav-scan: 1 (findings)' 'clamav findings missing'
assert_contains "$out" 'aggregate: 2 (operational error)' 'aggregate operational error missing'
call_log_order "$calls" \
  "security-health" \
  "kernel-health" \
  "security-clamav-scan"

printf '%s\n' 'TEST: ClamAV cancellation normalizes to aggregate failure'
calls="$tmp/calls-cancel.log"
out="$tmp/cancel.out"
err="$tmp/cancel.err"
run_status="$(run_with_env "$out" "$err" \
  "$ENV_CMD" PATH="$PATH_BUNDLE:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$calls" \
  FAKE_SECURITY_HEALTH_STATUS=0 \
  FAKE_KERNEL_HEALTH_STATUS=0 \
  FAKE_SECURITY_CLAMAV_SCAN_STATUS=3 \
  "$FALLBACK_LAUNCHER/weekly-health")"
[[ "$run_status" -eq 2 ]] || fail "cancellation aggregate returned $run_status"
assert_contains "$out" 'security-clamav-scan: 3 (cancelled before scan)' 'scan cancellation not preserved'
assert_contains "$out" 'aggregate: 2 (operational error)' 'cancellation did not normalize to aggregate error'

printf '%s\n' 'TEST: missing mandatory helper'
missing_err="$tmp/missing.err"
run_expect_status 2 \
  "$ENV_CMD" PATH="$PATH_MISSING:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$tmp/missing-calls.log" \
  "$FALLBACK_LAUNCHER/weekly-health" >/dev/null 2>"$missing_err"
assert_contains "$missing_err" 'missing mandatory helper(s)' 'missing helper error was not reported'

printf '%s\n' 'TEST: ambiguous PATH resolution fails closed'
ambig_err="$tmp/ambig.err"
run_expect_status 2 \
  "$ENV_CMD" PATH="$PATH_AMBIG_A:$PATH_AMBIG_B:$PATH_AMBIG_C:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$tmp/ambig-calls.log" \
  "$FALLBACK_LAUNCHER/weekly-health" >/dev/null 2>"$ambig_err"
assert_contains "$ambig_err" 'ambiguous helper resolution' 'ambiguous helper resolution was not rejected'

printf '%s\n' 'TEST: SIGINT propagation'
sigint_out="$tmp/sigint.out"
sigint_err="$tmp/sigint.err"
sigint_calls="$tmp/sigint-calls.log"
sigint_tool_pid_file="$tmp/sigint-tool.pid"
sigint_helper_pid_file="$tmp/sigint-helper.pid"
mkdir -p "$tmp/sigint-parent"
rm -f -- "$tmp/mktemp.path"
set +e
run_group_signal_case INT "$sigint_tool_pid_file" "$sigint_helper_pid_file" "$sigint_out" "$sigint_err" \
  "$ENV_CMD" PATH="$FAKE_MKTEMP_DIR:$PATH_BUNDLE:$SYSBIN" TMPDIR="$tmp/sigint-parent" \
  FAKE_WEEKLY_CALLS="$sigint_calls" \
  FAKE_SECURITY_HEALTH_PID_FILE="$sigint_helper_pid_file" FAKE_SECURITY_HEALTH_BUSY=1 \
  "$FALLBACK_LAUNCHER/weekly-health"
sigint_status=$?
set -e
wait_for_file "$sigint_tool_pid_file" || fail 'weekly-health did not start for SIGINT test'
wait_for_file "$sigint_helper_pid_file" || fail 'fake security-health helper did not start for SIGINT test'
wait_for_file "$tmp/mktemp.path" || fail 'weekly-health did not create a temporary workdir for SIGINT test'
sigint_workdir_path="$(cat "$tmp/mktemp.path")"
sigint_helper_pid="$(cat "$sigint_helper_pid_file")"
[[ "$sigint_status" -eq 130 ]] || fail "SIGINT run returned $sigint_status"
wait_for_pid_exit "$sigint_helper_pid" 'weekly-health helper after SIGINT'
mapfile -t sigint_lines < "$sigint_calls"
[[ "${#sigint_lines[@]}" -eq 1 ]] || fail 'SIGINT should stop after the first helper'
[[ ! -e "$sigint_workdir_path" ]] || fail 'weekly-health workdir was not removed after SIGINT'

printf '%s\n' 'TEST: SIGTERM propagation'
sigterm_out="$tmp/sigterm.out"
sigterm_err="$tmp/sigterm.err"
sigterm_calls="$tmp/sigterm-calls.log"
sigterm_tool_pid_file="$tmp/sigterm-tool.pid"
sigterm_helper_pid_file="$tmp/sigterm-helper.pid"
mkdir -p "$tmp/sigterm-parent"
rm -f -- "$tmp/mktemp.path"
set +e
run_group_signal_case TERM "$sigterm_tool_pid_file" "$sigterm_helper_pid_file" "$sigterm_out" "$sigterm_err" \
  "$ENV_CMD" PATH="$FAKE_MKTEMP_DIR:$PATH_BUNDLE:$SYSBIN" TMPDIR="$tmp/sigterm-parent" \
  FAKE_WEEKLY_CALLS="$sigterm_calls" \
  FAKE_SECURITY_HEALTH_PID_FILE="$sigterm_helper_pid_file" FAKE_SECURITY_HEALTH_BUSY=1 \
  "$FALLBACK_LAUNCHER/weekly-health"
sigterm_status=$?
set -e
wait_for_file "$sigterm_tool_pid_file" || fail 'weekly-health did not start for SIGTERM test'
wait_for_file "$sigterm_helper_pid_file" || fail 'fake security-health helper did not start for SIGTERM test'
wait_for_file "$tmp/mktemp.path" || fail 'weekly-health did not create a temporary workdir for SIGTERM test'
sigterm_workdir_path="$(cat "$tmp/mktemp.path")"
sigterm_helper_pid="$(cat "$sigterm_helper_pid_file")"
[[ "$sigterm_status" -eq 143 ]] || fail "SIGTERM run returned $sigterm_status"
wait_for_pid_exit "$sigterm_helper_pid" 'weekly-health helper after SIGTERM'
mapfile -t sigterm_lines < "$sigterm_calls"
[[ "${#sigterm_lines[@]}" -eq 1 ]] || fail 'SIGTERM should stop after the first helper'
[[ ! -e "$sigterm_workdir_path" ]] || fail 'weekly-health workdir was not removed after SIGTERM'

printf '%s\n' 'TEST: absence of error hiding on later helpers'
calls="$tmp/calls-no-hide.log"
out="$tmp/no-hide.out"
err="$tmp/no-hide.err"
run_status="$(run_with_env "$out" "$err" \
  "$ENV_CMD" PATH="$PATH_BUNDLE:$SYSBIN" \
  FAKE_WEEKLY_CALLS="$calls" \
  FAKE_SECURITY_HEALTH_STATUS=2 \
  FAKE_KERNEL_HEALTH_STATUS=0 \
  FAKE_SECURITY_CLAMAV_SCAN_STATUS=0 \
  "$FALLBACK_LAUNCHER/weekly-health")"
[[ "$run_status" -eq 2 ]] || fail "error-hiding run returned $run_status"
call_log_order "$calls" \
  "security-health" \
  "kernel-health" \
  "security-clamav-scan"
assert_contains "$out" 'aggregate: 2 (operational error)' 'aggregate error was not reported'

printf '%s\n' 'OK: weekly-health contract'
