#!/bin/bash
set -euo pipefail

# Installs pixi on a GitHub Actions runner for pixi-upgrade-dependencies-test.yml, and
# puts it on $GITHUB_PATH for later steps.
#
# CI-only: it lives under .github/, which is never published, so no consumer of @v3 ever
# fetches or runs it. The action it tests installs no pixi of its own - it upgrades with
# whatever the job provides - which is exactly why the test workflow has to provide one.
#
# Deliberately NOT `curl https://pixi.sh/install.sh | bash`. Piping a downloaded script
# straight into a shell executes whatever arrives, so a compromised or truncated response
# runs with no check at all - SonarCloud flags it as githubactions:S8482, and the repo
# already does better: install-direnv.sh pins a version and verifies a recorded checksum.
# This is that pattern, with the version and sums below refreshed by hand when the pin is
# bumped. A stale sum fails this script loudly, which is the point.
#
# Pinned because an upgrade is the judgement of one particular resolver: a pixi that
# floated with the runner image would make a surprising dependency bump, or a red test,
# unattributable.
VERSION=0.81.0

# uname -m rather than dpkg --print-architecture: no dpkg dependency, and pixi names its
# release assets by the target triple this maps to. Both sums were verified against the
# .sha256 files pixi publishes alongside each asset AND recomputed from the downloads.
case "$(uname -m)" in
  x86_64)
    TARGET=x86_64-unknown-linux-musl
    SHA256=7aa3ec39aecceff9062fa2ed4d42cbaa0bdc25ddea727d048e061cf188d434f6
    ;;
  aarch64)
    TARGET=aarch64-unknown-linux-musl
    SHA256=9f8d2113fe9dc01788a65f5c2acec34fa56b1193461a5c3e9a775d6d2d621bcb
    ;;
  *)
    echo "install-pixi: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

tarball="$(mktemp "${RUNNER_TEMP:-/tmp}/pixi.XXXXXX.tar.gz")"
trap 'rm -f "$tarball"' EXIT

# --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+, so no plaintext
# redirect can serve the asset. -f makes an HTTP error a failure rather than a file whose
# contents are an error page and whose checksum therefore just happens not to match.
curl -fsSL --proto '=https' --tlsv1.2 \
  "https://github.com/prefix-dev/pixi/releases/download/v${VERSION}/pixi-${TARGET}.tar.gz" \
  -o "$tarball"

# Verify before extracting, not after: the binary must never exist on disk unverified.
# The sum is the one recorded above rather than one fetched beside the asset - a checksum
# served from the same place as the file it describes attests to nothing.
echo "${SHA256}  ${tarball}" | sha256sum --check --quiet

# ~/.pixi/bin, matching where pixi's own installer puts it and where direnv/setup's
# use_pixi directive caches it.
install -d "$HOME/.pixi/bin"
tar -xzf "$tarball" -C "$HOME/.pixi/bin" pixi
chmod 755 "$HOME/.pixi/bin/pixi"

# Confirm what was actually produced. The archive containing one file named `pixi` is a
# fact about today's release, not a promise, so a layout change has to be an error here
# rather than a missing-command failure inside the action under test.
installed="$("$HOME/.pixi/bin/pixi" --version)"
if [[ "$installed" != "pixi ${VERSION}" ]]; then
  echo "install-pixi: expected 'pixi ${VERSION}', got '${installed}'" >&2
  exit 1
fi
echo "install-pixi: installed ${installed}"

echo "$HOME/.pixi/bin" >> "$GITHUB_PATH"
