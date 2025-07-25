include $(TOPDIR)/rules.mk

PKG_NAME:=gotify
PKG_VERSION:=2.6.3
PKG_RELEASE:=2

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/gotify/server.git
PKG_SOURCE_DATE=2025-06-28
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=bf9cb4c2c177e0c2049aa5078a535bfb278e29a75698cdd6929f8fb6724dd239

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/gotify/server
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/gotify
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A simple server for sending and receiving messages in real-time.
  URL:=https://gotify.net
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
/etc/gotify/config.yml
endef

GO_PKG_INSTALL_ARGS += -ldflags="-s -w -X main.Mode=prod"

define Build/Compile
	(cd "$(PKG_BUILD_DIR)/ui"; yarn install)
	$(MAKE) -C $(PKG_BUILD_DIR) build-js

	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/gotify/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/server $(1)/usr/bin/gotify

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/gotify.conf $(1)/etc/config/gotify
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/gotify.init $(1)/etc/init.d/gotify
	#$(INSTALL_DIR) $(1)/etc/gotify/
	#$(INSTALL_CONF) $(PKG_BUILD_DIR)/config.example.yml $(1)/etc/gotify/config.yml

	# $(INSTALL_DIR) $(1)/var/lib/gotify/images
	# $(INSTALL_DIR) $(1)/var/lib/gotify/acme_cache
	$(INSTALL_DIR) $(1)/usr/lib/gotify
endef

$(eval $(call BuildPackage,gotify))
