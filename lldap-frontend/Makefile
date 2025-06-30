include $(TOPDIR)/rules.mk

PKG_NAME:=lldap-frontend
PKG_VERSION:=0.6.1
PKG_RELEASE:=1

# XXX NOTE: OpenWRT does not have Rust WASM compiller, so instead to building just package prebuilt files.
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/lldap/lldap/releases/download/v$(PKG_VERSION)/amd64-lldap.tar.gz

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/lldap-frontend
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=lldap
  TITLE:=Light LDAP - Frontend
  URL:=https://github.com/lldap/lldap/
  ARCH:=all
endef

define Package/lldap-frontend/description
  Static files for the UI.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/lldap-frontend/install
	$(INSTALL_DIR) $(1)/usr/share/lldap/
	$(CP) -parv $(PKG_BUILD_DIR)/app $(1)/usr/share/lldap/
endef

$(eval $(call BuildPackage,lldap-frontend))
