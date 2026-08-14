# weekly-health

`weekly-health` is a local, read-only weekly orchestrator for the repository's
three security-health components:

1. `security-health`
2. `kernel-health`
3. `security-clamav-scan --yes`

It does not duplicate their internal logic. It only resolves and runs them,
collects their statuses, and prints a clear summary.

## Safety model

- read-only orchestration only;
- no `sudo` and no hidden privilege escalation;
- no package management;
- no network activity;
- no repairs, quarantine, or deletion;
- no attempt to kill unrelated processes;
- no automatic installation of missing tools.

The report can contain sensitive paths or journal output because it includes the
output of the component tools.

## Resolution

The tool resolves its sibling helpers conservatively:

- first, it prefers the directory that contains the `weekly-health`
  executable when all three helpers are present there;
- otherwise, it falls back to `PATH` only if all helpers resolve to the same
  directory;
- if resolution is missing or ambiguous, the tool fails closed with exit code
  `2`.

This makes symlink installs, copied installs, and package installs behave the
same way as long as the three helpers are installed together.

## Execution order

The component order is fixed:

1. `security-health`
2. `kernel-health`
3. `security-clamav-scan --yes`

The scan step is always invoked with `--yes`; `weekly-health` does not ask for
its own duration confirmation.

## Status contract

Each component keeps its own exit status in the report.

- `0` - clean;
- `1` - findings;
- `2` - operational error;
- `3` - the ClamAV scan was cancelled before starting;
- `130` - interrupted by `SIGINT`;
- `143` - terminated by `SIGTERM`.

Aggregate status rules:

- any `SIGINT` or `SIGTERM` propagates as `130` or `143`;
- any mandatory operational failure produces aggregate `2`;
- ClamAV cancellation `3` is treated as aggregate `2` because the scan did not
  run;
- otherwise, any finding produces aggregate `1`;
- only fully successful clean checks produce aggregate `0`.

## Output

The report uses clear section boundaries for each component and a final summary
block that lists the component status and the aggregate status.

## Testing

The selftests use fake helper executables so they can verify resolution, order,
status propagation, and signal handling without touching the real system.
