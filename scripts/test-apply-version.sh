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

# Only v<number> tags count; "latest" on HEAD must not become the version.
commit c8
git tag latest
fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "non-version tag ignored" "$SRC" "$(get CFBundleShortVersionString)"
git tag v4.5.6
fresh; sh "$ROOT/scripts/apply-version.sh" Info.plist
check "v-tag next to other tag" 4.5.6 "$(get CFBundleShortVersionString)"

# Leading "v" is stripped from VERSION too.
fresh; VERSION=v0.2.4 sh "$ROOT/scripts/apply-version.sh" Info.plist
check "VERSION strips leading v" 0.2.4 "$(get CFBundleShortVersionString)"

# Unsafe VERSION (space/quote would alter the PlistBuddy command) is rejected, plist untouched.
fresh
if VERSION='1.0 Add :Evil string x' sh "$ROOT/scripts/apply-version.sh" Info.plist 2>/dev/null; then R=0; else R=1; fi
check "VERSION with space rejected" 1 "$R"
check "plist untouched after reject" "$SRC" "$(get CFBundleShortVersionString)"
fresh
if VERSION='1.0"x' sh "$ROOT/scripts/apply-version.sh" Info.plist 2>/dev/null; then R=0; else R=1; fi
check "VERSION with quote rejected" 1 "$R"

# Shallow clone: commit count is unreliable, so warn (and keep the plist floor).
git clone -q --depth 1 "file://$T" "$T/shallow"
fresh
WARN="$(cd "$T/shallow" && sh "$ROOT/scripts/apply-version.sh" "$T/Info.plist" 2>&1 >/dev/null)"
case "$WARN" in *shallow*) check "shallow clone warns" ok ok ;; *) check "shallow clone warns" ok "no warning" ;; esac
check "shallow build number floor" 5 "$(get CFBundleVersion)"

# Wiring: build-app.sh must really apply the version to the app's plist (stubbed swift/codesign).
P="$T/proj"; mkdir -p "$P/scripts" "$P/Resources" "$T/stub" "$T/bin"
cp "$ROOT/scripts/build-app.sh" "$ROOT/scripts/apply-version.sh" "$P/scripts/"
cp "$ROOT/Resources/Info.plist" "$P/Resources/"
echo bin > "$T/bin/CoreGlance"
printf '#!/bin/sh\ncase "$*" in *--show-bin-path*) echo "%s" ;; esac\n' "$T/bin" > "$T/stub/swift"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/codesign"
chmod +x "$T/stub/swift" "$T/stub/codesign"
(cd "$P" && PATH="$T/stub:$PATH" VERSION=7.7.7 GITHUB_RUN_NUMBER=99 sh scripts/build-app.sh >/dev/null)
APPPLIST="$P/build/CoreGlance.app/Contents/Info.plist"
check "build-app.sh applies version" 7.7.7 "$(plutil -extract CFBundleShortVersionString raw "$APPPLIST")"
check "build-app.sh applies build number" 99 "$(plutil -extract CFBundleVersion raw "$APPPLIST")"
check "build-app.sh leaves source plist" "$SRC" "$(plutil -extract CFBundleShortVersionString raw "$P/Resources/Info.plist")"

exit $FAIL
