#!/usr/bin/env bash
# Report whether the JDK already on JAVA_HOME satisfies the requested java-version, so the
# action can leave it alone instead of installing an equivalent one and repointing
# JAVA_HOME at it. Writes `satisfied=true|false` to $GITHUB_OUTPUT and always exits 0: a
# non-zero exit from a composite action's step fails the whole action, and an unsatisfied
# request is a normal outcome, not an error.
#
# The feature version is the whole test. The scanner's requirement is a floor on the
# runtime it runs on, not a vendor, so a request met by any distribution is met - while an
# install this action does perform is still Temurin. An exact build is deliberately not
# compared: `java-version: '25'` asks for 25, and 25.0.5 is 25.
#
# Anything other than a bare feature number falls through to setup-java. setup-java accepts
# ranges and floating versions that only a semver implementation can evaluate, and
# misjudging one would silently scan on the wrong JDK; falling through costs the tool-cache
# lookup that was the status quo before this check existed.
#
# A separate file rather than an inline `run:` block so it is testable on its own, as
# require-token.sh is. See .github/workflows/sonar-scan-test.yml.
set -euo pipefail

# $GITHUB_OUTPUT is absent when the script is run directly; stdout then shows the verdict
# the step would have published.
output="${GITHUB_OUTPUT:-/dev/stdout}"
requested="${REQUESTED:-}"
java_home="${JAVA_HOME:-}"

not_satisfied() {
  echo "sonar/scan: setting up JDK $requested - $1."
  echo "satisfied=false" >> "$output"
  exit 0
}

if [[ ! "$requested" =~ ^[0-9]+$ ]]; then
  not_satisfied "'$requested' is not a bare feature version, so the installed JDK cannot be compared against it"
fi

release="$java_home/release"
if [[ -z "$java_home" || ! -r "$release" || ! -x "$java_home/bin/java" ]]; then
  not_satisfied "JAVA_HOME holds no JDK"
fi

# JAVA_VERSION="25.0.5", and "1.8.0_462" on a pre-9 JDK, where the feature version is the
# second component.
version="$(sed -n 's/^JAVA_VERSION="\([^"]*\)".*/\1/p' "$release")"
case "$version" in
  1.*) feature="$(echo "$version" | cut -d. -f2)" ;;
  *) feature="$(echo "$version" | cut -d. -f1)" ;;
esac

if [[ "$feature" != "$requested" ]]; then
  not_satisfied "JAVA_HOME holds JDK ${version:-unknown}"
fi

echo "sonar/scan: scanning on the JDK already on JAVA_HOME - $version at $java_home."
echo "satisfied=true" >> "$output"
