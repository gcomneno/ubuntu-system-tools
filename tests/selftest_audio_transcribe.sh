#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$repo_root/bin/audio-transcribe"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || {
    printf 'EXPECTED: <%s>\n' "$expected" >&2
    printf 'ACTUAL:   <%s>\n' "$actual" >&2
    fail "$message"
  }
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

run_expect_status() {
  local expected_status="$1"
  shift

  set +e
  "$@"
  local actual_status=$?
  set -e

  [[ "$actual_status" -eq "$expected_status" ]] || {
    fail "expected exit status $expected_status, got $actual_status"
  }
}

printf '%s\n' 'TEST: executable exists'

[[ -x "$tool" ]] || fail "missing executable: $tool"

printf '%s\n' 'TEST: help documents the stable interface'

"$tool" --help >"$tmp/help.out" 2>"$tmp/help.err"

assert_contains "$tmp/help.out" \
  'audio-transcribe [OPTIONS] FILE' \
  'help does not document the main invocation'

assert_contains "$tmp/help.out" \
  '--allow-download' \
  'help does not document explicit model download consent'

assert_contains "$tmp/help.out" \
  '--output FILE' \
  'help does not document file output'

[[ ! -s "$tmp/help.err" ]] || fail "help unexpectedly wrote to stderr"

printf '%s\n' 'TEST: embedded Markdown help is available'

"$tool" --help-md >"$tmp/help-md.out" 2>"$tmp/help-md.err"

assert_contains "$tmp/help-md.out" \
  '# audio-transcribe' \
  'Markdown help title is missing'

assert_contains "$tmp/help-md.out" \
  'No automatic dependency installation' \
  'Markdown help does not state the dependency policy'

[[ ! -s "$tmp/help-md.err" ]] \
  || fail "Markdown help unexpectedly wrote to stderr"

printf '%s\n' 'TEST: prepare isolated fake faster-whisper module'

fake_root="$tmp/fake-python"
mkdir -p "$fake_root/faster_whisper"

cat > "$fake_root/faster_whisper/__init__.py" <<'PY'
import json
import os
from types import SimpleNamespace


def _record(event, payload):
    path = os.environ["FAKE_WHISPER_LOG"]
    with open(path, "a", encoding="utf-8") as stream:
        stream.write(
            json.dumps(
                {"event": event, **payload},
                ensure_ascii=False,
                sort_keys=True,
            )
            + "\n"
        )


class WhisperModel:
    def __init__(self, model_size_or_path, **kwargs):
        _record(
            "init",
            {
                "model": model_size_or_path,
                "kwargs": kwargs,
            },
        )

    def transcribe(self, audio, **kwargs):
        _record(
            "transcribe",
            {
                "audio": str(audio),
                "kwargs": kwargs,
            },
        )

        segments = [
            SimpleNamespace(text=" Sì "),
            SimpleNamespace(text=" tutto bene "),
        ]

        info = SimpleNamespace(language="it")
        return iter(segments), info
PY

audio="$tmp/WhatsApp Ptt 2026-07-31 at 09.16.47.ogg"
printf 'fake audio fixture\n' >"$audio"

python_bin="$(command -v python3)"

printf '%s\n' 'TEST: default transcription writes clean text to stdout'

log_default="$tmp/default.jsonl"

env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$log_default" \
  "$tool" \
  --model small \
  --language it \
  "$audio" \
  >"$tmp/default.out" \
  2>"$tmp/default.err"

assert_eq \
  'Sì tutto bene' \
  "$(cat "$tmp/default.out")" \
  'stdout transcription differs'

[[ ! -s "$tmp/default.err" ]] \
  || fail "successful transcription unexpectedly wrote to stderr"

LOG_PATH="$log_default" AUDIO_PATH="$audio" python3 - <<'PY'
import json
import os
from pathlib import Path

events = [
    json.loads(line)
    for line in Path(os.environ["LOG_PATH"]).read_text(encoding="utf-8").splitlines()
]

assert len(events) == 2, events

init, transcribe = events

assert init["event"] == "init", init
assert init["model"] == "small", init
assert init["kwargs"]["device"] == "cpu", init
assert init["kwargs"]["compute_type"] == "int8", init
assert init["kwargs"]["local_files_only"] is True, init

assert transcribe["event"] == "transcribe", transcribe
assert transcribe["audio"] == os.environ["AUDIO_PATH"], transcribe
assert transcribe["kwargs"]["language"] == "it", transcribe
assert transcribe["kwargs"]["task"] == "transcribe", transcribe
PY

printf '%s\n' 'TEST: output file and explicit download consent'

log_download="$tmp/download.jsonl"
output_file="$tmp/result.txt"

env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$log_download" \
  "$tool" \
  --allow-download \
  --language auto \
  --output "$output_file" \
  "$audio" \
  >"$tmp/download.out" \
  2>"$tmp/download.err"

[[ ! -s "$tmp/download.out" ]] \
  || fail "file-output mode unexpectedly wrote transcription to stdout"

[[ ! -s "$tmp/download.err" ]] \
  || fail "file-output mode unexpectedly wrote to stderr"

assert_eq \
  'Sì tutto bene' \
  "$(cat "$output_file")" \
  'written transcription differs'

LOG_PATH="$log_download" python3 - <<'PY'
import json
import os
from pathlib import Path

events = [
    json.loads(line)
    for line in Path(os.environ["LOG_PATH"]).read_text(encoding="utf-8").splitlines()
]

init, transcribe = events

assert init["kwargs"]["local_files_only"] is False, init
assert transcribe["kwargs"]["language"] is None, transcribe
PY

printf '%s\n' 'TEST: doctor reports the selected runtime'

env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/doctor.jsonl" \
  "$tool" \
  --doctor \
  >"$tmp/doctor.out" \
  2>"$tmp/doctor.err"

assert_contains "$tmp/doctor.out" \
  "Python: $python_bin" \
  'doctor does not report the selected interpreter'

assert_contains "$tmp/doctor.out" \
  'faster-whisper: available' \
  'doctor does not report faster-whisper availability'

[[ ! -s "$tmp/doctor.err" ]] \
  || fail "successful doctor unexpectedly wrote to stderr"

printf '%s\n' 'TEST: invalid invocations fail predictably'

run_expect_status 2 \
  "$tool" \
  >"$tmp/no-args.out" \
  2>"$tmp/no-args.err"

assert_contains "$tmp/no-args.err" \
  'ERROR: missing audio file' \
  'missing-file diagnostic differs'

run_expect_status 2 \
  "$tool" \
  "$tmp/does-not-exist.ogg" \
  >"$tmp/missing.out" \
  2>"$tmp/missing.err"

assert_contains "$tmp/missing.err" \
  'ERROR: audio file not found' \
  'nonexistent-file diagnostic differs'

run_expect_status 2 \
  "$tool" \
  --banana \
  "$audio" \
  >"$tmp/unknown.out" \
  2>"$tmp/unknown.err"

assert_contains "$tmp/unknown.err" \
  'ERROR: unknown option: --banana' \
  'unknown-option diagnostic differs'

printf '%s\n' 'OK: audio-transcribe contract'
