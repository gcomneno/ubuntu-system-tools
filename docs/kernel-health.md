# kernel-health

`kernel-health` is a local, read-only analyzer for kernel warnings across recent
boots. It groups warnings by stable signature and describes recurrence and
quantitative dynamics without assigning severity or attempting remediation.

## Safety model

- read-only;
- no automatic `sudo` or root requirement;
- no network activity;
- no `sysctl` calls;
- no writes to `/proc` or `/sys`;
- no systemd or journal changes;
- no cleanup or automatic fixes.

The only system data source in version 1 is `journalctl -k`.

## Usage

```bash
kernel-health
kernel-health --boots 5
kernel-health --help
```

The default is three recent boots. `--boots N` accepts positive integers.

## Acquisition

For each requested boot, the tool runs the equivalent of:

```bash
journalctl -k -p warning --boot=0 --no-pager -o cat
journalctl -k -p warning --boot=-1 --no-pager -o cat
```

Older boot offsets continue as `-2`, `-3`, and so on.

A missing previous boot reduces reported coverage but does not make the command
fail. Failure to inspect the current boot is an operational error. The tool
never retries with elevated privileges.

## Classification

Only signatures present in the current boot are reported.

- `NEW`: present in the current boot and absent from available previous boots.
- `RECURRING`: present in the current boot and at least one available previous
  boot.
- `INCREASING`: recurring and supported by an explicit quantitative growth rule.

Version 1 applies `INCREASING` only to the known `delayed_fput` warning. Its
current-boot counter sequence must contain at least two values, be strictly
increasing, and finish at least twice the first value.

A successful analysis exits with status `0` even when findings exist. Invalid
usage or failure to inspect the current boot exits with status `2`.

## Stable signatures

Normalization is deliberately conservative.

1. Common journal metadata such as timestamps, hostnames and the `kernel:`
   prefix is removed when present.
2. Generic warning messages otherwise remain unchanged, so semantically
   different warnings are not merged by broad numeric replacement.
3. A specific parser recognizes:

   `workqueue: delayed_fput hogged CPU for >...us ... times, consider switching to WQ_UNBOUND`

   For that known warning, the threshold and occurrence counter are treated as
   dynamic fields. The stable display label is:

   `workqueue: delayed_fput hogged CPU`

The occurrence counters are preserved as ordered per-boot sequences such as
`4 → 8 → 16`.

## Output and incomplete history

The report includes boot coverage. If previous journal history is unavailable,
classification uses only the boots that could be read and the reduced coverage
is visible in the output.

`journalctl` diagnostics emitted alongside otherwise usable output are not
copied verbatim; the report only notes how many boots produced diagnostics.
This avoids turning incidental local journal details into report content.

## Testing

Acquisition, parsing, normalization, classification and rendering are separate
functions. Tests replace the `journalctl` executable through the internal
`KERNEL_HEALTH_JOURNALCTL` test hook, so the test suite never depends on the
host journal or root privileges.

Sanitized fixtures model the observed `delayed_fput` sequences across three
boots.

## Deferred follow-ups

Version 1 intentionally has no `--json` or `--porcelain` contract. A stable
machine-readable summary can be introduced later if another tool needs to
consume `kernel-health` without parsing human output.

`twr-weekly-health` integration is also deferred until such an integration is
small and natural. The kernel parsing and classification must remain owned by
`kernel-health` rather than being duplicated by a caller.
