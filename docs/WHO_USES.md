# who-uses

`who-uses` is a **read-only** scanning tool to find references to a term in:
- projects under `PROJECTS_DIR` (default: `$HOME/Progetti`)
- optionally, a limited set of system snapshots (best effort)

## Safety and privacy

- No destructive actions.
- Output should not leak personal absolute paths.
- `--json` is **projects-only** and emits **sanitized** output.

## Usage

```bash
who-uses scan <term> [options]
```

## Options
--deps-only
Scan dependency files only (e.g. pyproject.toml, requirements*.txt, package*.json, locks).

--projects-only / --no-system
Disable system snapshot scanning.

--no-projects
Disable project scanning.

--summary
Compact, sanitized human output (file hit lists).

--json
JSON output (v1), no human output, no logs, projects-only, sanitized, deterministic.

--include-venv
Include typical virtualenv directories (otherwise excluded).

--fail-on-hit
Exit 1 if at least one match is found (human mode).
In --json mode, exit codes are always based on hits (see below).

## Exit codes
0 = ok / no hits in --json
1 = hits found (--json or --fail-on-hit)
2 = operational error

## JSON output (v1)
who-uses scan <term> --json prints JSON only (no logs, no human text).

Guarantees:
- No absolute paths
- No matched text (only line/column)
- Deterministic output
- Projects-only (system scan disabled)

Schema (v1):
schema: who-uses-json-v1
cmd: string
term: string
options: { deps_only, include_venv, projects_only }
results[]:
    project: relative to PROJECTS_DIR (or ".")
    files[]:
        path: relative to the project
        matches[]: { line, column } (1-based)
summary: { projects_with_hits, files_with_hits, total_matches }

### Note:
In --json, pattern non valido (regex invalida) o errori di scansione di rg producono un JSON {"error": ...} ed exit code 2.

## Example:
```
who-uses scan requests --json | python3 -m json.tool
```
