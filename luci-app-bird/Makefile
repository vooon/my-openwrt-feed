include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-bird
PKG_VERSION:=0.6.0
PKG_RELEASE:=2

PKG_LICENSE:=LGPL-2.1+
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-bird
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=BIRD status overview
  DEPENDS:=+luci-base +rpcd-mod-bird
  ARCH:=all
endef

define Package/luci-app-bird/description
  LuCI overview of the BIRD routing daemon state (OSPF and BGP),
  similar to the WireGuard status page.
endef

define Build/Compile
endef

define Package/luci-app-bird/install
	$(INSTALL_DIR) $(1)/www
	$(CP) ./htdocs/luci-static $(1)/www/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-bird.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-bird.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-bird))
