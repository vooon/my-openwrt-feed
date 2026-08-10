#!/bin/sh
# Regression test for the BMX7 collector (files/extra/bmx7.uc).
#
# Runs the collector against a mocked "bmx7" ubus object and checks that
# the emitted metrics are correct.
#
# Usage: ucode test-bmx7.uc   (run from the package directory)

set -u

if command -v ucode >/dev/null 2>&1; then
	UCODE=ucode
elif [ -x ./ucode ]; then
	UCODE=./ucode
else
	echo "ucode interpreter not found; skipping bmx7 collector test" >&2
	exit 0
fi

cd "$(dirname "$0")"

exec "$UCODE" test-bmx7.uc