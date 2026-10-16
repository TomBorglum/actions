#!/bin/bash
# use_fnm <tool> <version>
#
# CI-only (GitHub Actions) direnv directive for Node via fnm. The action installs
# this file onto the runner's ~/.config/direnv/lib; it is never run outside GitHub
# Actions. Self-contained by design: it sources no other file in this repository.
#
# Deliberately simpler than the interactive terminal directive: arg checks and PATH_add
# exist to keep direnv's interactive load/unload clean, which CI does not do. Node has no
# canonical <TOOL>_HOME convention, so the bin dir on $GITHUB_PATH is the whole of what
# this exposes - there is no <TOOL>_HOME for the action to forward.
use_fnm() {
  # $1 is the trusted tool token ('node'); fnm is Node-only, so ignore it and take
  # the version. CI trusts the committed .envrc — no arg validation.
  local version=$2

  # Standard fnm install into ~/.fnm; guard only to skip re-downloading on a warm
  # rerun / full cache hit. --proto '=https' --tlsv1.2 pins the transfer to
  # HTTPS/TLS 1.2+ (no plaintext redirects).
  if [[ ! -d "$HOME/.fnm" ]]; then
    curl -fsSL --proto '=https' --tlsv1.2 https://fnm.vercel.app/install \
      | bash -s -- --install-dir "$HOME/.fnm" --skip-shell
  fi
  # Put the fnm binary on PATH (CI has no shell integration / PATH_add) so `fnm` is
  # callable below. No FNM_DIR export: fnm defaults its data dir to ~/.fnm.
  export PATH="$HOME/.fnm:$PATH"

  # `fnm install` is idempotent, so run it unconditionally and don't gate on its
  # exit — the resolution below is the real success signal.
  fnm install "$version" || true

  # Resolve the installed node's real bin dir instead of hardcoding fnm's on-disk
  # layout — ask the tool where it lives rather than assuming its layout. `fnm install`
  # does NOT put node on PATH, and CI has no shell integration (GitHub Actions runs
  # steps with `bash --noprofile --norc`), so a bare `which node` would find
  # nothing. `fnm exec --using` activates the version for one subprocess; `readlink
  # -f` canonicalizes fnm's multishell symlink to the real ~/.fnm/node-versions
  # path. This is robust to fnm changing its data dir or layout.
  local node_bin
  node_bin="$(fnm exec --using "$version" -- bash -c 'readlink -f "$(command -v node)"' 2>/dev/null || true)"
  if [[ -z "$node_bin" || ! -x "$node_bin" ]]; then
    echo "use_fnm: failed to install/resolve node $version" >&2
    fnm ls >&2 2>/dev/null || true
    # exit, not return: direnv silently ignores a directive that `return`s a
    # non-zero code (the job would go green with nothing installed), whereas a
    # non-zero `exit` from the .envrc propagates and fails the step.
    exit 1
  fi

  # Require an exact version. A partial like `22` resolves to the latest matching
  # release (e.g. v22.99.0), which would silently drift; reject it so the .envrc
  # pins one runtime. Ask the resolved binary its own version rather than parsing
  # the path, keeping the check independent of fnm's on-disk layout.
  local node_ver
  node_ver="$("$node_bin" -v 2>/dev/null || true)"
  if [[ "$node_ver" != "v$version" ]]; then
    echo "use_fnm: node '$version' is not an exact release (resolved to ${node_ver:-unknown}); pin a full version like 22.14.0" >&2
    exit 1
  fi

  # Expose the runtime to subsequent workflow steps: the node bin on $GITHUB_PATH.
  echo "$(dirname "$node_bin")" >> "$GITHUB_PATH"
  return 0
}
