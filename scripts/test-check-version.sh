#!/bin/sh
# Tests scripts/check-version.sh and scripts/release-notes.sh. Usage: sh scripts/test-check-version.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/checkver.XXXXXX")"
trap 'rm -r "$T"' EXIT
FAIL=0
check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; FAIL=1; fi
}
# run <name> <expected exit> <args...>  (uses PLIST/CHANGELOG from $T)
run() {
    name="$1"; want="$2"; shift 2
    PLIST="$T/Info.plist" CHANGELOG="$T/CHANGELOG.md" sh "$ROOT/scripts/check-version.sh" "$@" >"$T/out" 2>&1
    check "$name" "$want" "$?"
}
setplist() { cp "$ROOT/Resources/Info.plist" "$T/Info.plist"; plutil -replace CFBundleShortVersionString -string "$1" "$T/Info.plist"; }
printf '# Changelog\n\n## [Nevydáno]\n\n### Přidáno\n\n- x\n\n## [1.2.3] – 2026-01-01\n\n- a\n\n## [1.2.2] – 2025-12-01\n\n- b\n' >"$T/CHANGELOG.md"

setplist 1.2.3
run "match" 0 v1.2.3
run "match without v" 0 1.2.3
GITHUB_REF_NAME=v1.2.3 run "tag from GITHUB_REF_NAME" 0
setplist 1.2.2
run "plist mismatch" 1 v1.2.3
check "plist mismatch message" 1 "$(grep -c 'Info.plist is 1.2.2, tag is 1.2.3' "$T/out")"
setplist 1.2.3
run "changelog mismatch" 1 v1.2.4
check "changelog mismatch message" 1 "$(grep -c 'CHANGELOG section is 1.2.3, tag is 1.2.4' "$T/out")"
printf '# Changelog\n\n## [Nevydáno]\n\n- x\n' >"$T/CHANGELOG.md"
run "no numbered section" 1 v1.2.3
check "no section message" 1 "$(grep -c 'no numbered section' "$T/out")"
unset GITHUB_REF_NAME
run "missing tag" 1
check "missing tag message" 1 "$(grep -c 'missing tag' "$T/out")"

# release-notes on the real CHANGELOG.md
notes() { sh "$ROOT/scripts/release-notes.sh" "$1"; }
check "notes 0.2.4" "### Opraveno

- Okno O aplikaci a Nastavení ukazují skutečnou verzi. (#28)" "$(notes 0.2.4)"
check "notes 0.2.5 first line" "### Změněno" "$(notes 0.2.5 | head -n 1)"
check "notes 0.2.5 has no heading" 0 "$(notes 0.2.5 | grep -c '^## ')"
check "notes 0.2.5 stops before 0.2.4" 0 "$(notes 0.2.5 | grep -c 'skutečnou verzi')"
sh "$ROOT/scripts/release-notes.sh" 9.9.9 >/dev/null 2>&1
check "notes unknown version" 1 "$?"

exit $FAIL
