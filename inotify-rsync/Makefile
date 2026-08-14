include $(TOPDIR)/rules.mk

PKG_NAME:=inotify-rsync
PKG_VERSION:=0.4.0
PKG_RELEASE:=2

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/inotify-rsync
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Inotify Rsync Helper script
  DEPENDS:=+ucode +ucode-mod-uloop +ucode-mod-uci +ucode-mod-log +ucode-mod-inotify +@BUSYBOX_CONFIG_INOTIFYD +@BUSYBOX_DEFAULT_INOTIFYD +rsync
  ARCH:=all
endef

define Package/inotify-rsync/description
  Script helper to rsync files on changes.
endef

define Package/inotify-rsync/conffiles
/etc/config/inotify-rsync
endef

define Package/inotify-rsync/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/inotify-rsync.conf $(1)/etc/config/inotify-rsync

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/inotify-rsync.init $(1)/etc/init.d/inotify-rsync

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(CURDIR)/files/inotify-rsync.uc $(1)/usr/libexec/inotify-rsync.uc
endef

$(eval $(call BuildPackage,inotify-rsync))
