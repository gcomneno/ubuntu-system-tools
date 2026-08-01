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
        init_error = os.environ.get("FAKE_WHISPER_INIT_ERROR")
        if init_error:
            raise RuntimeError(init_error)

        _record(
            "init",
            {
                "model": model_size_or_path,
                "kwargs": kwargs,
            },
        )

    def transcribe(self, audio, **kwargs):
        transcribe_error = os.environ.get("FAKE_WHISPER_TRANSCRIBE_ERROR")
        if transcribe_error:
            raise RuntimeError(transcribe_error)

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

printf '%s\n' 'TEST: existing output is preserved without --force'

protected_output="$tmp/protected.txt"
printf 'keep this text\n' >"$protected_output"

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/protected.jsonl" \
  "$tool" \
  --output "$protected_output" \
  "$audio" \
  >"$tmp/protected.out" \
  2>"$tmp/protected.err"

assert_eq \
  'keep this text' \
  "$(cat "$protected_output")" \
  'existing output was modified without --force'

assert_contains "$tmp/protected.err" \
  'output file already exists; use --force' \
  'overwrite protection diagnostic differs'

printf '%s\n' 'TEST: --force replaces an existing output file'

env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/force.jsonl" \
  "$tool" \
  --force \
  --output "$protected_output" \
  "$audio" \
  >"$tmp/force.out" \
  2>"$tmp/force.err"

assert_eq \
  'Sì tutto bene' \
  "$(cat "$protected_output")" \
  '--force did not replace the existing output'

[[ ! -s "$tmp/force.out" ]] \
  || fail "forced file-output mode unexpectedly wrote to stdout"

[[ ! -s "$tmp/force.err" ]] \
  || fail "forced file-output mode unexpectedly wrote to stderr"

printf '%s\n' 'TEST: input and output cannot identify the same file'

same_file="$tmp/same-file.ogg"
printf 'original audio bytes\n' >"$same_file"

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/same-file.jsonl" \
  "$tool" \
  --force \
  --output "$same_file" \
  "$same_file" \
  >"$tmp/same-file.out" \
  2>"$tmp/same-file.err"

assert_eq \
  'original audio bytes' \
  "$(cat "$same_file")" \
  'same-file protection did not preserve the audio input'

assert_contains "$tmp/same-file.err" \
  'output file must differ from audio file' \
  'same-file diagnostic differs'

printf '%s\n' 'TEST: missing dependency fails before transcription'

missing_python="$tmp/python-without-faster-whisper"
cat > "$missing_python" <<'SH'
#!/usr/bin/env bash

if [[ "${1:-}" == "-c" ]]; then
  exit 1
fi

exec python3 "$@"
SH
chmod +x "$missing_python"

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$missing_python" \
  "$tool" \
  "$audio" \
  >"$tmp/missing-dependency.out" \
  2>"$tmp/missing-dependency.err"

assert_contains "$tmp/missing-dependency.err" \
  'faster-whisper is not available for Python' \
  'missing dependency diagnostic differs'

printf '%s\n' 'TEST: model initialization failure has a conditional cache hint'

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/init-failure.jsonl" \
  FAKE_WHISPER_INIT_ERROR='model cache unavailable' \
  "$tool" \
  "$audio" \
  >"$tmp/init-failure.out" \
  2>"$tmp/init-failure.err"

assert_contains "$tmp/init-failure.err" \
  'ERROR: model initialization failed: model cache unavailable' \
  'model initialization diagnostic differs'

assert_contains "$tmp/init-failure.err" \
  'if the selected model is not cached locally, retry with --allow-download' \
  'model cache hint is missing'

assert_not_contains "$tmp/init-failure.err" \
  'ERROR: transcription failed' \
  'model initialization failure was mislabeled as transcription failure'

printf '%s\n' 'TEST: transcription failure does not suggest a model download'

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/transcribe-failure.jsonl" \
  FAKE_WHISPER_TRANSCRIBE_ERROR='decoder exploded' \
  "$tool" \
  "$audio" \
  >"$tmp/transcribe-failure.out" \
  2>"$tmp/transcribe-failure.err"

assert_contains "$tmp/transcribe-failure.err" \
  'ERROR: transcription failed: decoder exploded' \
  'transcription failure diagnostic differs'

assert_not_contains "$tmp/transcribe-failure.err" \
  '--allow-download' \
  'transcription failure incorrectly suggested a model download'

printf '%s\n' 'TEST: output write failures are reported'

output_directory="$tmp/output-directory"
mkdir "$output_directory"

run_expect_status 2 \
  env \
  AUDIO_TRANSCRIBE_PYTHON="$python_bin" \
  PYTHONPATH="$fake_root" \
  FAKE_WHISPER_LOG="$tmp/write-failure.jsonl" \
  "$tool" \
  --force \
  --output "$output_directory" \
  "$audio" \
  >"$tmp/write-failure.out" \
  2>"$tmp/write-failure.err"

assert_contains "$tmp/write-failure.err" \
  'ERROR: cannot write output file' \
  'output write failure diagnostic differs'

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
