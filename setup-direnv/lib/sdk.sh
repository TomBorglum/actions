#!/bin/bash
# use_sdk <candidate> <version>
#
# CI-only (GitHub Actions) direnv directive for JVM SDKs via SDKMAN. The action
# installs this file onto the runner's ~/.config/direnv/lib; it is never run
# outside GitHub Actions. Self-contained by design: it sources no other file in
# this repository.
#
# Drives SDKMAN the way its own docs do - install, then select - and lets the action
# forward the result. The terminal directive cannot: it selects with a plain `export`
# so direnv can restore the previous value when the directory is left, which CI never
# does. Arg checks, an SDKMAN_DIR override and PATH_add serve that same interactive
# load/unload and are absent here for the same reason.
use_sdk() {
  local candidate=$1
  local version=$2

  # SDKMAN, once per .envrc evaluation rather than once per candidate: sdkman-init.sh
  # resets every <CANDIDATE>_HOME to its candidates/<c>/current symlink, so a second
  # `use sdk` line re-sourcing it would undo what the first one selected. The `sdk`
  # function it defines is the guard, and installing is only the precondition for
  # sourcing - a defined `sdk` already implies an installed SDKMAN - so both sit behind
  # the one test. --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+ (no
  # plaintext redirects).
  if ! command -v sdk >/dev/null 2>&1; then
    [[ -d "$HOME/.sdkman" ]] ||
      curl -fsSL --proto '=https' --tlsv1.2 https://get.sdkman.io | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
  fi

  # `sdk home` prints the candidate's install dir and exits non-zero when it isn't
  # installed, so it is the idempotency gate: skip `sdk install` - and its network
  # round-trip - on a warm cache. Don't gate on `sdk install`'s own exit code, which is
  # non-zero even when the candidate installs fine.
  if ! sdk home "$candidate" "$version" >/dev/null 2>&1; then
    sdk install "$candidate" "$version" || true
  fi

  # Point this shell at the declared version. `sdk use` sets <CANDIDATE>_HOME (JAVA_HOME,
  # MAVEN_HOME, …) to the pinned candidate dir rather than the candidates/<c>/current
  # symlink sdkman-init.sh left there, and fails when the version is not installed - so
  # it is both the selector and the success check for the install above.
  if ! sdk use "$candidate" "$version" >/dev/null; then
    echo "use_sdk: failed to install $candidate $version (SDKMAN_DIR=${SDKMAN_DIR:-unset})" >&2
    ls -la "${SDKMAN_DIR:-$HOME/.sdkman}/candidates/$candidate" >&2 2>/dev/null || true
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # <CANDIDATE>_HOME now travels on its own - the action forwards the environment. PATH
  # it does not, so the bin dir is published explicitly, read back off the variable
  # `sdk use` just set rather than rebuilt from an assumed layout.
  local home_var="${candidate^^}_HOME"
  echo "${!home_var}/bin" >> "$GITHUB_PATH"
  return 0
}
