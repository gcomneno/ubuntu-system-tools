#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/storage-docker-audit"

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

fakebin="$tmp/bin"
mkdir -p "$fakebin"

cat > "$fakebin/docker" <<'DOCKER'
#!/usr/bin/env bash

set -Eeuo pipefail

case "$*" in
    "version --format {{.Server.Version}}")
        printf '29.8.2\n'
        ;;

    "system df --format json")
        cat <<'EOF'
{"Active":"1","Reclaimable":"2GB (50%)","Size":"4GB","TotalCount":"3","Type":"Images"}
{"Active":"1","Reclaimable":"10MB (50%)","Size":"20MB","TotalCount":"2","Type":"Containers"}
{"Active":"1","Reclaimable":"300MB (60%)","Size":"500MB","TotalCount":"3","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"100MB","Size":"1GB","TotalCount":"2","Type":"Build Cache"}
EOF
        ;;

    "ps -a --no-trunc --format {{json .}}")
        cat <<'EOF'
{"ID":"container-running","Image":"repo:active","Names":"running-app","State":"running"}
{"ID":"container-stopped","Image":"repo:stopped","Names":"stopped-app","State":"exited"}
EOF
        ;;

    "image ls --no-trunc --format {{json .}}")
        cat <<'EOF'
{"ID":"sha256:image-active","Repository":"repo","Size":"100MB","Tag":"active"}
{"ID":"sha256:image-stopped","Repository":"repo","Size":"200MB","Tag":"stopped"}
{"ID":"sha256:image-unreferenced","Repository":"repo","Size":"300MB","Tag":"unused"}
EOF
        ;;

    "volume ls --format {{json .}}")
        cat <<'EOF'
{"Driver":"local","Name":"volume-active"}
{"Driver":"local","Name":"volume-stopped"}
{"Driver":"local","Name":"volume-unreferenced"}
EOF
        ;;

    "buildx du --format json")
        cat <<'EOF'
{"ID":"cache-reclaimable","LastUsedAt":"2 days ago","Mutable":false,"Reclaimable":true,"Shared":false,"Size":"100MB"}
{"ID":"cache-protected","LastUsedAt":"1 hour ago","Mutable":true,"Reclaimable":false,"Shared":true,"Size":"200MB"}
EOF
        ;;

    "ps --filter ancestor=sha256:image-active --format {{.ID}}")
        printf 'container-running\n'
        ;;

    "ps -a --filter ancestor=sha256:image-active --format {{.ID}}")
        printf 'container-running\n'
        ;;

    "ps --filter ancestor=sha256:image-stopped --format {{.ID}}")
        ;;

    "ps -a --filter ancestor=sha256:image-stopped --format {{.ID}}")
        printf 'container-stopped\n'
        ;;

    "ps --filter ancestor=sha256:image-unreferenced --format {{.ID}}")
        ;;

    "ps -a --filter ancestor=sha256:image-unreferenced --format {{.ID}}")
        ;;

    "ps --filter volume=volume-active --format {{.ID}}")
        printf 'container-running\n'
        ;;

    "ps -a --filter volume=volume-active --format {{.ID}}")
        printf 'container-running\n'
        ;;

    "ps --filter volume=volume-stopped --format {{.ID}}")
        ;;

    "ps -a --filter volume=volume-stopped --format {{.ID}}")
        printf 'container-stopped\n'
        ;;

    "ps --filter volume=volume-unreferenced --format {{.ID}}")
        ;;

    "ps -a --filter volume=volume-unreferenced --format {{.ID}}")
        ;;

    *)
        printf 'unexpected docker invocation: %s\n' "$*" >&2
        exit 99
        ;;
esac
DOCKER

chmod 0755 "$fakebin/docker"

echo "TEST: help"

help_output="$("$TOOL" --help)"
assert_contains "$help_output" "read-only Docker storage evidence audit"
assert_contains "$help_output" "AUTOMATIC_DELETION is always NO"
assert_contains "$help_output" "Docker-only audit never emits this class"

echo "TEST: deterministic classification contract"

output="$(PATH="$fakebin:$PATH" "$TOOL")"

assert_contains "$output" "DOCKER_STATUS=AVAILABLE"
assert_contains "$output" "IMAGE_SIZE_BYTES=4000000000"
assert_contains "$output" "IMAGE_RECLAIMABLE_BYTES=2000000000"
assert_contains "$output" "VOLUME_SIZE_BYTES=500000000"
assert_contains "$output" "BUILD_CACHE_SIZE_BYTES=1000000000"

assert_contains "$output" "TYPE=CONTAINER|ID=container-running|NAME=running-app|IMAGE=repo:active|STATE=running|CLASS=ACTIVE"
assert_contains "$output" "TYPE=CONTAINER|ID=container-stopped|NAME=stopped-app|IMAGE=repo:stopped|STATE=exited|CLASS=INACTIVE_PROTECTED"

assert_contains "$output" "TYPE=IMAGE|ID=sha256:image-active|REF=repo:active|SIZE_BYTES=100000000|RUNNING_REFS=1|CONTAINER_REFS=1|CLASS=ACTIVE"
assert_contains "$output" "TYPE=IMAGE|ID=sha256:image-stopped|REF=repo:stopped|SIZE_BYTES=200000000|RUNNING_REFS=0|CONTAINER_REFS=1|CLASS=INACTIVE_PROTECTED"
assert_contains "$output" "TYPE=IMAGE|ID=sha256:image-unreferenced|REF=repo:unused|SIZE_BYTES=300000000|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE"

assert_contains "$output" "TYPE=VOLUME|NAME=volume-active|DRIVER=local|RUNNING_REFS=1|CONTAINER_REFS=1|CLASS=ACTIVE"
assert_contains "$output" "TYPE=VOLUME|NAME=volume-stopped|DRIVER=local|RUNNING_REFS=0|CONTAINER_REFS=1|CLASS=INACTIVE_PROTECTED"
assert_contains "$output" "TYPE=VOLUME|NAME=volume-unreferenced|DRIVER=local|RUNNING_REFS=0|CONTAINER_REFS=0|CLASS=STALE_CANDIDATE"

assert_contains "$output" "TYPE=BUILD_CACHE|ID=cache-reclaimable|SIZE_BYTES=100000000|DOCKER_RECLAIMABLE=YES|SHARED=NO|MUTABLE=NO|LAST_USED=2 days ago|CLASS=STALE_CANDIDATE"
assert_contains "$output" "TYPE=BUILD_CACHE|ID=cache-protected|SIZE_BYTES=200000000|DOCKER_RECLAIMABLE=NO|SHARED=YES|MUTABLE=YES|LAST_USED=1 hour ago|CLASS=INACTIVE_PROTECTED"

assert_contains "$output" "ACTIVE_COUNT=3"
assert_contains "$output" "INACTIVE_PROTECTED_COUNT=4"
assert_contains "$output" "STALE_CANDIDATE_COUNT=3"
assert_contains "$output" "STALE_CONFIRMED_COUNT=0"
assert_contains "$output" "UNKNOWN_COUNT=0"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

echo "TEST: invalid invocation"

if "$TOOL" --not-a-real-option >/dev/null 2>&1; then
    fail "invalid option unexpectedly succeeded"
fi

echo "TEST: Docker daemon failure fails closed"

cat > "$fakebin/docker" <<'DOCKER'
#!/usr/bin/env bash

if [[ "$*" == "version --format {{.Server.Version}}" ]]; then
    exit 1
fi

exit 99
DOCKER

chmod 0755 "$fakebin/docker"

set +e
failure_output="$(PATH="$fakebin:$PATH" "$TOOL" 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected Docker-unavailable status 2, got $failure_status"

assert_contains "$failure_output" "DOCKER_STATUS=UNAVAILABLE"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

echo "OK: storage-docker-audit contract"
