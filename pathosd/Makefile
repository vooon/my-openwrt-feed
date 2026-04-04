include $(TOPDIR)/rules.mk

PKG_NAME:=pathosd
PKG_VERSION:=0.1.2
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vooon/pathosd.git
PKG_MIRROR_HASH:=aa491f78b0c800093cf6f0fdcc8d4df08d04e63094e0292a9245bac081b3f5da
PKG_SOURCE_VERSION:=v$(PKG_VERSION)

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/vooon/pathosd
GO_PKG_BUILD_PKG:=github.com/vooon/pathosd/cmd/pathosd
GO_PKG_LDFLAGS_X:= \
	github.com/prometheus/common/version.Version="$(PKG_VERSION)" \
	github.com/prometheus/common/version.Revision="$(PKG_SOURCE_VERSION)" \
	github.com/prometheus/common/version.Branch="openwrt"

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/pathosd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Health-driven BGP Anycast announcer daemon
  URL:=https://github.com/vooon/pathosd
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/pathosd/description
  pathosd performs health checks and announces or withdraws VIP routes over BGP
  based on service health.
endef

define Package/pathosd/conffiles
/etc/config/pathosd
/etc/pathosd/
endef

define Package/pathosd/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/pathosd.conf $(1)/etc/config/pathosd

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/pathosd.init $(1)/etc/init.d/pathosd

	$(INSTALL_DIR) $(1)/etc/pathosd
	$(INSTALL_CONF) $(CURDIR)/files/pathosd.yaml $(1)/etc/pathosd/pathosd.yaml

	$(INSTALL_DIR) $(1)/etc/capabilities
	$(INSTALL_DATA) $(CURDIR)/files/pathosd.json $(1)/etc/capabilities/pathosd.json

	$(INSTALL_DIR) $(1)/usr/share/pathosd/schema
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/schema/pathosd-config-v1.schema.json $(1)/usr/share/pathosd/schema/
endef

$(eval $(call BuildPackage,pathosd))
