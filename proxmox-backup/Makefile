include $(TOPDIR)/rules.mk

PKG_NAME:=proxmox-backup
PKG_VERSION:=3.4.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://git.proxmox.com/git/proxmox-backup.git
PKG_MIRROR_HASH:=b64c30a1f9ad724d54f93cde6b789846e1963a45c992791869d462001593a3cd
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=AGPL-3.0

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
#include ../../lang/rust/rust-package.mk
include ../../packages/lang/rust/rust-package.mk

define Package/proxmox-backup/Default
  SECTION:=net
  CATEGORY:=Network
  SECTION:=utils
  CATEGORY:=Utilities
  URL:=https://www.proxmox.com/en/products/proxmox-backup-server/overview
  DEPENDS:=$(RUST_ARCH_DEPENDS)
endef

define Package/proxmox-backup/Default/description
Proxmox Backup Server is an enterprise backup solution, for backing up and restoring VMs, containers, and physical hosts.
By supporting incremental, fully deduplicated backups, Proxmox Backup Server significantly reduces network load and saves valuable storage space.
With strong encryption and methods of ensuring data integrity, you can feel safe when backing up data, even to targets which are not fully trusted.
endef

define Package/proxmox-backup-client
  $(call Package/proxmox-backup/Default)
  TITLE:=Proxmox Backup Client
endef

define Package/proxmox-backup-client/description
$(call Package/proxmox-backup/Default/description)

The command-line client for Proxmox Backup Server is called proxmox-backup-client.
endef

define Package/pxar
  $(call Package/proxmox-backup/Default)
  TITLE:=Proxmox Backup PXAR utility
endef

define Package/pxar/description
$(call Package/proxmox-backup/Default/description)

Pxar is a command-line utility for creating and manipulating archives in the Proxmox File Archive Format (.pxar).
endef

define Package/proxmox-file-restore
  $(call Package/proxmox-backup/Default)
  TITLE:=Proxmox Backup File Restore
endef

define Package/proxmox-file-restore/description
$(call Package/proxmox-backup/Default/description)

Restore files from a backup snapshot.
endef


# FIX: Unable to update https://github.com/inejge/ldap3/
#CARGO_PKG_VARS += \
#	CARGO_NET_GIT_FETCH_WITH_CLI=true \

define Build/Compile

	cd $(PKG_BUILD_DIR); \
	$(CARGO_PKG_VARS) \
	cargo build -v \
		--release \
		--package proxmox-backup \
		$(if $(CONFIG_PACKAGE_proxmox-backup-migration-tool),--package proxmox-backup_migration_tool) \
		$(if $(CONFIG_PACKAGE_proxmox-backup-set-password),--package proxmox-backup_set_password) \

endef

define Package/proxmox-backup/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/proxmox-backup $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(CURDIR)/files/proxmox-backup.sh $(1)/usr/libexec/proxmox-backup

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/proxmox-backup.init $(1)/etc/init.d/proxmox-backup

	$(INSTALL_DIR) $(1)/etc/capabilities/
	$(INSTALL_DATA) $(CURDIR)/files/proxmox-backup.json $(1)/etc/capabilities/proxmox-backup.json

	# $(INSTALL_DIR) $(1)/etc/proxmox-backup
	# $(INSTALL_CONF) $(PKG_BUILD_DIR)/proxmox-backup_config.docker_template.toml $(1)/etc/proxmox-backup/proxmox-backup_config.toml

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/proxmox-backup.conf $(1)/etc/config/proxmox-backup
endef

define Package/proxmox-backup-migration-tool/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/proxmox-backup_migration_tool $(1)/usr/bin/
endef

define Package/proxmox-backup-set-password/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/proxmox-backup_set_password $(1)/usr/bin/
endef

$(eval $(call RustBinPackage,proxmox-backup-client))
$(eval $(call RustBinPackage,pxar))
$(eval $(call RustBinPackage,proxmox-file-restore))
$(eval $(call BuildPackage,proxmox-backup-client))
