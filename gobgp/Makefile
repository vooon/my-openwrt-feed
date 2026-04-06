include $(TOPDIR)/rules.mk

PKG_NAME:=gobgp
PKG_VERSION:=4.4.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/osrg/gobgp.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/osrg/gobgp/v4
GO_PKG_BUILD_PKG:= \
	$(if $(CONFIG_PACKAGE_gobgp),github.com/osrg/gobgp/v4/cmd/gobgp) \
	$(if $(CONFIG_PACKAGE_gobgpd),github.com/osrg/gobgp/v4/cmd/gobgpd)

ifeq ($(strip $(GO_PKG_BUILD_PKG)),)
GO_PKG_BUILD_PKG:=github.com/osrg/gobgp/v4/cmd/gobgp
endif

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/gobgp/Default
  SECTION:=net
  CATEGORY:=Network
  URL:=https://github.com/osrg/gobgp
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/gobgp
  $(call Package/gobgp/Default)
  TITLE:=GoBGP CLI
endef

define Package/gobgpd
  $(call Package/gobgp/Default)
  TITLE:=GoBGP daemon
endef

define Package/gobgp/description
  GoBGP command line client.
endef

define Package/gobgpd/description
  GoBGP daemon binary.
endef

define Package/gobgp/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/gobgp $(1)/usr/bin/
endef

define Package/gobgpd/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/gobgpd $(1)/usr/sbin/
endef

$(eval $(call BuildPackage,gobgp))
$(eval $(call BuildPackage,gobgpd))
