# direnv/update-pixi

Bump the [pixi](https://pixi.sh) version pinned by direnv's `use pixi` directive in an
`.envrc` to the latest pixi release, and report what moved, so a workflow can turn it into
a pull request.

**Dependabot has no direnv ecosystem.** A tool version pinned in an `.envrc` is therefore
never bumped for you — and unlike a version in a manifest, nothing else notices it has
gone stale either. This action is the half that detects the release and rewrites the line;
the workflow that opens the pull request is **not** here — see
[below](#what-this-action-does-not-do).

It is the pixi member of a family: one action per `.envrc` directive, each owning its own
line format and its own upstream. `use fnm` and `use sdk` are not covered yet.

> **Not to be confused with [`update-pixi-dependencies`](../../update-pixi-dependencies/),**
> which is the other half of the same chore from the other end. This action updates **pixi
> itself**, in the `.envrc`. That one updates **the dependencies inside a pixi workspace**,
> in `pixi.toml` and `pixi.lock`, using whatever pixi the job already provides. They touch
> no file in common and can run independently.

## Usage

```yaml
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      # No pixi needed - this action detects a release, it does not install one.
      - uses: TomBorglum/actions/direnv/update-pixi@v2
        id: pixi

      - if: steps.pixi.outputs.changed == 'true'
        run: echo "${{ steps.pixi.outputs.summary }}" >> "$GITHUB_STEP_SUMMARY"
```

See the [repository README](../../README.md#versioning-and-pinning) for what `@v2` means and
when to pin more tightly.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory containing the `.envrc` to update. |

The `.envrc` in **that** directory and no other. There is no parent-directory walk, unlike
pixi's own manifest discovery — a `working-directory` holding no `.envrc` is an error, not
an invitation to look upwards and update somebody else's pin.

## Outputs

| Output | Description |
| --- | --- |
| `changed` | `'true'` when the `.envrc` was rewritten, `'false'` when it already pinned the latest release. Gate a pull-request step on this. |
| `current-version` | The version the `.envrc` pinned before the run. |
| `latest-version` | The latest pixi release. Reported whether or not anything changed. |
| `summary` | Markdown table of what moved (dependency, from, to). Empty when nothing changed. Suitable for a pull request body. |

`summary` is a single-row table in the same shape
[`update-pixi-dependencies`](../../update-pixi-dependencies/) uses, so the workflow that
drives several directive actions can concatenate their summaries into one body without
reformatting any of them:

```markdown
| Dependency | From | To |
| --- | --- | --- |
| `pixi` | `0.81.0` | `0.82.0` |
```

Both versions are reported even when `changed` is `'false'`, so a caller can log "pixi is
current at X" without a second lookup.

## What the action runs

```
curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/prefix-dev/pixi/releases/latest
```

One HTTPS `HEAD` that downloads no payload, and whose answer is where GitHub redirected to
— `https://github.com/prefix-dev/pixi/releases/tag/v0.82.0`, from which the version is
taken.

**That URL is not an arbitrary choice of source.** It is the one pixi's own installer reads:
`install.sh` does `VERSION="${PIXI_VERSION:-latest}"` and then builds its download from
`${REPOURL}/releases/latest/download/…`. So the version detected here is one that
`use pixi` can install, by construction, rather than a second opinion that has to be
reconciled with the installer's. GitHub documents the URL as a permalink and documents its
"latest" as the most recent **non-prerelease, non-draft** release, so a prerelease can
never reach a pin.

Two alternatives were considered and rejected. The REST API
(`/repos/prefix-dev/pixi/releases/latest`) returns the same fact in JSON, but `gh` needs a
token and a composite action has no implicit `github.token` — it would mean an input every
caller must remember to pass, and an unauthenticated fallback shares a 60-request hourly
limit with every other job on the runner's IP. pixi also publishes
[`versions.json`](https://pixi.prefix.dev/versions.json), but that is the documentation
site's version switcher: it tracks docs deployments rather than releases, carries a `dev`
entry, and lives on a different host that `pixi.sh` only redirects to.

The rewrite replaces **one field**. The line's indentation, its optional template argument,
any trailing comment, and even a `\r` left by a Windows editor are put back verbatim:

```diff
-  use pixi 0.81.0 python  # pinned for the team
+  use pixi 0.82.0 python  # pinned for the team
```

It reads only direnv's documented dispatch form, `use pixi <version> [template]` — the
stdlib defines `use <program_name> [<version>]` as translating to `use_<program_name>`. A
hand-written `use_pixi 0.81.0` function call is not matched, and neither is a commented-out
line.

## How it fails

Every check is a hard error, because this action exists to produce a bump and a green run
that silently bumped nothing is worse than a red one.

| Condition | Why it is not tolerated |
| --- | --- |
| No `.envrc` in `working-directory` | Almost always a mis-pointed `working-directory`. Nothing walks up to a parent, so there is no other way to find out. |
| No `use pixi` directive in it | The workflow that drives this scans for the directive before delegating, so arriving here without one means the caller was wrong. Called directly, this is the only thing that distinguishes a typo from "already current". |
| More than one `use pixi` directive | Which line is the pin is genuinely ambiguous, and direnv's last-one-wins would make a guess silently wrong. |
| `use pixi` with no version | `use_pixi` requires one, so the `.envrc` does not load today. There is nothing to update, and inventing a pin would paper over a broken file. |
| A pin that is not a fully qualified `X.Y.Z` | Same reason: `use_pixi` rejects a partial pin outright, so the file is already broken. Fix the pin rather than bumping it. |
| The redirect lands somewhere unexpected | The permalink is documented; the shape of its target is observed. Asserting it turns an upstream change into a loud failure instead of a corrupt pin. |

A refusal leaves the `.envrc` byte-for-byte untouched — the rewrite is built in a scratch
directory and only copied over the original once it is complete.

## Requirements

Nothing to install and no token to pass. Beyond `bash`: `curl`, `mktemp`, `truncate` and
`openssl` — all present on GitHub-hosted Ubuntu images, though `openssl` in particular may
be missing from a slim self-hosted one.

## Network egress

One HTTPS `HEAD` request to `github.com`, unauthenticated, downloading no response body.
Nothing else — no package channel, no PyPI index, no API.

## What this action does not do

**It does not open a pull request.** That will be a reusable workflow in
[`TomBorglum/workflows`](https://github.com/TomBorglum/workflows), deliberately separate
and not yet written: it will scan the `.envrc`, delegate to whichever directive actions
apply, and open one pull request for the result — so a caller references the workflow and
never names a directive.
[`update-pixi-dependencies.yml`](https://github.com/TomBorglum/workflows/blob/main/.github/workflows/update-pixi-dependencies.yml)
is the established shape for that half: a GitHub App token (events created with
`GITHUB_TOKEN` do not trigger the required checks on the resulting PR), `sign-commits`,
an explicit `add-paths`, and a `dry-run` input so the workflow's own test needs no secrets.

**It does not install pixi, or run it.** It never downloads a binary, so the pin it writes
is not verified as solvable against your workspace — if a newer pixi wants a different
`pixi.lock`, that surfaces as a red required check on the pull request, where
[`setup-direnv`](../../setup-direnv/)'s `use_pixi` runs `pixi install --locked`.

**It does not compare version ordering.** The pin is rewritten whenever it differs from
what `releases/latest` reports, which is what
[`update-direnv.yml`](../../.github/workflows/update-direnv.yml) does for direnv. Worth
knowing why that is a choice: GitHub orders "latest" by `created_at` — the date of the
*commit* the tag points at — so a patch released today from an older line could in
principle outrank a higher version and move a pin backwards. pixi has never done it (every
release to date is monotonic in both version and commit date, each patch following its own
minor), and a downgrade would still arrive as a reviewable pull request rather than a
silent commit. A `sort -V` guard can be added later without a breaking change.

It also does not commit or push. It leaves one modified file in the checkout and four
outputs describing it.

## Tests

[`.github/workflows/direnv-update-pixi-test.yml`](../../.github/workflows/direnv-update-pixi-test.yml) runs
on every pull request, aggregated into the `direnv-update-pixi-tests-pass` required check. It
updates [`test/fixture-outdated`](test/fixture-outdated/) — an `.envrc` pinned
deliberately far behind — and asserts the whole rewritten line (so the template argument
is proven to survive), all four outputs, and that the `.envrc` is the only file touched.
It then asserts that a second run reports no change, that the version written really is the
latest release by comparing it with the REST API's answer, and that each of the refusals
above fails the step while leaving the checkout clean.

**Do not refresh the fixture's pin.** A fixture pinned to the latest release would make the
whole suite pass by having nothing to update.
