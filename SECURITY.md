# Security Policy

## Supported Versions

This repository publishes reusable GitHub Actions. Fixes land only on `main` and
reach consumers through the next release; please reproduce against the latest commit
on `main` before reporting an issue.

Because the moving `vX` and `vX.Y` tags are repointed on every release, a consumer
pinned to `@v1` picks up a fix automatically. An exact `vX.Y.Z` tag or a commit SHA
is immutable by design and is **not** backpatched — a fix ships in the next release,
and pinning that precisely means taking on the job of bumping it.

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately via GitHub's
[private vulnerability reporting](https://github.com/TomBorglum/actions/security/advisories/new)
(the **Security → Report a vulnerability** button on the repository). This keeps the
report confidential until a fix is available.

When reporting, please include:

- A description of the vulnerability and its impact.
- Steps to reproduce, or a proof of concept.
- The affected action(s) and the commit or tag you observed it on.

You can expect an acknowledgement within a few days. Once confirmed, a fix will be
prepared and a GitHub Security Advisory published crediting the reporter (unless you
prefer to remain anonymous).

## Scope & Notes

Code here runs **inside other people's workflows**, with whatever permissions and
secrets those workflows grant it. That raises the stakes on two things in particular,
and both are in scope:

- **What an action executes.** Every third-party action referenced from an
  `action.yml` here is pinned to a full commit SHA, not a tag, so an upstream tag
  being repointed cannot change what consumers run. Dependabot bumps those pins on a
  cooldown (see [`.github/dependabot.yml`](.github/dependabot.yml)) so a withdrawn or
  compromised upstream release has a window to surface before it is republished here.
- **What an action does with inputs and secrets.** Script injection through an
  unquoted `${{ }}` interpolation, a secret written to the log or to
  `$GITHUB_OUTPUT`, or an input that escapes into a shell command are all in scope.

Actions that fetch tooling from upstream sources over HTTPS verify it by checksum
where the upstream publishes one. Compromise of an upstream source itself is outside
this project's control; issues specific to *how this project fetches, verifies or
executes* it are in scope.

The moving `vX` / `vX.Y` tags are mutable **on purpose** — that is the published
contract, not a vulnerability. A report that these tags can change is not in scope;
consumers who need immutability pin a SHA.
