include $(TOPDIR)/rules.mk

PKG_NAME:=ddns-dhcp-sync
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=ASL-2.0
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/ddns-dhcp-sync
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Sync local DHCP static hosts with DDNS
  DEPENDS:=+jshn +curl
  ARCH:=all
endef

define Package/ddns-dhcp-sync/description
  Script helper to sync static hosts lease addresses with DDNS server.
endef

define Package/ddns-dhcp-sync/conffiles
/etc/config/ddns-dhcp-sync
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/ddns-dhcp-sync/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/ddns-dhcp-sync.conf $(1)/etc/config/ddns-dhcp-sync

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/ddns-dhcp-sync.init $(1)/etc/init.d/ddns-dhcp-sync

	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(CURDIR)/files/ddns-dhcp-sync.sh $(1)/usr/bin/ddns-dhcp-sync.sh
endef

$(eval $(call BuildPackage,ddns-dhcp-sync))
