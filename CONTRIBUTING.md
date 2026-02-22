# Contributing
Thanks for your interest in contributing!

## Development setup
Requirements (typical Ubuntu):
- bash
- `shellcheck`
- `pre-commit`
- `ripgrep` (`rg`)
- `python3` (used by `who-uses --json`)

Run checks locally:

```bash
shellcheck -x bin/who-uses
pre-commit run -a
```

## Project principles
Safety-first tools: default behavior must be non-destructive.
If a tool supports destructive actions, they must be:
- explicitly opt-in (e.g. `--apply`)
- dry-run by default
- clearly documented (README + `--help` / `--help-md`)
- scoped to safe targets (regenerable artifacts only)

No leaks: output must never print personal absolute paths or secrets.

Deterministic output when possible (especially for --json).

Prefer small patches over refactors.

## Pull requests
Before opening a PR:
```
run pre-commit run -a
```

keep changes focused (one feature/fix at a time)

update docs if behavior changes (README / docs)

## Reporting issues
Use GitHub Issues for bugs and feature requests.

For security issues, see SECURITY.md.
