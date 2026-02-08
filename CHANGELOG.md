# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- (nothing yet)

## 0.1.1

- Fix: `--fail-on-hit` no longer returns false positives in human summary mode (initialize HIT).
- Fix: Human scan correctly invokes `rg` with matching flags (no more `-S: comando non trovato`).

## 0.1.0

- Add `who-uses` (read-only scanning tool).
- Add `who-uses scan --json` (v1, projects-only, sanitized, deterministic; line/column only).
- CI: ShellCheck + pre-commit + custom no-leaks hook.
