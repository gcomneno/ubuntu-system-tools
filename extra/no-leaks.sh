#!/usr/bin/env bash
set -euo pipefail

# Generic leak patterns (keep conservative):
# - absolute home paths
# - common mount points
# - common secrets-like env assignments
PATTERN='(/home/[^/]+/|/mnt/|/media/|/run/media/|(^|[^A-Za-z0-9_])(TOKEN|SECRET|PASSWORD|API_KEY)\s*=\s*[^[:space:]]+)'

# pre-commit passes file list as args; if empty, scan repo files (rare)
files=("$@")
IGNORE_RE="^(extra/no-leaks\.sh|\.pre-commit-config\.yaml)$"

should_skip() {
  local f="$1"
  [[ "$f" =~ $IGNORE_RE ]]
}

if [[ ${#files[@]} -eq 0 ]]; then
  mapfile -t files < <(git ls-files)
fi

bad=0
for f in "${files[@]}"; do
  should_skip "$f" && continue
  [[ -f "$f" ]] || continue
  # Only scan likely-text files (best effort)
  if rg -n "$PATTERN" -- "$f" >/dev/null 2>&1; then
    echo "NO-LEAKS: blocked potential leak in: $f" >&2
    echo "Hint: avoid absolute paths; use \$HOME and env vars. Avoid committing secrets." >&2
    bad=1
  fi
done

exit "$bad"
