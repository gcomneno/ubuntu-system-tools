#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/bulk-epub-to-azw3"

command -v zip >/dev/null 2>&1 || {
  echo "SKIP: comando mancante: zip"
  exit 0
}

[[ -x "$SCRIPT" ]] || {
  echo "FAIL: script non eseguibile: $SCRIPT"
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
  local workdir

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

  cat > "$workdir/OEBPS/content.opf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:identifier id="bookid">test-book</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest/>
  <spine/>
</package>
EOF

  (
    cd "$workdir"
    zip -q -X "$dest" mimetype META-INF/container.xml OEBPS/content.opf
  )
}

create_valid_epub "$SRC/Book One.epub"
create_valid_epub "$SRC/nested/Book Two.epub"
printf 'not an epub\n' > "$SRC/broken.epub"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" --dry-run > "$TMPDIR/dry-run.log"

if find "$OUT" -type f | grep -q .; then
  echo "FAIL: dry-run ha creato file in output"
  exit 1
fi

grep -Eq 'EPUB trovati:[[:space:]]+3' "$TMPDIR/dry-run.log"
grep -Eq 'EPUB validi:[[:space:]]+2' "$TMPDIR/dry-run.log"
grep -Eq 'EPUB invalidi:[[:space:]]+1' "$TMPDIR/dry-run.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" > "$TMPDIR/run.log"

[[ -f "$OUT/Book One.azw3" ]]
[[ -f "$OUT/nested/Book Two.azw3" ]]
[[ ! -f "$OUT/broken.azw3" ]]

grep -Eq 'Convertiti:[[:space:]]+2' "$TMPDIR/run.log"
grep -Eq 'EPUB invalidi:[[:space:]]+1' "$TMPDIR/run.log"

PATH="$FAKEBIN:$PATH" "$SCRIPT" --src "$SRC" --out "$OUT" > "$TMPDIR/rerun.log"

grep -Eq 'Convertiti:[[:space:]]+0' "$TMPDIR/rerun.log"
grep -Eq 'Saltati:[[:space:]]+2' "$TMPDIR/rerun.log"

echo "OK: bulk-epub-to-azw3 selftest passed"
