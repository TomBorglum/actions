#!/usr/bin/env bash
# Publish the keys for direnv/setup's two cache entries. README.md states the key shape.
#
# Asserted directly by the cache-keys job in .github/workflows/direnv-setup-test.yml.
set -euo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"
working_directory="${WORKING_DIRECTORY:-.}"
cache_paths="${CACHE_PATHS:-}"
cache_paths_manifests="${CACHE_PATHS_MANIFESTS:-}"
os="${RUNNER_OS:-unknown}"
# RUNNER_OS is 'Linux' on x86_64 and aarch64 alike, so the architecture has to be named
# separately or an arm64 job restores x86_64 toolchain binaries.
arch="${RUNNER_ARCH:-unknown}"

# UTC, so the window does not depend on the runner's zone. One call rather than two, so a job
# crossing a second boundary cannot pair a month with a week read a moment earlier.
read -r month week <<< "$(date -u '+%Y-%m w%U')"

# LC_ALL=C: a locale's collation ignores punctuation, so the same list would sort differently
# between runners and cold-start an unchanged lineage.
normalize() {
  local list=$1
  printf '%s\n' "$list" \
    | awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }' \
    | LC_ALL=C sort
}

normalized="$(normalize "$cache_paths")"
manifest_patterns="$(normalize "$cache_paths_manifests")"

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

# The pattern is a glob, so the expansion is unquoted; an empty IFS keeps a space in a path
# whole.
expand() {
  local pattern=$1
  local IFS=
  # shellcheck disable=SC2206
  matches=($pattern)
}

manifests_digest=""
if [[ -n "$manifest_patterns" ]]; then
  if [[ -z "$normalized" ]]; then
    echo "direnv/setup: cache-paths-manifests is set but cache-paths is empty, so the" \
      "entry it rotates would not exist" >&2
    exit 1
  fi
  shopt -s globstar nullglob
  files=()
  while IFS= read -r pattern; do
    expand "$pattern"
    if [[ ${#matches[@]} -eq 0 ]]; then
      echo "direnv/setup: cache-paths-manifests pattern '$pattern' matches no file" >&2
      exit 1
    fi
    for match in "${matches[@]}"; do
      if [[ ! -f "$match" ]]; then
        echo "direnv/setup: cache-paths-manifests pattern '$pattern' matches '$match'," \
          "which is not a regular file" >&2
        exit 1
      fi
      files+=("$match")
    done
  done <<< "$manifest_patterns"
  mapfile -d '' -t files < <(printf '%s\0' "${files[@]}" | LC_ALL=C sort -zu)
  manifests_digest="$(digest_of "$(sha256sum -- "${files[@]}")")"
fi

# The digest precedes the rotating segments: restore-keys are prefix matches, so placed last it
# would be absent from the fallback rung and one lineage would match another.
tools_prefix="direnv-setup-tools-${tools_digest}-${os}-${arch}-${month}-"
paths_prefix="direnv-setup-paths-${digest}-${os}-${arch}-${month}-"

# Unlike the digest, the manifests segment is last: it rotates one lineage's key, so it stays
# out of paths_prefix and a changed manifest base-restores the lineage's newest entry.
paths_key="${paths_prefix}${week}"
if [[ -n "$manifests_digest" ]]; then paths_key="${paths_key}-${manifests_digest}"; fi

{
  echo "tools-digest=${tools_digest}"
  echo "digest=${digest}"
  echo "manifests-digest=${manifests_digest}"
  echo "tools-key=${tools_prefix}${week}"
  echo "tools-restore-keys=${tools_prefix}"
  echo "paths-key=${paths_key}"
  echo "paths-restore-keys=${paths_prefix}"
} >> "$output"
