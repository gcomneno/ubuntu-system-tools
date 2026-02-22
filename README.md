# ubuntu-system-tools

A small collection of **paranoid, read-only system inspection tools** for Ubuntu and Linux systems.

This repository is intentionally minimal: tools are designed to **observe and audit**, not to modify system state.

---

## Philosophy

- **Safety first**: default behavior is read-only.
- **Paranoid by design**: no destructive actions, no implicit changes.
- **Paranoid by design**: no destructive actions, no implicit changes.
    If a tool, like `hdd_cleanup`, could be dangerous, it does not belong here.
      -  explicit (`--apply`)
      - documented
      - limited to regenerable artifacts only
- **No assumptions**: everything configurable via environment variables.
- **No personal data**: no hardcoded paths, usernames, or machine-specific details.

If a tool could be dangerous, it does not belong here.

---

## Tools

### `hdd_cleanup`

Cleanup helper for developer workspaces: finds and (optionally) removes **regenerable artifacts** such as `target/`, `node_modules/`, `.venv/`, and common Python caches.

⚠️ **Safety model**:
- Default is **dry-run** (no deletion).
- Deletion requires explicit `--apply`.
- Intended for **dev directories** (e.g. `$HOME/Progetti`), not system paths.

Docs are embedded in the tool:
```bash
tools/hdd_cleanup --help-md
```



### `who-uses`

Scans projects and the system to find **references to a given term** (e.g. a package name, binary, or identifier).

It performs:
- project-wide text scans (dependencies + code/configs)
- best-effort system inspection (pip, PATH, systemd)

All operations are **read-only**.

---

## Usage

```bash
who-uses scan <term> [--include-venv] [--no-system] [--no-projects]
```

Example:
```
who-uses scan requests
```

## Configuration (optional)
All configuration is done via environment variables:

PROJECTS_DIR
Default: $HOME/Progetti

TOWER_BASE
Default: $HOME/Documents/tower-notes

LOG_DIR
Default: $TOWER_BASE/tower/logs

Logs are never written inside the repository.

## Requirements
- Bash
- ripgrep (rg)
- python3 (for pip inspection)
- systemd (optional, best-effort inspection)

## What this repo does NOT do
- No installs
- No removals by default (cleanup actions are opt-in, e.g. `hdd_cleanup --apply`)
- No service management
- No privilege escalation
- No system modification

If you are looking for an automation framework, this is not it.

## Status
Stable, intentionally small, and evolving slowly.

Contributions are welcome only if they preserve the safety and minimalism principles.

## JSON output (v1)

`who-uses scan <term> --json` prints **JSON only** (no logs, no human text).

Security guarantees:
- **No absolute paths**
- **No matched text** (only line/column)
- **Deterministic output** (stable ordering)
- **Projects-only** (system scan disabled in JSON mode)

Exit codes in `--json` mode:
- `0` = no hits
- `1` = hits found
- `2` = operational error (JSON error object printed)

Schema (v1):
```json
- `schema`: string (`who-uses-json-v1`)
- `cmd`: string
- `term`: string
- `options`:
  - `deps_only`: boolean
  - `include_venv`: boolean
  - `projects_only`: boolean (always `true` in JSON mode)
- `results[]`:
  - `project`: string (relative to `PROJECTS_DIR`, or `"."` if at root)
  - `files[]`:
    - `path`: string (relative to the project)
    - `matches[]`:
      - `line`: number (1-based)
      - `column`: number (1-based)
- `summary`:
  - `projects_with_hits`: number
  - `files_with_hits`: number
  - `total_matches`: number
```

---

## Security note

This tool is read-only and performs no network activity.  
Output may contain sensitive local system information (usernames, IP addresses, service names).  
Review output before sharing publicly.

