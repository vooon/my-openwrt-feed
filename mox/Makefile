include $(TOPDIR)/rules.mk

PKG_NAME:=mox
PKG_VERSION:=0.0.15
PKG_RELEASE:=3

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/mjl-/mox.git
PKG_MIRROR_HASH:=89b06f0ff05461c365882778259674a202aeb5eae9de33041acecf4dbc1f82df
#PKG_SOURCE_VERSION:=v${PKG_VERSION}
PKG_SOURCE_VERSION:=023a40e2b130c3af8847675e121283adef701e5a

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/mjl-/mox

include $(INCLUDE_DIR)/package.mk
# include ../../lang/golang/golang-package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/mox
  SECTION:=mail
  CATEGORY:=Mail
  TITLE:=Mail server for low-maintenance self-hosted email
  URL:=https://xmox.nl
  DEPENDS:=$(GO_ARCH_DEPENDS)
  USERID:=mox=587:mox=587
endef

define Package/mox/description
  Mox is a modern full-featured open source secure mail server for low-maintenance self-hosted email.
endef

define Package/mox/conffiles
/etc/config/mox
/etc/mox/*
/etc/mox/
endef

GO_PKG_LDFLAGS_X:= \
	github.com/mjl-/mox/moxvar.Version="$(PKG_SOURCE_VERSION)" \
	github.com/mjl-/mox/moxvar.VersionBare="$(PKG_SOURCE_VERSION)"

define Package/mox/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/usr/libexec/
	$(INSTALL_BIN) $(CURDIR)/files/mox.sh $(1)/usr/libexec/mox

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/mox.conf $(1)/etc/config/mox

	$(INSTALL_DIR) $(1)/etc/capabilities/
	$(INSTALL_DATA) $(CURDIR)/files/mox.json $(1)/etc/capabilities/mox.json

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/mox.init $(1)/etc/init.d/mox

	$(INSTALL_DIR) $(1)/etc/mox/
endef

$(eval $(call BuildPackage,mox))
