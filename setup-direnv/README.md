# setup-direnv

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
      - uses: TomBorglum/actions/setup-direnv@v1
        with:
          working-directory: .

      # Later steps see the runtime the .envrc declared.
      - run: java -version
      - run: mvn verify
```

See the [repository README](../README.md#versioning-and-pinning) for what `@v1` means and
when to pin more tightly.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory containing the `.envrc` to activate. |
| `cache` | `'true'` | Cache the toolchain dirs (`~/.sdkman`, `~/.fnm`, `~/.pixi`) across runs, keyed on the `.envrc`. Set to `'false'` to disable. |
| `stub-directives` | `''` | Whitespace-separated directive names to define as no-ops. See [below](#stub-directives). |

The action fails if there is no `.envrc` in `working-directory`, and it fails if the
`.envrc` uses a directive it does not define. Both are deliberate: a silent no-op would
leave later steps running against whatever the runner image happened to provide.

## Directives

| Directive | Installs | Exposes |
| --- | --- | --- |
| `use sdk <candidate> <version>` | SDKMAN, then the candidate | the candidate's `bin` on `PATH`, plus SDKMAN's `<CANDIDATE>_HOME` (`JAVA_HOME`, `MAVEN_HOME`, …) |
| `use fnm node <version>` | fnm, then Node | the resolved Node `bin` on `PATH` |
| `use pixi` | pixi, then the workspace's environment | the environment's `bin` and pixi's own `bin` on `PATH` |

`use_sdk` is **generic over its arguments**: it passes `<candidate> <version>` straight to
SDKMAN and derives `<CANDIDATE>_HOME` as `${candidate^^}_HOME`. So `use sdk gradle 8.7`,
`use sdk kotlin 2.0.0` and the like already work with no change here.

`use fnm node <version>` requires an **exact** release. A partial like `22` resolves to the
latest matching version and would drift silently, so it is rejected.

`use pixi` does not scaffold a manifest. CI activates a workspace the repository already
commits, so a missing `pixi.toml` is a hard error.

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
setup-direnv: no such directive 'use fmn'. Name it in the action's stub-directives input to ignore it.
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
      - uses: TomBorglum/actions/setup-direnv@v1
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
[`update-direnv.yml`](../.github/workflows/update-direnv.yml), which cuts a patch release
so the new binary reaches consumers with a changelog entry naming it.

## Network egress

Reached only by the directives a given `.envrc` actually uses, always over HTTPS with
`--proto '=https' --tlsv1.2`:

| Host | Reached by |
| --- | --- |
| `github.com/direnv/direnv/releases` | always (the direnv install) |
| `get.sdkman.io` and SDKMAN's own hosts | `use sdk` |
| `fnm.vercel.app` | `use fnm` |
| `pixi.sh` | `use pixi` |

## Tests

[`.github/workflows/setup-direnv-test.yml`](../.github/workflows/setup-direnv-test.yml)
runs one job per fixture in [`test/`](test/) on every pull request, aggregated into the
`tests-pass` required check. Each job asserts in a **later** step than the action's own, so
a passing run proves the cross-step export rather than a transient direnv shell.

Adding a directive means adding a fixture `.envrc` that exercises it end to end — install
plus cross-step propagation — and adding its job to `tests-pass`'s `needs:`.
