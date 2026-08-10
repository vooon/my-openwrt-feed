include $(TOPDIR)/rules.mk

PKG_NAME:=rpcd-mod-bird
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-2.1+
PKG_BUILD_FLAGS:=gc-sections

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/bird-rpcd
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=BIRD control socket rpcd module
  DEPENDS:=+rpcd
  MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
endef

define Package/bird-rpcd/description
  Exposes the BIRD routing daemon control socket via ubus so that
  sandboxed processes (e.g. the prometheus-node-exporter-ucode jail)
  can query it without direct socket access.
endef

define Package/bird-rpcd/install
	$(INSTALL_DIR) $(1)/usr/lib/rpcd
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/lib/rpcd/bird.so \
		$(1)/usr/lib/rpcd/
endef

define Package/bird-rpcd/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload
endef

$(eval $(call BuildPackage,bird-rpcd))