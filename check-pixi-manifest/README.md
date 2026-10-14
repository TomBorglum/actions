# check-pixi-manifest

Fail unless a `pixi.toml` is present in the given directory.

```yaml
- uses: TomBorglum/actions/check-pixi-manifest@v1
```

## Inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `working-directory` | `.` | Directory that must contain the `pixi.toml`. |

## What counts as present

Only a `pixi.toml`. A `pyproject.toml` carrying a `[tool.pixi.*]` table does **not**
count, and is refused with a message saying so rather than with a bare "not found".

That distinction is the point of the action. pixi itself accepts a manifest embedded in
`pyproject.toml` under `[tool.pixi.workspace]`, and resolves it automatically when no
`pixi.toml` exists — so a repository in that shape is a working pixi workspace that this
check still refuses. A caller looking at a workspace pixi is perfectly happy with needs to
be told *why* it was rejected.

## Why this is an action

It exists for [`TomBorglum/workflows`](https://github.com/TomBorglum/workflows)'
`pixi-upgrade.yml`, which must hard-fail when the repository calling it has no root
`pixi.toml`. Two GitHub constraints make a three-line inline check unworkable there:

- A reusable workflow's `actions/checkout` checks out the **calling** repository, so a
  script shipped next to that workflow is never on disk when it runs.
- A job that calls a reusable workflow cannot use `continue-on-error`, so the failure
  cannot be caught — and a test that proves the refusal works would have to leave a
  permanently failing job in the pull request.

An action is fetched by the runner independently of any checkout, and its failure is
assertable with a step-level `continue-on-error`. That is how
[`check-pixi-manifest-test.yml`](../.github/workflows/check-pixi-manifest-test.yml)
executes the real refusal with every job green.
