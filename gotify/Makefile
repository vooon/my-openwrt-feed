include $(TOPDIR)/rules.mk

PKG_NAME:=gotify
PKG_VERSION:=2.6.3
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/gotify/server.git
PKG_SOURCE_DATE=2025-06-28
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=885ac2bc50609050199940ad5bcd2e07a87906ca308016879a2e812a7ff4abe4

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/gotify/server
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
# include $(INCLUDE_DIR)/host-build.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk
#include ../../packages/lang/golang/golang-host-build.mk

define Package/gotify
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A simple server for sending and receiving messages in real-time.
  URL:=https://gotify.net
  # DEPENDS:=$(GO_ARCH_DEPENDS)
  DEPENDS:=$(GO_ARCH_DEPENDS)
  USERID:=gotify:gotify
endef

define Package/gotify/description
  We wanted a simple server for sending and receiving messages (in real time per WebSocket).
  For this, not many open source projects existed and most of the existing ones were abandoned.
  Also, a requirement was that it can be self-hosted. We know there are many free and commercial push services out there.
endef

define Package/gotify/conffiles
/etc/config/gotify
endef

define Host/Compile
endef

define Package/gotify/install
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/gotify.conf $(1)/etc/config/gotify
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/gotify.init $(1)/etc/init.d/gotify
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/gotify $(1)/usr/bin/gotify
endef

$(eval $(call BuildPackage,gotify))
