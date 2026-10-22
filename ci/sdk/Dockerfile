# OpenWrt SDK for this feed's CI, with the Go, Rust, Python and Node host
# toolchains prebuilt. The stock SDK builds golang/host (~10 min), rust/host
# (LLVM from source, hours) and node/host (~1 h) on first use; this layer
# does that once per SDK tag so a PR build only compiles the package itself.
#
# Built and pushed by .github/workflows/sdk-image.yml as
# ghcr.io/<repo>/sdk:<SDK_TAG>; used by .github/workflows/build.yml via
# scripts/sdk-build.sh. The SDK's feeds.conf.default pins the packages feed
# to one commit, so the toolchain versions are fixed per SDK_TAG.
#
# Local build (Rust takes a while):
#   podman build -t openwrt-sdk-vooon ci/sdk
#   podman build --build-arg HOST_PACKAGES=golang -t openwrt-sdk-vooon ci/sdk   # Go only
ARG SDK_TAG=x86-64-25.12.6
FROM ghcr.io/openwrt/sdk:${SDK_TAG}

# Host toolchain packages (names in the packages feed) to prebuild, in
# build order: the default Go, Go 1.27 (authelia), Rust, Python 3 (also
# node/host's build dependency), Node (authelia) and yarn (gotify).
ARG HOST_PACKAGES="golang golang1.27 rust python3 node node-yarn"

# The image runs as buildbot in /builder, where the SDK is unpacked.
# make prints only one "make[2] -C ... host-compile" line per package and
# nothing while its recipe runs (hours for rust), so a background loop
# reports every 5 minutes what is being built and the size of its build dir.
RUN set -e; \
	cp feeds.conf.default feeds.conf; \
	./scripts/feeds update -a; \
	./scripts/feeds install ${HOST_PACKAGES}; \
	make defconfig; \
	( while sleep 300; do \
		echo "[heartbeat] $(date -u +%H:%M) building $(cat .current 2>/dev/null): $(du -sh build_dir/hostpkg 2>/dev/null | cut -f1)"; \
	  done ) & hb=$!; \
	for p in ${HOST_PACKAGES}; do \
		echo "$p" > .current; \
		make -j"$(nproc)" "package/$p/host/compile" || make -j1 V=s "package/$p/host/compile"; \
	done; \
	kill $hb; rm -f .current
# Nothing is cleaned up afterwards on purpose: CONFIG_AUTOREMOVE (SDK
# default) already drops the build trees once a host package is installed,
# and the stamps that remain (build_dir/hostpkg/*/.built, dl/* as their
# prerequisites: golang-bootstrap's prepare stamp depends on its tarballs)
# are what keeps make from rebuilding the toolchains on first use.
