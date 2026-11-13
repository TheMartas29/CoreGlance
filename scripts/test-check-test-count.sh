#!/bin/sh
# Tests scripts/check-test-count.sh with fixture logs. Usage: sh scripts/test-check-test-count.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/testcount.XXXXXX")"
trap 'rm -r "$T"' EXIT
FAIL=0
check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; FAIL=1; fi
}
# Real `swift test` shape: per-suite lines first, "All tests" total last (but we must not rely on order).
mklog() { # total
    printf "Test Suite 'FooTests' passed at 2026-01-01 10:00:00.000.\n\t Executed 3 tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds\n" >"$T/log"
    printf "Test Suite 'All tests' passed at 2026-01-01 10:00:00.000.\n\t Executed %s tests, with 0 failures (0 unexpected) in 0.2 (0.2) seconds\n" "$1" >>"$T/log"
    printf "Test Suite 'BarTests' passed at 2026-01-01 10:00:00.000.\n\t Executed 1 test, with 0 failures (0 unexpected) in 0.1 (0.1) seconds\n" >>"$T/log"
}
run() { # name expected-exit
    sh "$ROOT/scripts/check-test-count.sh" "$T/log" "$T/min" >"$T/out" 2>&1
    check "$1" "$2" "$?"
}
printf '10\n' >"$T/min"

mklog 10; run "equal count passes" 0
check "equal message" 1 "$(grep -c 'ok, 10 tests (minimum 10)' "$T/out")"
mklog 12; run "more tests passes" 0
check "more message asks to raise" 1 "$(grep -c 'Raise .* to 12' "$T/out")"
mklog 9; run "fewer tests fails" 1
check "fewer message" 1 "$(grep -c '9 tests executed, minimum is 10' "$T/out")"
mklog 10; printf '11' >"$T/min"; run "min without newline" 1
printf '10\n' >"$T/min"

# Several "Executed" lines: the total (highest) is used, not the last line (1 test suite after the total).
mklog 10; run "total used, not last suite line" 0
printf '25\n' >"$T/min"; mklog 20; run "total below min fails despite larger-than-min suites" 1
printf '10\n' >"$T/min"

printf "Compiling...\nBuild complete!\n" >"$T/log"; run "no summary fails" 1
check "no summary message" 1 "$(grep -c "no 'Executed N tests' summary" "$T/out")"

printf 'abc\n' >"$T/min"; mklog 10; run "invalid min file fails" 2
sh "$ROOT/scripts/check-test-count.sh" "$T/missing" "$T/min" >"$T/out" 2>&1
check "missing log fails" 2 "$?"

# The committed minimum is a single number.
check "min-tests.txt is a number" 1 "$(grep -c '^[0-9][0-9]*$' "$ROOT/scripts/min-tests.txt")"
exit "$FAIL"
