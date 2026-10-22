include $(TOPDIR)/rules.mk

PKG_NAME:=pbs-helper
PKG_VERSION:=0.5.3
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/pbs-helper
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Proxmox Backup Helper script
  DEPENDS:=proxmox-backup-client +ca-bundle \
    +ucode +ucode-mod-fs +ucode-mod-log +ucode-mod-uci \
    +ucode-mod-uclient +ucode-mod-uloop
  ARCH:=all
endef

define Package/pbs-helper/description
  Back up the host to Proxmox Backup Server (pbs-backup), with optional
  Healthchecks and Gotify reporting. Also ships the shared ucode job
  runner (pbs.helper) used by qemu-instance-init.
  HTTPS reporting needs a libustream-* SSL library.
endef

define Package/pbs-helper/conffiles
/etc/config/pbs
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/pbs-helper/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/pbs.conf $(1)/etc/config/pbs

	$(INSTALL_DIR) $(1)/usr/share/ucode/pbs
	$(INSTALL_DATA) $(CURDIR)/files/helper.uc $(1)/usr/share/ucode/pbs/helper.uc

	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(CURDIR)/files/pbs-backup.uc $(1)/usr/bin/pbs-backup
	$(INSTALL_BIN) $(CURDIR)/files/pbs.sh $(1)/usr/bin/pbs.sh
endef

$(eval $(call BuildPackage,pbs-helper))
