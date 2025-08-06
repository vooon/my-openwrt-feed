include $(TOPDIR)/rules.mk

PKG_NAME:=proxmox-backup
PKG_VERSION:=4.0.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://git.proxmox.com/git/proxmox-backup.git
PKG_MIRROR_HASH:=59e5d48be14f9baaa8357c64fbfe3f769e121c94c01d5dcae067154e2d3d7bbd
# NOTE: version 4.0.5-1, there is no tag
#PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_VERSION:=7616c0a2ed079204c3a333622a0c5ef2b3469350

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=AGPL-3.0

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
#include ../../lang/rust/rust-package.mk
include ../../packages/lang/rust/rust-package.mk

define Package/proxmox-backup/Default
  SECTION:=utils
  CATEGORY:=Utilities
  URL:=https://www.proxmox.com/en/products/proxmox-backup-server/overview
  DEPENDS:=$(RUST_ARCH_DEPENDS) +libacl +libfuse3 +libopenssl +libzstd
endef

define Package/proxmox-backup/Default/description
Proxmox Backup Server is an enterprise backup solution, for backing up and restoring VMs, containers, and physical hosts.
By supporting incremental, fully deduplicated backups, Proxmox Backup Server significantly reduces network load and saves valuable storage space.
With strong encryption and methods of ensuring data integrity, you can feel safe when backing up data, even to targets which are not fully trusted.
endef

define Package/proxmox-backup-client
  $(call Package/proxmox-backup/Default)
  TITLE:=Proxmox Backup Client
  DEPENDS+= +pxar +qrencode
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

# define Package/proxmox-file-restore
#   $(call Package/proxmox-backup/Default)
#   TITLE:=Proxmox Backup File Restore
# endef
#
# define Package/proxmox-file-restore/description
# $(call Package/proxmox-backup/Default/description)
#
# Restore files from a backup snapshot.
# endef

CARGO_PKG_VARS += \
	CARGO_NET_GIT_FETCH_WITH_CLI=true \
	BINDGEN_EXTRA_CLANG_ARGS="-v --target=$(GNU_TARGET_NAME) --sysroot=$(STAGING_DIR) --gcc-install-dir=$(dir $(LIBGCC_A)) -I $(dir $(LIBGCC_A))/include" \
	CFLAGS="-I$(STAGING_DIR)/usr/include" \


define Build/Compile

	cd $(PKG_BUILD_DIR); \
	$(CARGO_PKG_VARS) \
	cargo build -v \
		--release \
		$(if $(CONFIG_PACKAGE_proxmox-backup-client),--package proxmox-backup-client) \
		$(if $(CONFIG_PACKAGE_pxar),--package pxar-bin) \
		$(if $(CONFIG_PACKAGE_proxmox-file-restore),--package proxmox-file-restore) \

endef

define Package/proxmox-backup-client/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/proxmox-backup-client $(1)/usr/bin/
endef

define Package/pxar/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/pxar $(1)/usr/bin/
endef

# define Package/proxmox-file-restore/install
# 	$(INSTALL_DIR) $(1)/usr/bin
# 	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/proxmox-file-restore $(1)/usr/bin/
# endef

$(eval $(call RustBinPackage,proxmox-backup-client))
$(eval $(call BuildPackage,proxmox-backup-client))
$(eval $(call BuildPackage,pxar))
#$(eval $(call BuildPackage,proxmox-file-restore))
