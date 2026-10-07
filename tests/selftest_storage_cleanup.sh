#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/bin/storage-cleanup"

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

fakebin="$tmp/bin"
state="$tmp/state"
mutations="$tmp/mutations"

mkdir -p "$fakebin"
: > "$mutations"

image_id="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
volume_name="safe-volume"

cat > "$fakebin/docker" <<'DOCKER'
#!/usr/bin/env bash

set -Eeuo pipefail

state="${FAKE_DOCKER_STATE:?}"
mutations="${FAKE_DOCKER_MUTATIONS:?}"
mode="${FAKE_DOCKER_MODE:-safe}"
image_id="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
volume_name="safe-volume"

counter_file="$state/reference-count"
image_present="$state/image-present"
volume_present="$state/volume-present"

increment_reference_counter() {
    local count=0

    if [[ -f "$counter_file" ]]; then
        count="$(cat "$counter_file")"
    fi

    count=$((count + 1))
    printf '%s\n' "$count" > "$counter_file"
    printf '%s\n' "$count"
}

case "$*" in
    "version --format {{.Server.Version}}")
        printf '29.8.2\n'
        ;;

    "image inspect --format {{.Id}} repo:unused")
        [[ -f "$image_present" ]] || exit 1
        printf '%s\n' "$image_id"
        ;;

    "image inspect --format {{.Id}} repo:running")
        printf '%s\n' "$image_id"
        ;;

    "image inspect --format {{.Id}} repo:stopped")
        printf '%s\n' "$image_id"
        ;;

    "image inspect --format {{.Id}} repo:race")
        printf '%s\n' "$image_id"
        ;;

    "image inspect --format {{.Id}} repo:survivor")
        printf '%s\n' "$image_id"
        ;;

    "image inspect --format {{.Id}} repo:remove-fail")
        printf '%s\n' "$image_id"
        ;;

    "volume inspect --format {{.Name}} $volume_name")
        [[ -f "$volume_present" ]] || exit 1
        printf '%s\n' "$volume_name"
        ;;

    "image ls --no-trunc --format {{.ID}}")
        if [[ "$mode" == "verify-backend-fail" ]]; then
            exit 1
        fi

        if [[ "$mode" == "verify-survivor" || -f "$image_present" ]]; then
            printf '%s\n' "$image_id"
        fi
        ;;

    "volume ls --format {{.Name}}")
        if [[ "$mode" == "verify-volume-backend-fail" ]]; then
            exit 1
        fi

        if [[ -f "$volume_present" ]]; then
            printf '%s\n' "$volume_name"
        fi
        ;;

    "ps --filter ancestor=$image_id --format {{.ID}}")
        case "$mode" in
            image-running)
                printf 'container-running\n'
                ;;
            image-race)
                call="$(increment_reference_counter)"
                if (( call >= 3 )); then
                    printf 'container-race\n'
                fi
                ;;
        esac
        ;;

    "ps -a --filter ancestor=$image_id --format {{.ID}}")
        case "$mode" in
            image-running)
                printf 'container-running\n'
                ;;
            image-stopped)
                printf 'container-stopped\n'
                ;;
            image-race)
                call="$(increment_reference_counter)"
                if (( call >= 3 )); then
                    printf 'container-race\n'
                fi
                ;;
        esac
        ;;

    "ps --filter volume=$volume_name --format {{.ID}}")
        if [[ "$mode" == "volume-running" ]]; then
            printf 'container-running\n'
        fi
        ;;

    "ps -a --filter volume=$volume_name --format {{.ID}}")
        case "$mode" in
            volume-running)
                printf 'container-running\n'
                ;;
            volume-stopped)
                printf 'container-stopped\n'
                ;;
        esac
        ;;

    "image rm -- $image_id")
        printf 'docker image rm -- %s\n' "$image_id" >> "$mutations"

        if [[ "$mode" == "remove-fail" ]]; then
            exit 1
        fi

        if [[ "$mode" != "verify-survivor" ]]; then
            rm -f "$image_present"
        fi

        printf '%s\n' "$image_id"
        ;;

    "volume rm -- $volume_name")
        printf 'docker volume rm -- %s\n' "$volume_name" >> "$mutations"
        rm -f "$volume_present"
        printf '%s\n' "$volume_name"
        ;;

    *)
        printf 'unexpected docker invocation: %s\n' "$*" >&2
        exit 99
        ;;
esac
DOCKER

chmod 0755 "$fakebin/docker"

reset_state() {
    rm -rf "$state"
    mkdir -p "$state"
    touch "$state/image-present" "$state/volume-present"
    : > "$mutations"
}

run_tool() {
    FAKE_DOCKER_STATE="$state" \
    FAKE_DOCKER_MUTATIONS="$mutations" \
    FAKE_DOCKER_MODE="${FAKE_DOCKER_MODE:-safe}" \
    PATH="$fakebin:$PATH" \
    "$TOOL" "$@"
}

echo "TEST: help documents controlled-action boundary"

help_output="$("$TOOL" --help)"

assert_contains "$help_output" "exact-target Docker storage cleanup"
assert_contains "$help_output" "Preview only"
assert_contains "$help_output" "explicit target plus --apply"
assert_contains "$help_output" "no prune commands"
assert_contains "$help_output" "AUTOMATIC_DELETION is always NO"

echo "TEST: image preview is non-mutating"

reset_state
FAKE_DOCKER_MODE="safe"
export FAKE_DOCKER_MODE

output="$(run_tool image repo:unused)"

assert_contains "$output" "MODE=PREVIEW"
assert_contains "$output" "TARGET_TYPE=IMAGE"
assert_contains "$output" "TARGET_ID=$image_id"
assert_contains "$output" "RUNNING_REFS=0"
assert_contains "$output" "CONTAINER_REFS=0"
assert_contains "$output" "PLANNED_COMMAND=docker image rm -- $image_id"
assert_contains "$output" "VERIFY_STATUS=NOT_RUN"
assert_contains "$output" "MUTATION_ATTEMPTED=NO"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

[[ ! -s "$mutations" ]] ||
    fail "image preview performed a mutation"

[[ -f "$state/image-present" ]] ||
    fail "image preview changed image state"

echo "TEST: image apply mutates exact resolved ID and verifies absence"

reset_state
FAKE_DOCKER_MODE="safe"
export FAKE_DOCKER_MODE

output="$(run_tool image repo:unused --apply)"

assert_contains "$output" "MODE=APPLY"
assert_contains "$output" "REVALIDATION_RUNNING_REFS=0"
assert_contains "$output" "REVALIDATION_CONTAINER_REFS=0"
assert_contains "$output" "MUTATION_COMMAND=docker image rm -- $image_id"
assert_contains "$output" "VERIFY_STATUS=PASS"
assert_contains "$output" "MUTATION_ATTEMPTED=YES"
assert_contains "$output" "AUTOMATIC_DELETION=NO"

grep -Fxq "docker image rm -- $image_id" "$mutations" ||
    fail "exact image mutation was not recorded"

[[ ! -f "$state/image-present" ]] ||
    fail "image remained after successful apply"

echo "TEST: running image reference refuses before mutation"

reset_state
FAKE_DOCKER_MODE="image-running"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:running --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected running-image refusal status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=image_in_use_by_running_container:$image_id"

[[ ! -s "$mutations" ]] ||
    fail "running image refusal performed a mutation"

echo "TEST: stopped image reference also refuses"

reset_state
FAKE_DOCKER_MODE="image-stopped"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:stopped --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected stopped-image refusal status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=image_referenced_by_container:$image_id"

[[ ! -s "$mutations" ]] ||
    fail "stopped image refusal performed a mutation"

echo "TEST: image reference appearing during revalidation refuses"

reset_state
FAKE_DOCKER_MODE="image-race"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:race --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected revalidation refusal status 2, got $failure_status"

assert_contains "$failure_output" "PRE-MUTATION REVALIDATION"
assert_contains "$failure_output" "ERROR=image_in_use_by_running_container:$image_id"

[[ ! -s "$mutations" ]] ||
    fail "revalidation refusal performed a mutation"

echo "TEST: volume preview is non-mutating"

reset_state
FAKE_DOCKER_MODE="safe"
export FAKE_DOCKER_MODE

output="$(run_tool volume "$volume_name")"

assert_contains "$output" "MODE=PREVIEW"
assert_contains "$output" "TARGET_TYPE=VOLUME"
assert_contains "$output" "TARGET_NAME=$volume_name"
assert_contains "$output" "PLANNED_COMMAND=docker volume rm -- $volume_name"
assert_contains "$output" "MUTATION_ATTEMPTED=NO"

[[ ! -s "$mutations" ]] ||
    fail "volume preview performed a mutation"

[[ -f "$state/volume-present" ]] ||
    fail "volume preview changed volume state"

echo "TEST: volume apply mutates exact name and verifies absence"

reset_state
FAKE_DOCKER_MODE="safe"
export FAKE_DOCKER_MODE

output="$(run_tool volume "$volume_name" --apply)"

assert_contains "$output" "MODE=APPLY"
assert_contains "$output" "MUTATION_COMMAND=docker volume rm -- $volume_name"
assert_contains "$output" "VERIFY_STATUS=PASS"
assert_contains "$output" "MUTATION_ATTEMPTED=YES"

grep -Fxq "docker volume rm -- $volume_name" "$mutations" ||
    fail "exact volume mutation was not recorded"

[[ ! -f "$state/volume-present" ]] ||
    fail "volume remained after successful apply"

echo "TEST: stopped volume reference refuses"

reset_state
FAKE_DOCKER_MODE="volume-stopped"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool volume "$volume_name" --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected stopped-volume refusal status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=volume_referenced_by_container:$volume_name"

[[ ! -s "$mutations" ]] ||
    fail "stopped volume refusal performed a mutation"

echo "TEST: invalid targets fail closed"

reset_state
FAKE_DOCKER_MODE="safe"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image '../bad target' --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected invalid-image status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=invalid_image_target:../bad target"

[[ ! -s "$mutations" ]] ||
    fail "invalid target performed a mutation"

echo "TEST: Docker remove failure is fatal"

reset_state
FAKE_DOCKER_MODE="remove-fail"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:remove-fail --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 2 ]] ||
    fail "expected remove failure status 2, got $failure_status"

assert_contains "$failure_output" "ERROR=image_remove_failed:$image_id"
assert_contains "$failure_output" "MUTATION_ATTEMPTED=YES"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

grep -Fxq "docker image rm -- $image_id" "$mutations" ||
    fail "remove-failure test did not reach the exact mutation"

echo "TEST: post-mutation survivor is verification failure"

reset_state
FAKE_DOCKER_MODE="verify-survivor"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:survivor --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 3 ]] ||
    fail "expected verification status 3, got $failure_status"

assert_contains "$failure_output" "VERIFY_STATUS=FAIL"
assert_contains "$failure_output" "ERROR=image_still_present:$image_id"
assert_contains "$failure_output" "MUTATION_ATTEMPTED=YES"

echo "TEST: post-mutation verification backend failure is fatal"

reset_state
FAKE_DOCKER_MODE="verify-backend-fail"
export FAKE_DOCKER_MODE

set +e
failure_output="$(run_tool image repo:unused --apply 2>&1)"
failure_status=$?
set -e

[[ "$failure_status" -eq 3 ]] ||
    fail "expected verification-backend status 3, got $failure_status"

assert_contains "$failure_output" "VERIFY_STATUS=FAIL"
assert_contains "$failure_output" "ERROR=image_verification_failed:$image_id"
assert_contains "$failure_output" "MUTATION_ATTEMPTED=YES"
assert_contains "$failure_output" "AUTOMATIC_DELETION=NO"

echo "OK: storage-cleanup controlled-action contract"
