include $(TOPDIR)/rules.mk

PKG_NAME:=uwsd
PKG_VERSION:=20260910
PKG_RELEASE:=5

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/jow-/uwsd.git
PKG_SOURCE_VERSION:=1450021ba05a6a801e8c0ad446e3b2d8458ba976
PKG_MIRROR_HASH:=9d1b667a9ff3871d784693bc19574c1c8aa8bab2805c5846227abd82c8b3756a

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=ISC
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_OPTIONS += \
	-DCMAKE_BUILD_TYPE=Release \
	-DUSE_MBEDTLS=$(if $(filter mbedtls,$(BUILD_VARIANT)),1,0)

define Package/uwsd/default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Single-process HTTP/WS server with ucode scripting
  URL:=https://github.com/jow-/uwsd
endef

define Package/uwsd/default/description
 uwsd is a single-process HTTP and WebSocket server and proxy with native
 ucode scripting support, written by the OpenWrt LuCI author.
endef

define Package/uwsd
  $(Package/uwsd/default)
  TITLE += (TLS: mbedtls)
  DEPENDS:=+libubox +libucode +libjson-c +libmbedtls +ucode-mod-fs \
    +USE_GLIBC:libcrypt-compat
  VARIANT:=mbedtls
  DEFAULT_VARIANT:=1
  PROVIDES:=uwsd-tls
  CONFLICTS:=uwsd-openssl
endef

define Package/uwsd/description
$(call Package/uwsd/default/description)

This variant is linked against the mbedTLS TLS library.
endef

define Package/uwsd-openssl
  $(Package/uwsd/default)
  TITLE += (TLS: openssl)
  DEPENDS:=+libubox +libucode +libjson-c +libopenssl +ucode-mod-fs \
    +USE_GLIBC:libcrypt-compat
  VARIANT:=openssl
  PROVIDES:=uwsd-tls
  CONFLICTS:=uwsd
endef

define Package/uwsd-openssl/description
$(call Package/uwsd/default/description)

This variant is linked against the OpenSSL TLS library.
endef

define Package/uwsd/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/uwsd $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/usr/share/uwsd
	$(INSTALL_DATA) ./files/utpl-wrapper.uc $(1)/usr/share/uwsd/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/example/cgi-wrapper.uc $(1)/usr/share/uwsd/

	$(INSTALL_DIR) $(1)/etc/uwsd
	$(INSTALL_CONF) ./files/uwsd.conf $(1)/etc/uwsd/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_BIN) ./files/uwsd.uci.conf $(1)/etc/config/uwsd

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/uwsd.init $(1)/etc/init.d/uwsd
endef

Package/uwsd-openssl/install = $(Package/uwsd/install)

define Package/uwsd/conffiles
/etc/config/uwsd
/etc/uwsd/
endef

Package/uwsd-openssl/conffiles = $(Package/uwsd/conffiles)

$(eval $(call BuildPackage,uwsd))
$(eval $(call BuildPackage,uwsd-openssl))
