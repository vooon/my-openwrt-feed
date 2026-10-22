include $(TOPDIR)/rules.mk

PKG_NAME:=qemu-instance-init
PKG_VERSION:=0.6.1
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/qemu-instance-init/default
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU:=Virtualization
  TITLE:=QEMU Instance init.d helper
  DEPENDS:=@TARGET_x86_64:qemu-x86_64-softmmu +uuidgen +ucode +ucode-mod-socket
  ARCH:=all
endef

define Package/qemu-instance-init
  $(Package/qemu-instance-init/default)
  VARIANT:=base
  DEFAULT_VARIANT:=1
  CONFLICTS:=qemu-instance-init-pbs
endef

define Package/qemu-instance-init/description
  Init script for qemu vm.
endef

define Package/qemu-instance-init-pbs
  $(Package/qemu-instance-init/default)
  TITLE += with Proxmox Backup Server backup
  DEPENDS += +pbs-helper +qemu-img +kmod-dm-snapshot
  VARIANT:=pbs
  PROVIDES:=qemu-instance-init
  CONFLICTS:=qemu-instance-init
endef

define Package/qemu-instance-init-pbs/description
  Init script for qemu vm, plus `/etc/init.d/qemu backup [instance]`:
  backs up instance disks to Proxmox Backup Server, with optional
  Healthchecks and Gotify reporting.
endef

define Package/qemu-instance-init/conffiles
/etc/config/qemu
endef

Package/qemu-instance-init-pbs/conffiles = $(Package/qemu-instance-init/conffiles)

define Build/Configure
endef

define Build/Compile
endef

define Package/qemu-instance-init/install
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/qemu.conf $(1)/etc/config/qemu

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/qemu.init $(1)/etc/init.d/qemu

	$(INSTALL_DIR) $(1)/usr/share/ucode/qemu
	$(INSTALL_DATA) $(CURDIR)/files/qmp.uc $(1)/usr/share/ucode/qemu/qmp.uc

	$(INSTALL_DIR) $(1)/usr/libexec/
	$(INSTALL_BIN) $(CURDIR)/files/qemu-qmp.uc $(1)/usr/libexec/qemu-qmp
endef

define Package/qemu-instance-init-pbs/install
	$(call Package/qemu-instance-init/install,$(1))

	$(INSTALL_DATA) $(CURDIR)/files/backup.uc $(1)/usr/share/ucode/qemu/backup.uc

	$(INSTALL_DIR) $(1)/usr/libexec/
	$(INSTALL_BIN) $(CURDIR)/files/qemu-backup.uc $(1)/usr/libexec/qemu-backup
endef

$(eval $(call BuildPackage,qemu-instance-init))
$(eval $(call BuildPackage,qemu-instance-init-pbs))
