include $(TOPDIR)/rules.mk

LUCI_TITLE:=BIRD status overview
LUCI_DESCRIPTION:=LuCI overview of the BIRD routing daemon state (OSPF and BGP), similar to the WireGuard status page.
LUCI_DEPENDS:=+luci-base +rpcd-mod-bird
LUCI_PKGARCH:=all

LUCI_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=LGPL-2.1+

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
