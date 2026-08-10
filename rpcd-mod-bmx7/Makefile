include $(TOPDIR)/rules.mk

PKG_NAME:=rpcd-mod-bmx7
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-2.1+
PKG_BUILD_FLAGS:=gc-sections

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/rpcd-mod-bmx7
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=BMX7 control socket rpcd module
  DEPENDS:=+rpcd
  MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
endef

define Package/rpcd-mod-bmx7/description
  Exposes the BMX7 mesh routing daemon control socket via ubus so that
  sandboxed processes (e.g. the prometheus-node-exporter-ucode jail) can
  query it without direct socket access.
endef

define Package/rpcd-mod-bmx7/install
	$(INSTALL_DIR) $(1)/usr/lib/rpcd
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/rpcd/bmx7.so \
		$(1)/usr/lib/rpcd/
endef

define Package/rpcd-mod-bmx7/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload
endef

$(eval $(call BuildPackage,rpcd-mod-bmx7))