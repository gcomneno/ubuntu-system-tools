#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$repo_root/bin/kernel-health"
fixture_delayed="$repo_root/tests/fixtures/kernel-health/delayed_fput"

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
    cat -- "$path" >&2
    fail "$message"
  }
}

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq -- "$unexpected" "$path"; then
    printf 'UNEXPECTED TEXT: %s\n' "$unexpected" >&2
    cat -- "$path" >&2
    fail "$message"
  fi
}

assert_in_section() {
  local path="$1"
  local section="$2"
  local expected="$3"
  local message="$4"

  awk -v section="$section" -v expected="$expected" '
    $0 == section { active=1; next }
    /^(INCREASING|RECURRING|NEW)$/ && active { exit }
    active && index($0, expected) { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$path" || {
    printf 'MISSING IN SECTION %s: %s\n' "$section" "$expected" >&2
    cat -- "$path" >&2
    fail "$message"
  }
}

assert_not_in_section() {
  local path="$1"
  local section="$2"
  local unexpected="$3"
  local message="$4"

  if awk -v section="$section" -v unexpected="$unexpected" '
    $0 == section { active=1; next }
    /^(INCREASING|RECURRING|NEW)$/ && active { exit }
    active && index($0, unexpected) { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$path"; then
    printf 'UNEXPECTED IN SECTION %s: %s\n' "$section" "$unexpected" >&2
    cat -- "$path" >&2
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

  [[ "$actual" -eq "$expected" ]] \
    || fail "expected exit status $expected, got $actual"
}

fake_journal="$tmp/journalctl"
cat > "$fake_journal" <<'FAKE'
#!/usr/bin/env bash

boot=0
for arg in "$@"; do
  case "$arg" in
    --boot=*) boot="${arg#*=}" ;;
  esac
done

if [[ -n "${FAKE_JOURNAL_CALLS:-}" ]]; then
  printf '%s\n' "$*" >> "$FAKE_JOURNAL_CALLS"
fi

key="${boot#-}"
path="${FAKE_JOURNAL_ROOT:?}/boot-${key}.log"

if [[ ! -f "$path" ]]; then
  printf 'Data from the specified boot is not available\n' >&2
  exit 1
fi

cat -- "$path"

if [[ "${FAKE_JOURNAL_DIAGNOSTIC_BOOT:-}" == "$boot" ]]; then
  printf 'Journal file is truncated, ignoring incomplete tail\n' >&2
fi
FAKE
chmod 0755 "$fake_journal"

run_case() {
  local root="$1"
  shift
  env \
    KERNEL_HEALTH_JOURNALCTL="$fake_journal" \
    FAKE_JOURNAL_ROOT="$root" \
    "$tool" "$@"
}

make_root() {
  local name="$1"
  local root="$tmp/$name"
  mkdir -p "$root"
  printf '%s\n' "$root"
}

printf '%s\n' 'TEST: executable and help'
[[ -x "$tool" ]] || fail "missing executable: $tool"
"$tool" --help > "$tmp/help.out" 2> "$tmp/help.err"
assert_contains "$tmp/help.out" '--boots N' 'help does not document --boots'
assert_contains "$tmp/help.out" 'Read-only kernel warning analysis' 'help does not state purpose'
[[ ! -s "$tmp/help.err" ]] || fail 'help unexpectedly wrote to stderr'

printf '%s\n' 'TEST 1: warning only in current boot is NEW'
root="$(make_root new)"
printf '%s\n' 'Aug 09 07:00:00 host-a kernel: firmware warning: sample-new-warning' > "$root/boot-0.log"
: > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/new.out"
assert_in_section "$tmp/new.out" NEW 'firmware warning: sample-new-warning' 'current-only warning was not NEW'

printf '%s\n' 'TEST 2: same signature across boots is RECURRING'
root="$(make_root recurring)"
printf '%s\n' 'Aug 09 07:00:00 host-a kernel: ACPI warning: stable sample' > "$root/boot-0.log"
printf '%s\n' 'Aug 08 07:00:00 host-a kernel: ACPI warning: stable sample' > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/recurring.out"
assert_in_section "$tmp/recurring.out" RECURRING 'ACPI warning: stable sample' 'recurring warning was not classified as RECURRING'

printf '%s\n' 'TEST 3: delayed_fput growth is INCREASING'
run_case "$fixture_delayed" > "$tmp/increasing.out"
assert_in_section "$tmp/increasing.out" INCREASING 'workqueue: delayed_fput hogged CPU' 'delayed_fput was not INCREASING'
assert_contains "$tmp/increasing.out" 'current: 4 → 8 → 16' 'current delayed_fput sequence differs'
assert_contains "$tmp/increasing.out" 'previous: 4 → 8 → 16 → 32 → 64 → 128' 'previous delayed_fput sequence differs'
assert_contains "$tmp/increasing.out" 'previous-2: 4 → 8 → 16 → 32 → 64' 'previous-2 delayed_fput sequence differs'

printf '%s\n' 'TEST 4: recurring delayed_fput without growth is not INCREASING'
root="$(make_root flat-delayed)"
printf '%s\n' \
  'host-a kernel: workqueue: delayed_fput hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND' \
  'host-a kernel: workqueue: delayed_fput hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND' \
  > "$root/boot-0.log"
printf '%s\n' \
  'host-b kernel: workqueue: delayed_fput hogged CPU for >10000us 4 times, consider switching to WQ_UNBOUND' \
  > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/flat.out"
assert_in_section "$tmp/flat.out" RECURRING 'workqueue: delayed_fput hogged CPU' 'flat delayed_fput should be RECURRING'
assert_not_in_section "$tmp/flat.out" INCREASING 'workqueue: delayed_fput hogged CPU' 'flat delayed_fput became INCREASING'

printf '%s\n' 'TEST 5: different timestamps keep the same signature'
root="$(make_root timestamps)"
printf '%s\n' 'Aug 09 07:00:00 host-a kernel: sample timestamp warning' > "$root/boot-0.log"
printf '%s\n' '2026-08-08T06:00:00+0200 host-a kernel: sample timestamp warning' > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/timestamps.out"
assert_in_section "$tmp/timestamps.out" RECURRING 'sample timestamp warning' 'timestamp metadata changed the signature'

printf '%s\n' 'TEST 6: different hostnames keep the same signature'
root="$(make_root hostnames)"
printf '%s\n' 'Aug 09 07:00:00 host-a kernel: sample hostname warning' > "$root/boot-0.log"
printf '%s\n' 'Aug 08 07:00:00 host-b kernel: sample hostname warning' > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/hostnames.out"
assert_in_section "$tmp/hostnames.out" RECURRING 'sample hostname warning' 'hostname metadata changed the signature'

printf '%s\n' 'TEST 7: delayed_fput counters keep one stable signature'
count="$(grep -Fc -- '- workqueue: delayed_fput hogged CPU' "$tmp/increasing.out")"
[[ "$count" -eq 1 ]] || fail "delayed_fput rendered as $count distinct findings"
assert_contains "$tmp/increasing.out" 'boots: 3/3' 'delayed_fput did not group across all boots'

printf '%s\n' 'TEST 8: semantically different warnings are not merged'
root="$(make_root distinct)"
printf '%s\n' 'host-a kernel: device alpha reported timeout' > "$root/boot-0.log"
printf '%s\n' 'host-b kernel: device beta reported timeout' > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/distinct.out"
assert_in_section "$tmp/distinct.out" NEW 'device alpha reported timeout' 'current distinct warning should be NEW'
assert_not_in_section "$tmp/distinct.out" RECURRING 'device alpha reported timeout' 'different warnings were merged'

printf '%s\n' 'TEST 9: no warnings renders empty sections'
root="$(make_root empty)"
: > "$root/boot-0.log"
: > "$root/boot-1.log"
: > "$root/boot-2.log"
run_case "$root" > "$tmp/empty.out"
assert_contains "$tmp/empty.out" 'coverage: 3/3 boots available' 'empty run lost coverage information'
assert_not_contains "$tmp/empty.out" '- ' 'empty run unexpectedly rendered a finding'

printf '%s\n' 'TEST 10: unavailable previous boots degrade coverage without failing'
root="$(make_root unavailable)"
printf '%s\n' 'host-a kernel: only-current-warning' > "$root/boot-0.log"
run_case "$root" > "$tmp/unavailable.out"
assert_contains "$tmp/unavailable.out" 'coverage: 1/3 boots available' 'unavailable history coverage differs'
assert_in_section "$tmp/unavailable.out" NEW 'only-current-warning' 'current warning was lost when history was unavailable'

printf '%s\n' 'TEST 11: incomplete journal diagnostics do not discard usable data'
root="$(make_root partial)"
printf '%s\n' 'host-a kernel: partial-journal-warning' > "$root/boot-0.log"
printf '%s\n' 'host-b kernel: partial-journal-warning' > "$root/boot-1.log"
: > "$root/boot-2.log"
env \
  KERNEL_HEALTH_JOURNALCTL="$fake_journal" \
  FAKE_JOURNAL_ROOT="$root" \
  FAKE_JOURNAL_DIAGNOSTIC_BOOT='-1' \
  "$tool" > "$tmp/partial.out"
assert_contains "$tmp/partial.out" 'journal notes: 1 boot(s) reported diagnostics' 'partial journal note is missing'
assert_in_section "$tmp/partial.out" RECURRING 'partial-journal-warning' 'partial journal data was not analyzed'

printf '%s\n' 'TEST 12: no privilege escalation or root dependency exists'
if grep -Eq -- '\bsudo\b|\bsysctl\b|/proc|/sys|geteuid|setuid' "$tool"; then
  fail 'tool contains privilege escalation or system mutation primitives'
fi
run_case "$root" > "$tmp/no-root.out"
assert_contains "$tmp/no-root.out" 'KERNEL HEALTH' 'read-only execution failed without any privilege helper'

printf '%s\n' 'TEST 13: valid --boots controls the requested boot count'
root="$(make_root boots-two)"
printf '%s\n' 'host-a kernel: two-boot-warning' > "$root/boot-0.log"
printf '%s\n' 'host-b kernel: two-boot-warning' > "$root/boot-1.log"
calls="$tmp/calls.log"
env \
  KERNEL_HEALTH_JOURNALCTL="$fake_journal" \
  FAKE_JOURNAL_ROOT="$root" \
  FAKE_JOURNAL_CALLS="$calls" \
  "$tool" --boots 2 > "$tmp/boots-two.out"
assert_contains "$tmp/boots-two.out" 'coverage: 2/2 boots available' '--boots 2 did not set coverage'
[[ "$(wc -l < "$calls")" -eq 2 ]] || fail '--boots 2 did not make exactly two journal calls'
assert_contains "$calls" '--boot=0' 'current boot was not requested'
assert_contains "$calls" '--boot=-1' 'previous boot was not requested'
assert_not_contains "$calls" '--boot=-2' '--boots 2 requested an extra boot'
assert_contains "$calls" '-k -p warning' 'journal acquisition does not use kernel warning filtering'

printf '%s\n' 'TEST 14: invalid --boots input is rejected'
run_expect_status 2 "$tool" --boots 0 > "$tmp/invalid-zero.out" 2> "$tmp/invalid-zero.err"
run_expect_status 2 "$tool" --boots nope > "$tmp/invalid-text.out" 2> "$tmp/invalid-text.err"
run_expect_status 2 "$tool" --boots -1 > "$tmp/invalid-negative.out" 2> "$tmp/invalid-negative.err"
assert_contains "$tmp/invalid-zero.err" 'must be a positive integer' 'zero --boots diagnostic differs'
assert_contains "$tmp/invalid-text.err" 'must be a positive integer' 'text --boots diagnostic differs'

printf '%s\n' 'OK: kernel-health contract'
