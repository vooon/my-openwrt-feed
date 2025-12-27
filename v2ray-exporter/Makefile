include $(TOPDIR)/rules.mk

PKG_NAME:=v2ray-exporter
PKG_VERSION:=0.6.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/wi1dcard/v2ray-exporter.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/wi1dcard/v2ray-exporter
GO_PKG_LDFLAGS_X:= \
	main.buildCommit="todo" \
	main.buildDate="$(shell date --iso-8601=s)" \
	main.buildVersion="${PKG_SOURCE_VERSION}" \


include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/v2ray-exporter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=v2ray prometheus exporter
  URL:=https://github.com/wi1dcard/v2ray-exporter
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/v2ray-exporter/description
endef

define Package/v2ray-exporter/conffiles
/etc/config/v2ray-exporter
endef

define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/v2ray-exporter/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/v2ray-exporter.conf $(1)/etc/config/v2ray-exporter

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/v2ray-exporter.init $(1)/etc/init.d/v2ray-exporter
endef

$(eval $(call BuildPackage,v2ray-exporter))
