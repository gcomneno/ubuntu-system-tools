# Safety Policy

`ubuntu-system-tools` contains small Ubuntu/Linux utilities for inspection,
diagnostics, conversion, cleanup and narrowly scoped recovery operations.

The repository is **safety-first**, but it is not exclusively read-only.

Every tool must clearly belong to one of the operational classes below and must
document its effects, privilege requirements and safety gates.

## Operational classes

### 1. Read-only inspection

These tools inspect local state without intentionally modifying the inspected
system or project data.

Examples:

- `garbage-collector`
- `security-health`
- diagnostic commands of `printer-doctor`
- project scans performed by `who-uses`

Temporary files, logs and reports created under user-controlled directories are
considered auxiliary output, not modification of the inspected target.

### 2. Safe-by-default controlled action

These tools can create, overwrite, delete or repair data, but only after an
explicit user action.

Examples:

- `hdd_cleanup purge-* --apply`
- real ebook conversion through `bulk-ebook-convert`
- `bulk-ebook-convert --force`
- `printer-doctor repair`

A controlled-action tool must:

- remain non-destructive in its default or inspection mode;
- expose the state-changing operation through an explicit command or flag;
- document the affected scope before execution;
- reject unsupported or ambiguous targets;
- avoid touching paths outside the scope selected by the user;
- provide a dry-run or equivalent preview when practical;
- use additional confirmation for especially destructive or broad operations;
- have automated tests for its principal safety gates.

## Hard rules

### Safe defaults

Running a tool without an explicit state-changing command or flag must not
perform destructive actions.

A default invocation may:

- inspect local state;
- create temporary files;
- write a documented log or report in a user-controlled location;
- display a plan or dry-run.

### Explicit scope

State-changing operations must act only on:

- paths supplied by the user;
- documented default paths under the user's control;
- the specific subsystem named by the command, such as a selected CUPS queue.

Tools must not silently broaden their scope.

### No hidden privilege escalation

A tool must not obtain elevated privileges silently.

When a narrowly scoped operation requires privileges:

- the privileged command must be visible in the implementation and
  documentation;
- it must occur only in an explicitly requested action;
- inspection and dry-run modes must not require elevation;
- failure to obtain privileges must produce a clear error.

### No automatic package or platform management

Tools may report missing dependencies and show installation instructions, but
must not automatically:

- install, remove or upgrade packages;
- modify package repositories;
- enable or disable unrelated services;
- alter user accounts;
- change firewall policy;
- mount, unmount or power off devices;
- perform operating-system upgrades.

### No implicit network activity

Repository tools must not make outbound network requests unless network access
is an explicitly documented part of that tool's primary purpose.

The current tools are expected to operate locally.

### Predictable interfaces

Tools must provide predictable command-line behaviour:

- stable command and option names;
- stable exit-code meanings;
- deterministic ordering where practical;
- machine-readable output without mixed human diagnostics when such a mode is
  advertised;
- clear errors for invalid combinations.

System-health output is naturally time-dependent and is not required to be
byte-for-byte deterministic.

### User data and output safety

Source code, defaults, fixtures and documentation must not embed personal
usernames, hostnames, addresses, device serial numbers, credentials or absolute
paths from a contributor's machine.

Local diagnostic output may naturally contain sensitive information such as:

- usernames;
- hostnames;
- absolute paths;
- IP or MAC addresses;
- journal messages;
- print-job metadata.

A tool that can emit such information must document the risk and, where
practical, provide a redacted or sanitized mode.

Users must not assume that unrestricted diagnostic output is safe to publish.

### Secrets

Tools must not:

- print credentials or API keys intentionally;
- store secrets in repository-controlled files;
- copy secrets into logs or reports;
- require secrets when the task can be performed without them.

## Allowed scope

Appropriate tools include:

- system and security health inspection;
- local hardware and service diagnostics;
- dependency and reference scans;
- reports and manifests written to user-controlled directories;
- cleanup of explicitly identified regenerable development artifacts;
- document and ebook conversion into user-selected output directories;
- narrowly scoped recovery of a selected local subsystem.

## Out of scope

The following do not belong in this repository:

- general configuration-management frameworks;
- unattended destructive maintenance;
- automatic package management;
- broad service orchestration;
- account or permission administration;
- firewall or network-policy management;
- disk partitioning or filesystem repair;
- mount, unmount or device power-control tools;
- lab reset or panic-button automation;
- tools whose safe scope cannot be explained and tested.

## Review requirements

A new or changed tool must document:

- what it does;
- what it can modify;
- its default behaviour;
- the explicit action required to modify state;
- affected paths or subsystems;
- privilege requirements;
- dependencies;
- relevant exit codes;
- output-sensitivity risks.

Tests must cover the principal refusal paths and safety gates for every
controlled-action tool.
