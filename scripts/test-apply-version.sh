#!/bin/sh
# Tests scripts/apply-version.sh in a throwaway git repo. Usage: bash scripts/test-apply-version.sh
set -eu
# CI (GitHub Actions) always exports these; the tests below set them explicitly where they matter.
unset GITHUB_RUN_NUMBER VERSION
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/applyver.XXXXXX")"
trap 'rm -r "$T"' EXIT
FAIL=0
check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; FAIL=1; fi
}
get() { plutil -extract "$1" raw "$T/Info.plist"; }
fresh() { cp "$ROOT/Resources/Info.plist" "$T/Info.plist"; }
commit() { git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$1"; }

cd "$T"
git init -q --template= .
commit one
SRC="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"

fresh; VERSION=9.9.9 sh "$ROOT/scripts/apply-version.sh" Info.plist
check "VERSION env" 9.9.9 "$(get CFBundleShortVersionString)"

fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "no tag keeps plist value" "$SRC" "$(get CFBundleShortVersionString)"

git tag v9.8.7
fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "tag on HEAD" 9.8.7 "$(get CFBundleShortVersionString)"
fresh; VERSION=1.2.3 sh "$ROOT/scripts/apply-version.sh" Info.plist
check "VERSION beats tag" 1.2.3 "$(get CFBundleShortVersionString)"

# 1 commit < plist build number (5): never goes below the old value
fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "build number floor" 5 "$(get CFBundleVersion)"
for i in 2 3 4 5 6 7; do commit "c$i"; done
fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "build number = commit count" 7 "$(get CFBundleVersion)"
fresh; GITHUB_RUN_NUMBER=42 sh "$ROOT/scripts/apply-version.sh" Info.plist
check "build number = run number" 42 "$(get CFBundleVersion)"

exit $FAIL
