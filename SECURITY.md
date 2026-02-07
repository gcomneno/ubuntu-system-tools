# Security Policy

## Reporting a Vulnerability

Please report security issues via **GitHub Security Advisories** (private disclosure).

- Do **not** open a public GitHub Issue for security-related reports.
- Provide:
  - a clear description of the issue
  - reproduction steps (minimal)
  - expected vs actual behavior
  - environment details (OS, tool version/commit, relevant flags)
  - potential impact and suggested fix (if you have one)

## Scope

This repository includes read-only system and project scanning utilities (e.g. `who-uses`).
We treat as security-relevant, among others:
- output leaks of sensitive information (absolute paths, tokens, credentials)
- unexpected writes / destructive behavior
- command injection / unsafe argument handling
- unsafe defaults that cause data exposure

## Response

We aim to:
- acknowledge reports promptly,
- assess severity and impact,
- provide a fix and coordinated disclosure when appropriate.
