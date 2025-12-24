include $(TOPDIR)/rules.mk

PKG_NAME:=netbird-mgmt
PKG_VERSION:=0.60.9
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/netbirdio/netbird.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Wesley Gimenes <wehagy@proton.me>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/netbirdio/netbird
GO_PKG_BUILD_PKG:=$(GO_PKG)/management $(GO_PKG)/relay $(GO_PKG)/signal
GO_PKG_LDFLAGS_X:=$(GO_PKG)/version.version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/netbird-mgmt
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=NetBird Management server
  URL:=https://netbird.io
  DEPENDS:=$(GO_ARCH_DEPENDS) +coturn +uhttpd
endef

define Package/netbird-mgmt/description
  NetBird is an open-source VPN management platform built on top of WireGuard® making it easy to create
  secure private networks for your organization or home.

  It requires zero configuration effort leaving behind the hassle of opening ports, complex firewall rules, VPN
  gateways, and so forth.
endef

define Package/netbird-mgmt/conffiles
/etc/config/netbird-mgmt
/etc/netbird/
endef

define Package/netbird-mgmt/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/management $(1)/usr/bin/netbird-mgmt
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/relay $(1)/usr/bin/netbird-relay
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/signal $(1)/usr/bin/netbird-signal

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/netbird-mgmt.config $(1)/etc/config/netbird-mgmt

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/netbird-mgmt.init $(1)/etc/init.d/netbird-mgmt

	$(INSTALL_DIR) $(1)/etc/netbird
endef

$(eval $(call GoBinPackage,netbird-mgmt))
$(eval $(call BuildPackage,netbird-mgmt))
