#!/bin/bash
set -euo pipefail

# The whole of the update-pixi-dependencies composite action. Run as a step inside a
# consumer's job, so every failure path below exits non-zero deliberately: this action
# exists to produce a dependency bump, and a green run that silently bumped nothing is
# the one outcome worse than a red one.
#
# Reads two variables the action passes through env: (never interpolated into the step's
# run: body - see SECURITY.md):
#   PINNING_STRATEGY - the --pinning-strategy value, validated below.
# The working directory is set by the step itself, so this script always runs with the
# workspace it is to upgrade as $PWD.

# This action installs nothing. pixi comes from the job, which is what lets a caller pin
# it the way they already pin everything else - and why the error names the two ways of
# providing one rather than just reporting an absence.
if ! command -v pixi >/dev/null 2>&1; then
  cat >&2 <<'MSG'
update-pixi-dependencies: pixi is not on PATH.
This action upgrades a workspace with the pixi the job already provides; it installs
none itself. Add a step that provides one before this action, for example:

  - uses: TomBorglum/actions/setup-direnv@v2   # with `use pixi <version>` in the .envrc
  - uses: prefix-dev/setup-pixi@<sha>          # with run-install: false
MSG
  exit 1
fi
# Log the version: every upgrade this action performs is the judgement of one particular
# pixi resolver, so a run that produced a surprising bump has to be attributable to one.
echo "update-pixi-dependencies: using $(pixi --version) in $(pwd)"

# A missing manifest is a hard error, and the test is load-bearing beyond its message:
# pixi's manifest discovery walks PARENT directories, so without it a working-directory
# that holds no manifest would quietly upgrade whichever workspace sits above it in the
# checkout - and report success for having done so.
#
# pixi.toml specifically, not pyproject.toml: this action's contract is a pixi.toml at
# the root of the directory it is pointed at.
if [[ ! -f pixi.toml ]]; then
  echo "update-pixi-dependencies: no pixi.toml in $(pwd)" >&2
  exit 1
fi

# The strategy reaches a command line, so it is allowlisted rather than quoted-and-hoped
# - the same judgement as setup-direnv's bare-identifier check on stub-directives. The
# set is pixi's own documented one; validating here also turns a typo into this message
# instead of a clap error from a tool the caller did not invoke directly.
case "${PINNING_STRATEGY:-}" in
  no-pin | semver | major | minor | latest-up | exact-version) ;;
  *)
    echo "update-pixi-dependencies: invalid pinning-strategy '${PINNING_STRATEGY:-}'." >&2
    echo "Expected one of: no-pin semver major minor latest-up exact-version" >&2
    exit 1
    ;;
esac

# sha256 of a file, or the empty string when it does not exist. The missing case is not a
# guard against error: a workspace that commits no pixi.lock has one created by the
# upgrade, and that is a change the caller must see.
hash_of() {
  if [[ -f "$1" ]]; then
    sha256sum "$1" | cut -d' ' -f1
  fi
}

toml_before="$(hash_of pixi.toml)"
lock_before="$(hash_of pixi.lock)"

# Everything intermediate lives outside the workspace. The point of --no-install is that
# this action leaves nothing behind in the checkout but the two files it is meant to
# rewrite, and a scratch copy of the manifest inside it would undo that.
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/update-pixi-dependencies.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp pixi.toml "$work/pixi.toml.before"

# --no-install: "Don't modify the environment, only modify the lock file". The downstream
# pull request needs exactly pixi.toml and pixi.lock, so materialising .pixi/envs/ would
# cost a full package download per run and leave a directory the PR step must then know
# to leave out.
#
# No --feature: a bare upgrade covers feature-scoped dependencies too, which the test
# fixture asserts by carrying one.
#
# stdout is captured rather than piped so pixi's exit code is the only success signal,
# then echoed into the log - a failed run's partial output is worth reading, and the
# JSON is otherwise invisible to anyone debugging from the log alone.
json="$work/upgrade.json"
upgrade_status=0
pixi upgrade --no-install --pinning-strategy "$PINNING_STRATEGY" --json >"$json" || upgrade_status=$?
cat "$json"
if ((upgrade_status != 0)); then
  echo "update-pixi-dependencies: pixi upgrade failed in $(pwd)" >&2
  exit 1
fi

# The change signal is the files themselves, hashed. Not `git status`, which assumes a
# git checkout and would report true for a modification some earlier step made; and not
# pixi's JSON, whose shape is documented nowhere and would make the gate depend on a
# schema that can shift between releases.
toml_after="$(hash_of pixi.toml)"
lock_after="$(hash_of pixi.lock)"
changed=false
if [[ "$toml_before" != "$toml_after" || "$lock_before" != "$lock_after" ]]; then
  changed=true
fi

# The summary is derived from the manifest's own before/after, so it depends on no output
# format: under exact-version every upgrade is a visible `==1.2.3` -> `==1.3.0`, which is
# what a pull request body should say.
summary=""
if [[ "$changed" == true ]]; then
  if [[ "$toml_before" == "$toml_after" ]]; then
    # The lockfile moved on its own - a transitive dependency resolved differently, or
    # the workspace committed no lockfile until now. There is no constraint change to
    # tabulate, and saying so beats an empty table.
    summary='Only `pixi.lock` changed; no version constraint in `pixi.toml` moved.'
  else
    diff_out="$work/pixi.toml.diff"
    # diff exits 1 for "files differ", which is the expected case here, so its status
    # carries no information worth gating on. --label because the fallback summary below
    # can end up in a pull request body, where the real header's scratch path and
    # timestamps would be noise at best.
    diff -u --label 'pixi.toml (before)' --label 'pixi.toml (after)' \
      "$work/pixi.toml.before" pixi.toml >"$diff_out" || true

    # Pair the -/+ lines of the diff on the dependency name. Both manifest spellings are
    # handled - `name = "==1.2.3"` and the inline table `name = { version = "==1.2.3",
    # ... }` - by taking the first double-quoted string on the line that contains a
    # digit as the constraint. awk exits non-zero when it paired nothing, which is the
    # signal to fall back below.
    if table="$(awk '
      /^(---|\+\+\+)/ { next }
      /^[-+]/ {
        sign = substr($0, 1, 1)
        line = substr($0, 2)

        # The dependency name: the key at the start of the line, bare or quoted. Anchored
        # at ^, so a `version =` inside an inline table cannot be mistaken for one.
        if (match(line, /^[[:space:]]*"?[A-Za-z0-9_.+-]+"?[[:space:]]*=/) == 0) next
        key = substr(line, RSTART, RLENGTH)
        sub(/[[:space:]]*=$/, "", key)
        sub(/^[[:space:]]*/, "", key)
        gsub(/"/, "", key)

        rest = line
        ver = ""
        while (match(rest, /"[^"]*"/)) {
          cand = substr(rest, RSTART + 1, RLENGTH - 2)
          rest = substr(rest, RSTART + RLENGTH)
          if (cand ~ /[0-9]/) { ver = cand; break }
        }
        if (ver == "") next

        if (sign == "-") {
          if (!(key in from)) { from[key] = ver; order[++n] = key }
        } else {
          if (!(key in to)) { to[key] = ver; if (!(key in from)) order[++n] = key }
        }
      }
      END {
        rows = 0
        for (i = 1; i <= n; i++) {
          k = order[i]
          if (seen[k]++) continue
          if ((k in from) && (k in to) && from[k] != to[k]) {
            printf "| `%s` | `%s` | `%s` |\n", k, from[k], to[k]
            rows++
          }
        }
        exit (rows > 0 ? 0 : 1)
      }
    ' "$diff_out")"; then
      summary="| Package | From | To |"$'\n'"| --- | --- | --- |"$'\n'"$table"
    else
      # A manifest restructured by the upgrade, or a strategy whose constraints are not
      # one-to-one (no-pin writes `*`, with no version to tabulate). The raw diff is less
      # pretty and never wrong, and an empty summary beside changed=true would read as a
      # bug in this action rather than a manifest it could not parse.
      summary="The manifest changed in a way this action could not summarise as a table:"$'\n\n'"\`\`\`diff"$'\n'"$(cat "$diff_out")"$'\n'"\`\`\`"
    fi
  fi
fi

echo "update-pixi-dependencies: changed=$changed"
if [[ -n "$summary" ]]; then
  echo "$summary"
fi

# Multi-line values go through the documented `{name}<<{delimiter}` form, and the
# delimiter is random per run: a crafted package name or version reaching the summary
# cannot then close the heredoc early and forge an output of its own. packages-json is
# pixi's own stdout, carried through unparsed - neither output above depends on its shape.
delimiter="UPDATE_PIXI_EOF_$(openssl rand -hex 16)"
{
  echo "changed=$changed"
  printf 'summary<<%s\n%s\n%s\n' "$delimiter" "$summary" "$delimiter"
  printf 'packages-json<<%s\n%s\n%s\n' "$delimiter" "$(cat "$json")" "$delimiter"
} >>"$GITHUB_OUTPUT"
