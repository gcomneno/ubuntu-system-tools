# Policy (Public)
This repository contains **paranoid, read-only inspection tools** for Ubuntu/Linux.

If a tool violates any rule below, it **does not belong here**.

## Hard rules (non-negotiable)
- **Idempotent**: multiple runs must not change system state.
- **Deterministic**: same inputs/environment → same outputs (stable ordering, stable formats).
- **Read-only**: no changes to the system.
- **No privilege escalation**: no `sudo`, no setcap, no polkit prompts.
- **No network activity**: no outbound requests, no API calls.
- **No system modification outside user-controlled paths** (and in practice: no modification at all).
- **No secrets / no personal data**: no usernames, hostnames, IPs, absolute paths, device serials in code or default output.

## Output safety (shareable by default)
- Default output must be safe to paste publicly:
  - **no absolute paths**
  - **no matched sensitive content**
  - avoid leaking usernames/hostnames
- If a tool can print sensitive data, it must require an explicit flag like `--unsafe` and must warn loudly.

## Scope
Allowed:
- system status/health checks
- hardware inventory
- dependency/reference scans on local projects (read-only)
- generating reports in user-controlled directories

Not allowed:
- package install/remove/update
- service management
- mount/unmount, poweroff devices
- account management, lab reset, “panic buttons”
