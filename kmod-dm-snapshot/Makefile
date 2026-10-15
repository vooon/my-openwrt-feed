#
# Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=kmod-dm-snapshot
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(INCLUDE_DIR)/package.mk

# OpenWrt's kmod-dm forces CONFIG_DM_SNAPSHOT=n. Feed packages come after
# the core ones in the kernel config overrides (scripts/package-metadata.pl
# kconfig), so selecting this package turns it back on as a module.
define KernelPackage/dm-snapshot
  SUBMENU:=Block Devices
  TITLE:=Device-mapper snapshot target (LVM snapshots)
  DEPENDS:=+kmod-dm
  KCONFIG:= \
	CONFIG_DM_SNAPSHOT \
	CONFIG_DM_BUFIO \
	CONFIG_DM_DEBUG_BLOCK_MANAGER_LOCKING=n
  FILES:= \
	$(LINUX_DIR)/drivers/md/dm-bufio.ko \
	$(LINUX_DIR)/drivers/md/dm-snapshot.ko
  AUTOLOAD:=$(call AutoLoad,31,dm-bufio dm-snapshot)
endef

define KernelPackage/dm-snapshot/description
 Device-mapper snapshot target, needed by `lvcreate -s` (classic LVM
 snapshots), e.g. for consistent backups of LVM-backed VM disks
 (qemu-instance-init-pbs).
endef

define Build/Compile
endef

$(eval $(call KernelPackage,dm-snapshot))
