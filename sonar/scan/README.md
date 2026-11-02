# sonar/scan

Run a [SonarQube Cloud](https://sonarcloud.io) scan on a JDK this action supplies, with the
scanner's own JRE provisioning disabled.

**The Java version is the point of this action, and it is not an input.** With JRE
provisioning skipped, the scanner runs on the JDK the workflow supplies and enforces its
own minimum against it. SonarSource raised that minimum to 21 on 2026-07-20, and a scanner
CLI bump can raise it again. Fixing it here means the next raise is one edit in this
repository rather than one in every repository that scans — which does not work if a
consumer can choose the version.

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

That is the whole interface. There is no Java version input and no scanner argument
passthrough: either one hands a consumer the decision this action exists to make for them.
A future need becomes a named input of its own, which is not a breaking change
([CONTRIBUTING.md](../../CONTRIBUTING.md#breaking-changes)) — removing one is, which is why
the interface ships narrow in the action's first release.

`sonar-token` is an input rather than an environment variable because **the `secrets`
context is unavailable inside a composite action** — GitHub withholds it deliberately, so
the caller has to pass the secret explicitly. The action rejects an empty value rather
than letting it reach the scanner, where it would surface as a SonarCloud credentials
error instead of a workflow one. `required: true` alone would not do that: GitHub does not
enforce it for a composite action's inputs.

## What the action runs

```yaml
- run: bash "$GITHUB_ACTION_PATH/require-token.sh"
- uses: actions/setup-java@... # temurin, 21
- uses: SonarSource/sonarqube-scan-action@...
  with:
    args: -Dsonar.scanner.skipJreProvisioning=true
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
report paths are all per-project and none of them belong here. That file is also where a
per-project scanner property goes now that there is no `args` input — every `-D` on a
scanner command line has an equivalent there.

**It does not produce coverage.** It only reads the reports your own steps wrote, at the
paths `sonar-project.properties` names.

**It does not support SonarQube Server.** The upstream action does, through
`SONAR_HOST_URL`; nothing here is written or tested for it.

## Migrating from a hand-rolled scan step

Replace the `setup-java` step and the `SonarSource/sonarqube-scan-action` step with this
one action, and move any remaining `-D` properties into `sonar-project.properties`. Drop
the `java-version` the old step set: this action supplies 21 and that is the point of it.

A `with:` key this action does not declare is only a warning, not an error — the runner
reports `Unexpected input(s) 'args', valid inputs are ['sonar-token']` and carries on
([`ActionRunner.cs`](https://github.com/actions/runner/blob/main/src/Runner.Worker/ActionRunner.cs)).
So a leftover `args:` or `java-version:` will not fail the job, and will not do anything
either. Delete it.

The token moves from `env:` to `with:`. The action sets `SONAR_TOKEN` on the scan step
itself, so a job-level `env: SONAR_TOKEN` is not read; passing nothing in `with:` fails the
action at its guard rather than at SonarCloud.

## Tests

**[`sonarcloud.yml`](../../.github/workflows/sonarcloud.yml) is the test that matters.** It
runs this action against this repository on every pull request with a real token, so it is
the only check that proves the scanner accepts the JDK — and the only one that fails when
SonarSource raises the floor again. An offline assertion on `java -version` cannot do
either: it reports green whatever the scanner would have made of that JDK.

[`.github/workflows/sonar-scan-test.yml`](../../.github/workflows/sonar-scan-test.yml)
covers what can be checked without a scan, aggregated into the `sonar-scan-tests-pass`
required check: that the token guard refuses an unset, empty or whitespace-only token with
its own message, and that `action.yml` runs it. It performs **no analysis** —
`SONAR_HOST_URL` points at the discard port on localhost, so nothing leaves the runner and
no token is needed.

That is also why the guard lives in `require-token.sh` and is run directly rather than
through the action: with the host unreachable, the action fails at the scan step whatever
token it was given, so its outcome cannot tell a rejected token from the connection failure
that follows a good one.
