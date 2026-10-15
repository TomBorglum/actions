# update-pixi-dependencies

Upgrade a [pixi](https://pixi.sh) workspace's dependencies in place — rewriting
`pixi.toml` and `pixi.lock` — and report what moved, so a workflow can turn it into a
pull request.

**Dependabot has no `pixi` ecosystem.** A version declared in a `pixi.toml` is therefore
never bumped for you, however many other ecosystems your repository has covered. This
action is the half of the replacement that performs the upgrade; the workflow that opens
the pull request is **not** here — see [below](#what-this-action-does-not-do).

## Usage

```yaml
jobs:
  upgrade:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      # This action does not install pixi. Provide one first - any step that puts pixi
      # on PATH will do.
      - uses: TomBorglum/actions/setup-direnv@v2   # an .envrc with `use pixi <version>`

      - uses: TomBorglum/actions/update-pixi-dependencies@v2
        id: upgrade

      - if: steps.upgrade.outputs.changed == 'true'
        run: echo "${{ steps.upgrade.outputs.summary }}" >> "$GITHUB_STEP_SUMMARY"
```

See the [repository README](../README.md#versioning-and-pinning) for what `@v2` means and
when to pin more tightly.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory containing the `pixi.toml` to upgrade. |
| `pinning-strategy` | `exact-version` | How pixi rewrites each constraint it upgrades. One of `no-pin`, `semver`, `major`, `minor`, `latest-up`, `exact-version`. |

`exact-version` is the default because it is what makes the resulting pull request
reviewable: every upgrade is a visible `==1.2.3` → `==1.3.0`, and the diff states exactly
what moved. The other strategies are pixi's own and are passed straight through —
`no-pin` writes `*`, `major` writes `>=1.2.3, <2`, and so on.

The value is checked against that list before it reaches a command line, and anything
else fails the step. It is an allowlist rather than careful quoting for the same reason
`setup-direnv` validates `stub-directives`: an input that reaches a command is the
script-injection vector [`SECURITY.md`](../SECURITY.md) names.

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
as pixi's interface rather than this action's.

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
  later is not a breaking change (see [CONTRIBUTING.md](../CONTRIBUTING.md#breaking-changes)).

`pixi upgrade`, not `pixi update`: `update` re-solves the lockfile *within* the existing
constraints, which is not a dependency bump. `upgrade` rewrites the constraints in the
manifest, which is what Dependabot would have done.

## Three ways it fails

All three are hard errors, because this action exists to produce a bump and a green run
that silently bumped nothing is worse than a red one.

| Condition | Why it is not tolerated |
| --- | --- |
| `pixi` is not on `PATH` | The action installs none (see below). The message names the two ways to provide one. |
| No `pixi.toml` in `working-directory` | pixi's manifest discovery walks **parent** directories, so without this check a mis-pointed `working-directory` would quietly upgrade whichever workspace sits above it in the checkout — and report success. |
| `pinning-strategy` is not one of the six | See [Inputs](#inputs). |

## Requirements

**pixi must already be on `PATH`.** This action installs none, so the version that
performs your upgrade is the one your job pins — with
[`setup-direnv`](../setup-direnv/) and an `.envrc` that declares `use pixi <version>`, or
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

**It does not open a pull request.** That is a reusable workflow, deliberately separate
and not yet written; [`update-direnv.yml`](../.github/workflows/update-direnv.yml) is the
shape it will take — a GitHub App token (events created with `GITHUB_TOKEN` do not trigger
the required checks on the resulting PR), a bot commit identity, and
`peter-evans/create-pull-request` gated on this action's `changed` output.

It also does not commit, push, or run `pixi install`. It leaves two modified files in the
checkout and three outputs describing them.

## Tests

[`.github/workflows/update-pixi-dependencies-test.yml`](../.github/workflows/update-pixi-dependencies-test.yml)
runs on every pull request, aggregated into the `tests-pass` required check. It upgrades
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
