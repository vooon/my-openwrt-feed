include $(TOPDIR)/rules.mk

PKG_NAME:=meow-rs
PKG_VERSION:=0.21.2
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/meow-rs/meow-rs.git
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_DATE:=2026-08-27
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
#include ../../lang/rust/rust-package.mk
include ../../packages/lang/rust/rust-package.mk

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
  DEPENDS:=$(RUST_ARCH_DEPENDS) +ca-bundle +ip-full +kmod-inet-diag +kmod-nft-tproxy +kmod-tun
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
