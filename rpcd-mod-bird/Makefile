include $(TOPDIR)/rules.mk

PKG_NAME:=rpcd-mod-bird
PKG_VERSION:=0.3.0
PKG_RELEASE:=1

PKG_LICENSE:=LGPL-2.1+

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

# data-only package: nothing to prepare/configure/compile
define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/rpcd-mod-bird
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=BIRD control socket rpcd module
  DEPENDS:=+rpcd-mod-ucode +ucode-mod-socket +ucode-mod-log
  MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
endef

define Package/rpcd-mod-bird/description
  Exposes the BIRD routing daemon control socket via ubus as a ucode rpcd
  plugin.  Provides:

    bird query   - raw command passthrough returning { code, stdout }
    bird status  - read-only structured snapshot of daemon/protocols,
                   OSPF/BGP/BFD state

  The parser uses ucode match() (the same POSIX engine as
  prometheus-node-exporter-ucode's bird.uc) to avoid musl/glibc regex
  differences.
endef

define Package/rpcd-mod-bird/install
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./src/bird.uc $(1)/usr/share/rpcd/ucode/bird.uc
endef

define Package/rpcd-mod-bird/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload
endef

$(eval $(call BuildPackage,rpcd-mod-bird))
