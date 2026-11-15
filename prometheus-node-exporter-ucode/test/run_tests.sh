#!/bin/sh
# prometheus-node-exporter-ucode tests: utest suite (test/*_test.uc) for the
# collectors and the metrics.uc core, with mocked ubus / uci / uclient / uloop.
#
# Env:
#   UCODE              ucode interpreter               [ucode]
#   UCODE_MODULE_PATH  dir with fs.so                  [interpreter default]
#   UTEST_SRC          utest src/ dir; fetched (pinned) when unset
set -eu

UTEST_REPO="https://github.com/m00qek/utest"
UTEST_REV="03aaa1b81c89009d4e8a284cb66259374e292688" # v1.5.1

here="$(cd "$(dirname "$0")" && pwd)"
pkg="$(dirname "$here")"
UCODE="${UCODE:-ucode}"

if [ -z "${UTEST_SRC:-}" ]; then
	cache="${TMPDIR:-/tmp}/utest-$UTEST_REV"
	if [ ! -f "$cache/src/utest.uc" ]; then
		rm -rf "$cache"
		git init -q "$cache"
		git -C "$cache" remote add origin "$UTEST_REPO"
		git -C "$cache" fetch -q --depth 1 origin "$UTEST_REV"
		git -C "$cache" checkout -q FETCH_HEAD
	fi
	UTEST_SRC="$cache/src"
fi

run_dir="$(mktemp -d)"
trap 'rm -rf "$run_dir"' EXIT

# Same invocation as vpn-sticky/test/run_tests.sh (see there for the details).
opts="$(printf '{"reporter":null,"filter":null,"config":"%s","run_dir":"%s","src_dir":"%s","lib_paths":[%s],"jobs":null,"seed":null}' \
	"$here/utest.config.uc" "$run_dir" "$UTEST_SRC" "${UCODE_MODULE_PATH:+\"$UCODE_MODULE_PATH\"}")"

# the runner spawns each test file as `ucode ...` from $PATH
case "$UCODE" in
*/*) PATH="$(cd "$(dirname "$UCODE")" && pwd):$PATH" ;;
esac
# UTEST_SRC: test/proxy/*.uc extend utest's built-in proxies
export PATH UTEST_SRC NE_PKG_DIR="$pkg"
# shellcheck disable=SC2086
"$UCODE" ${UCODE_MODULE_PATH:+-L "$UCODE_MODULE_PATH"} \
	-L "$UTEST_SRC" -L "$UTEST_SRC/utest/runner" -L "$UTEST_SRC/utest/runner/worker" \
	"$UTEST_SRC/utest/cli.uc" utest "$opts" "$here/"
