# sonar/scan

Run a [SonarQube Cloud](https://sonarcloud.io) scan on a JDK this action sets up, with the
scanner's own JRE provisioning disabled.

**The Java version is the point of this action.** With JRE provisioning skipped, the
scanner runs on the JDK the workflow supplies and enforces its own minimum against it.
SonarSource raised that minimum to 21 on 2026-07-20, and a scanner CLI bump can raise it
again. Pinning it here means the next raise is one edit in this repository rather than one
in every repository that scans.

## Usage

```yaml
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - uses: TomBorglum/actions/sonar/scan@v3
        with:
          sonar-token: ${{ secrets.SONAR_TOKEN }}
```

See the [repository README](../../README.md#versioning-and-pinning) for what `@v3` means
and when to pin more tightly.

Because this is an action and not a reusable workflow, it runs as a step and can sit after
the steps that produce coverage, in the same job and the same workspace:

```yaml
      - run: pytest --cov --cov-report=xml   # writes coverage.xml
      - run: npm test                        # writes lcov.info

      - uses: TomBorglum/actions/sonar/scan@v3
        with:
          sonar-token: ${{ secrets.SONAR_TOKEN }}
```

A reusable workflow could not: it runs as its own job on its own runner, so the coverage
those steps wrote would not exist for it to read.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `sonar-token` | *(required)* | SonarCloud token, normally `${{ secrets.SONAR_TOKEN }}`. |
| `java-version` | `21` | Java version the **scanner** runs on. Not a version being analysed. |
| `args` | *(empty)* | Extra scanner arguments, appended after this action's own. |

`sonar-token` is an input rather than an environment variable because **the `secrets`
context is unavailable inside a composite action** — GitHub withholds it deliberately, so
the caller has to pass the secret explicitly. The action rejects an empty value rather
than letting it reach the scanner, where it would surface as a SonarCloud credentials
error instead of a workflow one. `required: true` alone would not do that: GitHub does not
enforce it for a composite action's inputs.

`args` is appended last and later scanner arguments win, so it can override what the
upstream action sets, including `-Dsonar.projectBaseDir`.

## What the action runs

```yaml
- uses: actions/setup-java@... # temurin, ${{ inputs.java-version }}
- uses: SonarSource/sonarqube-scan-action@...
  with:
    args: -Dsonar.scanner.skipJreProvisioning=true ${{ inputs.args }}
```

### Why provisioning is skipped

The scanner can fetch its own JRE. It caches it in `<sonar.userHome>/cache`, which
defaults to `~/.sonar` — a path that does not survive a GitHub-hosted runner, since each
job gets a fresh VM. Nothing here caches it, so auto-provisioning means a JRE download on
every single run.

Supplying the JDK instead costs nothing measurable. Temurin is pre-installed in the hosted
Ubuntu image's tool cache, so `setup-java` only sets `JAVA_HOME`:

| Repository | Measured `Set up JDK` |
| --- | --- |
| `actions` | 1s |
| `expense-tracker` | 0s |

The trade accepted in exchange is this action's whole reason to exist: skipping
provisioning means tracking SonarSource's Java floor by hand, so the floor is tracked here
once.

## Side effects

**`setup-java` sets `JAVA_HOME` for the remainder of the caller's job**, not just for this
action. Call this action *after* any step that needs a different JDK. Every current
consumer scans last, so nothing follows it.

## What this action does not do

**It does not check out your repository.** Do that yourself, with `fetch-depth: 0` — the
default shallow checkout leaves SonarCloud unable to attribute issues to the right
commits.

**It does not configure the analysis.** `sonar-project.properties` stays in your
repository: the project key, the organization, the source and test roots, and the coverage
report paths are all per-project and none of them belong here.

**It does not produce coverage.** It only reads the reports your own steps wrote, at the
paths `sonar-project.properties` names.

**It does not support SonarQube Server.** The upstream action does, through
`SONAR_HOST_URL`; nothing here is written or tested for it.

## Tests

[`.github/workflows/sonar-scan-test.yml`](../../.github/workflows/sonar-scan-test.yml)
runs on every pull request, aggregated into the `sonar-scan-tests-pass` required check. It
asserts that a step *after* the action sees the JDK the action set up — the regression that
broke three repositories at `sonarqube-scan-action` 8.4.0 — that `java-version` selects it,
and that an empty `sonar-token` fails the action.

Those jobs perform **no analysis**: `SONAR_HOST_URL` points at the discard port on
localhost, so nothing leaves the runner and no token is needed. An actual scan is covered
by [`sonarcloud.yml`](../../.github/workflows/sonarcloud.yml), which runs this action
against this repository on every pull request.
