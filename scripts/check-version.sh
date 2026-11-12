#!/bin/sh
# Release guard: tag, CFBundleShortVersionString and the top numbered CHANGELOG section must agree.
# Usage: sh scripts/check-version.sh [--skip-plist] [tag]   (tag defaults to $GITHUB_REF_NAME, leading "v" stripped)
# --skip-plist compares only tag and CHANGELOG. CI uses it on tags: the automated release (puppetd) commits only
# CHANGELOG.md, so Resources/Info.plist lags behind; the shipped plist gets the tag version from apply-version.sh.
# Overrides for tests: PLIST=<Info.plist> CHANGELOG=<CHANGELOG.md>
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${PLIST:-$ROOT/Resources/Info.plist}"
CHANGELOG="${CHANGELOG:-$ROOT/CHANGELOG.md}"
SKIP_PLIST=0
if [ "${1:-}" = "--skip-plist" ]; then SKIP_PLIST=1; shift; fi
TAG="${1:-}"
if [ -z "$TAG" ]; then TAG="${GITHUB_REF_NAME:-}"; fi
TAG="${TAG#v}"
if [ -z "$TAG" ]; then echo "check-version: missing tag (argument or GITHUB_REF_NAME)" >&2; exit 1; fi

# First "## [X.Y.Z] ..." heading; "## [Nevydáno]" does not start with a digit and is skipped.
LOGVER="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$CHANGELOG" 2>/dev/null | head -n 1)"

FAIL=0
if [ "$SKIP_PLIST" -eq 0 ]; then
    PLISTVER="$(plutil -extract CFBundleShortVersionString raw "$PLIST" 2>/dev/null || true)"
    if [ -z "$PLISTVER" ]; then
        echo "check-version: CFBundleShortVersionString not found in $PLIST" >&2; FAIL=1
    elif [ "$PLISTVER" != "$TAG" ]; then
        echo "check-version: Info.plist is $PLISTVER, tag is $TAG" >&2; FAIL=1
    fi
fi
if [ -z "$LOGVER" ]; then echo "check-version: no numbered section in $CHANGELOG" >&2; FAIL=1; fi
if [ -n "$LOGVER" ] && [ "$LOGVER" != "$TAG" ]; then
    echo "check-version: top CHANGELOG section is $LOGVER, tag is $TAG" >&2; FAIL=1
fi
if [ "$FAIL" -eq 0 ]; then echo "check-version: ok ($TAG)"; fi
exit $FAIL
