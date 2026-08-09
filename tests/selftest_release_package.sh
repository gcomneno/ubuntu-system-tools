#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="v0.3.0"
PACKAGE="ubuntu-system-tools-$VERSION-linux"
ARCHIVE="$PACKAGE.tar.gz"

for cmd in bash cmp sha256sum tar; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "SKIP: missing command: $cmd"; exit 0; }
done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

DIST_A="$TMPDIR/dist-a"
DIST_B="$TMPDIR/dist-b"
PREFIX="$TMPDIR/prefix"
mkdir -p "$DIST_A" "$DIST_B" "$PREFIX"

bash "$ROOT/scripts/build-linux-release.sh" "$VERSION" "$DIST_A" >/dev/null
bash "$ROOT/scripts/build-linux-release.sh" "$VERSION" "$DIST_B" >/dev/null

[[ -f "$DIST_A/$ARCHIVE" ]]
[[ -f "$DIST_A/$ARCHIVE.sha256" ]]
(
  cd "$DIST_A"
  sha256sum -c "$ARCHIVE.sha256" >/dev/null
)

cmp -s -- "$DIST_A/$ARCHIVE" "$DIST_B/$ARCHIVE" || {
  echo "FAIL: Linux release archive is not reproducible" >&2
  exit 1
}

mkdir -p "$TMPDIR/extract"
tar -xzf "$DIST_A/$ARCHIVE" -C "$TMPDIR/extract"
PKG="$TMPDIR/extract/$PACKAGE"

[[ "$(<"$PKG/VERSION")" == "$VERSION" ]]
[[ -x "$PKG/install.sh" ]]
[[ -x "$PKG/uninstall.sh" ]]
[[ -f "$PKG/README.md" ]]
[[ -f "$PKG/README.it.md" ]]
[[ -f "$PKG/CHANGELOG.md" ]]
[[ -f "$PKG/LICENSE" ]]
[[ -f "$PKG/POLICY.md" ]]

mapfile -t PACKAGE_TOOLS < <(find "$PKG/bin" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
((${#PACKAGE_TOOLS[@]} > 0))

bash "$PKG/install.sh" --prefix "$PREFIX" >/dev/null

MANIFEST="$PREFIX/share/ubuntu-system-tools/manifest-$VERSION.sha256"
INSTALLED_UNINSTALLER="$PREFIX/share/ubuntu-system-tools/uninstall-$VERSION.sh"
[[ -f "$MANIFEST" ]]
[[ -x "$INSTALLED_UNINSTALLER" ]]

for name in "${PACKAGE_TOOLS[@]}"; do
  [[ -x "$PREFIX/bin/$name" ]]
  cmp -s -- "$PKG/bin/$name" "$PREFIX/bin/$name"
done

# Reinstalling identical copies is idempotent.
bash "$PKG/install.sh" --prefix "$PREFIX" >/dev/null

FIRST="${PACKAGE_TOOLS[0]}"
printf '\nlocal divergence\n' >> "$PREFIX/bin/$FIRST"

if bash "$PKG/install.sh" --prefix "$PREFIX" >/dev/null 2>&1; then
  echo "FAIL: installer overwrote a divergent file without --force" >&2
  exit 1
fi

grep -q 'local divergence' "$PREFIX/bin/$FIRST"

bash "$PKG/install.sh" --prefix "$PREFIX" --force >/dev/null
cmp -s -- "$PKG/bin/$FIRST" "$PREFIX/bin/$FIRST"

# Uninstall must preflight the complete installation before removing anything.
printf '\nchanged after install\n' >> "$PREFIX/bin/$FIRST"
LAST="${PACKAGE_TOOLS[${#PACKAGE_TOOLS[@]}-1]}"
[[ -f "$PREFIX/bin/$LAST" ]]

if "$INSTALLED_UNINSTALLER" --prefix "$PREFIX" >/dev/null 2>&1; then
  echo "FAIL: uninstaller removed a divergent file without --force" >&2
  exit 1
fi

[[ -f "$PREFIX/bin/$FIRST" ]]
[[ -f "$PREFIX/bin/$LAST" ]]

"$INSTALLED_UNINSTALLER" --prefix "$PREFIX" --force >/dev/null

for name in "${PACKAGE_TOOLS[@]}"; do
  [[ ! -e "$PREFIX/bin/$name" && ! -L "$PREFIX/bin/$name" ]]
done

[[ ! -e "$MANIFEST" ]]
[[ ! -e "$INSTALLED_UNINSTALLER" ]]

echo "OK: Linux release package contract"
