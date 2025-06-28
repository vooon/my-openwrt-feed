include $(TOPDIR)/rules.mk

PKG_NAME:=zitadel
PKG_VERSION:=3.3.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/zitadel/zitadel.git
PKG_SOURCE_DATE=2025-06-28
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=885ac2bc50609050199940ad5bcd2e07a87906ca308016879a2e812a7ff4abe4

PKG_LICENSE:=AGPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host zitadel/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/zitadel/zitadel
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/host-build.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-host-build.mk

define Package/zitadel
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Identity infrastructure, simplified for you.
  URL:=https://zitadel.com
  # DEPENDS:=$(GO_ARCH_DEPENDS) +pgsql-server
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

define Host/Compile
	$(GO_GENERAL_BUILD_CONFIG_VARS) \
	$(GO_HOST_BUILD_CONFIG_VARS) \
	$(GO_HOST_VARS) \
	$(MAKE) $(HOST_MAKE_FLAGS) -C $(HOST_BUILD_DIR) core_api
endef

define Host/Install
	$(call GoHost/Host/Install,$(1))
endef

define Build/Compile
	$(GO_GENERAL_BUILD_CONFIG_VARS) \
	$(GO_PKG_BUILD_CONFIG_VARS) \
	$(GO_PKG_VARS) \
	$(MAKE) -C $(PKG_BUILD_DIR) compile VERSION=$(PKG_VERSION)
endef

define Package/zitadel/install

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/zitadel.conf $(1)/etc/config/zitadel
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/zitadel.init $(1)/etc/init.d/zitadel
endef

$(eval $(call BuildPackage,zitadel))
$(eval $(call HostBuild))
