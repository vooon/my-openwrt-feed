include $(TOPDIR)/rules.mk

PKG_NAME:=frr-exporter
PKG_VERSION:=1.9.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/tynany/frr_exporter.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/tynany/frr_exporter
GO_PKG_LDFLAGS_X:= \
        github.com/prometheus/common/version.Version=$(PKG_SOURCE_VERSION) \
        github.com/prometheus/common/version.Revision=$(PKG_SOURCE_VERSION) \
        github.com/prometheus/common/version.Branch=HEAD \
	github.com/prometheus/common/version.BuildUser=${USER}:${HOSTNAME} \
	github.com/prometheus/common/version.BuildDate=$(shell date +%Y%m%d-%H:%M:%S)

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/frr-exporter
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Prometheus exporter for Free Range Routing
  URL:=https://github.com/tynany/frr_exporter.git
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/frr-exporter/description
endef

define Package/frr-exporter/conffiles
/etc/config/frr-exporter
endef

define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/frr-exporter/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/frr-exporter.conf $(1)/etc/config/frr-exporter

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/frr-exporter.init $(1)/etc/init.d/frr-exporter
endef

$(eval $(call BuildPackage,frr-exporter))
