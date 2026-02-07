# ubuntu-system-tools

A small collection of **paranoid, read-only system inspection tools** for Ubuntu and Linux systems.

This repository is intentionally minimal: tools are designed to **observe and audit**, not to modify system state.

---

## Philosophy

- **Safety first**: default behavior is read-only.
- **Paranoid by design**: no destructive actions, no implicit changes.
- **No assumptions**: everything configurable via environment variables.
- **No personal data**: no hardcoded paths, usernames, or machine-specific details.

If a tool could be dangerous, it does not belong here.

---

## Tools

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
- No removals
- No service management
- No privilege escalation
- No system modification

If you are looking for an automation framework, this is not it.

## Status
Stable, intentionally small, and evolving slowly.

Contributions are welcome only if they preserve the safety and minimalism principles.
