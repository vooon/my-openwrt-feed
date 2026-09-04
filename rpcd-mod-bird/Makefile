include $(TOPDIR)/rules.mk

PKG_NAME:=rpcd-mod-bird
PKG_VERSION:=0.5.0
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-2.1+
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/rpcd-mod-bird
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=BIRD control socket rpcd module
  DEPENDS:=+rpcd-mod-ucode +ucode-mod-socket +ucode-mod-log +ucode-mod-fs
  ARCH:=all
endef

define Package/rpcd-mod-bird/description
  Exposes the BIRD routing daemon control socket via ubus as a ucode rpcd
  plugin.
endef

define Build/Compile
endef

define Package/rpcd-mod-bird/install
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./src/bird.uc $(1)/usr/share/rpcd/ucode/bird.uc
	$(INSTALL_DATA) ./src/birdconfig.uc $(1)/usr/share/rpcd/ucode/birdconfig.uc
endef

define Package/rpcd-mod-bird/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload
endef

$(eval $(call BuildPackage,rpcd-mod-bird))
