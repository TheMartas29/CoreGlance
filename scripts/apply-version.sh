#!/bin/sh
# Sets CFBundleShortVersionString and CFBundleVersion in the given (build copy of) Info.plist.
# Version: env VERSION, else tag v<number>... on HEAD (other tags like "latest" are ignored), else the value
#   already in the plist. A leading "v" is stripped from both sources; anything but [0-9A-Za-z.+-] is rejected.
# Build number: GITHUB_RUN_NUMBER, else commit count; never lower than the value already in the plist (so it is
#   "at least" the plist value, not strictly greater). Local builds count commits, CI counts runs: the two
#   sequences differ, so a CI release can carry a lower build number than a copy built locally earlier.
#   In a shallow clone the commit count is meaningless, so the plist value is kept (with a warning).
# Usage: scripts/apply-version.sh <Info.plist>   (run inside the git repo)
set -eu
PLIST="$1"
PB=/usr/libexec/PlistBuddy

VER="${VERSION:-}"
if [ -z "$VER" ]; then
    VER="$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)"
fi
VER="${VER#v}"
if [ -n "$VER" ]; then
    case "$VER" in
        [0-9]*) ;;
        *) echo "apply-version: invalid version '$VER'" >&2; exit 1 ;;
    esac
    case "$VER" in
        *[!0-9A-Za-z.+-]*) echo "apply-version: invalid version '$VER'" >&2; exit 1 ;;
    esac
    "$PB" -c "Set :CFBundleShortVersionString $VER" "$PLIST"
fi

OLD="$("$PB" -c "Print :CFBundleVersion" "$PLIST")"
if [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
    NUM="$GITHUB_RUN_NUMBER"
elif [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
    echo "apply-version: shallow clone, commit count unreliable; keeping build number $OLD (use fetch-depth: 0)" >&2
    NUM=0
else
    NUM="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
fi
case "$NUM" in ''|*[!0-9]*) NUM=0 ;; esac
case "$OLD" in ''|*[!0-9]*) OLD=0 ;; esac
if [ "$NUM" -lt "$OLD" ]; then NUM="$OLD"; fi
"$PB" -c "Set :CFBundleVersion $NUM" "$PLIST"
