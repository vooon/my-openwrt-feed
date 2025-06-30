include $(TOPDIR)/rules.mk

PKG_NAME:=authelia
PKG_VERSION:=4.39.4
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/authelia/authelia.git
PKG_MIRROR_HASH:=
PKG_SOURCE_DATE=2025-06-29
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/authelia/authelia
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/authelia
  SECTION:=net
  CATEGORY:=Network
  TITLE:=The Single Sign-On Multi-Factor
  URL:=https://authelia.com
  DEPENDS:=$(GO_ARCH_DEPENDS)
  USERID:=authelia:authelia
endef

define Package/authelia/description
  Authelia is an open-source authentication and authorization server
  providing two-factor authentication and single sign-on (SSO) for your
  applications via a web portal.
  It acts as a companion for reverse proxies by allowing, denying, or redirecting requests.
endef

define Package/authelia/conffiles
/etc/config/authelia
/etc/authelia/app.conf
endef

#define Build/Compile
#	$(MAKE) -C $(PKG_BUILD_DIR) frontend
#
#	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
#endef


define Package/authelia/install
	$(call GoPackage/Package/Install/Bin,$(1))

	#$(INSTALL_BIN) $(CURDIR)/files/authelia-wrapper.sh $(1)/usr/bin/
	#$(INSTALL_DIR) $(1)/etc/config/
	#$(INSTALL_CONF) $(CURDIR)/files/authelia.conf $(1)/etc/config/authelia
	#$(INSTALL_DIR) $(1)/etc/capabilities/
	#$(INSTALL_DATA) $(CURDIR)/files/authelia.json $(1)/etc/capabilities/authelia.json
	#$(INSTALL_DIR) $(1)/etc/init.d/
	#$(INSTALL_BIN) $(CURDIR)/files/authelia.init $(1)/etc/init.d/authelia
	#$(INSTALL_DIR) $(1)/etc/authelia/
endef

$(eval $(call BuildPackage,authelia))
