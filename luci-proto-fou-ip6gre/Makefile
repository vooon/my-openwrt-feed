include $(TOPDIR)/rules.mk

LUCI_TITLE:=Support for FOU-encapsulated GRE over IPv6
LUCI_DESCRIPTION:=LuCI form for the netifd fou_ip6gre netifd protocol
LUCI_DEPENDS:=+luci-base +netifd-proto-fou-ip6gre
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
