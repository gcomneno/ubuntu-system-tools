# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Changed
- Document Calibre (`ebook-convert`) as an explicit, host-installed dependency for real ebook conversion.

## v0.2.0

### Added
- Add `bulk-epub-to-azw3` and `bulk-ebook-convert` for bulk ebook conversion via Calibre.
- Add `--from` / `--to` format selection with allowlists and source-quality warnings for PDF/DJVU.
- Add curated `--target` presets: kindle, kobo, archive, text.
- Add multi-target export with `--to azw3,epub,...`.
- Add `--preflight` EPUB metadata audit.
- Add `--manifest` JSONL conversion manifest with checksums and tool versions.
- Add `--quarantine` / `--quarantine-copy` for invalid and failed sources.
- Add `--debug-failed` Calibre debug-pipeline export on conversion failure.
- Add `--cover-policy` (keep, prefer-metadata, remove-first-image).
- Add `--cleanup` typography preset (off, conservative).
- Add `--extra-css` custom CSS injection with path validation.
- Add `--profile` Kindle conversion profiles (generic, kindle, kindle-paperwhite, kindle-scribe, kindle-legacy).
- Add selftest coverage for all converter options using fake `ebook-convert`.

### Changed
- Expand README documentation for the full ebook conversion workflow.

## v0.1.3

### Added
- --help-md for security-health
- CI: make check on Ubuntu 22.04 and 24.04
- install-system / uninstall-system targets

### Changed
- Uniform help layout across tools
- Default install prefix to ~/.local

### Fixed
- ShellCheck clean (SC2317)
- no-leaks compliance

## 0.1.2
- Add: `hdd_cleanup` (workspace cleanup tool; dry-run by default; destructive actions require `--apply`).
- Add: `hdd_cleanup --help-md` (embedded Markdown docs).
- Add: `hdd_cleanup --summary` and logging (default log under `~/.cache/ubuntu-system-tools/`).
 
## 0.1.1
- Fix: `--fail-on-hit` no longer returns false positives in human summary mode (initialize HIT).
- Fix: Human scan correctly invokes `rg` with matching flags (no more `-S: comando non trovato`).

## 0.1.0
- Add `who-uses` (read-only scanning tool).
- Add `who-uses scan --json` (v1, projects-only, sanitized, deterministic; line/column only).
- CI: ShellCheck + pre-commit + custom no-leaks hook.
