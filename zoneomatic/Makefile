include $(TOPDIR)/rules.mk

PKG_NAME:=zoneomatic
PKG_VERSION:=0.11.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vooon/zoneomatic.git
PKG_MIRROR_HASH:=208ab6a67d0259f74b4765a62289096fef7d2774eeca7e378ae7f1c8da051233
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/vooon/zoneomatic/cmd/zoneomatic
GO_PKG_LDFLAGS_X:= \
	github.com/prometheus/common/version.Version="$(PKG_SOURCE_VERSION)" \
	github.com/prometheus/common/version.Revision="$(PKG_SOURCE_VERSION)" \
	github.com/prometheus/common/version.BuildDate="$(shell date --iso-8601=s)" \

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/zoneomatic
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Simple DynDNS API server
  URL:=https://github.com/vooon/zoneomatic
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/zoneomatic/description
endef

define Package/zoneomatic/conffiles
/etc/config/zoneomatic
endef

define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/zoneomatic/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/zoneomatic.conf $(1)/etc/config/zoneomatic

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/zoneomatic.init $(1)/etc/init.d/zoneomatic
endef

$(eval $(call BuildPackage,zoneomatic))
