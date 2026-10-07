#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/storage-cleanup-proposal"

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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"

    [[ "$haystack" != *"$needle"* ]] ||
        fail "expected output not to contain: $needle"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

audit="$tmp/storage-docker-audit"

image_candidate="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
image_active="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

write_audit() {
    cat > "$audit"
    chmod 0755 "$audit"
}

echo "TEST: help documents proposal authority boundary"

help_output="$("$TOOL" --help)"

assert_contains "$help_output" "read-only Docker cleanup proposal manifest"
assert_contains "$help_output" "proposal is not deletion authority"
assert_contains "$help_output" "never emits or executes --apply"
assert_contains "$help_output" "Runs as the current user"
assert_contains "$help_output" "storage-docker-audit, sort, awk, and grep"
assert_contains "$help_output" "AUTOMATIC_DELETION is always NO"

echo "TEST: deterministic candidate proposal and deduplication"

write_audit <<EOF
#!/usr/bin/env bash
printf '%s\n' \
'TYPE=CONTAINER|ID=running|NAME=app|IMAGE=repo:active|STATE=running|CLASS=ACTIVE' \
'TYPE=IMAGE|ID=$image_active|REF=repo:active|SIZE_BYTES=100|RUNNING_REFS=1|CONTAINER_REFS=1|CLASS=ACTIVE' \
'TYPE=IMAGE|ID=$image_candidate|REF=repo:unused|SIZE_BYTES=300|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE' \
'TYPE=IMAGE|ID=$image_candidate|REF=repo:other-tag|SIZE_BYTES=300|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE' \
'TYPE=VOLUME|NAME=volume-z|DRIVER=local|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE' \
'TYPE=VOLUME|NAME=volume-a|DRIVER=local|RUNNING_REFS=0|CONTAINER_REFS=1|CLASS=INACTIVE_PROTECTED' \
'TYPE=BUILD_CACHE|ID=cache-a|SIZE_BYTES=900|DOCKER_RECLAIMABLE=YES|SHARED=NO|MUTABLE=NO|LAST_USED=old|CLASS=STALE_CANDIDATE' \
'STALE_CONFIRMED_COUNT=0' \
'AUTOMATIC_DELETION=NO'
EOF

output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL"
)"

assert_contains "$output" "PROPOSAL_SCOPE=DOCKER_IMAGE_VOLUME"
assert_contains "$output" "SOURCE_CLASS=STALE_CANDIDATE"
assert_contains "$output" "STALE_CONFIRMED=NO"
assert_contains "$output" "REVIEW_REQUIRED=YES"
assert_contains "$output" "AUTHORITY=NO"

assert_contains "$output" "PROPOSAL|TYPE=IMAGE|TARGET=$image_candidate"
assert_contains "$output" "PREVIEW_COMMAND=storage-cleanup image $image_candidate"
assert_contains "$output" "PROPOSAL|TYPE=VOLUME|TARGET=volume-z"
assert_contains "$output" "PREVIEW_COMMAND=storage-cleanup volume volume-z"

assert_not_contains "$output" "$image_active"
assert_not_contains "$output" "volume-a"
assert_not_contains "$output" "cache-a"
assert_not_contains "$output" "--apply"

[[ "$(grep -Fc "PROPOSAL|TYPE=IMAGE|TARGET=$image_candidate" <<<"$output")" -eq 1 ]] ||
    fail "duplicate image target was not deduplicated"

assert_contains "$output" "PROPOSAL_COUNT=2"
assert_contains "$output" "IMAGE_PROPOSAL_COUNT=1"
assert_contains "$output" "VOLUME_PROPOSAL_COUNT=1"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

echo "TEST: no candidates produces an empty safe manifest"

write_audit <<EOF
#!/usr/bin/env bash
printf '%s\n' \
'TYPE=IMAGE|ID=$image_active|REF=repo:active|SIZE_BYTES=100|RUNNING_REFS=1|CONTAINER_REFS=1|CLASS=ACTIVE' \
'STALE_CANDIDATE_COUNT=0' \
'STALE_CONFIRMED_COUNT=0' \
'AUTOMATIC_DELETION=NO'
EOF

output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL"
)"

assert_contains "$output" "PROPOSAL_COUNT=0"
assert_contains "$output" "IMAGE_PROPOSAL_COUNT=0"
assert_contains "$output" "VOLUME_PROPOSAL_COUNT=0"
assert_contains "$output" "REVIEW_REQUIRED=YES"
assert_contains "$output" "AUTHORITY=NO"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

echo "TEST: contradictory candidate evidence fails closed"

write_audit <<EOF
#!/usr/bin/env bash
printf '%s\n' \
'TYPE=IMAGE|ID=$image_candidate|REF=repo:bad|SIZE_BYTES=300|RUNNING_REFS=0|CONTAINER_REFS=1|CLASS=STALE_CANDIDATE' \
'STALE_CONFIRMED_COUNT=0' \
'AUTOMATIC_DELETION=NO'
EOF

set +e
failure_output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL" 2>&1
)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected contradictory evidence status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=contradictory_container_reference:IMAGE:$image_candidate"
assert_contains "$failure_output" "AUTHORITY=NO"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

echo "TEST: malformed exact image identity fails closed"

write_audit <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
'TYPE=IMAGE|ID=not-an-image-id|REF=repo:bad|SIZE_BYTES=300|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE' \
'STALE_CONFIRMED_COUNT=0' \
'AUTOMATIC_DELETION=NO'
EOF

set +e
failure_output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL" 2>&1
)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected malformed image status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=invalid_candidate_image_id:not-an-image-id"

echo "TEST: missing Docker audit safety contract fails closed"

write_audit <<EOF
#!/usr/bin/env bash
printf '%s\n' \
'TYPE=IMAGE|ID=$image_candidate|REF=repo:unused|SIZE_BYTES=300|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE' \
'AUTOMATIC_DELETION=NO'
EOF

set +e
failure_output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL" 2>&1
)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected missing-contract status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=docker_audit_contract_missing:STALE_CONFIRMED_COUNT=0"
assert_contains "$failure_output" "AUTHORITY=NO"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

echo "TEST: Docker audit failure fails closed"

write_audit <<'EOF'
#!/usr/bin/env bash
printf 'DOCKER_STATUS=UNAVAILABLE\n'
printf 'STALE_CONFIRMED_COUNT=0\n'
printf 'AUTOMATIC_DELETION=NO\n'
exit 2
EOF

set +e
failure_output="$(
    STORAGE_DOCKER_AUDIT_BIN="$audit" \
        "$TOOL" 2>&1
)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected audit failure status 2, got $failure_status"

assert_contains "$failure_output" "DOCKER_STATUS=UNAVAILABLE"
assert_contains "$failure_output" "ERROR=docker_audit_failed"
assert_contains "$failure_output" "AUTHORITY=NO"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

echo "TEST: unknown option is rejected"

set +e
failure_output="$("$TOOL" --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected unknown-option status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=unknown_option:--apply"

echo "OK: storage-cleanup-proposal read-only proposal contract"
