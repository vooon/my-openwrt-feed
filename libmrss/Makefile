#
# Copyright (C) 2006-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=libmrss
PKG_VERSION:=0.19.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=http://www.autistici.org/bakunin/libmrss/
PKG_MD5SUM:=a6f66b72898d27270e3a68007f90d62b

PKG_LICENSE:=LGPL2
PKG_LICENSE_FILES:=COPYING

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(INCLUDE_DIR)/package.mk

TARGET_CFLAGS += $(FPIC)

define Package/libmrss
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=mRss feed parser
DEPENDS:=+libnxml
  URL:=http://www.autistici.org/bakunin/libmrss/doc/
endef

define Package/libmrss/description
 mRss is a C library for parsing, writing and creating RSS/ATOM files or streams.
endef

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/usr/include/* $(1)/usr/include/
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libmrss.{a,so*} $(1)/usr/lib/
	$(INSTALL_DIR) $(1)/usr/lib/pkgconfig
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/pkgconfig/mrss.pc $(1)/usr/lib/pkgconfig/
endef

define Package/libmrss/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/libmrss.so.* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,libmrss))
