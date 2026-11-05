#!/usr/bin/env bash
# Reject a misconfigured caller before any credential handling begins.
#
# GitHub does not enforce `required: true` for a composite action's inputs - it is
# documentation, checked by nothing. Without this guard an unset or misspelled secret
# reaches configure-aws-credentials as an empty string and surfaces as an AWS error, which
# reads as a trust-policy problem rather than a workflow one.
#
# A separate file rather than an inline `run:` block so every case is testable without an
# OIDC token or an AWS account - see the input-validation job in
# .github/workflows/aws-assume-role-test.yml.
#
# No message echoes the value it rejected. A role ARN is passed as a secret and would print
# as `***`, which tells the reader nothing, so each message states the expected shape
# instead.
#
# Every value arrives through the environment, so no caller value is ever substituted into
# this script (see SECURITY.md).
#
# NEVER write the secrets context's expression form anywhere in this action, comments and
# descriptions included. The runner evaluates every ${} expression in a manifest wherever
# it appears, and that context does not exist in a composite action, so one mentioned in
# prose fails the whole action to load rather than reading as an example.
set -euo pipefail

# Defaulted first: an unset variable would abort under `set -u` before the test below could
# report anything useful.
role_arn="${INPUT_AWS_ROLE_ARN:-}"
aws_region="${INPUT_AWS_REGION:-}"
audience="${INPUT_AUDIENCE:-}"
session_duration="${INPUT_SESSION_DURATION:-}"
show_claims="${INPUT_SHOW_CLAIMS:-}"

# Whitespace is stripped for the emptiness tests: an unset secret interpolates to the empty
# string rather than to spaces, but a value of blanks is no more usable than no value.
if [[ -z "${role_arn//[[:space:]]/}" ]]; then
  echo "aws/assume-role: aws-role-arn is empty - pass the role ARN, as a secret." >&2
  exit 1
fi

# The ARN form specifically. configure-aws-credentials also accepts a bare role NAME,
# resolving it against the source account, and this rejects that: a name carries no account
# and makes the trust boundary unreadable from the caller's workflow.
#
# `aws[a-z-]*` rather than a literal `aws` so the aws-cn and aws-us-gov partitions are not
# refused. The check exists to require an ARN, not to require one partition.
if [[ ! "$role_arn" =~ ^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$ ]]; then
  echo "aws/assume-role: aws-role-arn must be a full IAM role ARN" \
       "(arn:aws:iam::<account-id>:role/<name>), not a bare role name." >&2
  exit 1
fi

# Masked as early as the ARN is known to be well-formed, so a caller who passed the ARN as a
# plain input does not publish the account id in the steps that follow.
#
# This CANNOT cover the caller's own `with:` block, which the runner echoes before this
# action starts. Passing the ARN as a secret remains the requirement - see README.md.
account_id="${role_arn#*:iam::}"
account_id="${account_id%%:*}"
echo "::add-mask::$account_id"

# The same shape configure-aws-credentials enforces, checked here so the failure names the
# input rather than arriving from inside the upstream action.
if [[ ! "$aws_region" =~ ^[a-z0-9-]+$ ]]; then
  echo "aws/assume-role: aws-region must match ^[a-z0-9-]+$ - got an empty or malformed" \
       "region." >&2
  exit 1
fi

if [[ -z "${audience//[[:space:]]/}" ]]; then
  echo "aws/assume-role: audience is empty - leave it unset for sts.amazonaws.com." >&2
  exit 1
fi

if [[ ! "$session_duration" =~ ^[0-9]+$ ]]; then
  echo "aws/assume-role: session-duration must be a whole number of seconds." >&2
  exit 1
fi

# AWS's own bounds for AssumeRoleWithWebIdentity. Checked here because the upstream action
# passes the value straight to STS, where a too-small number fails the release rather than
# the configuration.
if (( session_duration < 900 || session_duration > 43200 )); then
  echo "aws/assume-role: session-duration must be between 900 and 43200 seconds." >&2
  exit 1
fi

# An `if:` on a composite action step compares strings, so anything other than these two
# silently reads as false and the claims dump would never run. Rejected rather than coerced.
if [[ "$show_claims" != "true" && "$show_claims" != "false" ]]; then
  echo "aws/assume-role: show-claims must be 'true' or 'false'." >&2
  exit 1
fi

# The caller's permissions block, not an input - and the most common way this action fails.
# Without `id-token: write` the runner sets neither variable, and the upstream action
# reports a missing-token error that names nothing a caller can act on.
#
# This is why the input-validation test has to set a placeholder for the otherwise-valid
# case: the variable is absent on a runner whose job never asked for a token.
if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
  echo "aws/assume-role: no OIDC token is available - the calling job needs" \
       "'permissions: id-token: write'." >&2
  exit 1
fi

echo "role ARN, region, audience, session duration and claims flag all well-formed"
