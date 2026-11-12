#!/bin/sh
# Release guard: tag, CFBundleShortVersionString and the top numbered CHANGELOG section must agree.
# Usage: sh scripts/check-version.sh [tag]   (tag defaults to $GITHUB_REF_NAME, leading "v" is stripped)
# Overrides for tests: PLIST=<Info.plist> CHANGELOG=<CHANGELOG.md>
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${PLIST:-$ROOT/Resources/Info.plist}"
CHANGELOG="${CHANGELOG:-$ROOT/CHANGELOG.md}"
TAG="${1:-}"
if [ -z "$TAG" ]; then TAG="${GITHUB_REF_NAME:-}"; fi
TAG="${TAG#v}"
if [ -z "$TAG" ]; then echo "check-version: missing tag (argument or GITHUB_REF_NAME)" >&2; exit 1; fi

PLISTVER="$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || true)"
# First "## [X.Y.Z] ..." heading; "## [Nevydáno]" does not start with a digit and is skipped.
LOGVER="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$CHANGELOG" 2>/dev/null | head -n 1)"

FAIL=0
if [ -z "$PLISTVER" ]; then echo "check-version: CFBundleShortVersionString not found in $PLIST" >&2; FAIL=1; fi
if [ -z "$LOGVER" ]; then echo "check-version: no numbered section in $CHANGELOG" >&2; FAIL=1; fi
if [ -n "$PLISTVER" ] && [ "$PLISTVER" != "$TAG" ]; then
    echo "check-version: Info.plist is $PLISTVER, tag is $TAG" >&2; FAIL=1
fi
if [ -n "$LOGVER" ] && [ "$LOGVER" != "$TAG" ]; then
    echo "check-version: top CHANGELOG section is $LOGVER, tag is $TAG" >&2; FAIL=1
fi
if [ "$FAIL" -eq 0 ]; then echo "check-version: ok ($TAG)"; fi
exit $FAIL
