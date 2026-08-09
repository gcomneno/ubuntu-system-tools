#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  uninstall.sh [--prefix PATH] [--force]

Safely uninstall a Linux release-package installation.

Options:
  --prefix PATH  Installation prefix (default: $HOME/.local)
  --force        Remove divergent installed tool files after explicit review
  -h, --help     Show this help

Safety:
  - Linux only
  - never invokes sudo
  - preflights every installed tool before removing anything
  - refuses to remove changed files unless --force is supplied
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
need_cmd sha256sum

VERSION=""
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
  VERSION="$(<"$SCRIPT_DIR/VERSION")"
elif [[ "$PROGRAM_NAME" =~ ^uninstall-(v[0-9]+\.[0-9]+\.[0-9]+)\.sh$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
fi
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "cannot determine installed package version"

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

[[ -f "$MANIFEST" ]] || fail "installation manifest not found: $MANIFEST"

names=()
hashes=()
while read -r expected name; do
  [[ -n "$expected" && -n "$name" ]] || continue
  [[ "$name" != */* ]] || fail "invalid manifest entry: $name"
  names+=("$name")
  hashes+=("$expected")
done < "$MANIFEST"

((${#names[@]} > 0)) || fail "installation manifest is empty"

# Preflight every destination before the first removal.
for i in "${!names[@]}"; do
  name="${names[$i]}"
  expected="${hashes[$i]}"
  dest="$BINDIR/$name"

  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    continue
  fi

  if [[ -f "$dest" && ! -L "$dest" ]]; then
    current="$(sha256sum -- "$dest" | awk '{print $1}')"
    if [[ "$current" == "$expected" ]]; then
      continue
    fi
  fi

  ((FORCE == 1)) || fail "refusing to remove divergent destination: $dest (use --force only after review)"
done

for name in "${names[@]}"; do
  dest="$BINDIR/$name"
  if [[ -e "$dest" || -L "$dest" ]]; then
    rm -f -- "$dest"
    printf 'RM %s\n' "$dest"
  fi
done

rm -f -- "$MANIFEST" "$INSTALLED_VERSION" "$INSTALLED_UNINSTALLER"
rmdir -- "$STATE_DIR" 2>/dev/null || true
rmdir -- "$PREFIX/share" 2>/dev/null || true

printf '\nOK: ubuntu-system-tools %s uninstalled from %s.\n' "$VERSION" "$PREFIX"
