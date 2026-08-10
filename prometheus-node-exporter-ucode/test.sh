#!/bin/sh
# Run the prometheus-node-exporter-ucode collector tests.
#
# Each test is a ucode script in test/<name>.uc that mocks the collector's
# dependencies (ubus/fs/gauge/raw), loads files/extra/<name>.uc and asserts
# the emitted metrics.
#
# Usage: test.sh [test ...]
#   With no arguments, runs all tests.  With arguments, runs only the named
#   tests (e.g. `test.sh bird textfile`).
#
# For a locally built ucode that doesn't have the modules installed natively,
# point UCODE_MODULES at the directory containing the module .so files:
#   UCODE_MODULES=/path/to/modules test.sh

set -u
cd "$(dirname "$0")"

if [ -n "${UCODE:-}" ]; then
	:
elif command -v ucode >/dev/null 2>&1; then
	UCODE=ucode
elif [ -x ./ucode ]; then
	UCODE=./ucode
else
	echo "ucode interpreter not found (set UCODE)" >&2
	exit 1
fi

MOD_ARGS=""
if [ -n "${UCODE_MODULES:-}" ]; then
	MOD_ARGS="-L $UCODE_MODULES"
fi

TESTS="bird bmx7 nat_traffic textfile"

failed=0

run_test() {
	echo "=== $1 ==="
	if ! $UCODE $MOD_ARGS "test/$1.uc"; then
		echo "FAILED: $1" >&2
		failed=$(( failed + 1 ))
	else
		echo "ok: $1"
	fi
}

if [ $# -gt 0 ]; then
	for t in "$@"; do
		case " $TESTS " in
		*" $t "*)
			run_test "$t"
			;;
		*)
			echo "unknown test: $t" >&2
			failed=$(( failed + 1 ))
			;;
		esac
	done
else
	for t in $TESTS; do
		run_test "$t"
	done
fi

if [ "$failed" -gt 0 ]; then
	echo "$failed test(s) failed" >&2
	exit 1
fi

echo "all tests passed"