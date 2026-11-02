include $(TOPDIR)/rules.mk

PKG_NAME:=meow-rs
# renovate: datasource=github-releases depName=meow-rs/meow-rs
PKG_VERSION:=0.28.0
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/meow-rs/meow-rs.git
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

# meow-app links BoringSSL (boring-sys/quiche), so the host needs cmake and a
# C++ compiler in addition to rust/host. cmake ships with the OpenWrt build
# system (tools/cmake) and is always available in the host staging dir.
PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# boring-sys generates its bindings with bindgen, which dlopens libclang. The
# SDK image has no system libclang, but every OpenWrt tree with a BPF
# toolchain ships one under staging_dir/host/llvm-bpf; point bindgen at it
# when present and let it fall back to the system library otherwise.
LLVM_BPF_LIB:=$(STAGING_DIR_HOST)/llvm-bpf/lib
ifneq ($(wildcard $(LLVM_BPF_LIB)/libclang.so),)
  CARGO_PKG_VARS+= LIBCLANG_PATH=$(LLVM_BPF_LIB)
endif

# boring-sys and meow-lwip run bindgen's clang over target headers. clang
# knows nothing about the OpenWrt toolchain layout: the libc headers are in
# $(TOOLCHAIN_DIR)/include (not usr/include, where --sysroot would look),
# the compiler builtin headers (stddef.h) next to the target gcc's libgcc.a
# and the package headers in $(STAGING_DIR)/usr/include.
CARGO_PKG_VARS+= \
	BINDGEN_EXTRA_CLANG_ARGS="--target=$(REAL_GNU_TARGET_NAME) --sysroot=$(TOOLCHAIN_DIR) -isystem $(dir $(LIBGCC_A))include -isystem $(TOOLCHAIN_DIR)/include -I$(STAGING_DIR)/usr/include"

# meow-app is the CLI entry point; the workspace resolver picks up all
# workspace crates from the lockfile at crates/meow-app.
MAKE_PATH:=crates/meow-app

# Default features = `full`: all proxy protocols (ss, trojan, vless, vmess,
# snell, hysteria2, anytls), DNS server/encrypted, and the mixed/http/socks5/
# tproxy/tun listeners. Requires BoringSSL (cmake + C++ compiler) via
# boring-sys/quiche. Disable with `--no-default-features` if needed, but the
# release binaries ship `full`.
RUST_PKG_FEATURES:=

define Package/meow-rs
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A high-performance, rule-based tunneling proxy in Rust
  URL:=https://github.com/meow-rs/meow-rs
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libstdcpp +ca-bundle +ip-full +kmod-inet-diag +kmod-nft-tproxy +kmod-tun
  USERID:=meow=5589:meow=5589
endef

define Package/meow-rs/description
  A high-performance Rust implementation of the mihomo (Clash Meta) proxy
  kernel. Rule-based tunneling with support for multiple proxy protocols,
  transparent proxy, DNS snooping, a REST API, and a built-in web dashboard.
endef

define Package/meow-rs/conffiles
/etc/config/meow-rs
/etc/meow-rs/
endef

define Package/meow-rs/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/meow $(1)/usr/bin/meow-rs

	$(INSTALL_DIR) $(1)/etc/meow-rs
	$(INSTALL_DATA) ./files/config.yaml $(1)/etc/meow-rs/config.yaml

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/meow-rs.config $(1)/etc/config/meow-rs
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/meow-rs.init $(1)/etc/init.d/meow-rs
	$(INSTALL_DIR) $(1)/etc/capabilities
	$(INSTALL_DATA) ./files/meow-rs.json $(1)/etc/capabilities/meow-rs.json
endef

$(eval $(call RustBinPackage,meow-rs))
$(eval $(call BuildPackage,meow-rs))
