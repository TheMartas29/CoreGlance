#!/bin/sh
# Sets CFBundleShortVersionString and CFBundleVersion in the given (build copy of) Info.plist.
# Version: env VERSION, else tag on HEAD (without leading "v"), else the value already in the plist.
# Build number: GITHUB_RUN_NUMBER, else commit count; never lower than the value already in the plist.
# Usage: scripts/apply-version.sh <Info.plist>   (run inside the git repo)
set -eu
PLIST="$1"
PB=/usr/libexec/PlistBuddy

VER="${VERSION:-}"
if [ -z "$VER" ]; then
    VER="$(git describe --tags --exact-match 2>/dev/null || true)"
    VER="${VER#v}"
fi
if [ -n "$VER" ]; then
    "$PB" -c "Set :CFBundleShortVersionString $VER" "$PLIST"
fi

OLD="$("$PB" -c "Print :CFBundleVersion" "$PLIST")"
NUM="${GITHUB_RUN_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
case "$NUM" in ''|*[!0-9]*) NUM=0 ;; esac
case "$OLD" in ''|*[!0-9]*) OLD=0 ;; esac
if [ "$NUM" -lt "$OLD" ]; then NUM="$OLD"; fi
"$PB" -c "Set :CFBundleVersion $NUM" "$PLIST"
