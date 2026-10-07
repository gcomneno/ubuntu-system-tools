#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$repo_root/bin/storage-check"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local message="$3"

  grep -Fq -- "$expected" "$file" || {
    printf 'MISSING TEXT: %s\n' "$expected" >&2
    cat -- "$file" >&2
    fail "$message"
  }
}

run_capture() {
  local out="$1"
  local err="$2"
  shift 2

  set +e
  "$@" >"$out" 2>"$err"
  local rc=$?
  set -e

  printf '%s\n' "$rc"
}

printf '%s\n' 'TEST: help'
out="$tmp/help.out"
err="$tmp/help.err"
rc="$(run_capture "$out" "$err" "$tool" --help)"
[[ "$rc" -eq 0 ]] || fail "help returned $rc"
assert_contains "$out" 'storage-check - read-only storage health and growth attribution' 'help title missing'
assert_contains "$out" '--save-checkpoint may create or replace only the explicitly selected' 'checkpoint safety contract missing from help'
assert_contains "$out" '--docker' 'Docker audit option missing from help'
assert_contains "$out" '--ddev' 'DDEV audit option missing from help'

printf '%s\n' 'TEST: normal inspection'
mkdir -p "$tmp/projects/repo-a" "$tmp/projects/repo-b"
dd if=/dev/zero of="$tmp/projects/repo-a/blob" bs=1M count=1 status=none
dd if=/dev/zero of="$tmp/projects/repo-b/blob" bs=1M count=2 status=none

out="$tmp/normal.out"
err="$tmp/normal.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --elephant-min-bytes 1 \
  --root-warn-percent 100)"

[[ "$rc" -eq 0 ]] || fail "normal inspection returned $rc"
assert_contains "$out" '===== STORAGE HEALTH =====' 'health section missing'
assert_contains "$out" 'CHECKPOINT_STATUS=NOT_REQUESTED' 'checkpoint status missing'
assert_contains "$out" 'PROJECTS_DIR_STATUS=AVAILABLE' 'projects status missing'
assert_contains "$out" 'AUTOMATIC_DELETION=NO' 'safety result missing'

printf '%s\n' 'TEST: optional audit orchestration'

fake_docker_audit="$tmp/fake-storage-docker-audit"
fake_ddev_audit="$tmp/fake-storage-ddev-audit"

cat > "$fake_docker_audit" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'FAKE_DOCKER_AUDIT=PASS'
printf '%s\n' 'STALE_CONFIRMED_COUNT=0'
printf '%s\n' 'AUTOMATIC_DELETION=NO'
EOF

cat > "$fake_ddev_audit" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -ne 2 || "$1" != "--projects-dir" || "$2" != "$EXPECTED_PROJECTS_DIR" ]]; then
  printf '%s\n' 'unexpected DDEV audit invocation' >&2
  exit 91
fi

printf '%s\n' 'FAKE_DDEV_AUDIT=PASS'
printf '%s\n' 'STALE_CONFIRMED_COUNT=0'
printf '%s\n' 'AUTOMATIC_DELETION=NO'
EOF

chmod 0755 "$fake_docker_audit" "$fake_ddev_audit"

out="$tmp/orchestration.out"
err="$tmp/orchestration.err"

rc="$(
  run_capture     "$out"     "$err"     env     STORAGE_DOCKER_AUDIT_BIN="$fake_docker_audit"     STORAGE_DDEV_AUDIT_BIN="$fake_ddev_audit"     EXPECTED_PROJECTS_DIR="$tmp/projects"     "$tool"     --projects-dir "$tmp/projects"     --elephant-min-bytes 999999999999     --root-warn-percent 100     --docker     --ddev
)"

[[ "$rc" -eq 0 ]] || fail "optional audit orchestration returned $rc"
assert_contains "$out" '===== OPTIONAL DOCKER AUDIT =====' 'Docker audit section missing'
assert_contains "$out" 'FAKE_DOCKER_AUDIT=PASS' 'Docker audit delegation missing'
assert_contains "$out" '===== OPTIONAL DDEV AUDIT =====' 'DDEV audit section missing'
assert_contains "$out" 'FAKE_DDEV_AUDIT=PASS' 'DDEV audit delegation missing'

# Restore the normal-inspection output consumed by the following elephant assertions.
out="$tmp/normal.out"

printf '%s\n' 'TEST: elephant ordering and threshold'
mapfile -t elephant_lines < <(grep '^ELEPHANT_BYTES=' "$out")
[[ "${#elephant_lines[@]}" -eq 2 ]] ||
  fail "expected 2 elephant entries, got ${#elephant_lines[@]}"
[[ "${elephant_lines[0]}" == *$'PATH='"$tmp/projects/repo-b" ]] ||
  fail "largest elephant was not listed first"
[[ "${elephant_lines[1]}" == *$'PATH='"$tmp/projects/repo-a" ]] ||
  fail "smaller elephant was not listed second"

out="$tmp/threshold.out"
err="$tmp/threshold.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --elephant-min-bytes 1500000 \
  --root-warn-percent 100)"

[[ "$rc" -eq 0 ]] || fail "elephant threshold inspection returned $rc"
assert_contains "$out" 'ELEPHANT_COUNT=1' 'elephant threshold count differs'
assert_contains "$out" "PATH=$tmp/projects/repo-b" 'large project missing above threshold'

if grep -Fq -- "PATH=$tmp/projects/repo-a" "$out"; then
  fail "small project was not filtered by elephant threshold"
fi

printf '%s\n' 'TEST: warning exit status'
out="$tmp/warning.out"
err="$tmp/warning.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --elephant-min-bytes 999999999999 \
  --root-warn-percent 0)"

[[ "$rc" -eq 1 ]] || fail "warning inspection returned $rc"
assert_contains "$out" 'STORAGE_HEALTH=WARNING' 'warning health missing'

printf '%s\n' 'TEST: missing projects directory remains inspectable'
missing="$tmp/does-not-exist"
out="$tmp/missing.out"
err="$tmp/missing.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$missing" \
  --root-warn-percent 100)"

[[ "$rc" -eq 0 ]] || fail "missing project directory returned $rc"
assert_contains "$out" 'PROJECTS_BYTES=UNAVAILABLE' 'missing project bytes not marked unavailable'
assert_contains "$out" 'PROJECTS_DIR_STATUS=UNAVAILABLE' 'missing project status not marked unavailable'

printf '%s\n' 'TEST: checkpoint roundtrip'
checkpoint="$tmp/checkpoint.env"

out="$tmp/save.out"
err="$tmp/save.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --elephant-min-bytes 999999999999 \
  --root-warn-percent 100 \
  --save-checkpoint "$checkpoint")"

[[ "$rc" -eq 0 ]] || fail "checkpoint save returned $rc"
[[ -f "$checkpoint" ]] || fail "checkpoint was not created"
assert_contains "$checkpoint" 'ROOT_USED_BYTES=' 'checkpoint root bytes missing'
assert_contains "$checkpoint" 'HOME_BYTES=' 'checkpoint home bytes missing'
assert_contains "$checkpoint" 'VAR_BYTES=' 'checkpoint var bytes missing'
assert_contains "$checkpoint" 'PROJECTS_BYTES=' 'checkpoint projects bytes missing'

out="$tmp/compare.out"
err="$tmp/compare.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --elephant-min-bytes 999999999999 \
  --root-warn-percent 100 \
  --checkpoint "$checkpoint")"

[[ "$rc" -eq 0 ]] || fail "checkpoint compare returned $rc"
assert_contains "$out" 'CHECKPOINT_STATUS=AVAILABLE' 'checkpoint availability missing'
assert_contains "$out" 'ROOT_USED_DELTA_BYTES=' 'root delta missing'
assert_contains "$out" 'HOME_DELTA_BYTES=' 'home delta missing'
assert_contains "$out" 'VAR_DELTA_BYTES=' 'var delta missing'
assert_contains "$out" 'PROJECTS_DELTA_BYTES=' 'projects delta missing'

printf '%s\n' 'TEST: malformed checkpoint refusal'
bad_checkpoint="$tmp/bad-checkpoint.env"
printf '%s\n' \
  'ROOT_USED_BYTES=123' \
  'ROOT_AVAILABLE_BYTES=456' \
  'ROOT_USAGE_PERCENT=50' \
  'HOME_BYTES=789' \
  'VAR_BYTES=UNAVAILABLE' \
  'UNKNOWN_KEY=42' \
  > "$bad_checkpoint"

out="$tmp/bad.out"
err="$tmp/bad.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --projects-dir "$tmp/projects" \
  --checkpoint "$bad_checkpoint")"

[[ "$rc" -eq 2 ]] || fail "malformed checkpoint returned $rc"
assert_contains "$err" 'unsupported checkpoint key: UNKNOWN_KEY' 'malformed checkpoint refusal missing'

printf '%s\n' 'TEST: invalid threshold refusal'
out="$tmp/invalid.out"
err="$tmp/invalid.err"
rc="$(run_capture \
  "$out" \
  "$err" \
  "$tool" \
  --root-warn-percent 101)"

[[ "$rc" -eq 2 ]] || fail "invalid threshold returned $rc"
assert_contains "$err" 'root warning percentage must be between 0 and 100' 'invalid threshold refusal missing'

printf '%s\n' 'OK: storage-check contract'
