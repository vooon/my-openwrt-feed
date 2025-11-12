include $(TOPDIR)/rules.mk

PKG_NAME:=gotify-alertmanager-plugin
PKG_VERSION:=0.0.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://codeberg.org/ocimea/gotify-alertmanager-plugin.git
# PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_VERSION:=36dcd9e3c183bf0d95bd8072fffed42f3b44d136
PKG_MIRROR_HASH:=

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=codeberg.org/ocimea/gotify-alertmanager-plugin
#GO_PKG_EXCLUDES:=examples/
GO_PKG_INSTALL_ARGS += -buildmode=plugin

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/gotify-alertmanager-plugin
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Gotify AlertManager Plugin
  URL:=https://codeberg.org/ocimea/gotify-alertmanager-plugin
  DEPENDS:=$(GO_ARCH_DEPENDS) gotify
endef

define Package/gotify-alertmanager-plugin/description
  This Gotify plugin allowing to receive notifications from AlertManager.
endef

define Build/Compile
	(cd $(PKG_BUILD_DIR); \
	$(GO_GENERAL_BUILD_CONFIG_VARS) \
	$(GO_PKG_BUILD_CONFIG_VARS) \
	$(GO_PKG_VARS) \
	go build $(GO_PKG_INSTALL_ARGS) -o alertmanager.so)
endef

define Package/gotify-alertmanager-plugin/install
	$(INSTALL_DIR) $(1)/usr/lib/gotify
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/alertmanager.so $(1)/usr/lib/gotify/
endef

$(eval $(call BuildPackage,gotify-alertmanager-plugin))
