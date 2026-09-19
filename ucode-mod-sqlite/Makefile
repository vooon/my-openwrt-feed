include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-mod-sqlite
PKG_RELEASE:=1
PKG_LICENSE:=ISC
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_INSTALL := 1

define Package/ucode-mod-sqlite
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ucode module for the SQLite3 database engine
  DEPENDS:=+libucode +libsqlite3
endef

define Package/ucode-mod-sqlite/description
This module exposes the SQLite3 C API to ucode, allowing scripts to
open databases, execute statements and run prepared queries without
shelling out to the sqlite3 CLI.
endef

define Package/ucode-mod-sqlite/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/sqlite.so $(1)/usr/lib/ucode/
endef

$(eval $(call BuildPackage,ucode-mod-sqlite))
