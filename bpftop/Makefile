include $(TOPDIR)/rules.mk

PKG_NAME:=bpftop
# renovate: datasource=github-releases depName=Netflix/bpftop
PKG_VERSION:=0.9.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Netflix/bpftop.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/bpf.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# bpftop's build.rs cross-compiles an embedded BPF object with the `clang`
# found in PATH (libbpf-cargo SkeletonBuilder): put OpenWrt's BPF toolchain
# (bpf.mk CLANG, built or prebuilt llvm-bpf) first so the build does not
# depend on a host clang. libbpf-sys additionally compiles a vendored libbpf
# against the staging libelf/zlib headers and statically links it.
# (CARGO_PKG_VARS is reset by rust-package.mk: extend it after the include;
# TARGET_PATH_PKG is the PATH package recipes run with, including cargo.)
CARGO_PKG_VARS += \
	PATH="$(dir $(CLANG)):$(TARGET_PATH_PKG)" \
	CFLAGS="-I$(STAGING_DIR)/usr/include" \
	CARGO_NET_GIT_FETCH_WITH_CLI=true

define Package/bpftop
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Dynamic real-time view of running eBPF programs
  URL:=https://github.com/Netflix/bpftop
  DEPENDS:=$(RUST_ARCH_DEPENDS) $(BPF_DEPENDS) +libelf
endef

define Package/bpftop/description
  bpftop provides a dynamic real-time view of running eBPF programs. For each
  program it displays the average runtime, events per second and an estimated
  total CPU %, sorted by efficiency, updating in real time.
  Requires root/BPF capabilities and a kernel with BTF enabled
  (CONFIG_DEBUG_INFO_BTF).
endef

define Build/Compile
	[ -x "$(CLANG)" ] || { echo "bpftop needs the BPF toolchain: $(CLANG) is missing" >&2; exit 1; }
	$(call Build/Compile/Cargo,.)
endef

$(eval $(call RustBinPackage,bpftop))
$(eval $(call BuildPackage,bpftop))