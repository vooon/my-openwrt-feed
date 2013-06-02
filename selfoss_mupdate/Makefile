#
# Copyright (C) 2008 Freifunk Leipzig
# Copyright (C) 2008-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=selfoss_mupdate
PKG_VERSION:=2013-05-17

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=git://github.com/vooon/selfoss_mupdate.git
PKG_SOURCE_VERSION:=7057bc5bb1b6b6d844faf2132e04ea2b851ddba2
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION).tar.gz

PKG_LICENSE:=GPLv3

include $(INCLUDE_DIR)/package.mk

CONFIG_BUILD_NLS=1
include $(INCLUDE_DIR)/nls.mk

define Package/selfoss_mupdate
$(call Package/selfoss_mupdate/Default)
  SECTION:=lang
  CATEGORY:=Utilities
  SUBMENU:=
  DEPENDS:=+libmrss +libtidy +libsqlite3 +libjson +libiconv-full
  TITLE:=Selfoss mupdater (EXPERIMENTAL)
  URL:=http://todo
  MAINTAINER:=Vladimir <vooon341@gmail.com>
endef

define Package/selfoss_mupdate/description
Selfoss mupdater (fast c-prog)
endef

MAKE_FLAGS += LIBS_a="" \
	      LIBS="-lmrss -lnxml -ltidy -lcurl -lsqlite3 -ljson-c -liconv"
EXTRA_CFLAGS += -std=gnu99 -flto

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src $(MAKE_FLAGS) $(MAKE_VARS)
endef

define Build/Install
	mkdir -p $(PKG_INSTALL_DIR)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/selfoss_mupdate $(PKG_INSTALL_DIR)/usr/bin
endef

define Package/selfoss_mupdate/install
	mkdir -p $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/selfoss_mupdate $(1)/usr/bin
endef

$(eval $(call BuildPackage,selfoss_mupdate))
