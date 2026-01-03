include $(TOPDIR)/rules.mk

PKG_NAME:=gotify
PKG_VERSION:=2.8.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/gotify/server.git
PKG_MIRROR_HASH:=be6d6b8da6e7a450d8e695fbbcfb90378b3db0712df1a5e0fdad3763e78a195d
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/gotify/server
GO_PKG_LDFLAGS_X:=main.Mode=prod

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
