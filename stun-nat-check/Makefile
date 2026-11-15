include $(TOPDIR)/rules.mk

PKG_NAME:=stun-nat-check
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/stun-nat-check
  SECTION:=net
  CATEGORY:=Network
  TITLE:=STUN check of the NAT port mapping behaviour
  PKGARCH:=all
  DEPENDS:=+ucode +ucode-mod-socket +ucode-mod-digest
endef

define Package/stun-nat-check/description
  Asks several STUN servers from one local UDP port and compares the
  external endpoints they report: tells whether the NAT keeps one mapping
  per local port (UDP hole punching can work) or one per destination.
endef

define Build/Compile
endef

define Package/stun-nat-check/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/stun-nat-check.uc $(1)/usr/bin/stun-nat-check
endef

$(eval $(call BuildPackage,stun-nat-check))
