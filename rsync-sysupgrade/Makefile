include $(TOPDIR)/rules.mk

PKG_NAME:=rsync-sysupgrade
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/rsync-sysupgrade
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Sysupgrade via rsync
  DEPENDS:=+rsync
  ARCH:=all
endef

define Package/rsync-sysupgrade/description
  Simple wrapper around rsync and sysupgrade.
  Configure rsync server feed and firmware filename once in UCI,
  then run 'rsync-sysupgrade' to fetch and flash.
endef

define Package/rsync-sysupgrade/conffiles
/etc/config/rsync-sysupgrade
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/rsync-sysupgrade/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/rsync-sysupgrade.conf $(1)/etc/config/rsync-sysupgrade

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CURDIR)/files/rsync-sysupgrade.sh $(1)/usr/bin/rsync-sysupgrade
endef

$(eval $(call BuildPackage,rsync-sysupgrade))
