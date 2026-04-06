include $(TOPDIR)/rules.mk

PKG_NAME:=vpn-sticky
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/vpn-sticky
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Sticky VPN policy routing with connmark propagation
  PKGARCH:=all
  DEPENDS:=+ip-full +nftables +ucode +ucode-mod-uci
endef

define Package/vpn-sticky/description
  Maintains per-interface route tables and marks connections so LAN return
  traffic follows the originating VPN tunnel.
endef

define Package/vpn-sticky/conffiles
/etc/config/vpn-sticky
endef

define Build/Compile
endef

define Package/vpn-sticky/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/vpn-sticky.init $(1)/etc/init.d/vpn-sticky

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/vpn-sticky.conf $(1)/etc/config/vpn-sticky

	$(INSTALL_DIR) $(1)/usr/share/vpn-sticky
	$(INSTALL_DATA) ./files/vpn-sticky.nft.uc $(1)/usr/share/vpn-sticky/vpn-sticky.nft.uc
endef

define Package/vpn-sticky/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	changed=0
	for sec in $$(uci -q show firewall | sed -n "s/^firewall\\.\\(@include\\[[0-9]\\+\\]\\)\\.path='\\/usr\\/share\\/vpn-sticky\\/vpn-sticky\\.include'$$/\\1/p"); do
		uci -q delete "firewall.$$sec"
		changed=1
	done
	[ "$$changed" -eq 0 ] || uci -q commit firewall

	rm -f /etc/hotplug.d/iface/99-vpn-sticky
	rm -f /etc/vpn-sticky.nft /usr/sbin/vpn-sticky-apply
	rm -f /etc/uci-defaults/90-vpn-sticky-firewall
fi
exit 0
endef

define Package/vpn-sticky/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	changed=0
	for sec in $$(uci -q show firewall | sed -n "s/^firewall\\.\\(@include\\[[0-9]\\+\\]\\)\\.path='\\/usr\\/share\\/vpn-sticky\\/vpn-sticky\\.include'$$/\\1/p"); do
		uci -q delete "firewall.$$sec"
		changed=1
	done
	[ "$$changed" -eq 0 ] || uci -q commit firewall
	/etc/init.d/vpn-sticky stop >/dev/null 2>&1 || true
fi
exit 0
endef

$(eval $(call BuildPackage,vpn-sticky))
