#!/bin/bash
set -euo pipefail

# The whole of the direnv/upgrade-pixi composite action. Run as a step inside a consumer's job, so
# every failure path below exits non-zero deliberately: this action exists to produce a
# version bump, and a green run that silently bumped nothing is the one outcome worse than
# a red one.
#
# It takes no variables. The working directory is set by the step itself, so this script
# always runs with the directory holding the .envrc as $PWD - there is nothing to
# interpolate into the step's run: body and nothing to validate (see SECURITY.md).
#
# What it reads is a directive, not a file format of ours: direnv's stdlib documents
# `use <program_name> [<version>]` as a command dispatch, and the scope of this action is
# exactly one such call - `use pixi <version> [template]`. The version is its first
# argument; everything after it belongs to whoever wrote the .envrc, which is why the
# rewrite below replaces one field and preserves the rest of the line verbatim.

# Where the version comes from. The requirement it has to satisfy: whatever this action
# writes must be installable by the directive it writes it into, so the source is the one
# that directive's own installer resolves "latest" against rather than a second opinion to
# reconcile with it. GitHub defines "latest" as the most recent non-prerelease, non-draft
# release, so a prerelease can never reach a pin.
LATEST_URL='https://github.com/prefix-dev/pixi/releases/latest'
TAG_PREFIX='https://github.com/prefix-dev/pixi/releases/tag/'

# A fully qualified X.Y.Z. The directive REQUIRES one and rejects a partial pin outright,
# so writing anything else into an .envrc would break the next `direnv allow`. Applied to
# the version read out of the file and to the version read from upstream, for the same
# reason in both directions.
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# The pinned form, captured in three parts so the rewrite can put back everything it did
# not change: \1 the directive and its spacing, \2 the version, \3 the optional template
# argument, any trailing comment, and a trailing \r if the file was last saved by a
# Windows editor (\r is in [[:space:]], so it lands here rather than in the version).
DIRECTIVE_RE='^([[:space:]]*use[[:space:]]+pixi[[:space:]]+)([^[:space:]]+)(.*)$'
# The directive with no version at all. Matched separately so it can be reported as the
# distinct problem it is: a version is required, so such an .envrc does not load today.
UNPINNED_RE='^[[:space:]]*use[[:space:]]+pixi[[:space:]]*$'

if [[ ! -f .envrc ]]; then
  echo "direnv/upgrade-pixi: no .envrc in $(pwd)" >&2
  exit 1
fi

# Find the directive before touching anything. Deliberately a scan of THIS file only:
# the contract is the .envrc in the directory the action was pointed at, and nothing here
# looks in a parent for one.
#
# `|| [[ -n "$line" ]]` so a final line with no newline is still read.
pinned=0 unpinned=0 current='' lineno=0 at_line=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  if [[ "$line" =~ $DIRECTIVE_RE ]]; then
    pinned=$((pinned + 1))
    current="${BASH_REMATCH[2]}"
    at_line=$lineno
  elif [[ "$line" =~ $UNPINNED_RE ]]; then
    unpinned=$((unpinned + 1))
    at_line=$lineno
  fi
done < .envrc

# A commented-out line never reaches either branch: both patterns anchor the directive at
# the start of the line, with only whitespace allowed before it.
total=$((pinned + unpinned))
if ((total == 0)); then
  cat >&2 <<'MSG'
direnv/upgrade-pixi: no `use pixi <version>` directive in .envrc.
This action updates the pixi version pinned by direnv's `use pixi` directive. The .envrc
in the directory it was pointed at declares none, which usually means working-directory
is wrong. It reads only the documented dispatch form:

  use pixi 0.81.0            # and `use pixi 0.81.0 <template>`

A direct `use_pixi 0.81.0` function call is not matched.
MSG
  exit 1
fi
if ((total > 1)); then
  echo "direnv/upgrade-pixi: .envrc declares $total \`use pixi\` directives; which one is the pin is ambiguous" >&2
  exit 1
fi
if ((unpinned == 1)); then
  echo "direnv/upgrade-pixi: the \`use pixi\` directive on line $at_line of .envrc pins no version" >&2
  echo "        a version is required, so there is nothing to update here: use pixi <version> [template]" >&2
  exit 1
fi
if [[ ! "$current" =~ $SEMVER_RE ]]; then
  echo "direnv/upgrade-pixi: line $at_line of .envrc pins '$current', which is not a fully qualified X.Y.Z" >&2
  echo "        a partial pin is rejected by the directive, so this .envrc does not load today - fix the pin rather than bumping it" >&2
  exit 1
fi
echo "direnv/upgrade-pixi: .envrc pins pixi $current (line $at_line) in $(pwd)"

# Detection, not installation: one HTTPS request that downloads no payload. -I makes it a
# HEAD, -L follows the redirect GitHub answers with, and %{url_effective} reports where it
# landed. No token, so there is no input for a caller to forget and no API rate limit to
# share with every other job on the runner's IP.
# --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+ (no plaintext redirects).
url=''
if ! url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --proto '=https' --tlsv1.2 "$LATEST_URL")"; then
  echo "direnv/upgrade-pixi: could not resolve $LATEST_URL" >&2
  exit 1
fi

# The permalink is documented; the shape of what it redirects TO is observed, not promised.
# So assert it, rather than parsing hopefully: if GitHub ever lands somewhere else, this
# fails loudly instead of writing a corrupt pin into an .envrc.
if [[ "$url" != "$TAG_PREFIX"* ]]; then
  echo "direnv/upgrade-pixi: $LATEST_URL redirected to an unexpected target: $url" >&2
  exit 1
fi
tag="${url#"$TAG_PREFIX"}"
latest="${tag#v}"
if [[ ! "$latest" =~ $SEMVER_RE ]]; then
  echo "direnv/upgrade-pixi: '$tag' is not a version this directive can pin (expected vX.Y.Z)" >&2
  exit 1
fi
echo "direnv/upgrade-pixi: releases/latest reports pixi $latest"

changed=false
if [[ "$current" != "$latest" ]]; then
  changed=true
fi

# Plain inequality, not a version-ordering comparison - the same test update-direnv.yml
# makes for the version it maintains. Worth knowing why that is a choice: GitHub orders
# "latest" by created_at, the date of the COMMIT a tag points at, so a release cut today
# from an older line can outrank a higher version and would move a pin backwards. Upstream
# has never done that - every release to date is monotonic in both version and commit date
# - and a downgrade would still arrive as a reviewable pull request, not a silent commit.
if [[ "$changed" == true ]]; then
  work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/direnv-upgrade-pixi.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  new="$work/envrc.new"

  # Whether the file ends in a newline, because the rewrite below adds one per line and a
  # file that had none would otherwise gain one - a second hunk in the pull request, on a
  # line nothing changed about. $( ) strips trailing newlines, so an empty result means the
  # last byte was one.
  had_trailing_newline=1
  if [[ -n "$(tail -c 1 .envrc)" ]]; then
    had_trailing_newline=0
  fi

  : >"$new"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $DIRECTIVE_RE ]]; then
      # One field replaced. Everything else on the line - indentation, the template
      # argument, a trailing comment, a CRLF's \r - is put back from the captures.
      printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$latest" "${BASH_REMATCH[3]}" >>"$new"
    else
      printf '%s\n' "$line" >>"$new"
    fi
  done < .envrc
  if ((had_trailing_newline == 0)); then
    truncate -s -1 "$new"
  fi

  # Truncate in place rather than mv the temp file over it: the .envrc is a tracked file
  # whose mode and inode should survive the edit, and the scratch copy exists so that a
  # failure anywhere above leaves the original untouched.
  cat "$new" >.envrc
fi

# The one row a pull request body needs, in the same table shape
# pixi/upgrade-dependencies' summary uses - so the workflow that will drive several of
# these directive actions can concatenate their summaries into one body.
summary=''
if [[ "$changed" == true ]]; then
  summary="| Dependency | From | To |"$'\n'"| --- | --- | --- |"$'\n'"| \`pixi\` | \`$current\` | \`$latest\` |"
fi

echo "direnv/upgrade-pixi: changed=$changed"
if [[ -n "$summary" ]]; then
  echo "$summary"
fi

# Multi-line values go through the documented `{name}<<{delimiter}` form, with a random
# delimiter per run. Both versions are matched against SEMVER_RE above, so neither can
# contain a newline to forge an output with in the first place - the delimiter is random
# anyway, because that property should not be the thing holding the boundary.
delimiter="UPDATE_PIXI_EOF_$(openssl rand -hex 16)"
{
  echo "changed=$changed"
  echo "current-version=$current"
  echo "latest-version=$latest"
  printf 'summary<<%s\n%s\n%s\n' "$delimiter" "$summary" "$delimiter"
} >>"$GITHUB_OUTPUT"
