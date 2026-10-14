#!/bin/bash
# use_pixi <version> [template]
#
# CI-only (GitHub Actions) direnv directive for a pixi workspace. The action
# installs this file onto the runner's ~/.config/direnv/lib; it is never run
# outside GitHub Actions. Self-contained by design: it sources no other file in
# this repository.
#
# Deliberately simpler than the interactive terminal directive: its PATH_add exists to
# keep direnv's interactive load/unload clean, which CI does not do. It also does NOT
# scaffold a pixi.toml — CI activates a workspace the repo already commits, so a
# missing manifest is a hard error, not a convenience to paper over. pixi has no
# canonical <TOOL>_HOME convention, so the bin dirs on $GITHUB_PATH are the whole of what
# this exposes - there is no <TOOL>_HOME for the action to forward.
use_pixi() {
  # $1 is the pinned pixi version, mandatory. $2 is the workstation template name, which
  # CI accepts and ignores the way use_fnm ignores its trusted 'node' token: CI activates
  # a workspace the repo already commits, so there is nothing here for a template to do,
  # and ignoring it is what lets one .envrc serve a workstation and a runner alike.
  local version="${1:-}"

  # Presence is the only thing worth checking. pixi's installer resolves PIXI_VERSION to a
  # release tag, so a value that is not one - a partial like 0.81, or the old form's
  # `use pixi python` - fails the download and is caught by the post-install check below;
  # there is no silently-resolved partial here for a format check to prevent, as there is
  # for `fnm install 22`. An EMPTY value is the one real hazard: install.sh does
  # VERSION="${PIXI_VERSION:-latest}", so passing one through would install whatever is
  # latest that day, which is the drift the pin exists to stop.
  if [[ -z "$version" ]]; then
    echo "use_pixi: a pixi version is required: use pixi <version> [template]" >&2
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # Install pixi under an explicit home rather than relying on the installer's
  # default: PIXI_HOME pins the location (binary at $PIXI_HOME/bin/pixi), and this
  # one variable drives the guard, PATH, and $GITHUB_PATH below. Value stays ~/.pixi so
  # it matches the toolchain cache path the action restores.
  local pixi_home="$HOME/.pixi"
  local pixi_bin="$pixi_home/bin/pixi"
  # `pixi --version` reports a bare X.Y.Z, while the installer takes that or a v-prefixed
  # tag (it builds the download URL from v${VERSION#v}), which is how pixi's own docs
  # write it. Strip the prefix so this guard is no stricter than the installer it drives.
  local want="pixi ${version#v}"

  # Guard on the version the binary reports rather than on the install dir existing. This
  # action runs inside a consumer's job, so ~/.pixi may already hold a different pixi - an
  # earlier step, prefix-dev/setup-pixi, or a persistent $HOME on a self-hosted runner -
  # and ~/.pixi is also where `pixi global` keeps its own installs, so the directory
  # existing is not evidence the binary does. It also keeps correctness independent of the
  # cache key, which the `cache: false` input turns off. Costs one exec, against a body
  # that already runs `pixi install`.
  #
  # --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+ (no plaintext
  # redirects); PIXI_NO_PATH_UPDATE=1 stops the installer editing shell rc files, a no-op
  # in CI since we put pixi on PATH ourselves.
  if [[ "$("$pixi_bin" --version 2>/dev/null)" != "$want" ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 https://pixi.sh/install.sh \
      | PIXI_VERSION="$version" PIXI_HOME="$pixi_home" PIXI_NO_PATH_UPDATE=1 bash
    # The installer's exit code is not the only signal worth having, so confirm what it
    # actually produced. This is also what turns a pin the installer cannot resolve into
    # a clear failure instead of a run against the wrong pixi.
    if [[ "$("$pixi_bin" --version 2>/dev/null)" != "$want" ]]; then
      echo "use_pixi: could not install pixi $version" >&2
      exit 1
    fi
  fi
  # Put pixi on PATH (CI has no shell integration / PATH_add) so it is callable below.
  export PATH="$pixi_home/bin:$PATH"

  # Install the workspace's environment. `pixi install` is idempotent: it reuses an
  # environment that already exists (e.g. restored from cache) and only solves
  # what is missing, so it respects what is already there. It returns non-zero on real
  # failure, so gate on its exit code directly (rather than `|| true` + a later check).
  # This single gate is the success signal, and catches both a failed pixi install
  # (command-not-found) and a missing manifest, which pixi rejects more accurately
  # than a pixi.toml/pyproject.toml file test would. The terminal directive scaffolds a
  # manifest; CI does not.
  #
  # --locked when a lockfile is present, a plain install otherwise - pixi's CI guidance,
  # and setup-pixi's documented default. --locked verifies the lockfile against the
  # manifest and aborts on a discrepancy, where a bare `pixi install` would UPDATE it
  # instead ("if the lock file is not up-to-date it will be updated"): CI would then run
  # against dependencies that are not the committed ones, and the drift would never
  # surface. The conditional is because --locked has nothing to verify against when there
  # is no lockfile. The terminal directive deliberately does not do this - it is where the
  # lockfile is authored, which is why it pairs a plain install with `watch_file
  # pixi.toml`.
  local install_result=0
  if [[ -f pixi.lock ]]; then
    pixi install --locked || install_result=$?
  else
    pixi install || install_result=$?
  fi
  if (( install_result != 0 )); then
    echo "use_pixi: pixi install failed in $(pwd)" >&2
    exit 1
  fi

  # Resolve the environment's prefix via pixi itself rather than hardcoding
  # .pixi/envs/default — `pixi run` activates the default environment and exports
  # the conda-style $CONDA_PREFIX, so this tracks wherever the environment
  # actually lives (a detached-environments config or a cache-restored prefix).
  # Ask the tool where it lives rather than assuming its on-disk layout.
  local env_prefix
  env_prefix="$(pixi run bash -c 'printf %s "$CONDA_PREFIX"' 2>/dev/null || true)"
  if [[ -z "$env_prefix" || ! -d "$env_prefix/bin" ]]; then
    echo "use_pixi: failed to resolve pixi environment prefix in $(pwd)" >&2
    exit 1
  fi

  # Expose the runtime to subsequent workflow steps: the environment's bin, plus
  # pixi's own bin ($pixi_home/bin) so `pixi` stays callable in later steps.
  echo "$env_prefix/bin" >> "$GITHUB_PATH"
  echo "$pixi_home/bin" >> "$GITHUB_PATH"
  return 0
}
