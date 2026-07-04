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

echo "OK: bulk-epub-to-azw3 selftest passed"
