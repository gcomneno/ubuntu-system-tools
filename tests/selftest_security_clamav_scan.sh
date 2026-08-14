#!/usr/bin/env bash

set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$repo_root/bin/security-clamav-scan"

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

run_expect_status_with_input() {
  local expected="$1"
  local input="$2"
  shift 2

  set +e
  printf '%s' "$input" | "$@"
  local actual=$?
  set -e

  [[ "$actual" -eq "$expected" ]] || fail "expected exit status $expected, got $actual"
}

make_sysbin() {
  local dir="$1"
  local include_flock="${2:-1}"

  mkdir -p "$dir"
  for cmd in bash mkdir dirname sed date cat mktemp grep sleep basename; do
    ln -s -- "$(command -v "$cmd")" "$dir/$cmd"
  done
  if [[ "$include_flock" == "1" ]]; then
    ln -s -- "$(command -v flock)" "$dir/flock"
  fi
}

make_fake_clamscan() {
  local dir="$1"

  mkdir -p "$dir"
cat > "$dir/clamscan" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -n "${FAKE_CLAMSCAN_LOG:-}" ]]; then
  {
    for arg in "$@"; do
      printf '%s\n' "$arg"
    done
  } >> "$FAKE_CLAMSCAN_LOG"
fi

if [[ -n "${FAKE_CLAMSCAN_PID_FILE:-}" ]]; then
  printf '%s\n' "$$" > "$FAKE_CLAMSCAN_PID_FILE"
fi

if [[ -n "${FAKE_CLAMSCAN_SIGNAL_STATUS:-}" ]]; then
  exit "${FAKE_CLAMSCAN_SIGNAL_STATUS}"
fi

if [[ -n "${FAKE_CLAMSCAN_BUSY:-}" ]]; then
  while :; do
    :
  done
fi

if [[ -n "${FAKE_CLAMSCAN_SLEEP:-}" ]]; then
  sleep "$FAKE_CLAMSCAN_SLEEP"
fi

if [[ -n "${FAKE_CLAMSCAN_STDOUT:-}" ]]; then
  printf '%s\n' "$FAKE_CLAMSCAN_STDOUT"
fi

if [[ -n "${FAKE_CLAMSCAN_STDERR:-}" ]]; then
  printf '%s\n' "$FAKE_CLAMSCAN_STDERR" >&2
fi

exit "${FAKE_CLAMSCAN_STATUS:-0}"
EOF
  chmod 0755 "$dir/clamscan"
}

make_fake_flock() {
  local dir="$1"

  mkdir -p "$dir"
  cat > "$dir/flock" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/flock "$@"
EOF
  chmod 0755 "$dir/flock"
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
        raise SystemExit('tool exited before the child pid file appeared')
    time.sleep(0.05)
else:
    os.killpg(proc.pid, signal.SIGKILL)
    stdout, stderr = proc.communicate(timeout=5)
    with open(out_file, 'w', encoding='utf-8') as handle:
        handle.write(stdout)
    with open(err_file, 'w', encoding='utf-8') as handle:
        handle.write(stderr)
    raise SystemExit('timed out waiting for the fake clamscan pid file')

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

reset_targets() {
  rm -rf -- \
    "$HOME_DIR/Downloads" \
    "$HOME_DIR/Desktop" \
    "$HOME_DIR/Scrivania" \
    "$HOME_DIR/Documents" \
    "$HOME_DIR/Custom-One" \
    "$HOME_DIR/Custom-Two"
  mkdir -p -- "$HOME_DIR"
}

run_scan() {
  local out="$1"
  local err="$2"
  shift 2

  set +e
  "$@" >"$out" 2>"$err"
  local status=$?
  set -e
  printf '%s' "$status"
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

regex_escape() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//./\\.}"
  value="${value//\*/\\*}"
  value="${value//\?/\\?}"
  value="${value//\[/\\[}"
  value="${value//\]/\\]}"
  value="${value//^/\\^}"
  value="${value//\$/\\$}"
  value="${value//+/\\+}"
  value="${value//\{/\\{}"
  value="${value//\}/\\}}"
  value="${value//|/\\|}"
  value="${value//(/\\(}"
  value="${value//)/\\)}"

  printf '%s' "$value"
}

literal_path_regex() {
  local path="$1"

  printf '^%s(/|$)' "$(regex_escape "$path")"
}

ENV_CMD="$(command -v env)"
HOME_DIR="$tmp/home"
STATE_DIR="$tmp/state"
RUNTIME_DIR="$tmp/runtime"
DB_DIR="$tmp/clamav-db"
SYSBIN="$tmp/sysbin"
SYSBIN_NO_FLOCK="$tmp/sysbin-no-flock"
SYSBIN_NO_CLAMSCAN="$tmp/sysbin-no-clamscan"
FAKE_CLAMSCAN_DIR="$tmp/fake-clamscan"
FAKE_FLOCK_DIR="$tmp/fake-flock"

mkdir -p -- "$HOME_DIR" "$STATE_DIR" "$RUNTIME_DIR" "$DB_DIR"
printf 'signature\n' > "$DB_DIR/main.cvd"

make_sysbin "$SYSBIN"
make_sysbin "$SYSBIN_NO_FLOCK" 0
make_sysbin "$SYSBIN_NO_CLAMSCAN" 1
make_fake_clamscan "$FAKE_CLAMSCAN_DIR"
make_fake_flock "$FAKE_FLOCK_DIR"

default_path="$FAKE_CLAMSCAN_DIR:$FAKE_FLOCK_DIR:$SYSBIN"
no_flock_path="$FAKE_CLAMSCAN_DIR:$SYSBIN_NO_FLOCK"
no_clamscan_path="$FAKE_FLOCK_DIR:$SYSBIN_NO_CLAMSCAN"

assert_log_line() {
  local log="$1"
  local expected="$2"
  local message="$3"

  grep -Fxq -- "$expected" "$log" || {
    printf 'MISSING LOG TEXT: %s\n' "$expected" >&2
    cat -- "$log" >&2
    fail "$message"
  }
}

printf '%s\n' 'TEST: help is stable and documents exit codes'
help_out="$tmp/help.out"
help_err="$tmp/help.err"
run_expect_status 0 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --help >"$help_out" 2>"$help_err"
assert_contains "$help_out" '--target PATH' 'help does not document --target'
assert_contains "$help_out" '--full' 'help does not document --full'
assert_contains "$help_out" 'Exit codes:' 'help does not document exit codes'
assert_contains "$help_out" '130' 'help does not document signal exit codes'

printf '%s\n' 'TEST: default target selection'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Documents"
default_log="$tmp/default.log"
default_out="$tmp/default.out"
default_err="$tmp/default.err"
run_status="$(run_scan "$default_out" "$default_err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/default" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$default_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool")"
[[ "$run_status" -eq 0 ]] || fail "default scan returned $run_status"
assert_contains "$default_out" 'Result: clean' 'default scan did not finish cleanly'
assert_log_line "$default_log" '--recursive' 'default scan is not recursive'
assert_log_line "$default_log" '--cross-fs=no' 'default scan crosses filesystems'
assert_log_line "$default_log" "$HOME_DIR/Downloads" 'default Downloads target missing'
assert_log_line "$default_log" "$HOME_DIR/Documents" 'default Documents target missing'
assert_not_contains "$default_log" "$HOME_DIR/Desktop" 'default scan unexpectedly included Desktop'
assert_not_contains "$default_log" "$HOME_DIR/Scrivania" 'default scan unexpectedly included Scrivania'

printf '%s\n' 'TEST: Desktop fallback to Scrivania'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Scrivania" "$HOME_DIR/Documents"
scrivania_log="$tmp/scrivania.log"
run_status="$(run_scan "$tmp/scrivania.out" "$tmp/scrivania.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/scrivania" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$scrivania_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool")"
[[ "$run_status" -eq 0 ]] || fail "Scrivania fallback scan returned $run_status"
assert_log_line "$scrivania_log" "$HOME_DIR/Scrivania" 'Scrivania fallback target missing'
assert_not_contains "$scrivania_log" "$HOME_DIR/Desktop" 'Scrivania fallback unexpectedly included Desktop'

printf '%s\n' 'TEST: custom targets replace defaults'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Documents" "$HOME_DIR/Custom-One" "$HOME_DIR/Custom-Two"
custom_log="$tmp/custom.log"
run_status="$(run_scan "$tmp/custom.out" "$tmp/custom.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/custom" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$custom_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Custom-One" --target "$HOME_DIR/Custom-Two")"
[[ "$run_status" -eq 0 ]] || fail "custom target scan returned $run_status"
assert_log_line "$custom_log" "$HOME_DIR/Custom-One" 'custom target one missing'
assert_log_line "$custom_log" "$HOME_DIR/Custom-Two" 'custom target two missing'
assert_not_contains "$custom_log" "$HOME_DIR/Downloads" 'custom targets unexpectedly included default Downloads'
assert_not_contains "$custom_log" "$HOME_DIR/Documents" 'custom targets unexpectedly included default Documents'

printf '%s\n' 'TEST: full mode warning and exclusions'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Documents"
full_log="$tmp/full.log"
full_out="$tmp/full.out"
full_err="$tmp/full.err"
run_status="$(run_scan "$full_out" "$full_err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/full" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$full_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --full --yes)"
[[ "$run_status" -eq 0 ]] || fail "full scan returned $run_status"
assert_contains "$full_err" 'WARNING: --full scans / recursively and can take many hours.' 'full scan warning missing'
assert_log_line "$full_log" '/' 'full scan did not target root'
assert_log_line "$full_log" '--recursive' 'full scan is not recursive'
assert_log_line "$full_log" '--cross-fs=no' 'full scan crosses filesystems'
assert_log_line "$full_log" '--exclude-dir=^/proc(/|$)' 'full scan missing exact /proc exclusion'
assert_log_line "$full_log" '--exclude-dir=^/sys(/|$)' 'full scan missing exact /sys exclusion'
assert_log_line "$full_log" '--exclude-dir=^/dev(/|$)' 'full scan missing exact /dev exclusion'
assert_log_line "$full_log" '--exclude-dir=^/run(/|$)' 'full scan missing exact /run exclusion'
assert_log_line "$full_log" "--exclude-dir=$(literal_path_regex "$STATE_DIR/full/ubuntu-system-tools/clamav")" 'full scan missing exact log-directory exclusion'

printf '%s\n' 'TEST: log-directory regex escapes spaces and metacharacters'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Documents"
special_log_dir="$tmp/log dir (special)[v1]+/clamav cache"
special_sibling="$tmp/log dir (special)[v1]+/clamav cache-archive"
special_log="$tmp/special.log"
run_status="$(run_scan "$tmp/special.out" "$tmp/special.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/special" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$special_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" --log-dir "$special_log_dir")"
[[ "$run_status" -eq 0 ]] || fail "special log-dir scan returned $run_status"
assert_log_line "$special_log" "--exclude-dir=$(literal_path_regex "$special_log_dir")" 'log-directory regex was not anchored or escaped correctly'
assert_not_contains "$special_log" "$special_sibling" 'log-directory regex unexpectedly overmatched the sibling prefix'

printf '%s\n' 'TEST: invalid combinations and missing option values'
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/invalid-combo" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --full --target "$HOME_DIR/Downloads" >/dev/null 2>&1
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/missing-target" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --target >/dev/null 2>&1
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/missing-log" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --log-dir >/dev/null 2>&1
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/bogus" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --bogus >/dev/null 2>&1

printf '%s\n' 'TEST: invalid or missing targets'
reset_targets
mkdir -p "$HOME_DIR/Downloads" "$HOME_DIR/Documents"
printf 'not a directory\n' > "$HOME_DIR/target-file"
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/invalid-target" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/invalid-target.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/target-file" >/dev/null 2>&1
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/missing-target-path" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/missing-target.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/does-not-exist" >/dev/null 2>&1

printf '%s\n' 'TEST: missing clamscan'
run_expect_status 2 \
  "$ENV_CMD" PATH="$no_clamscan_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/no-clamscan" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: missing flock'
run_expect_status 2 \
  "$ENV_CMD" PATH="$no_flock_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/no-flock" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/no-flock.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: missing signature databases'
empty_db="$tmp/empty-db"
mkdir -p "$empty_db"
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/missing-db" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/missing-db.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$empty_db" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: symlinked parent components are rejected'
linked_root="$tmp/linked-root"
linked_external="$tmp/linked-external"
mkdir -p "$linked_external/home" "$linked_external/scan" "$linked_external/db" "$linked_external/state"
printf 'signature\n' > "$linked_external/db/main.cvd"
ln -s -- "$linked_external" "$linked_root"

run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$linked_root/home" XDG_STATE_HOME="$STATE_DIR/safe-home" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/symlink-home.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/safe-target" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/symlink-target.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$linked_root/scan" >/dev/null 2>&1

run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$linked_root/state" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/symlink-state.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/safe-db" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/symlink-db.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$linked_root/db" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: invalid log destination'
log_file="$tmp/log-file"
printf 'existing file\n' > "$log_file"
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/bad-log" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/bad-log.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --log-dir "$log_file" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: concurrent lock refusal'
lock_state="$STATE_DIR/lock-test"
mkdir -p "$lock_state/ubuntu-system-tools/clamav"
exec 9>"$lock_state/ubuntu-system-tools/clamav/security-clamav-scan.lock"
flock -n 9 || fail 'test harness could not hold the lock'
run_expect_status 2 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$lock_state" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/lock.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1
exec 9>&-

printf '%s\n' 'TEST: clean status 0'
clean_log="$tmp/clean.log"
run_status="$(run_scan "$tmp/clean.out" "$tmp/clean.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/clean" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$clean_log" FAKE_CLAMSCAN_STDOUT='scan summary: clean' SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads")"
[[ "$run_status" -eq 0 ]] || fail "clean scan returned $run_status"
assert_contains "$tmp/clean.out" 'Result: clean' 'clean status was not reported as clean'
assert_contains "$clean_log" "$HOME_DIR/Downloads" 'clean scan did not reach the fake clamscan'

printf '%s\n' 'TEST: finding status 1'
finding_log="$tmp/finding.log"
run_status="$(run_scan "$tmp/finding.out" "$tmp/finding.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/finding" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$finding_log" FAKE_CLAMSCAN_STATUS=1 FAKE_CLAMSCAN_STDOUT='FOUND' SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads")"
[[ "$run_status" -eq 1 ]] || fail "finding scan returned $run_status"
assert_contains "$tmp/finding.out" 'Result: detection found; no file modified' 'finding status was not reported'
assert_contains "$finding_log" "$HOME_DIR/Downloads" 'finding scan did not reach the fake clamscan'

printf '%s\n' 'TEST: operational clamscan failure normalized to 2'
run_status="$(run_scan "$tmp/opfail.out" "$tmp/opfail.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/opfail" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/opfail.log" FAKE_CLAMSCAN_STATUS=2 SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads")"
[[ "$run_status" -eq 2 ]] || fail "operational failure scan returned $run_status"

printf '%s\n' 'TEST: cancellation status 3 before scanning'
cancel_out="$tmp/cancel.out"
cancel_err="$tmp/cancel.err"
cancel_log="$tmp/cancel.log"
rm -f -- "$cancel_log"
run_expect_status_with_input 3 $'n\n' \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/cancel" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$cancel_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --full >"$cancel_out" 2>"$cancel_err"
assert_contains "$cancel_err" 'WARNING: --full scans / recursively and can take many hours.' 'cancelled full scan did not warn'
[[ ! -e "$cancel_log" ]] || fail 'cancelled scan unexpectedly invoked clamscan'

printf '%s\n' 'TEST: SIGINT propagation'
sigint_out="$tmp/sigint.out"
sigint_err="$tmp/sigint.err"
sigint_log="$tmp/sigint.log"
sigint_tool_pid_file="$tmp/sigint-tool.pid"
sigint_clamscan_pid_file="$tmp/sigint-clamscan.pid"
set +e
run_group_signal_case INT "$sigint_tool_pid_file" "$sigint_clamscan_pid_file" "$sigint_out" "$sigint_err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/sigint" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$sigint_log" FAKE_CLAMSCAN_PID_FILE="$sigint_clamscan_pid_file" FAKE_CLAMSCAN_BUSY=1 \
  SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads"
sigint_status=$?
set -e
wait_for_file "$sigint_tool_pid_file" || fail 'security-clamav-scan did not start for SIGINT test'
wait_for_file "$sigint_clamscan_pid_file" || fail 'fake clamscan did not start for SIGINT test'
sigint_clamscan_pid="$(cat "$sigint_clamscan_pid_file")"
[[ "$sigint_status" -eq 130 ]] || fail "SIGINT run returned $sigint_status"
wait_for_pid_exit "$sigint_clamscan_pid" 'fake clamscan after SIGINT'
mapfile -t sigint_lines < "$sigint_log"
[[ "${#sigint_lines[@]}" -eq 5 ]] || fail 'SIGINT test unexpectedly started more than one scan invocation'

run_expect_status 0 \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/sigint-reuse" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$tmp/sigint-reuse.log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads" >/dev/null 2>&1

printf '%s\n' 'TEST: SIGTERM propagation'
sigterm_out="$tmp/sigterm.out"
sigterm_err="$tmp/sigterm.err"
sigterm_log="$tmp/sigterm.log"
sigterm_tool_pid_file="$tmp/sigterm-tool.pid"
sigterm_clamscan_pid_file="$tmp/sigterm-clamscan.pid"
set +e
run_group_signal_case TERM "$sigterm_tool_pid_file" "$sigterm_clamscan_pid_file" "$sigterm_out" "$sigterm_err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/sigterm" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$sigterm_log" FAKE_CLAMSCAN_PID_FILE="$sigterm_clamscan_pid_file" FAKE_CLAMSCAN_BUSY=1 \
  SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Downloads"
sigterm_status=$?
set -e
wait_for_file "$sigterm_tool_pid_file" || fail 'security-clamav-scan did not start for SIGTERM test'
wait_for_file "$sigterm_clamscan_pid_file" || fail 'fake clamscan did not start for SIGTERM test'
sigterm_clamscan_pid="$(cat "$sigterm_clamscan_pid_file")"
[[ "$sigterm_status" -eq 143 ]] || fail "SIGTERM run returned $sigterm_status"
wait_for_pid_exit "$sigterm_clamscan_pid" 'fake clamscan after SIGTERM'
mapfile -t sigterm_lines < "$sigterm_log"
[[ "${#sigterm_lines[@]}" -eq 5 ]] || fail 'SIGTERM test unexpectedly started more than one scan invocation'

printf '%s\n' 'TEST: exact safety-relevant arguments and no forbidden actions'
exact_log="$tmp/exact.log"
mkdir -p "$HOME_DIR/Custom-One"
run_status="$(run_scan "$tmp/exact.out" "$tmp/exact.err" \
  "$ENV_CMD" PATH="$default_path" HOME="$HOME_DIR" XDG_STATE_HOME="$STATE_DIR/exact" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  FAKE_CLAMSCAN_LOG="$exact_log" SECURITY_CLAMAV_SCAN_DB_DIRS="$DB_DIR" \
  "$tool" --target "$HOME_DIR/Custom-One" --log-dir "$STATE_DIR/exact-logs")"
[[ "$run_status" -eq 0 ]] || fail "exact-args scan returned $run_status"
assert_log_line "$exact_log" '--recursive' 'exact-args scan is missing recursion'
assert_log_line "$exact_log" '--cross-fs=no' 'exact-args scan is missing cross-fs=no'
assert_log_line "$exact_log" "--database=$DB_DIR" 'exact-args scan is missing database dir'
assert_log_line "$exact_log" "$HOME_DIR/Custom-One" 'exact-args scan is missing target'
assert_log_line "$exact_log" "--exclude-dir=$(literal_path_regex "$STATE_DIR/exact-logs")" 'exact-args scan is missing the anchored log-dir exclusion'
assert_not_contains "$exact_log" '--move=' 'exact-args scan unexpectedly used quarantine/move'
assert_not_contains "$exact_log" '--copy=' 'exact-args scan unexpectedly used copy quarantine'
assert_not_contains "$exact_log" 'freshclam' 'exact-args scan unexpectedly referenced freshclam'
assert_not_contains "$exact_log" 'curl' 'exact-args scan unexpectedly referenced curl'
assert_not_contains "$exact_log" 'wget' 'exact-args scan unexpectedly referenced wget'

printf '%s\n' 'OK: security-clamav-scan contract'
