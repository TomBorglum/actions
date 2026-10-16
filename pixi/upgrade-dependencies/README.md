# pixi/upgrade-dependencies

Upgrade a [pixi](https://pixi.sh) workspace's dependencies in place — rewriting
`pixi.toml` and `pixi.lock` — and report what moved, so a workflow can turn it into a
pull request.

**Dependabot has no `pixi` ecosystem.** A version declared in a `pixi.toml` is therefore
never bumped for you, however many other ecosystems your repository has covered. This
action is the half of the replacement that performs the upgrade; the workflow that opens
the pull request is **not** here — see [below](#what-this-action-does-not-do).

> **Not to be confused with [`direnv/upgrade-pixi`](../../direnv/upgrade-pixi/),** which is the same chore from
> the other end. This action upgrades **the dependencies inside a workspace**, using whatever
> pixi the job provides. That one bumps **pixi itself**, in the `use pixi <version>` line of an
> `.envrc`. They touch no file in common and can run independently.

## Usage

```yaml
jobs:
  upgrade:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      # This action does not install pixi. Provide one first - any step that puts pixi
      # on PATH will do.
      - uses: TomBorglum/actions/direnv/setup@v3   # an .envrc with `use pixi <version>`

      - uses: TomBorglum/actions/pixi/upgrade-dependencies@v3
        id: upgrade

      - if: steps.upgrade.outputs.changed == 'true'
        run: echo "${{ steps.upgrade.outputs.summary }}" >> "$GITHUB_STEP_SUMMARY"
```

See the [repository README](../../README.md#versioning-and-pinning) for what `@v3` means and
when to pin more tightly.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory containing the `pixi.toml` to upgrade. |
| `pinning-strategy` | `exact-version` | How pixi rewrites each constraint it upgrades. Passed through to `pixi upgrade --pinning-strategy`, which owns the valid values. |

`exact-version` is the default because it is what makes the resulting pull request
reviewable: every upgrade is a visible `==1.2.3` → `==1.3.0`, and the diff states exactly
what moved. Every other strategy is pixi's own and is passed straight through — `no-pin`
writes `*`, `major` writes `>=1.2.3, <2`, and so on; pixi's
[configuration reference](https://pixi.prefix.dev/latest/reference/pixi_configuration/)
is the list.

**The value is not validated here, on purpose.** It reaches pixi as one quoted argument —
never `eval`'d, never handed to a shell — so it cannot inject a command, and being a
single argument it cannot smuggle a second flag either: the worst a crafted value achieves
is an argument pixi rejects, which fails the step. pixi's own error then names the values
it accepts, which beats anything this action could say, and an allowlist here would be a
copy of pixi's list to go stale — rejecting a valid strategy the day pixi adds one. (The
`stub-directives` check in [`direnv/setup`](../../direnv/setup/) is not the same case: that
value reaches a generated function definition, which is code.)

## Outputs

| Output | Description |
| --- | --- |
| `changed` | `'true'` when `pixi.toml` or `pixi.lock` differs after the upgrade, `'false'` otherwise. Gate a pull-request step on this. |
| `summary` | Markdown table of what moved (package, from, to). Empty when nothing changed. Suitable for a pull request body. |
| `packages-json` | The stdout of `pixi upgrade --json`, **verbatim and unparsed**. |

`changed` is decided by hashing `pixi.toml` and `pixi.lock` before and after the upgrade.
Not `git status`, which assumes a git checkout and would report a change some earlier step
had made; and not pixi's JSON, whose shape is documented nowhere and would make the gate
depend on a schema that can shift between pixi releases. A workspace that commits no
`pixi.lock` gets one created, and that counts as a change.

`summary` is derived from the `pixi.toml` diff for the same reason — it depends on no
output format. Two cases do not produce a table: when only `pixi.lock` moved it says so,
and when the manifest changed in a shape it could not pair up (a `no-pin` run writes `*`,
with no version to tabulate) it falls back to the raw diff in a fenced block. It is never
empty while `changed` is `true`.

`packages-json` is pixi's own output, carried through untouched. Nothing in this action
parses it, so nothing here breaks if its shape changes — but for the same reason, treat it
as pixi's interface rather than this action's. As of pixi 0.81.0 it is a **lockfile** diff,
keyed by environment and then platform:

```json
{
  "version": 1,
  "environment": {
    "default": {
      "linux-64": [
        {
          "name": "tzdata",
          "before": null,
          "after": {
            "conda": "https://conda.anaconda.org/conda-forge/noarch/tzdata-2026c-h151e31d_0.conda",
            "sha256": "b928c30d…", "md5": "fcb489df…",
            "license": "LicenseRef-Public-Domain", "size": 118849, "timestamp": 1784250406640
          },
          "type": "conda",
          "explicit": true
        }
      ]
    }
  }
}
```

Note what it is *not*: a list of constraint changes. `before` and `after` are locked
package records, so `before` is `null` for every entry when the workspace committed no
`pixi.lock`, and a package that moved only because a transitive pin shifted appears here
with no corresponding `pixi.toml` change at all. That is why `summary` is derived from the
manifest instead — the two answer different questions.

## What the action runs

```
pixi upgrade --no-install --pinning-strategy <strategy> --json
```

- **`--no-install`** — "Don't modify the environment, only modify the lock file". A pull
  request needs exactly `pixi.toml` and `pixi.lock`, so materialising `.pixi/envs/` would
  cost a full package download per run and leave a directory in the checkout that the
  pull-request step would then have to know to leave out. The action asserts in CI that
  no environment appears.
- **No `--feature`** — a bare `pixi upgrade` covers `[feature.*.dependencies]` as well as
  the default feature's. The test fixture carries a feature-scoped dependency precisely so
  that this keeps being re-checked.
- **No package selection** — everything upgradeable is upgraded. `pixi upgrade` accepts
  `[PACKAGES]...` and `--exclude`; neither is exposed yet, and adding an optional input
  later is not a breaking change (see [CONTRIBUTING.md](../../CONTRIBUTING.md#breaking-changes)).

`pixi upgrade`, not `pixi update`: `update` re-solves the lockfile *within* the existing
constraints, which is not a dependency bump. `upgrade` rewrites the constraints in the
manifest, which is what Dependabot would have done.

## How it fails

Both of its own checks are hard errors, because this action exists to produce a bump and a
green run that silently bumped nothing is worse than a red one.

| Condition | Why it is not tolerated |
| --- | --- |
| `pixi` is not on `PATH` | The action installs none (see below). The message names the two ways to provide one. |
| No `pixi.toml` in `working-directory` | pixi's manifest discovery walks **parent** directories, so without this check a mis-pointed `working-directory` would quietly upgrade whichever workspace sits above it in the checkout — and report success. |

Anything else that goes wrong is pixi's to report: a non-zero exit from `pixi upgrade` —
an unresolvable solve, an unknown `pinning-strategy`, a manifest it rejects — fails the
step with pixi's own message, never `|| true`'d into a green run.

## Requirements

**pixi must already be on `PATH`.** This action installs none, so the version that
performs your upgrade is the one your job pins — with
[`direnv/setup`](../../direnv/setup/) and an `.envrc` that declares `use pixi <version>`, or
with `prefix-dev/setup-pixi` and `run-install: false`. An upgrade is the judgement of one
particular resolver, which is a thing worth pinning rather than inheriting from a runner
image. The version in use is echoed into the log on every run.

Beyond pixi: `bash`, `sha256sum`, `diff`, `awk`, `mktemp` and `openssl` — all present on
GitHub-hosted Ubuntu images, though `openssl` in particular may be missing from a slim
self-hosted one.

## Network egress

The action itself reaches nothing. `pixi upgrade` reaches the channels your `pixi.toml`
declares (`conda-forge` by default) and, for `pypi-dependencies`, your configured PyPI
index.

## What this action does not do

**It does not open a pull request.** That is a reusable workflow, deliberately separate:
[`TomBorglum/workflows/.github/workflows/update-pixi-dependencies.yml`](https://github.com/TomBorglum/workflows/blob/main/.github/workflows/update-pixi-dependencies.yml),
which wraps this action and is what to call to get the pull request as well:

```yaml
jobs:
  update:
    uses: TomBorglum/workflows/.github/workflows/update-pixi-dependencies.yml@v1
    secrets:
      app-client-id: ${{ secrets.AUTOMATION_APP_CLIENT_ID }}
      app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

It provides pixi with [`direnv/setup`](../../direnv/setup/) from the calling repository's own
`.envrc`, authenticates as a GitHub App (events created with `GITHUB_TOKEN` do not trigger
the required checks on the resulting PR), and gates
`peter-evans/create-pull-request` on this action's `changed` output — the shape
[`update-direnv.yml`](../../.github/workflows/update-direnv.yml) established, with two
differences worth knowing if you are reading that one as a model. It sets `sign-commits`,
which signs the commit as the App and makes the bot identity that workflow resolves by
hand unnecessary; and it names `add-paths` explicitly, because `direnv/setup` runs
`pixi install` and the materialised environment would otherwise be committed along with
the two files that matter.

It also does not commit, push, or run `pixi install`. It leaves two modified files in the
checkout and three outputs describing them.

## Tests

[`.github/workflows/pixi-upgrade-dependencies-test.yml`](../../.github/workflows/pixi-upgrade-dependencies-test.yml)
runs on every pull request, aggregated into the `pixi-upgrade-dependencies-tests-pass`
required check. It upgrades
[`test/fixture-outdated`](test/fixture-outdated/) — a workspace pinned to deliberately
stale versions — and asserts the manifest, the lockfile, the absence of an environment and
all three outputs, then asserts that a second run reports no change and that each of the
three refusals above fails the step.

Three of those assertions guard behaviour pixi's reference pages do not document, and were
verified by hand against a real pixi: that `--json` still **writes** the manifest (its
v0.68 reference describes `--json` as previewing upgrades "without modifying files"), that
`--pinning-strategy` is accepted and honoured by `upgrade` (it is documented on `pixi exec`
and `pixi global update`), and that a bare upgrade covers feature-scoped dependencies. Each
has a test whose only job is to notice if a future pixi changes it.

**Do not refresh the fixture's pins.** A fixture pinned to the latest versions would make
the whole suite pass by having nothing to upgrade.
