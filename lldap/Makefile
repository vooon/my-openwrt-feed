include $(TOPDIR)/rules.mk

PKG_NAME:=lldap
PKG_VERSION:=0.6.1
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/lldap/lldap.git
PKG_MIRROR_HASH:=b64c30a1f9ad724d54f93cde6b789846e1963a45c992791869d462001593a3cd
PKG_SOURCE_DATE=2025-06-11
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
#include ../../lang/rust/rust-package.mk
include ../../packages/lang/rust/rust-package.mk

define Package/lldap
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=$(RUST_ARCH_DEPENDS)
  TITLE:=Light LDAP implementation
  URL:=https://github.com/lldap/lldap/
  USERID:=lldap=389:lldap=389
endef

define Package/lldap/Default/description
  This project is a lightweight authentication server that provides an opinionated, simplified LDAP interface for authentication.
  It integrates with many backends, from KeyCloak to Authelia to Nextcloud and more!
endef

define Package/lldap/description
$(call Package/lldap/Default/description)

Server.
endef

define Package/lldap/conffiles
/etc/config/lldap
endef

define Package/lldap-migration-tool
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=$(RUST_ARCH_DEPENDS) lldap
  TITLE:=Light LDAP Migration Tool
  URL:=https://github.com/lldap/lldap/
endef

define Package/lldap/description
$(call Package/lldap/Default/description)

Migration Tool.
endef

# FIX: Unable to update https://github.com/inejge/ldap3/
CARGO_PKG_VARS += \
	CARGO_NET_GIT_FETCH_WITH_CLI=true \

define Build/Compile
	$(call Build/Compile/Cargo,server)
	$(call Build/Compile/Cargo,set-password)
	$(call Build/Compile/Cargo,migration-tool)

	# XXX TODO: build App WASM

endef

define Package/lldap/install
	$(INSTALL_DIR) $(1)/etc/lldap
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/lldap.init $(1)/etc/init.d/lldap
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/lldap $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/lib/lldap
endef

$(eval $(call RustBinPackage,lldap))
$(eval $(call BuildPackage,lldap))
