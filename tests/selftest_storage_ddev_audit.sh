#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/storage-ddev-audit"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"

    [[ "$haystack" == *"$needle"* ]] ||
        fail "expected output to contain: $needle"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

projects="$tmp/projects"
fakebin="$tmp/bin"

mkdir -p \
    "$projects/registered/.ddev" \
    "$projects/worktree/.ddev" \
    "$fakebin"

cat > "$projects/registered/.ddev/config.yaml" <<'EOF'
name: registered
type: php
EOF

cat > "$projects/registered/.ddev/.ddev-docker-compose-full.yaml" <<EOF
services:
  web:
    labels:
      com.ddev.approot: $projects/registered
EOF

cat > "$projects/worktree/.ddev/config.yaml" <<'EOF'
type: php
EOF

cat > "$projects/worktree/.ddev/.ddev-docker-compose-full.yaml" <<EOF
services:
  web:
    labels:
      com.ddev.approot: $projects/old-worktree-path
EOF

git init -q "$projects/registered"
git init -q "$projects/worktree"

cat > "$fakebin/ddev" <<'DDEV'
#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$*" != "list --json-output" ]]; then
    printf 'unexpected ddev invocation: %s\n' "$*" >&2
    exit 99
fi

jq -nc \
    --arg registered "$DDEV_TEST_PROJECTS/registered" \
    --arg missing "$DDEV_TEST_PROJECTS/missing-registered" \
    '{
        raw: [
            {
                name: "registered",
                status: "paused",
                approot: $registered,
                type: "php"
            },
            {
                name: "missing-registered",
                status: "paused",
                approot: $missing,
                type: "php"
            }
        ]
    }'
DDEV

chmod 0755 "$fakebin/ddev"

echo "TEST: help"

help_output="$("$TOOL" --help)"
assert_contains "$help_output" "read-only DDEV provenance and metadata audit"
assert_contains "$help_output" "STALE_PATH"
assert_contains "$help_output" "DDEV-only audit"
assert_contains "$help_output" "AUTOMATIC_DELETION is always NO"

echo "TEST: provenance classification"

output="$(
    DDEV_TEST_PROJECTS="$projects" \
    PATH="$fakebin:$PATH" \
    "$TOOL" --projects-dir "$projects"
)"

assert_contains "$output" "DDEV_STATUS=AVAILABLE"
assert_contains "$output" "REGISTERED_PROJECT_COUNT=2"
assert_contains "$output" "PROJECTS_DIR_STATUS=AVAILABLE"

assert_contains "$output" "PROJECT=registered|DDEV_STATUS=paused|TYPE=php|APPROOT=$projects/registered|REGISTRY_STATE=REGISTERED|SOURCE_STATE=PRESENT|CONFIG_STATE=PRESENT|GIT_STATE=WORKTREE|DDEV_METADATA_STATE=CONSISTENT|GENERATED_APPROOT=$projects/registered|CLASS=INACTIVE_PROTECTED"

assert_contains "$output" "PROJECT=missing-registered|DDEV_STATUS=paused|TYPE=php|APPROOT=$projects/missing-registered|REGISTRY_STATE=REGISTERED|SOURCE_STATE=MISSING|CONFIG_STATE=MISSING|GIT_STATE=UNAVAILABLE|DDEV_METADATA_STATE=STALE_PATH|GENERATED_APPROOT=UNAVAILABLE|CLASS=STALE_CANDIDATE"

assert_contains "$output" "PROJECT=worktree|DDEV_STATUS=UNREGISTERED|TYPE=UNKNOWN|APPROOT=$projects/worktree|REGISTRY_STATE=UNREGISTERED|SOURCE_STATE=PRESENT|CONFIG_STATE=PRESENT|GIT_STATE=WORKTREE|DDEV_METADATA_STATE=STALE_PATH|GENERATED_APPROOT=$projects/old-worktree-path|CLASS=INACTIVE_PROTECTED"

assert_contains "$output" "DISCOVERED_UNREGISTERED_COUNT=1"
assert_contains "$output" "ACTIVE_COUNT=0"
assert_contains "$output" "INACTIVE_PROTECTED_COUNT=2"
assert_contains "$output" "STALE_CANDIDATE_COUNT=1"
assert_contains "$output" "STALE_CONFIRMED_COUNT=0"
assert_contains "$output" "UNKNOWN_COUNT=0"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

echo "TEST: invalid relative projects directory"

set +e
relative_output="$(
    DDEV_TEST_PROJECTS="$projects" \
    PATH="$fakebin:$PATH" \
    "$TOOL" --projects-dir relative/path 2>&1
)"
relative_status=$?
set -e

[[ "$relative_status" -eq 2 ]] ||
    fail "expected relative-path status 2, got $relative_status"

assert_contains "$relative_output" "ERROR=projects_dir_must_be_absolute"

echo "TEST: malformed DDEV JSON fails closed"

cat > "$fakebin/ddev" <<'DDEV'
#!/usr/bin/env bash

printf '{"raw":"not-an-array"}\n'
DDEV

chmod 0755 "$fakebin/ddev"

set +e
malformed_output="$(
    PATH="$fakebin:$PATH" \
    "$TOOL" --projects-dir "$projects" 2>&1
)"
malformed_status=$?
set -e

[[ "$malformed_status" -eq 2 ]] ||
    fail "expected malformed-json status 2, got $malformed_status"

assert_contains "$malformed_output" "ERROR=invalid_ddev_json"

echo "TEST: DDEV operational failure fails closed"

cat > "$fakebin/ddev" <<'DDEV'
#!/usr/bin/env bash

exit 1
DDEV

chmod 0755 "$fakebin/ddev"

set +e
failure_output="$(
    PATH="$fakebin:$PATH" \
    "$TOOL" --projects-dir "$projects" 2>&1
)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected DDEV failure status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=ddev_list_failed"

echo "OK: storage-ddev-audit contract"
