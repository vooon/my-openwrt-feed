include $(TOPDIR)/rules.mk

PKG_NAME:=zitadel
PKG_VERSION:=3.3.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/zitadel/zitadel.git
PKG_SOURCE_DATE=2025-06-28
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=8bbd6325e3687f9daab554a3f9e78947019571490c0131e8174a93519564ac26

PKG_LICENSE:=AGPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/zitadel/zitadel
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
include ../../lang/golang/golang-package.mk

define Package/zitadel
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Identity infrastructure, simplified for you.
  URL:=https://zitadel.com
  DEPENDS:=$(GO_ARCH_DEPENDS)
  USERID:=zitadel:zitadel
endef

define Package/zitadel/description
  With ZITADEL, you are assured of a robust and customizable
  turnkey solution for all your authentication and authorization needs.
endef

define Package/zitadel/conffiles
/etc/config/zitadel
endef

define Package/zitadel/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/zitadel.conf $(1)/etc/config/zitadel
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/zitadel.init $(1)/etc/init.d/zitadel
endef

$(eval $(call BuildPackage,zitadel))
