#!/bin/sh
# Prints the body of one CHANGELOG section (without its heading). Usage: sh scripts/release-notes.sh <version>
# Exit 1 when the version has no section. Override file for tests: CHANGELOG=<path>
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHANGELOG="${CHANGELOG:-$ROOT/CHANGELOG.md}"
VER="${1:-}"
VER="${VER#v}"
if [ -z "$VER" ]; then echo "usage: release-notes.sh <version>" >&2; exit 1; fi
OUT="$(awk -v ver="$VER" '
    /^## \[/ { if (on) exit; on = (index($0, "## [" ver "]") == 1); found = found || on; next }
    on { print }
    END { if (!found) exit 2 }
' "$CHANGELOG")" || { echo "release-notes: no section [$VER] in $CHANGELOG" >&2; exit 1; }
# Trim leading/trailing blank lines.
printf '%s\n' "$OUT" | sed -e '/./,$!d' | awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i] }'
