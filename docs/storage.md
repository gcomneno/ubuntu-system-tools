# Storage workflow

Ubuntu System Tools provides a safety-first storage workflow for observing,
classifying, proposing, reviewing, and explicitly cleaning selected Docker
storage.

The workflow is deliberately split into separate authority boundaries:

```text
observe
→ measure
→ attribute
→ correlate
→ classify
→ propose
→ human review
→ exact target
→ preview
→ explicit apply
→ revalidate
→ clean
→ verify
```

The central rule is:

```text
discovery != authority
classification != authority
proposal != authority
STALE_CANDIDATE != STALE_CONFIRMED
unknown != safe to delete
```

## Storage health and growth

`storage-check` is read-only by default.

It reports:

- root filesystem usage and available space;
- `$HOME`, `/var`, and the configured project root when readable;
- large project directories using configurable thresholds;
- growth against an explicit checkpoint.

Examples:

```bash
storage-check
storage-check --save-checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
storage-check --checkpoint "$HOME/.cache/ubuntu-system-tools/storage.env"
```

Optional Docker and DDEV audits can be delegated explicitly:

```bash
storage-check --docker --ddev
```

## Docker audit

`storage-docker-audit` inspects Docker containers, images, volumes, and BuildKit
cache without invoking prune or removal operations.

Evidence is classified conservatively as:

```text
ACTIVE
INACTIVE_PROTECTED
STALE_CANDIDATE
UNKNOWN
```

The Docker audit never promotes an artifact to `STALE_CONFIRMED`.

## DDEV audit

`storage-ddev-audit` correlates DDEV registry information, project roots, Git
worktrees, and generated approot metadata.

A stale generated path may be reported as:

```text
DDEV_METADATA_STATE=STALE_PATH
```

This is evidence only and is not deletion authority.

## Cleanup proposals

`storage-cleanup-proposal` converts only Docker image and volume
`STALE_CANDIDATE` evidence into a deterministic review manifest.

The proposal layer remains read-only:

```text
STALE_CANDIDATE != STALE_CONFIRMED
PROPOSAL != AUTHORITY
```

Image proposals use the immutable Docker image ID. Volume proposals use the
exact volume name.

Example:

```bash
storage-cleanup-proposal
```

Proposal output contains preview commands only:

```text
storage-cleanup image IMAGE_ID
storage-cleanup volume VOLUME_NAME
```

It never emits `--apply`.

The manifest always reports:

```text
REVIEW_REQUIRED=YES
AUTHORITY=NO
AUTOMATIC_DELETION=NO
```

The proposal fails closed unless its Docker audit source explicitly reports:

```text
STALE_CONFIRMED_COUNT=0
AUTOMATIC_DELETION=NO
```

BuildKit cache is not proposed for cleanup.

## Exact-target cleanup

`storage-cleanup` is a separate controlled-action tool.

It accepts exactly one Docker image or volume target.

Preview is the default:

```bash
storage-cleanup image IMAGE_REF_OR_ID
storage-cleanup volume VOLUME_NAME
```

Mutation requires the same exact target plus explicit `--apply`:

```bash
storage-cleanup image IMAGE_REF_OR_ID --apply
storage-cleanup volume VOLUME_NAME --apply
```

Before mutation, the tool:

1. resolves the exact target;
2. rejects references from running containers;
3. rejects references from stopped containers;
4. rechecks references immediately before mutation.

After Docker reports a successful removal, the tool verifies that the exact
target is absent.

It does not:

- run generic prune commands;
- remove containers;
- clear BuildKit cache;
- delete DDEV projects;
- invoke `sudo`;
- derive mutation authority from an audit classification.

## Authority model

The complete storage workflow intentionally keeps evidence, decisions, and
mutation separate:

```text
audit evidence
    ↓
classification
    ↓
proposal
    ↓
human review
    ↓
explicit exact target
    ↓
preview
    ↓
explicit --apply
    ↓
revalidation
    ↓
mutation
    ↓
verification
```

A candidate is never automatically treated as safe to delete.

## Privileges and dependencies

Inspection and proposal tools run as the current user and do not invoke
`sudo`.

Docker-related inspection requires the user's normal Docker access.

Relevant standard dependencies include Bash, `sort`, `awk`, and `grep`.

## Output sensitivity

Storage diagnostics may contain local project paths, Docker references, image
IDs, and volume names.

Review output before publishing or sharing it.
