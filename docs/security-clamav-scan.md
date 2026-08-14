# security-clamav-scan

`security-clamav-scan` is a local, read-only ClamAV scanner for user-owned
directories and an explicit full-system scan. It never repairs, quarantines, or
deletes files.

## Safety model

- read-only inspection only;
- no `sudo` and no internal privilege escalation;
- no package installation, `freshclam`, or signature downloads;
- no quarantine, copy, move, or deletion of scanned files;
- no implicit network activity;
- recursive `clamscan` with cross-filesystem scanning disabled;
- per-user nonblocking lock to refuse concurrent scans cleanly;
- scan logs may contain sensitive paths and filenames.

The tool only writes auxiliary log output beneath a user-controlled state
directory unless `--log-dir` is supplied explicitly.

## Usage

```bash
security-clamav-scan
security-clamav-scan --target /path/to/dir
security-clamav-scan --full --yes
security-clamav-scan --log-dir /tmp/clamav-logs
```

Options:

- `--target PATH` scans a directory recursively; repeatable; any explicit
  targets replace the default targets;
- `--full` scans `/` recursively and shows a prominent long-scan warning;
- `--log-dir PATH` writes logs under the supplied directory;
- `--yes` skips only the long-scan confirmation;
- `-h`, `--help` prints usage.

## Scope

Default targets are used only when they exist and only when no explicit target is
given:

- `$HOME/Downloads`;
- `$HOME/Desktop` or `$HOME/Scrivania`;
- `$HOME/Documents`.

The tool does not implicitly include `/tmp`, `/var/tmp`, or other system paths.
If no usable default targets are present, the scan fails closed instead of
guessing a broader scope.

Explicit `--target` values must identify existing directories. The tool rejects
missing, ambiguous, or symlink-broadening targets rather than following them
silently.

`--full` explicitly selects `/`. It is the only mode that can scan the whole
filesystem tree.

## Logging

The default log directory is:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-system-tools/clamav/
```

Each run writes a separate log file there. Logs are intentionally detailed so
they can be inspected after the scan, which means they may contain local file
paths and filenames. Do not publish the logs without review.

If the log directory cannot be created or written, the command fails with exit
code `2`.

## ClamAV requirements

`security-clamav-scan` is intentionally narrow. It expects a user-installed
ClamAV scanner and local signature databases, but it does not install or update
anything itself.

The implementation checks local database directories and refuses to guess when
none are available. It does not run `freshclam`.

## Concurrency

A per-user `flock` lock prevents concurrent runs. The lock is nonblocking and
authoritative:

- if the lock is already held, the command fails with exit code `2`;
- the tool never terminates another process to obtain the lock;
- lock cleanup is automatic on exit and on signals.

## Exit codes

- `0` - scan completed cleanly;
- `1` - ClamAV reported a detection; no file was modified;
- `2` - invalid usage or operational error;
- `3` - the user cancelled before scanning;
- `130` - interrupted by `SIGINT`;
- `143` - terminated by `SIGTERM`.

Cancellation before scanning is not reported as clean.

## Full-scan warning

`--full` prints a prominent warning before any scan starts. The confirmation is
interactive unless `--yes` is supplied.

## Testing

The selftests use fake `clamscan` and isolated HOME/XDG directories so CI never
needs a real ClamAV installation or malware sample.
