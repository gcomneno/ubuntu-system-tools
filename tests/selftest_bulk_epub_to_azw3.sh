#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/bulk-epub-to-azw3"

command -v zip >/dev/null 2>&1 || {
  echo "SKIP: missing command: zip"
  exit 0
}

[[ -x "$SCRIPT" ]] || {
  echo "FAIL: script is not executable: $SCRIPT"
  exit 1
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/src"
OUT="$TMPDIR/out"
FAKEBIN="$TMPDIR/fakebin"

mkdir -p "$SRC/nested" "$OUT" "$FAKEBIN"

cat > "$FAKEBIN/ebook-convert" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "--version" ]]; then
  echo "ebook-convert fake 1.2.3"
  exit 0
fi

input="$1"
output="$2"

printf 'converted from %s\n' "$input" > "$output"
EOF

chmod +x "$FAKEBIN/ebook-convert"

create_valid_epub() {
  local dest="$1"
  local title="$2"
  local creator="$3"
  local language="$4"
  local identifier="$5"
  local include_cover="$6"
  local include_spine="$7"
  local workdir
  local metadata=""
  local manifest=""
  local spine=""

  workdir="$(mktemp -d "$TMPDIR/epub.XXXXXX")"

  mkdir -p "$workdir/META-INF" "$workdir/OEBPS"

  printf 'application/epub+zip' > "$workdir/mimetype"

  cat > "$workdir/META-INF/container.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

  if [[ -n "$title" ]]; then
    metadata+="    <dc:title>$title</dc:title>"$'\n'
  fi

  if [[ -n "$creator" ]]; then
    metadata+="    <dc:creator>$creator</dc:creator>"$'\n'
  fi

  if [[ -n "$language" ]]; then
    metadata+="    <dc:language>$language</dc:language>"$'\n'
  fi

  if [[ -n "$identifier" ]]; then
    metadata+="    <dc:identifier id=\"bookid\">$identifier</dc:identifier>"$'\n'
  fi

  if [[ "$include_cover" == "yes" ]]; then
    metadata+="    <meta name=\"cover\" content=\"cover-image\"/>"$'\n'
    manifest+="    <item id=\"cover-image\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"$'\n'
    printf 'fake cover image\n' > "$workdir/OEBPS/cover.jpg"
  fi

  if [[ "$include_spine" == "yes" ]]; then
    manifest+="    <item id=\"chapter-1\" href=\"chapter-1.xhtml\" media-type=\"application/xhtml+xml\"/>"$'\n'
    spine+="    <itemref idref=\"chapter-1\"/>"$'\n'
    cat > "$workdir/OEBPS/chapter-1.xhtml" <<'EOF'
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter 1</title></head><body><p>Hello.</p></body></html>
EOF
  fi

  cat > "$workdir/OEBPS/content.opf" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
$metadata  </metadata>
  <manifest>
$manifest  </manifest>
  <spine>
$spine  </spine>
</package>
EOF

  if [[ "$include_cover" == "yes" && "$include_spine" == "yes" ]]; then
    (
      cd "$workdir"
      zip -q -X "$dest" mimetype META-INF/container.xml OEBPS/content.opf OEBPS/cover.jpg OEBPS/chapter-1.xhtml
    )
  elif [[ "$include_cover" == "yes" ]]; then
    (
      cd "$workdir"
      zip -q -X "$dest" mimetype META-INF/container.xml OEBPS/content.opf OEBPS/cover.jpg
    )
  elif [[ "$include_spine" == "yes" ]]; then
    (
      cd "$workdir"
      zip -q -X "$dest" mimetype META-INF/container.xml OEBPS/content.opf OEBPS/chapter-1.xhtml
    )
  else
    (
      cd "$workdir"
      zip -q -X "$dest" mimetype META-INF/container.xml OEBPS/content.opf
    )
  fi
}

create_valid_epub "$SRC/Book One.epub" "Book One" "Test Author" "en" "book-one-id" "yes" "yes"
create_valid_epub "$SRC/nested/Book Two.epub" "" "" "" "" "no" "no"
printf 'not an epub\n' > "$SRC/broken.epub"

"$SCRIPT" --src "$SRC" --out "$OUT" --preflight > "$TMPDIR/preflight.log"

if find "$OUT" -type f | grep -q .; then
  echo "FAIL: preflight created files in output"
  exit 1
fi

grep -Eq 'Mode: PREFLIGHT' "$TMPDIR/preflight.log"
grep -Eq 'Title:[[:space:]]+Book One' "$TMPDIR/preflight.log"
grep -Eq 'Creator:[[:space:]]+Test Author' "$TMPDIR/preflight.log"
grep -Eq 'Language:[[:space:]]+en' "$TMPDIR/preflight.log"
grep -Eq 'Identifier:[[:space:]]+book-one-id' "$TMPDIR/preflight.log"
grep -Eq 'Cover:[[:space:]]+yes' "$TMPDIR/preflight.log"
grep -Eq 'Spine items:[[:space:]]+1' "$TMPDIR/preflight.log"
grep -Eq 'Title:[[:space:]]+\(missing\)' "$TMPDIR/preflight.log"
grep -Eq 'missing creator' "$TMPDIR/preflight.log"
grep -Eq 'cover not detected' "$TMPDIR/preflight.log"
grep -Eq 'empty spine' "$TMPDIR/preflight.log"
grep -Eq 'Preflighted:[[:space:]]+2' "$TMPDIR/preflight.log"
grep -Eq 'EPUB invalid:[[:space:]]+1' "$TMPDIR/preflight.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" --dry-run > "$TMPDIR/dry-run.log"

if find "$OUT" -type f | grep -q .; then
  echo "FAIL: dry-run created files in output"
  exit 1
fi

grep -Eq 'EPUB found:[[:space:]]+3' "$TMPDIR/dry-run.log"
grep -Eq 'EPUB valid:[[:space:]]+2' "$TMPDIR/dry-run.log"
grep -Eq 'EPUB invalid:[[:space:]]+1' "$TMPDIR/dry-run.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" > "$TMPDIR/run.log"

[[ -f "$OUT/Book One.azw3" ]]
[[ -f "$OUT/nested/Book Two.azw3" ]]
[[ ! -f "$OUT/broken.azw3" ]]

grep -Eq 'Converted:[[:space:]]+2' "$TMPDIR/run.log"
grep -Eq 'EPUB invalid:[[:space:]]+1' "$TMPDIR/run.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" > "$TMPDIR/rerun.log"

grep -Eq 'Converted:[[:space:]]+0' "$TMPDIR/rerun.log"
grep -Eq 'Skipped:[[:space:]]+2' "$TMPDIR/rerun.log"

if "$SCRIPT" --src "$SRC" --preflight --manifest 2>/dev/null; then
  echo "FAIL: preflight + manifest should fail"
  exit 1
fi

MANIFEST_DRY="$TMPDIR/manifest-dry.jsonl"
OUT_DRY="$TMPDIR/out-dry-manifest"
mkdir -p "$OUT_DRY"
PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT_DRY" --dry-run --manifest "$MANIFEST_DRY" > "$TMPDIR/manifest-dry.log"

[[ -f "$MANIFEST_DRY" ]]

python3 - "$MANIFEST_DRY" <<'PY'
import json
import sys
from collections import Counter

records = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
if len(records) != 3:
    raise SystemExit(f"expected 3 manifest records, got {len(records)}")

statuses = Counter(record["status"] for record in records)
if statuses != Counter({"invalid": 1, "planned": 2}):
    raise SystemExit(f"unexpected dry-run manifest statuses: {statuses}")

for record in records:
    for key in ("source", "output", "timestamp", "source_size", "source_sha256"):
        if key not in record:
            raise SystemExit(f"missing manifest field {key}: {record}")
PY

OUT_MAN="$TMPDIR/out-manifest"
mkdir -p "$OUT_MAN"
MANIFEST_REAL="$TMPDIR/manifest-real.jsonl"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT_MAN" --manifest "$MANIFEST_REAL" > "$TMPDIR/manifest-real.log"

[[ -f "$OUT_MAN/Book One.azw3" ]]
[[ -f "$OUT_MAN/nested/Book Two.azw3" ]]

python3 - "$MANIFEST_REAL" <<'PY'
import json
import sys
from collections import Counter

records = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
if len(records) != 3:
    raise SystemExit(f"expected 3 manifest records, got {len(records)}")

statuses = Counter(record["status"] for record in records)
if statuses != Counter({"converted": 2, "invalid": 1}):
    raise SystemExit(f"unexpected conversion manifest statuses: {statuses}")

for record in records:
    if record["status"] == "converted":
        for key in ("output_size", "output_sha256", "ebook_convert_version"):
            if key not in record:
                raise SystemExit(f"missing converted manifest field {key}: {record}")
PY

OUT_DEFAULT="$TMPDIR/out-default-manifest"
mkdir -p "$OUT_DEFAULT"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT_DEFAULT" --manifest > "$TMPDIR/manifest-default.log"

[[ -f "$OUT_DEFAULT/conversion-manifest.jsonl" ]]

MANIFEST_SKIP="$TMPDIR/manifest-skip.jsonl"
PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT_MAN" --manifest "$MANIFEST_SKIP" > "$TMPDIR/manifest-skip.log"

python3 - "$MANIFEST_SKIP" <<'PY'
import json
import sys
from collections import Counter

records = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
if len(records) != 3:
    raise SystemExit(f"expected 3 manifest records, got {len(records)}")

statuses = Counter(record["status"] for record in records)
if statuses != Counter({"skipped": 2, "invalid": 1}):
    raise SystemExit(f"unexpected skip manifest statuses: {statuses}")

for record in records:
    if record["status"] == "skipped":
        if record.get("reason") != "already exists":
            raise SystemExit(f"unexpected skip reason: {record}")
        if "output_sha256" not in record:
            raise SystemExit(f"missing output_sha256 on skipped record: {record}")
PY

if "$SCRIPT" --src "$SRC" --preflight --quarantine "$TMPDIR/bad-quarantine" 2>/dev/null; then
  echo "FAIL: preflight + quarantine should fail"
  exit 1
fi

if "$SCRIPT" --quarantine-copy --src "$SRC" --out "$OUT" 2>/dev/null; then
  echo "FAIL: quarantine-copy without quarantine should fail"
  exit 1
fi

QUARANTINE_SRC="$TMPDIR/quarantine-src"
QUARANTINE_OUT="$TMPDIR/quarantine-out"
QUARANTINE_DIR="$TMPDIR/quarantine"
FAKEBIN_FAIL="$TMPDIR/fakebin-fail"

mkdir -p "$QUARANTINE_SRC/nested" "$QUARANTINE_OUT" "$QUARANTINE_DIR" "$FAKEBIN_FAIL"

create_valid_epub "$QUARANTINE_SRC/Book One.epub" "Book One" "Test Author" "en" "book-one-id" "yes" "yes"
create_valid_epub "$QUARANTINE_SRC/nested/Book Two.epub" "Book Two" "Test Author" "en" "book-two-id" "yes" "yes"
printf 'not an epub\n' > "$QUARANTINE_SRC/broken.epub"

cat > "$FAKEBIN_FAIL/ebook-convert" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "--version" ]]; then
  echo "ebook-convert fake 1.2.3"
  exit 0
fi

input=""
output=""
debug_pipeline=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug-pipeline)
      debug_pipeline="$2"
      shift 2
      ;;
    *)
      if [[ -z "$input" ]]; then
        input="$1"
      elif [[ -z "$output" ]]; then
        output="$1"
      fi
      shift
      ;;
  esac
done

if [[ "$(basename "$input")" == "Book One.epub" ]] && [[ -z "$debug_pipeline" ]]; then
  echo "simulated conversion failure" >&2
  exit 1
fi

if [[ -n "$debug_pipeline" ]]; then
  mkdir -p "$debug_pipeline"
  printf 'debug pipeline for %s\n' "$input" > "$debug_pipeline/pipeline.txt"
  echo "simulated conversion failure with debug" >&2
  exit 1
fi

printf 'converted from %s\n' "$input" > "$output"
EOF

chmod +x "$FAKEBIN_FAIL/ebook-convert"

set +e
PATH="$FAKEBIN_FAIL:$PATH" "$SCRIPT" \
  --src "$QUARANTINE_SRC" \
  --out "$QUARANTINE_OUT" \
  --quarantine "$QUARANTINE_DIR" > "$TMPDIR/quarantine-run.log"
quarantine_status=$?
set -e

if [[ "$quarantine_status" -ne 2 ]]; then
  echo "FAIL: expected exit code 2 when conversion fails, got $quarantine_status"
  exit 1
fi

[[ -f "$QUARANTINE_DIR/invalid/broken.epub/reason.txt" ]]
[[ -f "$QUARANTINE_DIR/invalid/broken.epub/source.path" ]]
grep -qx 'not a valid EPUB' "$QUARANTINE_DIR/invalid/broken.epub/reason.txt"

[[ -f "$QUARANTINE_DIR/failed/Book One.epub/reason.txt" ]]
[[ -f "$QUARANTINE_DIR/failed/Book One.epub/source.path" ]]
[[ -f "$QUARANTINE_DIR/failed/Book One.epub/convert.log" ]]
grep -qx 'conversion failed' "$QUARANTINE_DIR/failed/Book One.epub/reason.txt"
grep -q 'simulated conversion failure' "$QUARANTINE_DIR/failed/Book One.epub/convert.log"

if [[ -L "$QUARANTINE_DIR/invalid/broken.epub/source.epub" ]]; then
  [[ "$(readlink "$QUARANTINE_DIR/invalid/broken.epub/source.epub")" == "$QUARANTINE_SRC/broken.epub" ]]
elif [[ ! -f "$QUARANTINE_DIR/invalid/broken.epub/source.epub" ]]; then
  echo "FAIL: expected symlink or copy for quarantined invalid EPUB"
  exit 1
fi

QUARANTINE_COPY_DIR="$TMPDIR/quarantine-copy"
mkdir -p "$QUARANTINE_COPY_DIR"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$QUARANTINE_SRC" \
  --out "$TMPDIR/quarantine-copy-out" \
  --quarantine "$QUARANTINE_COPY_DIR" \
  --quarantine-copy \
  --force > "$TMPDIR/quarantine-copy.log"

[[ -f "$QUARANTINE_COPY_DIR/invalid/broken.epub/source.epub" ]]
[[ ! -L "$QUARANTINE_COPY_DIR/invalid/broken.epub/source.epub" ]]

MOBI_SRC="$TMPDIR/mobi-src"
MOBI_OUT="$TMPDIR/mobi-out"
mkdir -p "$MOBI_SRC/nested" "$MOBI_OUT"

printf 'fake mobi\n' > "$MOBI_SRC/Story.mobi"
printf 'fake mobi\n' > "$MOBI_SRC/nested/Other.mobi"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --from mobi \
  --to epub \
  --src "$MOBI_SRC" \
  --out "$MOBI_OUT" \
  --dry-run > "$TMPDIR/mobi-dry.log"

grep -Eq 'FROM: mobi' "$TMPDIR/mobi-dry.log"
grep -Eq 'TO: epub' "$TMPDIR/mobi-dry.log"
grep -Eq 'DRY \[epub\]: ebook-convert .*/Story\.mobi.*/Story\.epub' "$TMPDIR/mobi-dry.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --from mobi \
  --to epub \
  --src "$MOBI_SRC" \
  --out "$MOBI_OUT" > "$TMPDIR/mobi-run.log"

[[ -f "$MOBI_OUT/Story.epub" ]]
[[ -f "$MOBI_OUT/nested/Other.epub" ]]
grep -Eq 'Source found:[[:space:]]+2' "$TMPDIR/mobi-run.log"
grep -Eq 'Converted:[[:space:]]+2' "$TMPDIR/mobi-run.log"

WRAPPER="$ROOT/bin/bulk-ebook-convert"
[[ -x "$WRAPPER" ]]
PATH="$FAKEBIN:$PATH" "$WRAPPER" --from mobi --to epub --src "$MOBI_SRC" --out "$TMPDIR/mobi-wrapper-out" --dry-run > "$TMPDIR/mobi-wrapper.log"
grep -Eq 'FROM: mobi' "$TMPDIR/mobi-wrapper.log"

if "$SCRIPT" --from mobi --preflight --src "$MOBI_SRC" 2>/dev/null; then
  echo "FAIL: preflight with --from mobi should fail"
  exit 1
fi

if "$SCRIPT" --from foo --to epub --src "$SRC" 2>/dev/null; then
  echo "FAIL: unsupported --from should fail"
  exit 1
fi

if "$SCRIPT" --from epub --to foo --src "$SRC" 2>/dev/null; then
  echo "FAIL: unsupported --to should fail"
  exit 1
fi

PDF_SRC="$TMPDIR/pdf-src"
mkdir -p "$PDF_SRC"
printf 'fake pdf\n' > "$PDF_SRC/sample.pdf"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --from pdf \
  --to epub \
  --src "$PDF_SRC" \
  --out "$TMPDIR/pdf-out" \
  --dry-run > "$TMPDIR/pdf-dry.log"

grep -Eq 'WARNING: PDF is often a poor source for ebook conversion' "$TMPDIR/pdf-dry.log"

DJVU_SRC="$TMPDIR/djvu-src"
mkdir -p "$DJVU_SRC"
printf 'fake djvu\n' > "$DJVU_SRC/sample.djvu"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --from djvu \
  --to epub \
  --src "$DJVU_SRC" \
  --out "$TMPDIR/djvu-out" \
  --dry-run > "$TMPDIR/djvu-dry.log"

grep -Eq 'NOTE: DJVU conversion quality depends on an embedded text layer' "$TMPDIR/djvu-dry.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --target kindle \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --dry-run > "$TMPDIR/target-kindle.log"

grep -Eq 'TARGET: kindle' "$TMPDIR/target-kindle.log"
grep -Eq 'TO: azw3' "$TMPDIR/target-kindle.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --target archive \
  --src "$SRC" \
  --out "$TMPDIR/target-archive-out" \
  --dry-run > "$TMPDIR/target-archive.log"

grep -Eq 'TARGET: archive' "$TMPDIR/target-archive.log"
grep -Eq 'TO: epub' "$TMPDIR/target-archive.log"

if "$SCRIPT" --target foo --src "$SRC" 2>/dev/null; then
  echo "FAIL: unknown --target should fail"
  exit 1
fi

if "$SCRIPT" --target kindle --to mobi --src "$SRC" 2>/dev/null; then
  echo "FAIL: --target with --to should fail"
  exit 1
fi

if "$SCRIPT" --target kindle --to azw3,epub --src "$SRC" 2>/dev/null; then
  echo "FAIL: --target with multiple --to formats should fail"
  exit 1
fi

MULTI_BASE="$TMPDIR/multi-base"
mkdir -p "$MULTI_BASE"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --to azw3,epub \
  --out "$MULTI_BASE" \
  --dry-run > "$TMPDIR/multi-dry.log"

grep -Eq 'Targets: azw3,epub' "$TMPDIR/multi-dry.log"
grep -Eq 'DRY \[azw3\]: ebook-convert .*/Book One\.epub.*/Book One\.azw3' "$TMPDIR/multi-dry.log"
grep -Eq 'DRY \[epub\]: ebook-convert .*/Book One\.epub.*/Book One\.epub' "$TMPDIR/multi-dry.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --to azw3,epub \
  --out "$MULTI_BASE" > "$TMPDIR/multi-run.log"

[[ -f "$MULTI_BASE/azw3/Book One.azw3" ]]
[[ -f "$MULTI_BASE/epub/Book One.epub" ]]
[[ -f "$MULTI_BASE/azw3/nested/Book Two.azw3" ]]
[[ -f "$MULTI_BASE/epub/nested/Book Two.epub" ]]
grep -Eq 'Converted:[[:space:]]+4' "$TMPDIR/multi-run.log"

printf 'existing azw3 output\n' > "$MULTI_BASE/azw3/Book One.azw3"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --to azw3,epub \
  --out "$MULTI_BASE" > "$TMPDIR/multi-skip.log"

grep -Eq 'SKIP \[azw3\]: already exists' "$TMPDIR/multi-skip.log"
grep -Eq 'Converted:[[:space:]]+0' "$TMPDIR/multi-skip.log"
grep -Eq 'Skipped:[[:space:]]+4' "$TMPDIR/multi-skip.log"

MULTI_DEFAULT="$TMPDIR/multi-default"
mkdir -p "$MULTI_DEFAULT"

(
  cd "$MULTI_DEFAULT"
  PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --to azw3,epub
) > "$TMPDIR/multi-default.log"

[[ -f "$MULTI_DEFAULT/azw3/Book One.azw3" ]]
[[ -f "$MULTI_DEFAULT/epub/Book One.epub" ]]

DEBUG_DIR="$TMPDIR/debug-failed"
DEBUG_OUT="$TMPDIR/debug-out"
mkdir -p "$DEBUG_DIR" "$DEBUG_OUT"

PATH="$FAKEBIN_FAIL:$PATH" "$SCRIPT" \
  --src "$QUARANTINE_SRC" \
  --out "$DEBUG_OUT" \
  --debug-failed "$DEBUG_DIR" \
  --dry-run > "$TMPDIR/debug-dry.log"

grep -Eq 'Debug-failed:' "$TMPDIR/debug-dry.log"
grep -Eq 'DEBUG-FAIL \[azw3\]: would write to .*/Book One\.epub on failure' "$TMPDIR/debug-dry.log"

set +e
PATH="$FAKEBIN_FAIL:$PATH" "$SCRIPT" \
  --src "$QUARANTINE_SRC" \
  --out "$DEBUG_OUT" \
  --debug-failed "$DEBUG_DIR" > "$TMPDIR/debug-run.log"
debug_status=$?
set -e

if [[ "$debug_status" -ne 2 ]]; then
  echo "FAIL: expected exit code 2 when debug-failed conversion fails, got $debug_status"
  exit 1
fi

[[ -f "$DEBUG_DIR/Book One.epub/pipeline.txt" ]]
grep -Eq 'debug pipeline for .*/Book One\.epub' "$DEBUG_DIR/Book One.epub/pipeline.txt"
grep -Eq 'DEBUG-FAIL \[azw3\]: exported to' "$TMPDIR/debug-run.log"

if "$SCRIPT" --src "$SRC" --preflight --debug-failed "$DEBUG_DIR" 2>/dev/null; then
  echo "FAIL: preflight + debug-failed should fail"
  exit 1
fi

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cover-policy prefer-metadata \
  --dry-run > "$TMPDIR/cover-prefer.log"

grep -Eq 'Cover-policy: prefer-metadata \(--prefer-metadata-cover\)' "$TMPDIR/cover-prefer.log"
grep -F -- '--prefer-metadata-cover' "$TMPDIR/cover-prefer.log"
grep -Fq 'DRY [azw3]:' "$TMPDIR/cover-prefer.log"
grep -Fq 'Book One.epub' "$TMPDIR/cover-prefer.log"
grep -Fq 'Book One.azw3' "$TMPDIR/cover-prefer.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cover-policy remove-first-image \
  --dry-run > "$TMPDIR/cover-remove.log"

grep -Eq 'Cover-policy: remove-first-image \(--remove-first-image\)' "$TMPDIR/cover-remove.log"
grep -F -- '--remove-first-image' "$TMPDIR/cover-remove.log"
grep -Fq 'DRY [azw3]:' "$TMPDIR/cover-remove.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cover-policy keep \
  --dry-run > "$TMPDIR/cover-keep.log"

if grep -Eq 'Cover-policy:' "$TMPDIR/cover-keep.log"; then
  echo "FAIL: keep cover policy should not emit cover-policy banner"
  exit 1
fi

if "$SCRIPT" --src "$SRC" --cover-policy bad-policy --dry-run 2>/dev/null; then
  echo "FAIL: unknown cover policy should fail"
  exit 1
fi

if "$SCRIPT" --src "$SRC" --preflight --cover-policy prefer-metadata 2>/dev/null; then
  echo "FAIL: preflight + cover-policy should fail"
  exit 1
fi

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cleanup conservative \
  --dry-run > "$TMPDIR/cleanup-conservative.log"

grep -Eq 'Cleanup: conservative \(--enable-heuristics\)' "$TMPDIR/cleanup-conservative.log"
grep -F -- '--enable-heuristics' "$TMPDIR/cleanup-conservative.log"
grep -Fq 'DRY [azw3]:' "$TMPDIR/cleanup-conservative.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cleanup off \
  --dry-run > "$TMPDIR/cleanup-off.log"

if grep -Eq 'Cleanup:' "$TMPDIR/cleanup-off.log"; then
  echo "FAIL: off cleanup should not emit cleanup banner"
  exit 1
fi

if "$SCRIPT" --src "$SRC" --cleanup bad-mode --dry-run 2>/dev/null; then
  echo "FAIL: unknown cleanup mode should fail"
  exit 1
fi

if "$SCRIPT" --src "$SRC" --preflight --cleanup conservative 2>/dev/null; then
  echo "FAIL: preflight + cleanup should fail"
  exit 1
fi

PATH="$FAKEBIN:$PATH" "$SCRIPT" \
  --src "$SRC" \
  --out "$OUT_DRY" \
  --cover-policy prefer-metadata \
  --cleanup conservative \
  --dry-run > "$TMPDIR/cleanup-cover-combined.log"

grep -F -- '--prefer-metadata-cover' "$TMPDIR/cleanup-cover-combined.log"
grep -F -- '--enable-heuristics' "$TMPDIR/cleanup-cover-combined.log"

echo "OK: bulk-epub-to-azw3 selftest passed"
