include $(TOPDIR)/rules.mk

PKG_NAME:=netifd-proto-dummy
PKG_RELEASE:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/netifd-proto-dummy
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Dummy interface netifd protocol
  PKGARCH:=all
  DEPENDS:=+kmod-dummy +ip
endef

define Package/netifd-proto-dummy/description
  Creates Linux dummy interfaces straight from /etc/config/network:

    config interface 'dummy_vip'
        option proto   'dummy'
        option macaddr '00:11:22:33:44:55'
        list   ipaddr  '192.168.99.1/24'

  On ifup the plugin runs 'ip link add <iface> type dummy' and hands the
  device over to netifd, on ifdown the device is removed again.
endef

define Build/Compile
endef

define Package/netifd-proto-dummy/install
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/lib/netifd/proto/dummy.sh $(1)/lib/netifd/proto/dummy.sh
endef

$(eval $(call BuildPackage,netifd-proto-dummy))