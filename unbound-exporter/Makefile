include $(TOPDIR)/rules.mk

PKG_NAME:=unbound-exporter
PKG_VERSION:=0.5.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/letsencrypt/unbound_exporter.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v$(PKG_VERSION)

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/letsencrypt/unbound_exporter

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/unbound-exporter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Prometheus exporter for Unbound
  URL:=https://github.com/letsencrypt/unbound_exporter
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/unbound-exporter/description
  Exports Unbound metrics in Prometheus format.
endef

define Package/unbound-exporter/conffiles
/etc/config/unbound-exporter
endef

define Package/unbound-exporter/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/unbound-exporter.conf $(1)/etc/config/unbound-exporter

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/unbound-exporter.init $(1)/etc/init.d/unbound-exporter
endef

$(eval $(call BuildPackage,unbound-exporter))
