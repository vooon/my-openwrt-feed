include $(TOPDIR)/rules.mk

PKG_NAME:=zoneomatic
PKG_VERSION:=0.3.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/vooon/zoneomatic.git
PKG_MIRROR_HASH:=8dbe2c6582656d61d5087677c5a79bb5e62860eef8b5de15ca0c92eb2456dbc0
PKG_SOURCE_VERSION:=${PKG_VERSION}

PKG_LICENSE:=ASL-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/vooon/zoneomatic/cmd/zoneomatic

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


GO_PKG_CUSTOM_LDFLAGS += \
	-w -s \

#	-X github.com/vooon/zoneomatic/internal/utils.BuildTag="$(PKG_SOURCE_VERSION)" \
#	-X github.com/vooon/zoneomatic/internal/utils.BuildState="tagged" \
#	-X github.com/vooon/zoneomatic/internal/utils.BuildDate="$(shell date --iso-8601=s)" \


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
