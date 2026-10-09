# Contributing

Releases are automated with [release-please](https://github.com/googleapis/release-please).
It reads the commit history on `main`, decides the next version, and maintains a
"chore(main): release X.Y.Z" pull request that updates [`CHANGELOG.md`](CHANGELOG.md)
and the version. Merging that PR tags the version and publishes the GitHub Release.

For that to work, commits must follow [Conventional Commits](https://www.conventionalcommits.org/).
This document is the guard rail for how to name commits and branches so the
automation does the right thing.

## Commit message format

```
<type>(<optional scope>): <description>

<optional body — what changed and why>

<optional footer — BREAKING CHANGE:, Refs #123, Co-Authored-By:>
```

The first line (the *subject*) is what release-please parses. Keep it lowercase,
in the imperative mood ("add", not "added" or "adds"), with no trailing period,
and ideally under ~72 characters.

Where a change belongs to one action, use its directory as the scope:
`fix(setup-direnv): quote the working-directory input`.

## Types

These are the types configured in [`release-please-config.json`](release-please-config.json).
A type does two independent things: it selects the changelog section the change
appears under, and — because release-please treats any commit in a **visible**
(non-hidden) section as a *releasable unit* — it decides whether the change can
cut a release on its own. We keep only `feat`, `fix`, and `deps` visible, so only
those (plus any breaking change) cut releases; every other type is hidden and
merely rides along.

| Type | Example | Changelog section | Cuts a release? |
| --- | --- | --- | --- |
| `feat` | `feat: add a setup-pixi action` | Features | yes — **minor** (1.1.0) |
| `fix` | `fix(setup-direnv): export PATH to later steps` | Bug Fixes | yes — **patch** (1.0.1) |
| `deps` | `deps: bump actions/checkout to v7.0.1` | Dependencies | yes — **patch** (1.0.1) |
| `perf` | `perf: skip a redundant direnv reload` | *(hidden)* | no — rides along¹ |
| `revert` | `revert: undo the fnm pin` | *(hidden)* | no — rides along¹ |
| `docs` | `docs: document the pinning policy` | *(hidden)* | no — rides along¹ |
| `chore` | `chore: tidy script comments` | *(hidden)* | no — rides along¹ |
| `ci` | `ci: pin actions by sha` | *(hidden)* | no — rides along¹ |
| `build` `refactor` `style` `test` | `refactor: extract a helper` | *(hidden)* | no — rides along¹ |

¹ **Rides along**: does not trigger a release on its own and — being hidden —
does not appear in the notes either. A PR containing only ride-along types will
not open a release PR until a `feat`/`fix`/`deps` lands.

> **Visibility = releasability.** If you un-hide a section in
> `release-please-config.json`, commits of that type will start cutting releases.
> That is deliberate for `deps`; be intentional before un-hiding anything else
> (a `docs:`-only change cutting a release is usually noise).

### `deps:` vs `ci:`

**If a consumer receives the change, it's `deps:` (or `feat`/`fix`); if it only
touches this repo's own CI, it's `ci:`/`chore:`.**

The dividing line is which runner the code ends up on:

| Where the bump lands | Runs on | Type |
| --- | --- | --- |
| A published `action.yml` | *consumers'* runners | `deps:` — releasable |
| `.github/workflows/**` | this repo's runners | `ci:` — hidden |

An action pinned inside a published `action.yml` is part of what this repo ships.
Bumping it changes what other people's workflows execute, so it has to cut a release
and appear in the notes — otherwise consumers on `@v1` silently receive new code with
no changelog entry explaining it. [`.github/dependabot.yml`](.github/dependabot.yml)
encodes this split as two update entries with different prefixes.

> **Never put an `action.yml` at the repository root.** Dependabot's `github-actions`
> fetcher special-cases the `/` directory: it scans `.github/workflows/` *and* a
> root-level `action.yml`. Our `/` entry is the `ci:` one, so an action at the root
> would have its bumps labelled `ci:` and ship to consumers unreleased. Every action
> gets its own subdirectory, and its own `deps:` entry.

## Breaking changes

A breaking change forces a **major** bump (2.0.0). Mark it either with a `!`
after the type, or with a `BREAKING CHANGE:` footer:

```
feat!: rename the working-directory input to path
```

```
feat: rename the working-directory input to path

BREAKING CHANGE: `working-directory` is now `path`; update callers.
```

Be deliberate here: a major bump means the `v1` tag stops moving, and every consumer
pinned to `@v1` stays on the old code until they edit their workflow to `@v2`. That
is the point of the tag — but it also means a careless `!` strands your users.

Renaming or removing an input, renaming an action's directory, and changing what an
action writes to `$GITHUB_PATH` or `$GITHUB_ENV` are all breaking. Adding an optional
input with a default is not.

## Squash merges

Pull requests are **squash-merged**, so the whole branch collapses into a single
commit on `main` whose subject is taken from the **PR title** and whose body is
the branch's own commit messages. Therefore:

> **The PR title must be a valid Conventional Commit.**

A PR titled `Update direnv script` (no type) is invisible to release-please and
will neither appear in the changelog nor bump the version. Title it
`fix: ...` / `feat: ...` instead. That holds however many commits the branch
carries, because `squash_merge_commit_title` is `PR_TITLE`. GitHub's default,
`COMMIT_OR_PR_TITLE`, takes the subject from the *commit* when a branch has
exactly one — so a single sloppy commit subject would quietly cut no release.

The one thing release-please still reads from a squash commit's body is a
`BREAKING CHANGE:` footer. That body is the branch's own commit messages
(`squash_merge_commit_message` is `COMMIT_MESSAGES`), **not** the PR
description, so put the footer in a commit on the branch. A footer written only
in the PR description never reaches `main` and is never parsed.

A squash-merged PR yields exactly one changelog entry: its title. So prefer
**focused PRs** — one logical change, one type. A branch that would produce
several separate entries is two PRs: the `main-protection` ruleset requires
linear history and allows only squash and rebase, so the merge commit that would
have preserved each Conventional Commit individually cannot land.

## Version selection

release-please aggregates **every commit merged since the last release** (across
all PRs, not just one branch) and applies the highest-impact bump:

```
any  feat! / BREAKING CHANGE       →  MAJOR
else any  feat                     →  MINOR
else any  fix / deps               →  PATCH
else only ride-along types         →  no release
   (perf, revert, docs, chore, ci, …)
```

## Tags and the pinning policy

Every release produces three tags, and they are not equivalent:

| Tag | Moves? | For |
| --- | --- | --- |
| `v1.0.0` | never | consumers who want byte-for-byte reproducibility |
| `v1.0` | on every 1.0.x release | patches only |
| `v1` | on every 1.x release | the common case — features and fixes, no breaking changes |

`vX` and `vX.Y` are force-moved by
[`release-please.yml`](.github/workflows/release-please.yml) after each release. That
mutability is the published contract: `@v1` is what most consumers should write, and
it is how a security fix reaches them without their intervention.

Exact `vX.Y.Z` tags are immutable, and the `version-tags` repository ruleset enforces
it — `deletion` and `non_fast_forward` over a `v*.*.*` pattern, which needs two
literal dots and so matches `v1.0.0` but neither `v1` nor `v1.0`. Nobody can repoint
a released version, including maintainers; there are no bypass actors.

**This repo pins its own dependencies the other way.** Every third-party action in a
workflow or an `action.yml` here is pinned to a full 40-character commit SHA with the
version in a trailing comment:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

That is not inconsistent with publishing moving tags — it is the same judgement from
both sides. Inbound dependencies we do not control get pinned immutably; outbound
tags we do control are offered as a convenience, with immutable alternatives
alongside. Dependabot updates a SHA pin and its comment together, so keep the comment
accurate.

## Adding a new action

Each action lives in its own top-level directory and is consumed as
`TomBorglum/actions/<name>@v1`. A PR introducing one should land all of:

- `<name>/action.yml`, with every third-party `uses:` pinned by SHA.
- A test workflow, `.github/workflows/<name>-test.yml`, that exercises the action
  end to end on `pull_request`. Test what would actually break a consumer — in
  particular that anything the action exports via `$GITHUB_PATH` or `$GITHUB_ENV` is
  visible to *subsequent* steps, not just inside the action.
- A `tests-pass` job in that workflow, with `if: always()` and `needs:` listing every
  other job, failing if any of them failed or was cancelled. **Add it to the
  `main-protection` ruleset's required status checks**, which is a repository-settings
  change and not part of the PR. Every job added to the workflow later must be added to
  `needs:` too — a job left out runs but gates nothing.
- A `deps:`-prefixed Dependabot entry for the new directory in
  [`.github/dependabot.yml`](.github/dependabot.yml). Forgetting this means the action's
  pins silently stop being updated.
- A row in the action index in [`README.md`](README.md), and a `<name>/README.md`
  documenting its inputs.

**Do not add a `paths:` filter to a test workflow.** A path-filtered workflow cannot gate
a merge: when the filter excludes a pull request its checks stay *Pending* rather than
passing, so a required check over a filtered workflow blocks that PR forever. Let the
workflow run on every pull request, or gate the heavy jobs with `if:` on a cheap
changed-files job — a *skipped* job reports Success and does not block.

Title the PR `feat: add <name> action` — a new action is a feature, and a minor bump
is what moves the `v1` tag to include it.

## Branch names

release-please ignores branch names entirely — it only reads commit subjects and
PR titles on `main` (its own release branch, `release-please--branches--main`, is
the exception, and it manages that one itself). Branch names are therefore a
human convention only. Mirror the commit type for readability:

```
<type>/<short-kebab-description>

feat/setup-pixi
fix/direnv-path-export
deps/bump-checkout
docs/pinning-policy
```
