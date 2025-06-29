include $(TOPDIR)/rules.mk

PKG_NAME:=casdoor
PKG_VERSION:=1.952.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/casdoor/casdoor.git
PKG_MIRROR_HASH:=6fc4d832eefcd3e6bf81c468ad403d15635d4da4dc69e575df4a5982338d45cc
PKG_SOURCE_DATE=2025-06-29
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/casdoor/casdoor
#GO_PKG_EXCLUDES:=examples/

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/casdoor
  SECTION:=net
  CATEGORY:=Network
  TITLE:=An open-source UI-first IAM, SSO.
  URL:=https://casdoor.com
  DEPENDS:=$(GO_ARCH_DEPENDS) +lsof +casbin-static
  USERID:=casdoor:casdoor
endef

define Package/casdoor/description
  An open-source UI-first Identity and Access Management (IAM) / Single-Sign-On (SSO) platform
  with web UI supporting OAuth 2.0, OIDC, SAML, CAS, LDAP, SCIM, WebAuthn, TOTP, MFA and RADIUS.
endef

define Package/casdoor/conffiles
/etc/config/casdoor
/etc/casdoor/app.conf
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) frontend

	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef


define Package/casdoor/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/casdoor.conf $(1)/etc/config/casdoor
	$(INSTALL_DIR) $(1)/etc/capabilities/
	$(INSTALL_DATA) $(CURDIR)/files/casdoor.json $(1)/etc/capabilities/casdoor.json
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/casdoor.init $(1)/etc/init.d/casdoor
	$(INSTALL_DIR) $(1)/etc/casdoor/
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/conf/app.conf $(1)/etc/casdoor/app.conf
	$(INSTALL_DIR) $(1)/usr/share/casdoor/web/
	$(CP) -parv $(PKG_BUILD_DIR)/web/build $(1)/usr/share/casdoor/web/build
	$(CP) -parv $(PKG_BUILD_DIR)/swagger $(1)/usr/share/casdoor/
endef

$(eval $(call BuildPackage,casdoor))
