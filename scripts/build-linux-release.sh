#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "$PROGRAM_NAME: error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

[[ "$(uname -s)" == "Linux" ]] || fail "Linux release packages can only be built on Linux"

need_cmd awk
need_cmd gzip
need_cmd install
need_cmd sha256sum
need_cmd tar

VERSION="${1:-}"
DISTDIR="${2:-$ROOT/dist}"

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must match vMAJOR.MINOR.PATCH"
[[ -n "$DISTDIR" ]] || fail "dist directory must not be empty"

PACKAGE_NAME="ubuntu-system-tools-$VERSION-linux"
ARCHIVE_NAME="$PACKAGE_NAME.tar.gz"
CHECKSUM_NAME="$ARCHIVE_NAME.sha256"

mkdir -p -- "$DISTDIR"
DISTDIR="$(cd "$DISTDIR" && pwd)"
ARCHIVE="$DISTDIR/$ARCHIVE_NAME"
CHECKSUM="$DISTDIR/$CHECKSUM_NAME"

WORK="$(mktemp -d)"
cleanup() {
  rm -rf -- "$WORK"
}
trap cleanup EXIT INT TERM

STAGE="$WORK/$PACKAGE_NAME"
mkdir -p -- "$STAGE/bin" "$STAGE/docs"

mapfile -t TOOL_PATHS < <(awk '/^TOOLS :=/ {for (i = 3; i <= NF; i++) print $i}' "$ROOT/Makefile")
((${#TOOL_PATHS[@]} > 0)) || fail "could not determine release tools from Makefile"

for tool in "${TOOL_PATHS[@]}"; do
  src="$ROOT/$tool"
  [[ -f "$src" ]] || fail "missing tool declared by Makefile: $tool"
  install -m 0755 -- "$src" "$STAGE/bin/$(basename "$tool")"
done

install -m 0755 -- "$ROOT/packaging/linux/install.sh" "$STAGE/install.sh"
install -m 0755 -- "$ROOT/packaging/linux/uninstall.sh" "$STAGE/uninstall.sh"
printf '%s\n' "$VERSION" > "$STAGE/VERSION"

for file in README.md README.it.md CHANGELOG.md LICENSE POLICY.md; do
  [[ -f "$ROOT/$file" ]] || fail "missing release metadata file: $file"
  install -m 0644 -- "$ROOT/$file" "$STAGE/$file"
done

if [[ -d "$ROOT/docs" ]]; then
  while IFS= read -r -d '' file; do
    rel="${file#"$ROOT/docs/"}"
    mkdir -p -- "$STAGE/docs/$(dirname "$rel")"
    install -m 0644 -- "$file" "$STAGE/docs/$rel"
  done < <(find "$ROOT/docs" -type f -print0 | LC_ALL=C sort -z)
fi

rm -f -- "$ARCHIVE" "$CHECKSUM"

# Stable file ordering, metadata and gzip header make repeated builds byte-identical.
LC_ALL=C tar \
  --sort=name \
  --mtime='@0' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$WORK" \
  -cf - "$PACKAGE_NAME" \
  | gzip -n > "$ARCHIVE"

(
  cd "$DISTDIR"
  sha256sum -- "$ARCHIVE_NAME" > "$CHECKSUM_NAME"
)

printf 'Linux package: %s\n' "$ARCHIVE"
printf 'SHA-256 file: %s\n' "$CHECKSUM"
printf 'Tools: %d\n' "${#TOOL_PATHS[@]}"
