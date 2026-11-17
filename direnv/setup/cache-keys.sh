#!/usr/bin/env bash
# Publish the keys for direnv/setup's two cache entries. README.md states the key shape and
# what each segment buys; this script is the only place the shape is constructed.
#
# Asserted directly by the cache-keys job in .github/workflows/direnv-setup-test.yml, which
# is why every value arrives through the environment and the outputs go to
# ${GITHUB_OUTPUT:-/dev/stdout}.
set -euo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"
working_directory="${WORKING_DIRECTORY:-.}"
cache_paths="${CACHE_PATHS:-}"
os="${RUNNER_OS:-unknown}"

# UTC, so a job running near midnight cannot be assigned a different window depending on the
# runner's zone. One call rather than two, so a job crossing a second boundary cannot pair a
# month with a week read a moment earlier.
#
# The week needs no year of its own: %U is the week of the same calendar year the month
# segment already pins, and it never repeats within a month. The 'w' marker is what keeps
# 2026-11-w46 from reading as a date with a day of 46.
#
# Both fields are fixed-width and the month is followed by a separator in every key below, so
# the month fallback rung cannot prefix-match a neighbouring month.
read -r month week <<< "$(date -u '+%Y-%m w%U')"

# Sorted under LC_ALL=C: a locale's collation ignores punctuation, so the same list would
# digest differently between runners and cold-start a lineage that is in fact unchanged.
normalized="$(printf '%s\n' "$cache_paths" \
  | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }' \
  | LC_ALL=C sort)"

# The lineage segment. Two callers with different path sets must not share a key: the first
# to save owns it, and the loser is handed cache-hit: true having restored none of its own
# paths. working-directory is in the digest because a monorepo's workspaces resolve the same
# relative path to different trees.
digest="$(
  {
    printf '%s\n' "$working_directory"
    if [[ -n "$normalized" ]]; then printf '%s\n' "$normalized"; fi
  } | sha256sum | cut -c1-12
)"

# The digest precedes the rotating segments because restore-keys are prefix matches: placed
# last it would be absent from the fallback rung, and direnv-setup-<os>-<month>- would match
# every lineage and return whichever saved most recently.
tools_prefix="direnv-setup-tools-${os}-${month}-"
paths_prefix="direnv-setup-${digest}-${os}-${month}-"

{
  echo "digest=${digest}"
  echo "tools-key=${tools_prefix}${week}"
  echo "tools-restore-keys=${tools_prefix}"
  echo "paths-key=${paths_prefix}${week}"
  echo "paths-restore-keys=${paths_prefix}"
} >> "$output"
