include $(TOPDIR)/rules.mk

PKG_NAME:=gotify2telegram
PKG_VERSION:=1.3.0
PKG_RELEASE:=7

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vooon/gotify2telegram.git
PKG_MIRROR_HASH:=f7a806e75b829a7e3ee6093ad080acfd0d57530af2f0861623585b82f7f1702e
# PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_VERSION:=a726e18f6eb81626e67d857ea3d0d8d070bfaffb

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/vooon/gotify2telegram
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/gotify2telegram
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Gotify forwarding plugin to Telegram.
  URL:=https://github.com/anhbh310/gotify2telegram/
  DEPENDS:=$(GO_ARCH_DEPENDS) gotify
endef

define Package/gotify2telegram/description
  This Gotify plugin forwards all received messages to Telegram through the Telegram bot.
endef

GO_PKG_INSTALL_ARGS += -ldflags '-w -s' -buildmode=plugin

define Build/Compile
	(cd $(PKG_BUILD_DIR); \
	$(GO_GENERAL_BUILD_CONFIG_VARS) \
	$(GO_PKG_BUILD_CONFIG_VARS) \
	$(GO_PKG_VARS) \
	go build $(GO_PKG_INSTALL_ARGS) -o telegram.so)
endef

define Package/gotify2telegram/install
	$(INSTALL_DIR) $(1)/usr/lib/gotify
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/telegram.so $(1)/usr/lib/gotify/
endef

$(eval $(call BuildPackage,gotify2telegram))
