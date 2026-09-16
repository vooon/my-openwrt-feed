include $(TOPDIR)/rules.mk

PKG_NAME:=mihomo-meta
PKG_VERSION:=1.19.31
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/MetaCubeX/mihomo.git
PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL3.0+
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

PKG_BUILD_VERSION:=v${PKG_VERSION}
PKG_BUILD_TIME:=$(shell date -u -Iseconds)

GO_PKG:=github.com/metacubex/mihomo
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/constant.Version=$(PKG_BUILD_VERSION)
	$(GO_PKG)/constant.BuildTime=$(PKG_BUILD_TIME)

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/mihomo-meta
  SECTION:=net
  CATEGORY:=Network
  TITLE:=A rule based proxy in Go.
  URL:=https://wiki.metacubex.one
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +ip-full +kmod-inet-diag +kmod-tun
  PROVIDES:=mihomo
  CONFLICTS:=mihomo-alpha
  USERID:=mihomo=5588:mihomo=5588
  VARIANT:=meta
  DEFAULT_VARIANT:=1
endef

define Package/mihomo-meta/description
  A rule based proxy in Go.
endef

define Package/mihomo-meta/config
	menu "Build options"
		depends on PACKAGE_mihomo-meta

		config MIHOMO_WITH_GVISOR
			bool "Build with gVisor userspace network stack support"
			default y

		config MIHOMO_WITH_LOW_MEMORY
			bool "Build with reduced memory usage (smaller relay/UDP buffers)"

		config MIHOMO_NO_TAILSCALE
			bool "Build without Tailscale outbound support"

		config MIHOMO_NO_ZEROTIER
			bool "Build without ZeroTier outbound support"

		config MIHOMO_NO_EASYTIER
			bool "Build without EasyTier outbound support"

		config MIHOMO_NO_FAKE_TCP
			bool "Build without Fake-TCP support"
	endmenu
endef

PKG_CONFIG_DEPENDS:= \
	CONFIG_MIHOMO_WITH_GVISOR \
	CONFIG_MIHOMO_WITH_LOW_MEMORY \
	CONFIG_MIHOMO_NO_TAILSCALE \
	CONFIG_MIHOMO_NO_ZEROTIER \
	CONFIG_MIHOMO_NO_EASYTIER \
	CONFIG_MIHOMO_NO_FAKE_TCP

GO_PKG_TAGS:= $(subst $(space),$(comma),$(strip \
	$(if $(CONFIG_MIHOMO_WITH_GVISOR),with_gvisor) \
	$(if $(CONFIG_MIHOMO_WITH_LOW_MEMORY),with_low_memory) \
	$(if $(CONFIG_MIHOMO_NO_TAILSCALE),no_tailscale) \
	$(if $(CONFIG_MIHOMO_NO_ZEROTIER),no_zerotier) \
	$(if $(CONFIG_MIHOMO_NO_EASYTIER),no_easytier) \
	$(if $(CONFIG_MIHOMO_NO_FAKE_TCP),no_fake_tcp) \
))

define Package/mihomo-meta/conffiles
/etc/config/mihomo
/etc/mihomo/
endef

define Package/mihomo-meta/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/mihomo
	$(INSTALL_DATA) ./files/config.yaml $(1)/etc/mihomo/config.yaml

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/mihomo.conf $(1)/etc/config/mihomo
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/mihomo.init $(1)/etc/init.d/mihomo
	$(INSTALL_DIR) $(1)/etc/capabilities
	$(INSTALL_DATA) ./files/mihomo.json $(1)/etc/capabilities/mihomo.json
endef

define Build/Prepare
	$(Build/Prepare/Default)
	$(RM) -r $(PKG_BUILD_DIR)/rules/logic_test
endef

$(eval $(call GoBinPackage,mihomo-meta))
$(eval $(call BuildPackage,mihomo-meta))
