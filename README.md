# actions

Reusable GitHub Actions, maintained in one place and released together.

Each action lives in its own top-level directory and is referenced by path:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: TomBorglum/actions/setup-direnv@v1
        with:
          working-directory: .
```

## Actions

| Action | Purpose |
| --- | --- |
| [`setup-direnv`](setup-direnv/) | Install direnv and evaluate a repository's `.envrc`, exporting the language runtimes and variables it declares to later workflow steps. |

## Versioning and pinning

Releases are automated from [Conventional Commits](https://www.conventionalcommits.org/)
by [release-please](https://github.com/googleapis/release-please). Each release
produces three tags:

| Pin | Moves? | Use when |
| --- | --- | --- |
| `@v1` | on every 1.x release | **the default choice** — you want fixes and new features without editing your workflow |
| `@v1.2` | on every 1.2.x release | you want patches only |
| `@v1.2.3` | never | you need a reproducible build |
| `@<sha>` | never | you pin everything by SHA as policy |

`v1` and `v1.2` are deliberately mutable — that is how a fix reaches you without
your intervention. Exact versions are immutable and enforced as such by a repository
ruleset, so `@v1.2.3` and `@<sha>` are equally safe pins.

A major bump means `v1` stops moving. You stay on 1.x until you change the pin to
`@v2`, so a breaking change can never arrive unannounced.

See the [changelog](CHANGELOG.md) for what each release contained, and
[releases](https://github.com/TomBorglum/actions/releases) for the generated notes.

## Guardrails

`main` is protected by a repository ruleset: pull requests only, linear history, no
force-pushes or deletions, and required SonarCloud and per-action test checks — with no
bypass actors, including for maintainers. Version tags have their own ruleset making them
immutable.

Each action's tests gate its own merges. They run on every pull request and report through
a single `tests-pass` check per action, so a red test cannot be merged around.

Every third-party action used here, in a workflow or inside a published `action.yml`,
is pinned to a full commit SHA; Dependabot keeps those pins fresh, with a cooldown on
the ones that ship to consumers.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) is the guard rail: commit conventions, which
commit types cut a release, the `deps:` vs `ci:` rule, the tag and pinning policy,
and the checklist for adding a new action.

## Security

Code here runs inside other people's workflows. See [SECURITY.md](SECURITY.md) for
what is in scope and how to report a vulnerability privately.

## License

[MIT](LICENSE)
