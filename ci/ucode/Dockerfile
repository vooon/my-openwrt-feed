# Test image for the feed's ucode and shell packages: ci.yml runs
# ci/ucode/test-package.sh in it, one job per touched package. It holds
# the pinned ucode build with its upstream modules, ucode-lsp, the utest
# framework, nftables (vpn-sticky golden check) and the C toolchain for
# the ucode-mod-* plugins. Everything is installed here, once; the tests
# only run inside.
#
# The versions are pinned in the repo files and passed in as build args:
#   UCODE_LSP_VERSION  scripts/uc-lint.mjs      (UCODE_LSP_VERSION)
#   UTEST_REV          */test/run_tests.sh      (UTEST_REV, all the same)
# (the ucode commit is inside scripts/build-ucode.sh itself.)
#
# Built with the feed root as context by .github/workflows/ucode-image.yml,
# pushed as ghcr.io/<repo>/ucode-ci:<ucode sha>. Locally:
#   podman build -f ci/ucode/Dockerfile -t ucode-ci \
#       --build-arg UCODE_LSP_VERSION="$(sed -n "s/^const UCODE_LSP_VERSION = '\([^']*\)';.*/\1/p" scripts/uc-lint.mjs)" \
#       --build-arg UTEST_REV="$(sed -n 's/^UTEST_REV="\([0-9a-f]*\)".*/\1/p' pbs-helper/test/run_tests.sh)" .
FROM docker.io/library/node:22-bookworm-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates gcc make cmake git pkg-config \
		libjson-c-dev libsqlite3-dev nftables \
	&& rm -rf /var/lib/apt/lists/*

# pinned ucode + upstream modules; src/include stays for the C plugins
COPY scripts/build-ucode.sh /tmp/build-ucode.sh
RUN sh /tmp/build-ucode.sh /opt/ucode \
	&& rm -rf /opt/ucode/src/.git /opt/ucode/src/build/CMakeFiles /tmp/build-ucode.sh
ENV UCODE=/opt/ucode/src/build/ucode \
	UCODE_MODULES=/opt/ucode/src/build \
	UCODE_MODULE_PATH=/opt/ucode/src/build \
	UCODE_INCLUDE=/opt/ucode/src/include

# ucode-lsp; UCODE_LSP makes scripts/uc-lint.mjs use it instead of npx
ARG UCODE_LSP_VERSION
RUN npm install -g --no-fund --no-audit "ucode-lsp@${UCODE_LSP_VERSION:?}" \
	&& npm cache clean --force
ENV UCODE_LSP=ucode-lsp

# utest; test-package.sh uses this copy when a suite pins the same revision
ARG UTEST_REV
RUN git init -q /opt/utest \
	&& git -C /opt/utest remote add origin https://github.com/m00qek/utest \
	&& git -C /opt/utest fetch -q --depth 1 origin "${UTEST_REV:?}" \
	&& git -C /opt/utest checkout -q FETCH_HEAD \
	&& rm -rf /opt/utest/.git \
	&& echo "$UTEST_REV" > /opt/utest/REV
ENV UTEST_DIR=/opt/utest
