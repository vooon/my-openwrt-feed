include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-bird
PKG_VERSION:=0.3.0
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-2.1+

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

# data-only package: nothing to prepare/configure/compile
define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-bird
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=BIRD status overview
  DEPENDS:=+luci-base +rpcd-mod-bird
  MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
endef

define Package/luci-app-bird/description
  Read-only LuCI overview of the BIRD routing daemon state (OSPF and BGP),
  similar to the WireGuard status page.  Backed by the read-only
  "bird status" rpcd method (query only "show" commands).
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
