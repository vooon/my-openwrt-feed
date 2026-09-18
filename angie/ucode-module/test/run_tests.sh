#!/bin/sh
# Run the angie-mod-ucode regression tests.
#
# Two layers, neither of which needs an angie/nginx build:
#   - C unit tests for http_parse.c, the module's byte-level request/response
#     parsing (built with $CC, skipped when there is no host compiler).
#   - the example template (examples/profiles.ut), which depends on the
#     "request"/"response"/"uhttpd" globals that the C module injects; those
#     are mocked so it runs against a standalone ucode interpreter.
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

# 0. C unit tests for the module's byte-level parsing (http_parse.c).  These
#    need nothing but a host compiler; skipped if there is none.
CC="${CC:-cc}"
if command -v "$CC" >/dev/null 2>&1; then
	if $CC -std=c99 -D_POSIX_C_SOURCE=200809L -Wall -Wextra \
		-Wno-unused-parameter -o "${TMPDIR:-/tmp}/http_parse_test" \
		test/http_parse_test.c http_parse.c 2>&1 &&
		"${TMPDIR:-/tmp}/http_parse_test"; then
		echo "OK   http_parse.c unit tests"
	else
		echo "FAIL http_parse.c unit tests"
		fail=1
	fi
	rm -f "${TMPDIR:-/tmp}/http_parse_test"
else
	echo "SKIP http_parse.c unit tests (no $CC)"
fi

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

# 3. the standalone template test tool (angie-ucode-test) must compile and
#    render the example template through the mocked globals.
if $UCODE $MOD_ARGS test/angie-ucode-test.uc -- \
	--method GET --uri /profiles --header "X-Username: home" \
	../examples/profiles.ut >/dev/null 2>tool.err; then
	echo "OK   angie-ucode-test renders examples/profiles.ut"
else
	cat tool.err
	echo "FAIL angie-ucode-test run"
	fail=1
fi
rm -f tool.err

exit $fail