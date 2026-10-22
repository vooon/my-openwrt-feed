#!/bin/sh
# Build packages of this feed inside an OpenWrt SDK container.
#
# Used by .github/workflows/build.yml; runs the same way locally, from the
# feed checkout, with podman or docker (the image is ci/sdk/Dockerfile; the
# stock ghcr.io/openwrt/sdk:<tag> works too but builds golang/rust from
# source first):
#
#   mkdir -p out
#   podman run --rm -u root -v "$PWD:/feed" -v "$PWD/out:/out" \
#       ghcr.io/vooon/my-openwrt-feed/sdk:x86-64-25.12.6 \
#       /feed/scripts/sdk-build.sh mihomo-meta rpcd-mod-bird
#
# -u root: the image user (buildbot) cannot write the mounted directories;
# the SDK has no objection to building as root.
#
# Env:
#   SDK_DIR   unpacked SDK                     [/builder]
#   FEED_DIR  this feed (mounted checkout)     [/feed]
#   OUT_DIR   where built packages are copied, if the directory exists [/out]
#   JOBS      parallel jobs                    [nproc]
set -eu

SDK_DIR="${SDK_DIR:-/builder}"
FEED_DIR="${FEED_DIR:-/feed}"
OUT_DIR="${OUT_DIR:-/out}"
JOBS="${JOBS:-$(nproc)}"
FEED=vooon

if [ $# -eq 0 ]; then
	echo "usage: $0 <package>..." >&2
	exit 2
fi

cd "$SDK_DIR"

# The SDK's default feeds (pinned commits) plus this feed. In the ci/sdk
# image the default feeds are already fetched and indexed; the stock SDK
# needs a full update.
{
	cat feeds.conf.default
	echo "src-link $FEED $FEED_DIR"
} > feeds.conf
if [ -f feeds/packages.index ]; then
	./scripts/feeds update "$FEED"
else
	./scripts/feeds update -a
fi

# -f: prefer this feed's package over a same-named one in the default feeds
./scripts/feeds install -p "$FEED" -f "$@"
make defconfig > /dev/null

rc=0
for pkg in "$@"; do
	echo "::group::make package/$pkg/compile"
	if ! make -j"$JOBS" "package/$pkg/compile"; then
		echo "::endgroup::"
		echo "::group::retry: make package/$pkg/compile -j1 V=s"
		make -j1 V=s "package/$pkg/compile" || rc=1
	fi
	echo "::endgroup::"
done

if [ -d "$OUT_DIR" ]; then
	find bin/packages -path "*/$FEED/*" -type f -exec cp -v {} "$OUT_DIR"/ \;
fi

exit $rc
