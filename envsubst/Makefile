include $(TOPDIR)/rules.mk

PKG_NAME:=envsubst
PKG_VERSION:=0.24.1
PKG_RELEASE:=1

PKG_SOURCE:=gettext-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=@GNU/gettext
PKG_HASH:=6164ec7aa61653ac9cdfb41d5c2344563b21f707da1562712e48715f1d2052a6
PKG_BUILD_DIR:=$(BUILD_DIR)/gettext-$(PKG_VERSION)

PKG_MAINTAINER:=Jo-Philipp Wich <jo@mein.io>
PKG_LICENSE:=LGPL-2.1-or-later
PKG_LICENSE_FILES:=gettext-runtime/intl/COPYING.LIB
PKG_CPE_ID:=cpe:/a:gnu:gettext

include $(INCLUDE_DIR)/package.mk

define Package/envsubst
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Environment variables substitution
  URL:=https://github.com/a8m/envsubst
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/envsubst/description
  envsubst from gettext.
endef


PKG_SUBDIRS:= \
	$$$$(foreach dir, \
		gettext-runtime \
	,$$$$(wildcard $$$$(dir)) )

TARGET_CFLAGS += $(FPIC)
TARGET_CFLAGS += -std=gnu23
ifneq ($(HOST_OS),Linux)
  TARGET_CFLAGS += -I$(STAGING_DIR_HOSTPKG)/include
endif

CONFIGURE_ARGS += \
	--disable-shared \
	--enable-static \
	--disable-libasprintf \
	--disable-rpath \
	--enable-nls \
	--disable-java \
	--disable-openmp \
	--disable-curses \
	--with-included-gettext \
	--without-libintl-prefix \
	--without-libexpat-prefix \
	--with-libunistring-prefix=$(STAGING_DIR)/usr \
	--with-libxml2-prefix=$(STAGING_DIR) \
	--without-emacs

define Build/Compile
	$(call Build/Compile/Default)
endef
#	$(call Build/Compile/Default,SUBDIRS='$(PKG_SUBDIRS)')

define Build/Install
	$(call Build/Install/Default)
endef
#	$(call Build/Install/Default,install SUBDIRS='$(PKG_SUBDIRS)')

define Package/envsubst/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/gettext-runtime/src/envsubst $(1)/usr/bin/
endef

$(eval $(call BuildPackage,envsubst))
