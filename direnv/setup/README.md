# direnv/setup

Install direnv on a GitHub Actions runner, evaluate a repository's `.envrc`, and export
everything it declares — language runtimes and plain variables alike — to **subsequent**
workflow steps.

The point is that a runtime version is declared **once**. `use sdk java 21.0.2-tem` in a
committed `.envrc` is honoured both by direnv on a workstation and by this action in CI, so
the two cannot drift.

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: TomBorglum/actions/direnv/setup@v3
        with:
          working-directory: .

      # Later steps see the runtime the .envrc declared.
      - run: java -version
      - run: mvn verify
```

See the [repository README](../../README.md#versioning-and-pinning) for what `@v3` means and
when to pin more tightly.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory containing the `.envrc` to activate. |
| `cache` | `'true'` | Cache the toolchain dirs (`~/.sdkman`, `~/.fnm`, `~/.pixi`) and the paths in `cache-paths`. See [Caching](#caching) and [Disabling it](#disabling-it). |
| `cache-paths` | `''` | Newline-separated paths to cache as a second entry — a pixi environment, a cargo home, a build output directory. Ignored when `cache` is `'false'`. |
| `stub-directives` | `''` | Whitespace-separated directive names to define as no-ops. See [below](#stub-directives). |

The action fails if there is no `.envrc` in `working-directory`, and it fails if the
`.envrc` uses a directive it does not define. Both are deliberate: a silent no-op would
leave later steps running against whatever the runner image happened to provide.

## Directives

| Directive | Installs | Exposes |
| --- | --- | --- |
| `use sdk <candidate> <version>` | SDKMAN, then the candidate | the candidate's `bin` on `PATH`, plus SDKMAN's `<CANDIDATE>_HOME` (`JAVA_HOME`, `MAVEN_HOME`, …) |
| `use fnm node <version>` | fnm, then Node | the resolved Node `bin` on `PATH` |
| `use pixi <version> [template]` | pixi at the pinned version, then the workspace's environment | the environment's `bin` and pixi's own `bin` on `PATH` |

`use_sdk` is **generic over its arguments**: it passes `<candidate> <version>` straight to
SDKMAN and derives `<CANDIDATE>_HOME` as `${candidate^^}_HOME`. So `use sdk gradle 8.7`,
`use sdk kotlin 2.0.0` and the like already work with no change here.

`use fnm node <version>` requires an **exact** release. A partial like `22` resolves to the
latest matching version and would drift silently, so it is rejected.

`use pixi <version>` has no equivalent format rule, and the difference is deliberate rather
than an oversight: `fnm install 22` *succeeds* and quietly resolves to some other release,
which is what fnm's check exists to catch, whereas pixi's installer resolves the version to
a release tag — so a partial like `0.81` is not a tag, fails the download, and is reported.
The version string is passed through to the installer, which accepts `0.81.0` and `v0.81.0`
alike. What **is** required is that a version be given at all: with none, the installer
would fall back to whatever is latest that day, so an unversioned `use pixi` fails the step.

The `[template]` argument is **accepted and ignored**. On a workstation it scaffolds a
`pixi.toml` from a named template, but CI activates a workspace the repository already
commits, so there is nothing here for it to do — ignoring it is what lets one `.envrc`
serve a workstation and a runner alike. For the same reason `use pixi` does not scaffold a
manifest: a missing `pixi.toml` is a hard error.

A committed `pixi.lock` is **verified, not updated**. The directive installs with
`--locked` when a lockfile is present (and a plain `pixi install` when there is none), so a
lockfile that has drifted from `pixi.toml` fails the step instead of being silently
rewritten — CI would otherwise run against dependencies that are not the committed ones.
A workspace that also declares [`requires-pixi`](https://pixi.prefix.dev/latest/reference/pixi_manifest/)
composes with this for free: if the version the `.envrc` pins does not satisfy it, pixi
itself refuses, so this action needs no code for it.

## Caching

Two entries, both restored before the `.envrc` is evaluated:

| Entry | Paths | Key |
| --- | --- | --- |
| toolchains | `~/.sdkman`, `~/.fnm`, `~/.pixi` | `direnv-setup-tools-<digest>-<os>-<arch>-<YYYY-MM>-w<WW>` |
| `cache-paths` | what the input names | `direnv-setup-paths-<digest>-<os>-<arch>-<YYYY-MM>-w<WW>` |

Each entry has one fallback rung: its own key truncated after the month,
`direnv-setup-tools-<digest>-<os>-<arch>-<YYYY-MM>-`.

Each `<digest>` is the first 12 hex characters of a `sha256`, computed by
[`cache-keys.sh`](cache-keys.sh) — over `working-directory` for the toolchain entry, and over
`working-directory` and the sorted `cache-paths` list for the other. Reordering the list
leaves the latter unchanged.

A key held by two callers whose contents differ belongs to whichever saved first. The others
restore that entry, install what is missing, and are refused the save for the rest of the
window. `working-directory` is in both digests for that reason: one repository's workspaces
can declare different toolchains.

`<arch>` is named separately because `<os>` is `Linux` on x86_64 and aarch64 alike.

Dates are UTC. `w<WW>` rotates the entry weekly, so a long-lived lineage is refreshed rather
than written once. `<YYYY-MM>` ends it: nothing saved in a previous month is reachable through
the fallback, which is what bounds the size of an entry that is base-restored and re-saved
each week.

No manifest is in either key. A change to `.envrc`, `pixi.lock` or `Cargo.lock` restores the
week's entry as a base and the job updates it, rather than cold-starting. A cold start happens
on the first run of a month, on an edit to the `cache-paths` list, and on a
`working-directory` change.

`cache-paths` is saved only on a push to the repository's default branch, and every other
event restores without saving: only the default branch's entries are readable from another
branch. The cost is that a pull request has no entry of its own, so a dependency change
recompiles on every push to it until merge. The toolchain entry saves on every event.

Each run logs both keys, whether each hit was on the exact key, and the size of every cached
path.

### Disabling it

`cache: 'false'` skips both entries and computes no key.

Its use is verifying a cold install: a warm entry leaves each directive's install-dir guard
skipping its download, so the installer goes unexercised. The input is the only lever for
that, because the restore happens inside the action and before activation, so no step can
clear the toolchain dirs first. The `cache-disabled` job in
[`direnv-setup-test.yml`](../../.github/workflows/direnv-setup-test.yml) is what uses it.

A toolchain dir cached in a bad state is restored by every run in that month's lineage, and a
job that fails mid-install still caches one. Delete the entry from the repository's caches.
Set `cache: 'false'` only while finding out what keeps writing a bad one.

## How the environment reaches later steps

**A directive's job is to leave the environment correct; the action forwards it.** After
evaluating the `.envrc`, the action copies the resulting environment into `$GITHUB_ENV`
wholesale, so no directive writes there itself. Two consequences:

- **Not everything needs a directive.** Anything set through **stock** direnv — `export
  FOO=bar`, `dotenv`, `dotenv_if_exists` — reaches later steps with no `use_*` function
  existing for it.
- **A directive can drive its tool the way the tool documents.** `use_sdk` runs `sdk
  install` then `sdk use`, and `sdk use` is what sets `<CANDIDATE>_HOME` — no hand-derived
  path, no second copy of the value. What a directive must not do is leave the environment
  saying one thing while publishing another.

Values are written with a heredoc under a random delimiter, so a value containing a newline
or an `=` survives intact and a crafted value cannot forge an entry of its own.

Two names are held back from the copy:

- **`DIRENV_*`** — direnv's own bookkeeping (the diff it uses to reverse a load), which
  means nothing to a step that is not running direnv.
- **`PATH`** — which belongs to `$GITHUB_PATH`, appended to by the directives. Writing a
  whole `PATH` through `$GITHUB_ENV` would freeze later steps to this step's copy and undo
  anything a subsequent action adds.

A name direnv *unsets* is also skipped, since `$GITHUB_ENV` cannot express an unset.

## Unknown directives are an error

direnv's own `use` calls `use_<name>` without checking it exists, and treats the resulting
"command not found" as non-fatal. On a runner that is the worst possible outcome: a typo'd
`use fmn node 22.14.0`, or a lib file that failed to install, would leave the step green
with no Node installed and the failure surfacing several steps later, somewhere else.

This action overrides `use` to reject a directive it cannot resolve:

```
direnv/setup: no such directive 'use fmn'. Name it in the action's stub-directives input to ignore it.
```

It is the same reasoning behind the directives' own `exit 1`-rather-than-`return 1`
convention — direnv ignores a non-zero `return` from a directive, so a `return` would let a
job pass with nothing installed.

If you want a directive ignored rather than rejected, name it in `stub-directives`.

## `stub-directives`

Some directives are meaningful on a workstation and meaningless on a runner — one that
configures an editor integration, or writes a local settings file. Naming them in
`stub-directives` defines each as a no-op, so the `.envrc` evaluates instead of being
rejected by the strictness above:

```yaml
      - uses: TomBorglum/actions/direnv/setup@v3
        with:
          stub-directives: sonarqube_mcp claude_env
```

- Arguments are **accepted and ignored**: `use claude_env --merge x` is as stubbed as
  `use claude_env`.
- A stub **exports nothing** and writes nothing. It cannot act on its arguments — if a
  directive needs to put something on `$GITHUB_PATH`, it needs a real implementation.
- A stub **shadows a built-in** of the same name, so `stub-directives: pixi` will skip a
  pixi install rather than perform one.
- Each call logs one line to stderr naming the directive and its arguments, so a stubbed
  run is distinguishable in the log from one that did work.
- Names must be bare identifiers (`[A-Za-z_][A-Za-z0-9_]*`). Anything else fails the step.

## Requirements

Linux runners, `x86_64` or `aarch64`. The action needs `bash`, `curl`, `sudo`,
`sha256sum`, `install`, `jq` and `openssl` on the runner — all present on GitHub-hosted
Ubuntu images, but `jq` and `openssl` in particular may be missing from a slim self-hosted
one.

direnv itself is installed from a **pinned** release and verified against a checksum
recorded in [`install-direnv.sh`](install-direnv.sh), rather than taken from the runner's
apt repositories, so the version does not float with the runner image. It is bumped by
[`update-direnv.yml`](../../.github/workflows/update-direnv.yml), which cuts a patch release
so the new binary reaches consumers with a changelog entry naming it.

## Network egress

Reached only by the directives a given `.envrc` actually uses, always over HTTPS with
`--proto '=https' --tlsv1.2`:

| Host | Reached by |
| --- | --- |
| `github.com/direnv/direnv/releases` | always (the direnv install) |
| `get.sdkman.io` and SDKMAN's own hosts | `use sdk` |
| `fnm.vercel.app` | `use fnm` |
| `pixi.sh` | `use pixi <version>` |
