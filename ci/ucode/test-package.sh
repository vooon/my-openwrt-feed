#!/bin/sh
# Lint, syntax-check and test packages of this feed with the pinned ucode
# toolchain. ci.yml runs it in the ci/ucode/Dockerfile image, one job per
# touched package; it runs the same way locally:
#
#   ci/ucode/test-package.sh --list          # packages this script covers
#   ci/ucode/test-package.sh <package>...    # run the checks
#
#   podman run --rm --cap-add NET_ADMIN -v "$PWD:/feed" \
#       ghcr.io/vooon/my-openwrt-feed/ucode-ci:<tag> \
#       /feed/ci/ucode/test-package.sh vpn-sticky pbs-helper
#
# NET_ADMIN lets `nft -c` validate the vpn-sticky goldens; without it that
# pass is skipped with a warning. Outside the image, point UCODE,
# UCODE_MODULES (or UCODE_MODULE_PATH) and UCODE_INCLUDE at a
# scripts/build-ucode.sh output (<dir>/src/build/ucode, <dir>/src/build,
# <dir>/src/include); scripts/uc-lint.mjs then fetches ucode-lsp with npx
# and the utest suites clone utest themselves.
set -eu

COVERED="inotify-rsync netifd-proto-dummy netifd-proto-fou pbs-helper
prometheus-node-exporter-ucode qemu-instance-init rpcd-mod-bird
ucode-mod-inotify ucode-mod-sqlite uwsd vpn-sticky"

if [ "${1:-}" = "--list" ]; then
	# shellcheck disable=SC2086   # one name per line
	printf '%s\n' $COVERED
	exit 0
fi
if [ $# -eq 0 ]; then
	echo "usage: $0 --list | <package>..." >&2
	exit 2
fi

cd "$(dirname "$0")/../.."

UCODE="${UCODE:-ucode}"
UCODE_MODULES="${UCODE_MODULES:-${UCODE_MODULE_PATH:-}}"
UCODE_MODULE_PATH="$UCODE_MODULES"
export UCODE UCODE_MODULES UCODE_MODULE_PATH

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Compile every .uc/.ut file of a package to bytecode without executing it.
# ucode resolves imports at compile time, but the OpenWrt modules (uci,
# ubus, ...) are not in the upstream tree, so strip the import lines, turn
# `export function` back into a plain function (script-mode -c) and
# compile. Template files (.ut, or starting with `{%`) are compiled with -T.
syntax_check() {
	find "$1" -type f \( -name '*.uc' -o -name '*.ut' \) | sort | while read -r f; do
		name="$(basename "$f")"
		sed -e '/^[ \t]*import /d' -e 's/^[ \t]*export[ \t]*//' "$f" > "$work/$name"
		tmpl=
		if [ "${f##*.}" = ut ] || head -n1 "$f" | grep -q '^{%'; then
			tmpl=-T
		fi
		# shellcheck disable=SC2086   # $tmpl: empty or -T
		if ! "$UCODE" ${UCODE_MODULES:+-L "$UCODE_MODULES"} $tmpl -c -o "$work/$name.out" "$work/$name"; then
			echo "::error::$f: syntax check failed"
			exit 1
		fi
		echo "ok: $f"
	done
}

# Run a package's utest suite; use the image's utest copy (UTEST_DIR) when
# the suite pins the same revision, else the runner clones it.
run_utest() {
	runner="$1/test/run_tests.sh"
	if [ -n "${UTEST_DIR:-}" ] && [ -f "$UTEST_DIR/REV" ] &&
		grep -q "^UTEST_REV=\"$(cat "$UTEST_DIR/REV")\"" "$runner"; then
		UTEST_SRC="$UTEST_DIR/src" "$runner"
	else
		"$runner"
	fi
}

# nft command for the vpn-sticky golden check, empty when there is no
# netlink access (needs root + NET_ADMIN)
nft_cmd() {
	if nft list tables > /dev/null 2>&1; then
		echo nft
	else
		echo "::warning::vpn-sticky: nft -c check skipped (no netlink access; run with --cap-add NET_ADMIN)" >&2
	fi
}

# Build a C plugin module against the pinned ucode headers and run its
# smoke test with the upstream modules + the plugin on the module path.
build_plugin() {
	pkg="$1" mod="$2"
	cmake -S "$pkg/src" -B "$work/$mod-build" \
		-Ducode_include_dir="${UCODE_INCLUDE:?set UCODE_INCLUDE to the ucode headers to build $pkg}"
	cmake --build "$work/$mod-build"
	mkdir -p "$work/$mod-mods"
	cp "${UCODE_MODULES:?set UCODE_MODULES to the built ucode modules}"/*.so "$work/$mod-mods"/
	cp "$work/$mod-build/$mod.so" "$work/$mod-mods"/
	"$UCODE" -L "$work/$mod-mods" "$pkg/test/$mod.uc"
}

for pkg in "$@"; do
	# shellcheck disable=SC2086   # the list is word-split on purpose
	case " $(printf '%s ' $COVERED)" in
	*" $pkg "*) ;;
	*)
		echo "::error::$pkg: not covered by $0 (see --list)"
		exit 2
		;;
	esac

	echo "::group::$pkg: ucode-lsp lint"
	node scripts/uc-lint.mjs "$pkg"
	echo "::endgroup::"

	echo "::group::$pkg: ucode -c syntax check"
	syntax_check "$pkg"
	echo "::endgroup::"

	echo "::group::$pkg: tests"
	case "$pkg" in
	prometheus-node-exporter-ucode)
		prometheus-node-exporter-ucode/test.sh
		;;
	rpcd-mod-bird | uwsd | netifd-proto-dummy | netifd-proto-fou)
		"$pkg/test/run_tests.sh"
		;;
	pbs-helper | qemu-instance-init)
		run_utest "$pkg"
		;;
	vpn-sticky)
		NFT="$(nft_cmd)" run_utest vpn-sticky
		;;
	ucode-mod-inotify)
		build_plugin ucode-mod-inotify inotify
		;;
	ucode-mod-sqlite)
		build_plugin ucode-mod-sqlite sqlite
		;;
	inotify-rsync)
		echo "no test suite"
		;;
	esac
	echo "::endgroup::"
done
