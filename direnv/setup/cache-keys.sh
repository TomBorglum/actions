#!/usr/bin/env bash
# Publish the keys for direnv/setup's two cache entries. README.md states the key shape.
#
# Asserted directly by the cache-keys job in .github/workflows/direnv-setup-test.yml.
set -euo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"
working_directory="${WORKING_DIRECTORY:-.}"
cache_paths="${CACHE_PATHS:-}"
os="${RUNNER_OS:-unknown}"
# RUNNER_OS is 'Linux' on x86_64 and aarch64 alike, so the architecture has to be named
# separately or an arm64 job restores x86_64 toolchain binaries.
arch="${RUNNER_ARCH:-unknown}"

# UTC, so the window does not depend on the runner's zone. One call rather than two, so a job
# crossing a second boundary cannot pair a month with a week read a moment earlier.
read -r month week <<< "$(date -u '+%Y-%m w%U')"

# LC_ALL=C: a locale's collation ignores punctuation, so the same list would sort differently
# between runners and cold-start an unchanged lineage.
normalized="$(printf '%s\n' "$cache_paths" \
  | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }' \
  | LC_ALL=C sort)"

digest_of() {
  local value=$1
  printf '%s' "$value" | sha256sum | cut -c1-12
}

# One key holds one set of contents, and a save is skipped on an exact hit, so a key shared by
# two callers whose contents differ is owned by whichever saves first and the rest restore it
# and then install from scratch for the rest of the window. Both lineages therefore carry
# working-directory: one repository's workspaces can declare different toolchains, and a
# monorepo resolves the same relative path to different trees.
tools_digest="$(digest_of "$working_directory")"
digest="$(
  digest_of "$(
    printf '%s\n' "$working_directory"
    if [[ -n "$normalized" ]]; then printf '%s\n' "$normalized"; fi
  )"
)"

# The digest precedes the rotating segments: restore-keys are prefix matches, so placed last it
# would be absent from the fallback rung and one lineage would match another.
tools_prefix="direnv-setup-tools-${tools_digest}-${os}-${arch}-${month}-"
paths_prefix="direnv-setup-paths-${digest}-${os}-${arch}-${month}-"

{
  echo "tools-digest=${tools_digest}"
  echo "digest=${digest}"
  echo "tools-key=${tools_prefix}${week}"
  echo "tools-restore-keys=${tools_prefix}"
  echo "paths-key=${paths_prefix}${week}"
  echo "paths-restore-keys=${paths_prefix}"
} >> "$output"
