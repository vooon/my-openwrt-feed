include $(TOPDIR)/rules.mk

PKG_NAME:=xray-exporter
PKG_VERSION:=0.1.9
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/compassvpn/xray-exporter.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

#GO_PKG:=github.com/compassvpn/xray-exporter
GO_PKG:=xray-exporter
GO_PKG_LDFLAGS_X:= \
	main.buildCommit="todo" \
	main.buildDate="$(shell date --iso-8601=s)" \
	main.buildVersion="${PKG_SOURCE_VERSION}" \


include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/xray-exporter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=xray prometheus exporter
  URL:=https://github.com/compassvpn/xray-exporter
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/xray-exporter/description
endef

define Package/xray-exporter/conffiles
/etc/config/xray-exporter
endef

define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/xray-exporter/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/xray-exporter.conf $(1)/etc/config/xray-exporter

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/xray-exporter.init $(1)/etc/init.d/xray-exporter
endef

$(eval $(call BuildPackage,xray-exporter))
