include $(TOPDIR)/rules.mk

PKG_NAME:=netifd-proto-fou
PKG_RELEASE:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/netifd-proto-fou-lib
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Shared helpers for the netifd fou tunnel protos
  PKGARCH:=all
endef

define Package/netifd-proto-fou-lib/description
  Shared /lib/netifd/fou.sh backing the fou-ip6gre and fou-ip6tnl
  netifd protocol plugins, plus the package documentation.
endef

define Package/netifd-proto-fou-lib/install
	$(INSTALL_DIR) $(1)/lib/netifd
	$(INSTALL_DATA) ./files/lib/netifd/fou.sh $(1)/lib/netifd/fou.sh
	$(INSTALL_DIR) $(1)/usr/share/doc/netifd-proto-fou
	$(INSTALL_DATA) ./README.md $(1)/usr/share/doc/netifd-proto-fou/README.md
endef

define Package/netifd-proto-fou-ip6gre
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=FOU-encapsulated GRE over IPv6 netifd protocol
  PKGARCH:=all
  DEPENDS:=+netifd-proto-fou-lib +kmod-gre6 +kmod-fou6 +ip
endef

define Package/netifd-proto-fou-ip6gre/description
  netifd protocol 'fou-ip6gre': Foo-over-UDP (FOU) encapsulated GRE tunnel
  over an IPv6 underlay, carrying both IPv4 and IPv6 payloads. Spokes tunnel
  to a hub (/128 tunnel endpoint) that the mesh routes with OSPF/BGP/ECMP;
  the hub uses 'option listen 1' to decapsulate from any spoke. The
  per-flow UDP source port (encap-sport auto) gives per-flow ECMP hashing.
endef

define Package/netifd-proto-fou-ip6gre/install
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/lib/netifd/proto/fou-ip6gre.sh $(1)/lib/netifd/proto/fou-ip6gre.sh
endef

define Package/netifd-proto-fou-ip6tnl
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=FOU-encapsulated ip6tnl netifd protocol
  PKGARCH:=all
  DEPENDS:=+netifd-proto-fou-lib +kmod-ip6-tunnel +kmod-fou6 +ip
endef

define Package/netifd-proto-fou-ip6tnl/description
  netifd protocol 'fou-ip6tnl': FOU-encapsulated ip6tnl tunnel over IPv6.
  'option mode' selects ip4ip6 (IPv4-in-IPv6, default) or ip6ip6
  (IPv6-in-IPv6). Leaner than fou-ip6gre (no GRE header) but each mode
  carries a single family.
endef

define Package/netifd-proto-fou-ip6tnl/install
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/lib/netifd/proto/fou-ip6tnl.sh $(1)/lib/netifd/proto/fou-ip6tnl.sh
endef

define Build/Compile
endef

$(eval $(call BuildPackage,netifd-proto-fou-lib))
$(eval $(call BuildPackage,netifd-proto-fou-ip6gre))
$(eval $(call BuildPackage,netifd-proto-fou-ip6tnl))