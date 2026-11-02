#!/usr/bin/env bash
# Reject an empty SonarCloud token before it reaches the scanner.
#
# GitHub does not enforce `required: true` for a composite action's inputs - it is
# documentation, checked by nothing. Without this guard an unset or misspelled secret
# reaches the scanner as an empty string and surfaces as an authentication error from
# SonarCloud, which reads as a credentials problem rather than a workflow one.
#
# A separate file rather than an inline `run:` block so the guard is testable on its own:
# the test workflow points every job at the discard port, so the action fails at the scan
# step whatever the token is, and an assertion on the action's outcome cannot tell the two
# failures apart. See .github/workflows/sonar-scan-test.yml.
#
# The token arrives through the environment, so no caller value is ever substituted into
# this script (see SECURITY.md).
#
# NEVER write the secrets context's expression form anywhere in this action, comments and
# descriptions included. The runner evaluates every ${} expression in a manifest wherever
# it appears, and that context does not exist in a composite action, so one mentioned in
# prose fails the whole action to load rather than reading as an example.
set -euo pipefail

# Defaulted first because an unset variable would abort under `set -u` before the test
# below could report anything useful. Whitespace is then stripped: an unset secret
# interpolates to the empty string rather than to spaces, but a token of blanks is no more
# usable than no token at all.
token="${SONAR_TOKEN:-}"
if [[ -z "${token//[[:space:]]/}" ]]; then
  echo "sonar/scan: sonar-token is empty - pass the SONAR_TOKEN secret." >&2
  exit 1
fi
