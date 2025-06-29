include $(TOPDIR)/rules.mk

PKG_NAME:=casbin-static
PKG_VERSION:=2025.04.21
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/casbin/static.git
PKG_MIRROR_HASH:=f7be4051929e2cdea63340ca1be62fb151dc4fe03b13000186c2b68faf19e7ae
PKG_SOURCE_DATE=2025-04-21
#PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_VERSION:=6b3f6a72898feb8858ab8a89b9a3720f72791728

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/casbin-static
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Casbin static resources like js, css, img
  URL:=https://github.com/casbin/static
  ARCH:=all
endef

define Package/casbin-static/description
  Static files for the UI.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/casbin-static/install
	$(INSTALL_DIR) $(1)/usr/share/casbin/
	find $(PKG_BUILD_DIR) -mindepth 1 -maxdepth 1 ! -name '.*' -a ! -name 'apk-*' -a ! -name 'ipkg-*' -exec $(CP) -parv {} $(1)/usr/share/casbin/static/ \;
endef

$(eval $(call BuildPackage,casbin-static))
