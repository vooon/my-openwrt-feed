include $(TOPDIR)/rules.mk

PKG_NAME:=lldap
PKG_VERSION:=0.6.2
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/lldap/lldap.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
#include ../../lang/rust/rust-package.mk
include ../../packages/lang/rust/rust-package.mk

# NOTE: use prebuilt webasm web-interface
FRONTEND_FILE=$(PKG_NAME)-$(PKG_VERSION)-amd64.tar.gz
define Download/lldap-frontend
  URL:=https://github.com/lldap/lldap/releases/download/v$(PKG_VERSION)/
  URL_FILE:=amd64-lldap.tar.gz
  FILE:=$(FRONTEND_FILE)
  HASH:=a69a3d547cbef17d440753a206ad94ea3735f3cf55caa292df0faf77dab3b81b
endef

define Package/lldap
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=$(RUST_ARCH_DEPENDS)
  TITLE:=Light LDAP - Server
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
# /etc/lldap/lldap_config.toml

define Package/lldap-migration-tool
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=$(RUST_ARCH_DEPENDS) lldap
  TITLE:=Light LDAP - Migration Tool
  URL:=https://github.com/lldap/lldap/
endef

define Package/lldap-migration-tool/description
$(call Package/lldap/Default/description)

Migration Tool.
endef

define Package/lldap-set-password
  SECTION:=net
  CATEGORY:=Network
  DEPENDS:=$(RUST_ARCH_DEPENDS) lldap
  TITLE:=Light LDAP - Password tool
  URL:=https://github.com/lldap/lldap/
endef

define Package/lldap-set-password/description
$(call Package/lldap/Default/description)

Password Tool.
endef


# FIX: Unable to update https://github.com/inejge/ldap3/
CARGO_PKG_VARS += \
	CARGO_NET_GIT_FETCH_WITH_CLI=true \

define Build/Compile
	# XXX: does not work.
	#$$(call Build/Compile/Cargo,server)

	cd $(PKG_BUILD_DIR); \
	$(CARGO_PKG_VARS) \
	cargo build -v \
		--release \
		--package lldap \
		$(if $(CONFIG_PACKAGE_lldap-migration-tool),--package lldap_migration_tool) \
		$(if $(CONFIG_PACKAGE_lldap-set-password),--package lldap_set_password) \

	# XXX TODO: build App WASM

endef

define Package/lldap/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/lldap $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(CURDIR)/files/lldap.sh $(1)/usr/libexec/lldap

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/lldap.init $(1)/etc/init.d/lldap

	$(INSTALL_DIR) $(1)/etc/capabilities/
	$(INSTALL_DATA) $(CURDIR)/files/lldap.json $(1)/etc/capabilities/lldap.json

	# $(INSTALL_DIR) $(1)/etc/lldap
	# $(INSTALL_CONF) $(PKG_BUILD_DIR)/lldap_config.docker_template.toml $(1)/etc/lldap/lldap_config.toml

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/lldap.conf $(1)/etc/config/lldap

	$(INSTALL_DIR) $(1)/usr/share/lldap/
	gzip -dc $(DL_DIR)/$(FRONTEND_FILE) | $(HOST_TAR) -C $(1)/usr/share/lldap $(TAR_OPTIONS) --strip-components=1 amd64-lldap/app
endef

define Package/lldap-migration-tool/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/lldap_migration_tool $(1)/usr/bin/
endef

define Package/lldap-set-password/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/lldap_set_password $(1)/usr/bin/
endef

$(eval $(call Download,lldap-frontend))
$(eval $(call RustBinPackage,lldap))
$(eval $(call BuildPackage,lldap))
$(eval $(call BuildPackage,lldap-migration-tool))
$(eval $(call BuildPackage,lldap-set-password))
