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

Clone the repository:

```bash
git clone https://github.com/gcomneno/ubuntu-system-tools
cd ubuntu-system-tools
```

The recommended development installation creates symbolic links in
`~/.local/bin`, keeping the repository as the canonical source:

```bash
make install PREFIX=$HOME/.local
```

Moving or deleting the cloned repository will break those links.

For autonomous executable copies instead:

```bash
make install-copy PREFIX=$HOME/.local
```

System-wide installation always uses copies rather than links into a
user checkout:

```bash
make install-system
```

Uninstall a user-local installation:

```bash
make uninstall PREFIX=$HOME/.local
```

The installer refuses to replace or remove unrelated files. `FORCE=1`
is available only for an explicitly verified copy installation or
uninstallation.

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

Audit removable development artifacts without deleting anything:

``` bash
garbage-collector ~/Progetti --max-depth 4
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

### `garbage-collector`

Read-only scanner for removable development artifacts such as `.venv/`,
`node_modules/`, `target/`, Python caches and build output.

-   Audit-only
-   No deletion mode
-   Reports size per artifact
-   Prints total potentially reclaimable space

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

### `bulk-epub-to-azw3`

Bulk-convert ebook files for Kindle and other targets using Calibre's `ebook-convert`.

**Calibre is required for real conversion.** This tool is a safety-first wrapper around Calibre; it does not ship or install Calibre. Install it on the host before running a real conversion (not needed for `--dry-run` or `--preflight`):

```bash
sudo apt update
sudo apt install -y calibre
ebook-convert --version
```

By default, the source format is EPUB, the target format is AZW3, the source directory is the current working directory, and the output directory is `./azw3`.

The same converter is also available as `bulk-ebook-convert`, which accepts explicit `--from` and `--to` format options.

Dry-run from a directory containing EPUB files:

```bash
bin/bulk-epub-to-azw3 --dry-run
bin/bulk-ebook-convert --from epub --to azw3 --dry-run
```

Run the real conversion:

```bash
bin/bulk-epub-to-azw3
bin/bulk-ebook-convert --from mobi --to epub --src ./mobi
```

Use explicit source and output directories:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --dry-run
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle
bin/bulk-ebook-convert --from docx --to epub --src ./manuscripts --out ./epub
```

When `--out` is omitted, the output directory defaults to `./<to>` (for example `./epub` or `./azw3`).

Supported input formats: `epub`, `mobi`, `azw`, `azw3`, `pdf`, `djvu`, `docx`, `doc`, `txt`, `html`, `htm`, `cbz`, `cbr`.

Supported output formats: `azw3`, `epub`, `mobi`, `pdf`, `txt`, `docx`, `kepub`.

Curated conversion targets:

```bash
bin/bulk-ebook-convert --target kindle --src ./epub
bin/bulk-ebook-convert --target kobo --src ./epub
bin/bulk-ebook-convert --target archive --src ./mixed --out ./archive
bin/bulk-ebook-convert --target text --src ./epub
```

Target mapping: `kindle` → `azw3`, `kobo` → `kepub`, `archive` → `epub`, `text` → `txt`. `--target` cannot be combined with `--to`.

Export one library to multiple formats in a single run:

```bash
bin/bulk-ebook-convert --from epub --to azw3,epub,txt --src ./epub
bin/bulk-ebook-convert --from epub --to azw3,epub --src ./epub --out ./export
```

With multiple `--to` formats, each target gets its own output tree (`./azw3`, `./epub`, ... or `OUT/azw3`, `OUT/epub`, ...).

Unsupported formats are rejected before scanning. `pdf` and `djvu` sources emit quality warnings before conversion.

The tool validates EPUB files before conversion, preserves subdirectories, skips existing output files by default, and supports `--force` to overwrite existing output files.

Preflight EPUB metadata without converting:

```bash
bin/bulk-epub-to-azw3 --preflight
```

The preflight report includes the OPF package path, title, creator, language, identifier, cover detection, spine item count, and basic warnings for missing metadata.

Write a JSONL conversion manifest with checksums and tool versions:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --manifest
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --dry-run --manifest ./reports/plan.jsonl
```

Each manifest line records the source and output paths, status (`converted`, `skipped`, `invalid`, `failed`, or `planned` during dry-run), file sizes, SHA-256 checksums, timestamp, `ebook-convert` version, and skip or failure reasons when applicable.

Quarantine invalid or failed EPUB files for review without moving the originals:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --quarantine ./review
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --quarantine ./review --quarantine-copy
```

Each quarantined item is recorded under `review/invalid/...` or `review/failed/...` with a reason file, source path, optional symlink to the original EPUB, and conversion logs for failures.

Export Calibre debug-pipeline artifacts for failed conversions:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --debug-failed ./debug
```

On failure, the tool reruns `ebook-convert` with `--debug-pipeline` and writes per-book debug output under `./debug/...`.

Control Kindle cover handling during conversion:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --cover-policy prefer-metadata --dry-run
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --cover-policy remove-first-image
```

Policies: `keep` (default), `prefer-metadata` (`--prefer-metadata-cover`), `remove-first-image` (`--remove-first-image`).

Choose a Kindle conversion profile for device-specific Calibre tuning:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --profile kindle-paperwhite --dry-run
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --profile kindle-scribe
```

Profiles: `generic` (default, no extra flags), `kindle` (`--output-profile kindle`), `kindle-paperwhite` (`kindle_pw3`), `kindle-scribe` (`kindle_scribe`), `kindle-legacy` (`kindle` + `--mobi-file-type both`). `--profile` controls Calibre output tuning; `--target kindle` selects the azw3 export format.

Enable conservative typography cleanup for messy EPUB HTML:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --cleanup conservative --dry-run
```

Modes: `off` (default), `conservative` (`--enable-heuristics`). Opt-in only because heuristics can alter book structure.

Inject custom CSS for repeatable Kindle typography tweaks:

```bash
bin/bulk-epub-to-azw3 --src ./epub --out ./kindle --extra-css ./kindle.css --dry-run
```

The CSS file must exist before conversion starts. Paths with spaces are quoted in dry-run output.

Combine advanced options as needed (`--profile`, `--cover-policy`, `--cleanup`, `--extra-css`, `--manifest`, `--quarantine`, `--debug-failed`). Dry-run shows the resolved Calibre flags for each file.

**Dependencies for `bulk-epub-to-azw3` / `bulk-ebook-convert`:**

| Dependency | When required | Install / verify |
| --- | --- | --- |
| **Calibre (`ebook-convert`)** | Real conversion only | `sudo apt install -y calibre` then `ebook-convert --version` |
| `unzip`, `grep` | EPUB preflight and EPUB validation | `sudo apt install -y unzip` |
| `python3`, `sha256sum`, `date` | `--manifest` | Usually preinstalled on Ubuntu |

Calibre is **not** required for `--dry-run` (planning output) or `--preflight` (metadata audit). The repository intentionally does not install system packages for you; see [What this repository does NOT do](#what-this-repository-does-not-do).

```bash
sudo apt update
sudo apt install -y calibre unzip
ebook-convert --version
```


## Requirements

-   Bash
-   ripgrep (`rg`)
-   python3
-   **Calibre (`ebook-convert`)** — required for real ebook conversion with `bulk-epub-to-azw3` / `bulk-ebook-convert` (not bundled; install separately)
-   `unzip` — required for EPUB preflight/validation in the ebook converter
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
-   No broad or unattended service orchestration
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
