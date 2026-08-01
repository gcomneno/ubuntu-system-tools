#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_symlink_to() {
  local link="$1"
  local expected="$2"

  [[ -L "$link" ]] || fail "expected symlink: $link"
  [[ "$(readlink -- "$link")" == "$expected" ]] \
    || fail "wrong target: $link -> $(readlink -- "$link")"
}

printf '%s\n' 'TEST: default install creates repository symlinks'

prefix="$tmp/links"
make -s -C "$repo_root" install PREFIX="$prefix"

for src in "$repo_root"/bin/*; do
  name="$(basename -- "$src")"

  case " $(
    printf '%s ' \
      hdd_cleanup \
      security-health \
      who-uses \
      printer-doctor \
      garbage-collector \
      bulk-epub-to-azw3 \
      bulk-ebook-convert \
      safe-uninstall \
      audio-transcribe
  ) " in
    *" $name "*)
      assert_symlink_to "$prefix/bin/$name" "$src"
      ;;
  esac
done

printf '%s\n' 'TEST: repeated symlink installation is idempotent'
make -s -C "$repo_root" install PREFIX="$prefix"

printf '%s\n' 'TEST: identical legacy copy is migrated to symlink'

legacy_prefix="$tmp/legacy"
mkdir -p "$legacy_prefix/bin"
cp "$repo_root/bin/hdd_cleanup" "$legacy_prefix/bin/hdd_cleanup"

make -s -C "$repo_root" install PREFIX="$legacy_prefix"

assert_symlink_to \
  "$legacy_prefix/bin/hdd_cleanup" \
  "$repo_root/bin/hdd_cleanup"

printf '%s\n' 'TEST: unrelated file is not overwritten'

foreign_prefix="$tmp/foreign"
mkdir -p "$foreign_prefix/bin"
printf '%s\n' 'foreign command' > "$foreign_prefix/bin/hdd_cleanup"

if make -s -C "$repo_root" install PREFIX="$foreign_prefix" >/dev/null 2>&1; then
  fail "install unexpectedly overwrote an unrelated file"
fi

grep -qx 'foreign command' "$foreign_prefix/bin/hdd_cleanup" \
  || fail "unrelated file was modified"

printf '%s\n' 'TEST: copy installation creates autonomous executable files'

copy_prefix="$tmp/copies"
make -s -C "$repo_root" install-copy PREFIX="$copy_prefix"

for name in \
  hdd_cleanup \
  security-health \
  who-uses \
  printer-doctor \
  garbage-collector \
  bulk-epub-to-azw3 \
  bulk-ebook-convert \
  safe-uninstall \
  audio-transcribe
do
  dest="$copy_prefix/bin/$name"
  src="$repo_root/bin/$name"

  [[ -f "$dest" ]] || fail "copy missing: $dest"
  [[ ! -L "$dest" ]] || fail "copy is unexpectedly a symlink: $dest"
  [[ -x "$dest" ]] || fail "copy is not executable: $dest"
  cmp -s -- "$src" "$dest" || fail "copy differs from source: $dest"
done

printf '%s\n' 'TEST: safe uninstall removes owned links and copies'

make -s -C "$repo_root" uninstall PREFIX="$prefix"
make -s -C "$repo_root" uninstall PREFIX="$copy_prefix"

find "$prefix/bin" -mindepth 1 -print -quit | grep -q . \
  && fail "symlink uninstall left installed tools"

find "$copy_prefix/bin" -mindepth 1 -print -quit | grep -q . \
  && fail "copy uninstall left installed tools"

printf '%s\n' 'OK: installation contract'
