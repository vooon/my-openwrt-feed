#!/bin/sh
# Regression test for the BIRD collector (files/extra/bird.uc).
#
# Runs the collector against a mocked "bird" ubus object and checks that
# the emitted metrics match the expected czerwonk/bird_exporter schema.
#
# Usage: ucode test-bird.uc   (run from the package directory)

set -u

# Locate a native ucode interpreter for testing.
if command -v ucode >/dev/null 2>&1; then
	UCODE=ucode
elif [ -x ./ucode ]; then
	UCODE=./ucode
else
	echo "ucode interpreter not found; skipping bird collector test" >&2
	exit 0
fi

cd "$(dirname "$0")"

exec "$UCODE" test-bird.uc