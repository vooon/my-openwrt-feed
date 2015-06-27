#
# Copyright (C) 2012 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=lcd4linux-glcd128x64
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/lcd4linux-glcd128x64
	SECTION:=utils
	CATEGORY:=Utilities
	DEPENDS:=@TARGET_ar71xx +lcd4linux-custom
	TITLE:=GLCD2USB 128x64 configuration
endef

define Build/Compile
endef

define Package/lcd4linux-glcd128x64/install
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DIR) $(1)/usr/share/lcd4linux
	$(INSTALL_DIR) $(1)/usr/lib/lcd4linux
	$(INSTALL_BIN) ./files/lcd4linux-glcd128x64.conf $(1)/etc/
	$(INSTALL_BIN) ./files/tux.png $(1)/usr/share/lcd4linux/
	$(INSTALL_BIN) ./files/yota-status.sh $(1)/usr/lib/lcd4linux/
endef

$(eval $(call BuildPackage,lcd4linux-glcd128x64))
