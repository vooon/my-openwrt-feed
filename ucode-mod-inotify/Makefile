include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-mod-inotify
PKG_RELEASE:=1
PKG_LICENSE:=ISC
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_INSTALL := 1

define Package/ucode-mod-inotify
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ucode module for the Linux inotify API
  DEPENDS:=+libucode
endef

define Package/ucode-mod-inotify/description
This module exposes the Linux inotify API to ucode, allowing scripts
to watch for filesystem events without shelling out to the inotifyd
applet (which would otherwise leak orphaned child processes when the
parent daemon is killed).
endef

define Package/ucode-mod-inotify/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/ucode/inotify.so $(1)/usr/lib/ucode/
endef

$(eval $(call BuildPackage,ucode-mod-inotify))