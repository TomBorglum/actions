#!/usr/bin/env bash
# Print the claims AWS conditions on, before any AWS call is made.
#
# A trust policy is matched against these values and nothing else, so a mismatch is
# otherwise undiagnosable from a workflow run: STS answers "Not authorized to perform
# sts:AssumeRoleWithWebIdentity" and names no condition. This is the only place the
# tag-shaped `sub` and the `job_workflow_ref` of a called workflow can be observed.
#
# ONLY THE PAYLOAD IS DECODED. The token itself is a live bearer credential and never
# reaches the log; it is registered as a secret below so that even an accidental print of it
# is masked. The payload is a different string from the token, so masking the one does not
# hide the other.
#
# Off by default. A consumer that never asks for it makes no token request at all - see
# action.yml, and the hint printed when the assumption fails.
#
# NEVER write the secrets context's expression form anywhere in this action, comments and
# descriptions included. The runner evaluates every ${} expression in a manifest wherever
# it appears, and that context does not exist in a composite action, so one mentioned in
# prose fails the whole action to load rather than reading as an example.
set -euo pipefail

audience="${INPUT_AUDIENCE:-}"
request_url="${ACTIONS_ID_TOKEN_REQUEST_URL:-}"
request_token="${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}"

# validate-inputs.sh checks the URL before this step runs, so reaching this is either a
# direct invocation in a test or a runner that granted the URL without the token.
if [[ -z "$request_url" || -z "$request_token" ]]; then
  echo "aws/assume-role: no OIDC token is available - the calling job needs" \
       "'permissions: id-token: write'." >&2
  exit 1
fi

# Percent-encoded rather than interpolated raw. The default audience needs no encoding, but
# this action takes any audience, and the forms other providers use carry `:` and `/`
# (api://AzureADTokenExchange, https://github.com/<owner>) which would otherwise alter the
# query string.
encoded_audience="$(printf '%s' "$audience" | jq -sRr @uri)"

token="$(curl -fsSL --proto '=https' \
  -H "Authorization: bearer $request_token" \
  "${request_url}&audience=${encoded_audience}" \
  | jq -r .value)"

if [[ -z "$token" || "$token" == "null" ]]; then
  echo "aws/assume-role: the OIDC token endpoint returned no token." >&2
  exit 1
fi
echo "::add-mask::$token"

# base64url -> base64, then padded to a multiple of 4 so base64 -d accepts it.
payload="$(printf '%s' "$token" | cut -d. -f2)"
payload="${payload//-/+}"
payload="${payload//_//}"
while (( ${#payload} % 4 )); do payload+="="; done

echo "OIDC token claims for audience: $audience"
printf '%s' "$payload" | base64 -d | jq .
