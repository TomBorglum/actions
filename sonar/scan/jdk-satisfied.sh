#!/usr/bin/env bash
# Publish satisfied=true|false for the JDK on JAVA_HOME against the requested version, so
# sonar/scan can skip its setup step. README.md states what is compared and why.
#
# Always exits 0: a non-zero exit from a composite action's step fails the whole action,
# and an unsatisfied request is an outcome rather than an error. Asserted directly by
# .github/workflows/sonar-scan-test.yml.
set -euo pipefail

# Absent when the script is run directly, which is how the tests drive it.
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

# JAVA_VERSION is "25.0.5", or "1.8.0_462" on a pre-9 JDK, where 8 is the second component.
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
