#!/bin/sh
# Run the angie-mod-ucode regression tests.
#
# Tests the example template (examples/profiles.ut) which depends on the
# "request"/"response"/"uhttpd" globals that the C module injects.  Those are
# mocked here so the tests run against a standalone ucode interpreter; no
# angie/nginx build is needed.
#
# Uses `ucode` from $PATH (override with UCODE).  For a locally built ucode
# whose modules are not on the default search path, point UCODE_MODULES at
# the directory containing the ucode module .so files.

set -e
cd "$(dirname "$0")"
cd ..

UCODE="${UCODE:-ucode}"

MOD_ARGS=""
if [ -n "${UCODE_MODULES:-}" ]; then
	MOD_ARGS="-L $UCODE_MODULES"
fi

fail=0

# 1. the template must syntax-compile in template mode.
if $UCODE $MOD_ARGS -T -c -o /dev/null examples/profiles.ut; then
	echo "OK   examples/profiles.ut compiles (template mode)"
else
	echo "FAIL examples/profiles.ut does not compile"
	fail=1
fi

# 2. behaviour assertions against mocked request/response/uhttpd globals.
#    (the template body is printed to stdout as a side effect; only the
#    assertions on stderr matter, so discard stdout here.)
if $UCODE $MOD_ARGS test/profiles.test.uc >/dev/null 2>assertions.err; then
	echo "OK   template behaviour assertions"
else
	cat assertions.err
	echo "FAIL template behaviour assertions"
	fail=1
fi
rm -f assertions.err

exit $fail