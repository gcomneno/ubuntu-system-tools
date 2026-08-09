#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  install.sh [--prefix PATH] [--force]

Install the Linux release package as autonomous executable copies.

Options:
  --prefix PATH  Installation prefix (default: $HOME/.local)
  --force        Replace existing divergent destinations after explicit review
  -h, --help     Show this help

Safety:
  - Linux only
  - never invokes sudo
  - never installs host dependencies
  - preflights every destination before copying any tool
EOF
}

fail() {
  echo "$PROGRAM_NAME: error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

[[ "$(uname -s)" == "Linux" ]] || fail "this release package supports Linux only"

need_cmd cmp
need_cmd install
need_cmd sha256sum
need_cmd sort

[[ -f "$ROOT/VERSION" ]] || fail "missing package VERSION file"
[[ -d "$ROOT/bin" ]] || fail "missing package bin directory"

VERSION="$(<"$ROOT/VERSION")"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid package version: $VERSION"

PREFIX="${HOME:?HOME is not set}/.local"
FORCE=0

while (($#)); do
  case "$1" in
    --prefix)
      (($# >= 2)) || fail "--prefix requires a path"
      PREFIX="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$PREFIX" ]] || fail "installation prefix must not be empty"
[[ "$PREFIX" = /* ]] || fail "installation prefix must be an absolute path"

BINDIR="$PREFIX/bin"
STATE_DIR="$PREFIX/share/ubuntu-system-tools"
MANIFEST="$STATE_DIR/manifest-$VERSION.sha256"
INSTALLED_UNINSTALLER="$STATE_DIR/uninstall-$VERSION.sh"
INSTALLED_VERSION="$STATE_DIR/VERSION-$VERSION"

mapfile -t TOOLS < <(find "$ROOT/bin" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
((${#TOOLS[@]} > 0)) || fail "package contains no tools"

# Preflight every destination before the first mutation.
for name in "${TOOLS[@]}"; do
  src="$ROOT/bin/$name"
  dest="$BINDIR/$name"
  [[ -x "$src" ]] || fail "package tool is not executable: $name"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s -- "$src" "$dest"; then
      continue
    fi
    ((FORCE == 1)) || fail "refusing to replace unrelated or divergent destination: $dest (use --force only after review)"
  fi
done

install -d -- "$BINDIR" "$STATE_DIR"

TMP_MANIFEST="$(mktemp "$STATE_DIR/.manifest-$VERSION.XXXXXX")"
cleanup() {
  rm -f -- "$TMP_MANIFEST"
}
trap cleanup EXIT INT TERM

for name in "${TOOLS[@]}"; do
  src="$ROOT/bin/$name"
  dest="$BINDIR/$name"
  install -m 0755 -- "$src" "$dest"
  hash="$(sha256sum -- "$dest" | awk '{print $1}')"
  printf '%s  %s\n' "$hash" "$name" >> "$TMP_MANIFEST"
  printf 'COPY %s -> %s\n' "$src" "$dest"
done

install -m 0644 -- "$ROOT/VERSION" "$INSTALLED_VERSION"
install -m 0755 -- "$ROOT/uninstall.sh" "$INSTALLED_UNINSTALLER"
install -m 0644 -- "$TMP_MANIFEST" "$MANIFEST"

printf '\nOK: ubuntu-system-tools %s installed for Linux.\n' "$VERSION"
printf 'Prefix: %s\n' "$PREFIX"
printf 'Tools:  %d\n' "${#TOOLS[@]}"
printf 'Uninstall: %q --prefix %q\n' "$INSTALLED_UNINSTALLER" "$PREFIX"
