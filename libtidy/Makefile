#
# Copyright (C) 2008 Freifunk Leipzig
# Copyright (C) 2008-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libtidy
PKG_VERSION:=2012-08-21

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=git://github.com/w3c/tidy-html5.git
PKG_SOURCE_VERSION:=0cf6d998431a61f1bd630e7883d4d43df4ad8ccc
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

include $(INCLUDE_DIR)/package.mk

define Package/libtidy
$(call Package/libtidy/Default)
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=HTML Tidy (HTML5 branch)
  URL:=http://github.com/w3c/tidy-html5.git
  MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
endef

define Package/libtidy/description
 HTML Tidy for HTML5 (experimental)
endef

define Build/Configure
	( cd $(PKG_BUILD_DIR) && sh ./build/gnuauto/setup.sh )
	$(call Build/Configure/Default)
endef

define Build/Install
	$(call Build/Install/Default)
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/* $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtidy.{a,so} $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtidy-0.99.so* $(1)/usr/lib/
endef

define Package/libtidy/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtidy.so $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libtidy-0.99.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libtidy))
