#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/pdf2epub"

for cmd in python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "SKIP: missing command: $cmd"; exit 0; }
done

[[ -x "$SCRIPT" ]] || { echo "FAIL: script is not executable: $SCRIPT"; exit 1; }

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SRC="$TMPDIR/src"
OUT="$TMPDIR/out"
FAKEBIN="$TMPDIR/fakebin"
mkdir -p "$SRC" "$OUT" "$FAKEBIN"

cat > "$FAKEBIN/pdfinfo" <<'EOF'
#!/usr/bin/env bash
cat <<'EOT'
Title:           Smart PDF
Author:          Test Author
Creator:         Test Creator
EOT
EOF

cat > "$FAKEBIN/pdftotext" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output="${@: -1}"
cat > "$output" <<'EOT'
Smart PDF
Executive summary
Alpha beta gamma.

Section One
This is body text.

Table block      value one
row two          value two
EOT
EOF

cat > "$FAKEBIN/ebook-convert" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
input="$1"
output="$2"
cp "$input" "$output"
EOF

chmod +x "$FAKEBIN/pdfinfo" "$FAKEBIN/pdftotext" "$FAKEBIN/ebook-convert"

touch "$SRC/input.pdf"
PATH="$FAKEBIN:$PATH" "$SCRIPT" "$SRC/input.pdf" "$OUT/output.epub" >/dev/null

[[ -f "$OUT/output.epub" ]]
grep -q '## Sommario' "$OUT/output.epub"
grep -q 'Executive summary' "$OUT/output.epub"
grep -q 'Section One' "$OUT/output.epub"

echo "OK: selftest_pdf2epub"