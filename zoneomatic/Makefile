include $(TOPDIR)/rules.mk

PKG_NAME:=zoneomatic
PKG_VERSION:=0.13.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vooon/zoneomatic.git
PKG_MIRROR_HASH:=1f4ffeec33849e96bc0a2fb6080f2e67a12cc64e53d65b61967a509c301ff150
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/vooon/zoneomatic/cmd/zoneomatic
GO_PKG_LDFLAGS_X:= \
	github.com/vooon/zoneomatic/internal/buildinfo.Version="$(PKG_VERSION)" \
	github.com/vooon/zoneomatic/internal/buildinfo.Commit="$(PKG_SOURCE_VERSION)" \
	github.com/vooon/zoneomatic/internal/buildinfo.Branch="$(PKG_SOURCE_VERSION)" \
	github.com/vooon/zoneomatic/internal/buildinfo.Date="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)" \

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
