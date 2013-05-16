#
# Copyright (C) 2006-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libnxml
PKG_VERSION:=0.18.3
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=http://www.autistici.org/bakunin/libnxml/
PKG_MD5SUM:=857f43970e7f0724d28f4ddc87085daf

PKG_LICENSE:=LGPL2
PKG_LICENSE_FILES:=COPYING

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(INCLUDE_DIR)/package.mk

TARGET_CFLAGS += $(FPIC)

define Package/libnxml
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=nXML parser
DEPENDS:=+libcurl
  URL:=http://www.autistici.org/bakunin/libnxml/doc/
endef

define Package/libnxml/description
 nXML is a C library for parsing, writing and creating XML 1.0 and 1.1 files or streams.
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/* $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libnxml.{a,so*} $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/nxml.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libnxml/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libnxml.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libnxml))
