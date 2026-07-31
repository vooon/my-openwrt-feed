include $(TOPDIR)/rules.mk

PKG_NAME:=nylon
PKG_VERSION:=0.4.5
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/encodeous/nylon.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/encodeous/nylon

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/nylon
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Self-healing WireGuard mesh with Babel routing
  URL:=https://github.com/encodeous/nylon
  DEPENDS:=$(GO_ARCH_DEPENDS) +kmod-tun +ip-full +ca-bundle
endef

define Package/nylon/description
  Nylon is a self-healing WireGuard mesh that routes around failures.
  If a link goes down, nylon reroutes traffic through the next-best path
  in seconds. Implements the Babel routing protocol (RFC 8966) on top of
  a modified wireguard-go, using measured latency as the routing metric.
endef

define Package/nylon/conffiles
/etc/config/nylon
/etc/nylon/
endef

define Package/nylon/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/nylon $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/nylon.conf $(1)/etc/config/nylon

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/nylon.init $(1)/etc/init.d/nylon

	$(INSTALL_DIR) $(1)/etc/nylon
endef

$(eval $(call BuildPackage,nylon))
