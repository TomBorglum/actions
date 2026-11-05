# aws/assume-role

Assume an IAM role with the calling job's GitHub OIDC token and return the STS credentials
as step outputs.

**Pass `aws-role-arn` as a secret.** The runner echoes a caller's `with:` block, so a plain
input publishes the AWS account id in a log that is world-readable on a public repository.
The action masks the account id itself, but only for the steps that follow it — by then the
caller's own echo has already happened.

The exchange is the whole of what this action does. It fetches no secret and logs in to no
registry: what the credentials are used for is the caller's business, and keeping it that way
is what makes the action reusable by the next workflow with a different need.

## Usage

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write          # required; the action fails early without it
    steps:
      - uses: TomBorglum/actions/aws/assume-role@v3
        id: creds
        with:
          aws-role-arn: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: eu-north-1

      - name: Read a parameter with the assumed credentials
        env:
          AWS_ACCESS_KEY_ID: ${{ steps.creds.outputs.aws-access-key-id }}
          AWS_SECRET_ACCESS_KEY: ${{ steps.creds.outputs.aws-secret-access-key }}
          AWS_SESSION_TOKEN: ${{ steps.creds.outputs.aws-session-token }}
          AWS_REGION: eu-north-1
        run: aws ssm get-parameter --name /example/parameter --with-decryption
```

See the [repository README](../../README.md#versioning-and-pinning) for what `@v3` means
and when to pin more tightly. A workflow that assumes a role with this action is a good
candidate for a SHA pin: the action runs in the same job as the credentials it hands back.

The credentials are step outputs, so a step that needs them has to name them, as above.
Nothing else in the job can see them.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `aws-role-arn` | *(required)* | The role to assume, as a full ARN. Pass it as a secret. A bare role name is refused. |
| `aws-region` | *(required)* | The region the role is assumed in. |
| `audience` | `sts.amazonaws.com` | The OIDC audience requested, matched by the trust policy's `aud` condition. |
| `session-duration` | `900` | Seconds the credentials stay valid, 900 to 43200. |
| `session-name` | `<run_id>-<run_attempt>` | The STS session name, as it appears in CloudTrail. |
| `show-claims` | `false` | Print the token's claims before the exchange. Only the payload is decoded. |

A bare role name is refused deliberately. `configure-aws-credentials` accepts one and
resolves it against the source account, which leaves the trust boundary unreadable from the
caller's workflow. Requiring the ARN makes the account explicit.

The partition is not fixed: `aws`, `aws-cn` and `aws-us-gov` ARNs are all accepted.

## Outputs

| Output | Description |
| --- | --- |
| `aws-access-key-id` | Access key id of the assumed session. |
| `aws-secret-access-key` | Secret access key of the assumed session. |
| `aws-session-token` | Session token of the assumed session. |
| `aws-expiration` | When the session expires. |

Each value is registered as a secret by `configure-aws-credentials` before it becomes an
output, so all four are masked in logs.

`aws-account-id` and `authenticated-arn` exist upstream and are deliberately not forwarded.
Both carry the account id, and upstream only populates them when credentials are exported to
the environment, which this action does not do.

## What the action runs

1. **Validate the inputs** — `validate-inputs.sh`. Runs before any credential handling, and
   also checks that the job holds `id-token: write`. No message echoes the value it rejected;
   each states the expected shape instead.
2. **Show the OIDC token claims** — `show-claims.sh`, only when `show-claims` is `true`.
3. **Assume the role** — `aws-actions/configure-aws-credentials`, SHA-pinned, with
   `output-credentials: true` and `output-env-credentials: false`.
4. **Explain a failed assumption** — a `::notice::` naming `show-claims`, printed only when
   step 3 is what failed and the dump was not already on.

### Why the claims dump is off by default

A trust policy is matched against the token's claims and nothing else, and STS reports a
mismatch as `Not authorized to perform sts:AssumeRoleWithWebIdentity` while naming no
condition. Printing the claims is the only way to see the `sub` and `job_workflow_ref` a
policy is being compared against.

It is off by default because the claims name the repository, workflow, ref and actor, and a
consumer that never asked for that should not publish it on every run. Step 4 is what keeps
it discoverable: the one run where the dump matters is the run that failed, and that run says
how to get it.

The token itself never reaches the log. Only the payload is base64url-decoded, and the token
is registered as a secret so that even an accidental print of it is masked.

## How it fails

| Cause | Message |
| --- | --- |
| `aws-role-arn` unset or blank | `aws-role-arn is empty - pass the role ARN, as a secret.` |
| A bare role name, or any non-role ARN | `aws-role-arn must be a full IAM role ARN ...` |
| `aws-region` malformed | `aws-region must match ^[a-z0-9-]+$ ...` |
| `session-duration` not a number, or outside 900–43200 | `session-duration must be ...` |
| `show-claims` neither `true` nor `false` | `show-claims must be 'true' or 'false'.` |
| The job lacks `id-token: write` | `no OIDC token is available - the calling job needs 'permissions: id-token: write'.` |
| The trust policy does not match | Upstream's STS error, plus the notice from step 4. |

`required: true` on a composite action's input is documentation and nothing enforces it,
which is why the first two exist as runtime checks.

## Requirements

- `permissions: id-token: write` on the calling job.
- An IAM role whose trust policy accepts this workflow's claims. For a role assumed from a
  reusable workflow, that means conditioning on `job_workflow_ref` as well as `sub`; for one
  assumed from a workflow in its own repository, `job_workflow_ref` is absent and a condition
  on it leaves the statement unmatched.
- `curl` and `jq`, both present on GitHub-hosted runners, when `show-claims` is `true`.

## Side effects

- Sets no environment variable in the calling job. No `AWS_*` credential is exported.
- Writes no file and no profile. Nothing persists after the job.
- Masks the account id parsed from `aws-role-arn`, and the OIDC token when the dump runs.
- Makes one STS `AssumeRoleWithWebIdentity` call, and one GitHub token request per dump.

## What this action does not do

- Read a secret, a parameter or a key from AWS. Use the credentials it returns.
- Log in to any registry or service.
- Export credentials to the job environment. There is deliberately no input for it: a
  credential every later step inherits is not the shape this action is for.
- Refresh the session. When `session-duration` elapses the credentials are dead; assume
  again.
- Work with any provider other than AWS. The token is requested for an AWS audience by
  default and handed to STS.
