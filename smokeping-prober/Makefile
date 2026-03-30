include $(TOPDIR)/rules.mk

PKG_NAME:=smokeping-prober
PKG_VERSION:=0.11.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/SuperQ/smokeping_prober.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/SuperQ/smokeping_prober
GO_PKG_LDFLAGS_X:= \
	github.com/prometheus/common/version.Version="$(PKG_VERSION)" \
	github.com/prometheus/common/version.Revision="$(PKG_SOURCE_VERSION)" \
	github.com/prometheus/common/version.Branch="HEAD" \
	github.com/prometheus/common/version.BuildUser="${USER}:${HOSTNAME}" \
	github.com/prometheus/common/version.BuildDate="$(shell date +%Y%m%d-%H:%M:%S)"

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/smokeping-prober
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Prometheus smokeping prober
  URL:=https://github.com/SuperQ/smokeping_prober
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/smokeping-prober/description
  Prometheus style "smokeping" prober.
endef

define Package/smokeping-prober/conffiles
/etc/config/smokeping-prober
endef

define Package/smokeping-prober/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/smokeping-prober.conf $(1)/etc/config/smokeping-prober

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/smokeping-prober.init $(1)/etc/init.d/smokeping-prober
endef

$(eval $(call BuildPackage,smokeping-prober))
