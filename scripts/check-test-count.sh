#!/bin/sh
# Ratchet: fails when `swift test` ran fewer XCTest tests than the minimum stored in scripts/min-tests.txt.
# Usage: sh scripts/check-test-count.sh <swift-test-log> [min-file]   (min-file defaults to scripts/min-tests.txt)
# The log has several "Executed N tests" lines (per suite + total); the highest N is the total.
# The minimum is never rewritten automatically: raise it by hand when tests are added.
set -u
LOG="${1:-}"
MIN_FILE="${2:-$(dirname "$0")/min-tests.txt}"
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "check-test-count: log file not found: '$LOG'" >&2; exit 2
fi
if [ ! -f "$MIN_FILE" ]; then
    echo "check-test-count: minimum file not found: '$MIN_FILE'" >&2; exit 2
fi
MIN="$(tr -d '[:space:]' <"$MIN_FILE")"
case "$MIN" in
    ''|*[!0-9]*) echo "check-test-count: $MIN_FILE must contain a single number, got '$MIN'" >&2; exit 2 ;;
esac
N="$(sed -n 's/.*Executed \([0-9][0-9]*\) tests\{0,1\}.*/\1/p' "$LOG" | sort -n | tail -1)"
if [ -z "$N" ]; then
    echo "check-test-count: no 'Executed N tests' summary in $LOG; tests did not run?" >&2; exit 1
fi
if [ "$N" -lt "$MIN" ]; then
    echo "check-test-count: FAIL: $N tests executed, minimum is $MIN ($MIN_FILE). Tests were deleted or skipped." >&2; exit 1
fi
if [ "$N" -gt "$MIN" ]; then
    echo "check-test-count: $N tests executed, minimum is $MIN. Raise $MIN_FILE to $N."
else
    echo "check-test-count: ok, $N tests (minimum $MIN)."
fi
