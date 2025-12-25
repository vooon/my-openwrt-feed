include $(TOPDIR)/rules.mk

PKG_NAME:=envsubst
PKG_VERSION:=1.4.3
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/a8m/envsubst.git
PKG_MIRROR_HASH:=
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host node-yarn/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/a8m/envsubst
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/envsubst

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/envsubst
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Environment variables substitution for Go
  URL:=https://github.com/a8m/envsubst
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/envsubst/description
  Alternative to envsubst from gettext.
endef


#define Package/envsubst/install
#	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
#
#	$(INSTALL_DIR) $(1)/usr/bin/
#	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/envsubst $(1)/usr/bin/envsubst
#endef

$(eval $(call BuildPackage,envsubst))
