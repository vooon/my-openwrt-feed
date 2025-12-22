include $(TOPDIR)/rules.mk

PKG_NAME:=inotify-rsync
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/inotify-rsync
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Inotify Rsync Helper script
  DEPENDS:=+@BUSYBOX_CONFIG_INOTIFYD +@BUSYBOX_DEFAULT_INOTIFYD +rsync
  ARCH:=all
endef

define Package/inotify-rsync/description
  Script helper to rsync files on changes.
endef

define Package/inotify-rsync/conffiles
/etc/config/inotify-rsync
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/inotify-rsync/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/inotify-rsync.conf $(1)/etc/config/inotify-rsync

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/inotify-rsync.init $(1)/etc/init.d/inotify-rsync
endef

$(eval $(call BuildPackage,inotify-rsync))
