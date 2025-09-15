include $(TOPDIR)/rules.mk

PKG_NAME:=authelia
PKG_VERSION:=4.39.10
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/authelia/authelia.git
PKG_MIRROR_HASH:=9021b3406471d42a61210594b9e22325176f155eff32b605d7d2870db623d929
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

HOST_BUILD_DEPENDS:=node/host
PKG_BUILD_DEPENDS:=golang/host node/host authelia/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/authelia/authelia/v4/cmd/authelia

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/host-build.mk
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
/etc/authelia/configuration.yml
/etc/authelia/
endef

define Host/Compile
endef

define Host/Install
	# XXX: quite ad-hoc solution...
	npm install -g pnpm@latest-10
endef

GO_PKG_CUSTOM_LDFLAGS += \
	-w -s \
	-X github.com/authelia/authelia/v4/internal/utils.BuildTag="$(PKG_SOURCE_VERSION)" \
	-X github.com/authelia/authelia/v4/internal/utils.BuildState="tagged" \
	-X github.com/authelia/authelia/v4/internal/utils.BuildDate="$(shell date --iso-8601=s)" \


define Build/Compile
	cd $(PKG_BUILD_DIR)/web; \
	pnpm install; \
	pnpm build;

	cd $(PKG_BUILD_DIR); \
	cp -rp api ./internal/server/public_html/

	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/authelia/install
	$(call GoPackage/Package/Install/Bin,$(1))

	#$(INSTALL_BIN) $(CURDIR)/files/authelia.sh $(1)/usr/libexec/

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/authelia.conf $(1)/etc/config/authelia

	#$(INSTALL_DIR) $(1)/etc/capabilities/
	#$(INSTALL_DATA) $(CURDIR)/files/authelia.json $(1)/etc/capabilities/authelia.json

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/authelia.init $(1)/etc/init.d/authelia

	$(INSTALL_DIR) $(1)/etc/authelia/
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/config.template.yml $(1)/etc/authelia/configuration.yml
endef

$(eval $(call HostBuild))
$(eval $(call BuildPackage,authelia))
