#!/bin/bash
set -euo pipefail

# Installs direnv on a GitHub Actions runner for the direnv/setup composite action.
# Exits 0, not non-zero, when direnv is already present: this runs as a step inside a
# consumer's job, where any non-zero exit fails that step.
if command -v direnv >/dev/null 2>&1; then
  echo "direnv already installed: $(direnv version)"
  exit 0
fi

# Pinned version + known-good checksums. direnv publishes no vendor checksums file, so
# these are recorded by us: .github/workflows/update-direnv.yml computes them from the
# release assets when it bumps VERSION, and opens a `deps:` PR because this binary runs
# on consumers' runners.
#
# Pinning is what makes a consumer's run reproducible - the version no longer floats
# with the runner image, which differs between ubuntu-latest and its arm variant - and
# verifying an embedded hash means a tampered release artifact is rejected even when
# the download itself succeeds.
VERSION=2.38.2

# uname -m rather than dpkg --print-architecture: no dpkg dependency, and direnv names
# its assets by the arch this maps to.
case "$(uname -m)" in
  x86_64)  ARCH=amd64; SHA256=148820a187930d36ca6a204504e5cdb30d8396cd1a97e64c3b3f10d793c11247 ;;
  aarch64) ARCH=arm64; SHA256=ec2a32dbe2f19dd085bd9315a1b4ea88b55ec288aa7eabe8723490baf466cb23 ;;
  *) echo "Unsupported architecture for direnv: $(uname -m)" >&2; exit 1 ;;
esac

# --proto '=https' --tlsv1.2 pins the transfer to HTTPS/TLS 1.2+, so no redirect can
# downgrade it to a clear-text protocol.
curl -fsSL --proto '=https' --tlsv1.2 \
  "https://github.com/direnv/direnv/releases/download/v${VERSION}/direnv.linux-${ARCH}" \
  -o /tmp/direnv

echo "${SHA256}  /tmp/direnv" | sha256sum -c -

# /usr/local/bin is already on the runner's PATH, so nothing needs $GITHUB_PATH and
# direnv is callable in this same step.
sudo install -m 0755 /tmp/direnv /usr/local/bin/direnv
rm -f /tmp/direnv
direnv version
