include $(TOPDIR)/rules.mk

PKG_NAME:=qemu-instance-init
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/qemu-instance-init
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU:=Virtualization
  TITLE:=QEMU Instance init.d helper
  DEPENDS:=@TARGET_x86_64:qemu-x86_64-softmmu +proxmox-backup-client +curl +uuidgen +jshn +socat
  ARCH:=all
endef

define Package/qemu-instance-init/description
  Init script for qemu vm.
endef

define Package/qemu-instance-init/conffiles
/etc/config/qemu
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/qemu-instance-init/install
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/qemu.conf $(1)/etc/config/qemu

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/qemu.init $(1)/etc/init.d/qemu
endef

$(eval $(call BuildPackage,qemu-instance-init))
