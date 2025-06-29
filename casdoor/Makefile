include $(TOPDIR)/rules.mk

PKG_NAME:=casdoor
PKG_VERSION:=1.952.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/casdoor/casdoor.git
PKG_SOURCE_DATE=2025-06-29
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=

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
  DEPENDS:=$(GO_ARCH_DEPENDS)
  USERID:=casdoor:casdoor
endef

define Package/casdoor/description
  An open-source UI-first Identity and Access Management (IAM) / Single-Sign-On (SSO) platform
  with web UI supporting OAuth 2.0, OIDC, SAML, CAS, LDAP, SCIM, WebAuthn, TOTP, MFA and RADIUS.
endef

define Package/casdoor/conffiles
/etc/config/casdoor
/etc/casdoor/app.ini
endef

define Host/Compile
	# XXX: do on host
	# npm install sass
endef

define Host/Install
endef

#define Build/Compile
#endef

define Package/casdoor/install
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/casdoor.conf $(1)/etc/config/casdoor
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/casdoor.init $(1)/etc/init.d/casdoor
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/casdoor $(1)/usr/bin/casdoor
endef

$(eval $(call BuildPackage,casdoor))
$(eval $(call HostBuild))
