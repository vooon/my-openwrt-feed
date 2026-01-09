include $(TOPDIR)/rules.mk

PKG_NAME:=netbird-mgmt
PKG_VERSION:=0.62.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/netbirdio/netbird.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Wesley Gimenes <wehagy@proton.me>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/netbirdio/netbird
GO_PKG_BUILD_PKG:=$(GO_PKG)/management $(GO_PKG)/relay $(GO_PKG)/signal $(if $(CONFIG_PACKAGE_netbird-alt),$(GO_PKG)/client)
GO_PKG_LDFLAGS_X:=$(GO_PKG)/version.version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/netbird/default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Connect your devices into a single secure private WireGuard®-based mesh network
  URL:=https://netbird.io
endef

define Package/netbird/description/default
  NetBird is an open-source VPN management platform built on top of WireGuard® making it easy to create
  secure private networks for your organization or home.

  It requires zero configuration effort leaving behind the hassle of opening ports, complex firewall rules, VPN
  gateways, and so forth.
endef

define Package/netbird-mgmt
  $(call Package/netbird/default)
  TITLE:=NetBird Management server
  DEPENDS:=$(GO_ARCH_DEPENDS) +coturn +netbird-dashboard
  USERID:=netbird:netbird
endef

define Package/netbird-mgmt/description
  $(call Package/netbird/description/default)

  Management server components.
endef

define Package/netbird-wasm
  $(call Package/netbird/default)
  TITLE:=NetBird WASM binary
  ARCH:=all
endef

define Package/netbird-wasm/description
  $(call Package/netbird/description/default)

  WASM for NetBird Dashboard.
endef

define Package/netbird-alt
  $(call Package/netbird/default)
  TITLE:=NetBird alternate
  DEPENDS:=$(GO_ARCH_DEPENDS) +kmod-wireguard
  PROVIDES:=netbird
endef

define Package/netbird-alt/description
  $(call Package/netbird/description/default)

  NetBird client (from netbird-mgmt).
endef

define Package/netbird-mgmt/conffiles
/etc/config/netbird-mgmt
/etc/netbird/
endef

define Package/netbird-alt/conffiles
/root/.config/netbird/
/etc/config/netbird
endef


define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))

if ($(CONFIG_PACKAGE_netbird-wasm),y)
	( \
		cd $(PKG_BUILD_DIR); \
		$(GO_PKG_BUILD_VARS) \
		GOOS=js GOARCH=wasm \
		go build -ldflags "$(GO_PKG_CUSTOM_LDFLAGS) $(GO_PKG_DEFAULT_LDFLAGS)" -o $(PKG_INSTALL_DIR)/netbird.wasm ./client/wasm/cmd
	)
endif

endef

define Package/netbird-mgmt/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/management $(1)/usr/bin/netbird-mgmt
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/relay $(1)/usr/bin/netbird-relay
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/signal $(1)/usr/bin/netbird-signal

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/netbird-mgmt.init $(1)/etc/init.d/netbird-mgmt

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/netbird-mgmt.config $(1)/etc/config/netbird-mgmt

	$(INSTALL_DIR) $(1)/etc/netbird

	# default state dir. will be creatred by init
	# $(INSTALL_DIR) $(1)/var/lib/netbird

	# config samples
	$(INSTALL_DIR) $(1)/usr/share/netbird/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/infrastructure_files/*.tmpl \
		$(PKG_BUILD_DIR)/infrastructure_files/base.setup.env \
		$(PKG_BUILD_DIR)/infrastructure_files/setup.env.example \
		$(PKG_BUILD_DIR)/infrastructure_files/nginx.tmpl.conf \
		$(1)/usr/share/netbird/config/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/infrastructure_files/configure.sh \
		$(1)/usr/share/netbird/config/

endef

define Package/netbird-wasm/install
	$(INSTALL_DIR) $(1)/usr/share/netbird/www/
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/netbird.wasm $(1)/usr/share/netbird/www/
endef

define Package/netbird-alt/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/client $(1)/usr/bin/netbird
	$(INSTALL_BIN) ./files/netbird.init $(1)/etc/init.d/netbird
	$(INSTALL_CONF) ./files/netbird.conf $(1)/etc/config/netbird
endef

$(eval $(call GoBinPackage,netbird-mgmt))
$(eval $(call GoBinPackage,netbird-wasm))
$(eval $(call GoBinPackage,netbird-alt))
$(eval $(call BuildPackage,netbird-mgmt))
$(eval $(call BuildPackage,netbird-wasm))
$(eval $(call BuildPackage,netbird-alt))
