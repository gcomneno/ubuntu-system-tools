# ubuntu-system-tools

A small collection of **paranoid, safety-first system utilities**
for Ubuntu and Linux.

The project focuses on **inspection, diagnostics and developer-oriented
maintenance**, following a conservative philosophy:

-   **Read-only by default**
-   **Explicit opt-in for state-changing operations**
-   **Minimal dependencies**
-   **Predictable CLI behaviour**

The goal is to provide tools that solve everyday Linux problems without
becoming a full system management framework.

------------------------------------------------------------------------

## Philosophy

This repository intentionally favors **small, composable utilities**
over large automation suites.

Core principles:

-   Safety first
-   Read-only whenever possible
-   Explicit confirmation before destructive actions
-   Deterministic behaviour
-   No hidden privilege escalation
-   User-controlled scope

If a command changes system state, it should do so only after an
explicit user request.

------------------------------------------------------------------------

## Install

``` bash
git clone https://github.com/gcomneno/ubuntu-system-tools
cd ubuntu-system-tools
make install PREFIX=$HOME/.local
```

Uninstall:

``` bash
make uninstall PREFIX=$HOME/.local
```

------------------------------------------------------------------------

## Quick Examples

Inspect recent security-related events:

``` bash
security-health --since "24 hours ago"
```

Find where a dependency or identifier is used:

``` bash
who-uses scan requests
```

Preview regenerable developer artifacts:

``` bash
hdd_cleanup
```

Diagnose a CUPS printer queue:

``` bash
printer-doctor doctor
```

List configured CUPS printers:

``` bash
printer-doctor list
```

Recover a disabled CUPS queue:

``` bash
printer-doctor repair
```

------------------------------------------------------------------------

## Configuration

Create a local configuration:

``` bash
make init-config
nano ~/.config/ubuntu-system-tools/config.env
```

Load it:

``` bash
set -a
source ~/.config/ubuntu-system-tools/config.env
set +a
```

------------------------------------------------------------------------

## Included tools

### `hdd_cleanup`

Safely identifies regenerable developer artifacts such as
`node_modules/`, `.venv/`, `target/` and common caches.

-   Dry-run by default
-   `--apply` required for deletion
-   Intended for developer workspaces

### `who-uses`

Find where a package, dependency, binary or identifier is referenced.

Features:

-   project scanning
-   dependency inspection
-   optional system inspection
-   JSON output
-   read-only operation

### `security-health`

Inspect recent security-related events from the local system journal.

Features:

-   sudo activity
-   login/logout events
-   kernel warnings
-   optional output redaction

### `printer-doctor`

Vendor-agnostic diagnostics and recovery for CUPS printer queues.

Features:

-   inspect CUPS scheduler
-   list configured printers
-   inspect configured printers
-   inspect queues
-   detect disabled queues
-   list pending jobs
-   recover queues explicitly
-   optional cancellation of stuck jobs after confirmation

Non-goals:

-   cartridge cleaning
-   nozzle checks
-   vendor-specific maintenance
-   proprietary driver management

------------------------------------------------------------------------

## Requirements

-   Bash
-   ripgrep (`rg`)
-   python3
-   systemd (optional)
-   CUPS (only for `printer-doctor`)

------------------------------------------------------------------------

## Design goals

Every utility should be:

-   small
-   understandable
-   scriptable
-   deterministic
-   safe by default

Whenever practical, tools expose self-contained documentation via
`--help-md`.

------------------------------------------------------------------------

## What this repository does NOT do

-   No automatic installs
-   No destructive actions by default
-   No service management
-   No hidden privilege escalation
-   No unsafe system modifications

If you are looking for an automation framework, this is intentionally
not it.

------------------------------------------------------------------------

## Status

Stable, intentionally small, and evolving slowly.

Contributions are welcome if they preserve the project's safety,
simplicity and determinism.

------------------------------------------------------------------------

## JSON output (who-uses)

`who-uses scan <term> --json` emits deterministic JSON with:

-   no absolute paths
-   no matched text
-   projects-only scanning
-   stable ordering

Exit codes:

-   `0` = no hits
-   `1` = hits found
-   `2` = operational error

------------------------------------------------------------------------

## Security note

These tools perform only local operations.

Some commands may display sensitive local information (usernames,
hostnames, IP addresses, service names). Review output before sharing it
publicly.

------------------------------------------------------------------------

## Policy

See `POLICY.md`.
