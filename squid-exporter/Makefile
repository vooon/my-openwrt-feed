include $(TOPDIR)/rules.mk

PKG_NAME:=squid-exporter
PKG_VERSION:=1.13.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/boynux/squid-exporter.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/boynux/squid-exporter
GO_PKG_LDFLAGS_X:= \
	github.com/prometheus/common/version.Version="$(PKG_VERSION)" \
	github.com/prometheus/common/version.Revision="$(PKG_SOURCE_VERSION)" \
	github.com/prometheus/common/version.Branch="HEAD" \
	github.com/prometheus/common/version.BuildUser="${USER}:${HOSTNAME}" \
	github.com/prometheus/common/version.BuildDate="$(shell date +%Y%m%d-%H:%M:%S)"

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/squid-exporter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Prometheus exporter for Squid
  URL:=https://github.com/boynux/squid-exporter
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/squid-exporter/description
  Exports Squid metrics in Prometheus format.
endef

define Package/squid-exporter/conffiles
/etc/config/squid-exporter
endef

define Package/squid-exporter/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/squid-exporter.conf $(1)/etc/config/squid-exporter

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/squid-exporter.init $(1)/etc/init.d/squid-exporter
endef

$(eval $(call BuildPackage,squid-exporter))
