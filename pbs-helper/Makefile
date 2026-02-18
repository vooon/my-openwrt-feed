include $(TOPDIR)/rules.mk

PKG_NAME:=pbs-helper
PKG_VERSION:=0.2.0
PKG_RELEASE:=2

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/pbs-helper
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Proxmox Backup Helper script
  DEPENDS:=proxmox-backup-client +jshn +curl
  ARCH:=all
endef

define Package/pbs-helper/description
  Script helper to backup host.
endef

define Package/pbs-helper/conffiles
/etc/pbs.env
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/pbs-helper/install
	$(INSTALL_DIR) $(1)/etc/
	$(INSTALL_CONF) $(CURDIR)/files/pbs.env $(1)/etc/pbs.env

	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(CURDIR)/files/pbs.sh $(1)/usr/bin/pbs.sh
endef

$(eval $(call BuildPackage,pbs-helper))
