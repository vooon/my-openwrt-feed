#!/bin/sh
# Run the uwsd utpl-wrapper unit tests.
#
# Uses `ucode` from $PATH (override with UCODE).  On hosts where the ucode
# module search path is not the default (e.g. when running the interpreter
# straight from an OpenWrt build tree), point UCODE_MODULE_PATH at the
# directory containing the built ucode modules (e.g. ipkg-install/usr/lib/ucode).
#
# ucode has no setenv(), so the scratch DOCUMENT_ROOT the wrapper resolves
# templates against is created and exported here.
#
# On the OpenWrt router itself (`ssh root@<router>` after scp'ing the package
# directory) this needs nothing: ucode + ucode-mod-fs come from opkg.

set -e

cd "$(dirname "$0")"

UCODE="${UCODE:-ucode}"

DOCUMENT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/utpl-wrapper-test.XXXXXX")"
export DOCUMENT_ROOT

cleanup() {
	rm -rf "$DOCUMENT_ROOT"
}
trap cleanup EXIT

if [ -n "$UCODE_MODULE_PATH" ]; then
	exec "$UCODE" -L "$UCODE_MODULE_PATH" utpl-wrapper.test.uc
fi

exec "$UCODE" utpl-wrapper.test.uc
