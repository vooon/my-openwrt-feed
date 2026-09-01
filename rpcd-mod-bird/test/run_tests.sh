#!/bin/sh
# Run the rpcd-mod-bird unit tests.
#
# Uses `ucode` from $PATH (override with UCODE).  On hosts where the ucode
# module search path is not the default (e.g. when running the interpreter
# straight from an OpenWrt build tree), point UCODE_MODULE_PATH at the
# directory containing the built ucode modules (e.g. ipkg-install/usr/lib/ucode).
#
# On the OpenWrt router itself (`ssh root@<router>` after scp'ing the package
# directory) this needs nothing: ucode + ucode-mod-fs come from opkg.

set -e

cd "$(dirname "$0")"

UCODE="${UCODE:-ucode}"

if [ -n "$UCODE_MODULE_PATH" ]; then
	exec "$UCODE" -L "$UCODE_MODULE_PATH" birdconfig.test.uc
fi

exec "$UCODE" birdconfig.test.uc