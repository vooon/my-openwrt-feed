#
# Copyright (C) 2026 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=angie
PKG_VERSION:=1.11.4
PKG_RELEASE:=1

PKG_SOURCE:=angie-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://download.angie.software/files/
PKG_HASH:=b95009ceef7a1c40809aead95f71901ca1c5c9d2630eca0763853811b641983c

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=BSD-2-Clause
PKG_LICENSE_FILES:=LICENSE

PKG_FIXUP:=autoreconf
PKG_BUILD_PARALLEL:=1
PKG_INSTALL:=1
PKG_BUILD_FLAGS:=gc-sections lto

PKG_CONFIG_DEPENDS := \
	CONFIG_ANGIE_DAV \
	CONFIG_ANGIE_FLV \
	CONFIG_ANGIE_STUB_STATUS \
	CONFIG_ANGIE_HTTP_CHARSET \
	CONFIG_ANGIE_HTTP_GZIP \
	CONFIG_ANGIE_HTTP_GZIP_STATIC \
	CONFIG_ANGIE_HTTP_SSI \
	CONFIG_ANGIE_HTTP_USERID \
	CONFIG_ANGIE_HTTP_ACCESS \
	CONFIG_ANGIE_HTTP_AUTH_BASIC \
	CONFIG_ANGIE_HTTP_AUTH_REQUEST \
	CONFIG_ANGIE_HTTP_AUTOINDEX \
	CONFIG_ANGIE_HTTP_GEO \
	CONFIG_ANGIE_HTTP_MAP \
	CONFIG_ANGIE_HTTP_SPLIT_CLIENTS \
	CONFIG_ANGIE_HTTP_REFERER \
	CONFIG_ANGIE_HTTP_REWRITE \
	CONFIG_ANGIE_HTTP_PROXY \
	CONFIG_ANGIE_HTTP_FASTCGI \
	CONFIG_ANGIE_HTTP_UWSGI \
	CONFIG_ANGIE_HTTP_SCGI \
	CONFIG_ANGIE_HTTP_GRPC \
	CONFIG_ANGIE_HTTP_MEMCACHED \
	CONFIG_ANGIE_HTTP_LIMIT_CONN \
	CONFIG_ANGIE_HTTP_LIMIT_REQ \
	CONFIG_ANGIE_HTTP_EMPTY_GIF \
	CONFIG_ANGIE_HTTP_BROWSER \
	CONFIG_ANGIE_HTTP_UPSTREAM_HASH \
	CONFIG_ANGIE_HTTP_UPSTREAM_IP_HASH \
	CONFIG_ANGIE_HTTP_UPSTREAM_LEAST_CONN \
	CONFIG_ANGIE_HTTP_UPSTREAM_RANDOM \
	CONFIG_ANGIE_HTTP_UPSTREAM_KEEPALIVE \
	CONFIG_ANGIE_HTTP_UPSTREAM_ZONE \
	CONFIG_ANGIE_HTTP_UPSTREAM_STICKY \
	CONFIG_ANGIE_HTTP_CACHE \
	CONFIG_ANGIE_HTTP_API \
	CONFIG_ANGIE_HTTP_METRIC \
	CONFIG_ANGIE_HTTP_PROMETHEUS \
	CONFIG_ANGIE_HTTP_DOCKER \
	CONFIG_ANGIE_HTTP_ACME \
	CONFIG_ANGIE_HTTP_V2 \
	CONFIG_ANGIE_HTTP_QUIC \
	CONFIG_ANGIE_PCRE \
	CONFIG_ANGIE_HTTP_REAL_IP \
	CONFIG_ANGIE_HTTP_SECURE_LINK \
	CONFIG_ANGIE_HTTP_SUB \
	CONFIG_ANGIE_STREAM_REAL_IP \
	CONFIG_PACKAGE_angie-mod-stream

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nls.mk

define Package/angie/default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Angie web server
  URL:=https://angie.software/
endef

define Package/angie/default/description
 Angie is an HTTP, reverse proxy, and mail proxy server forked from nginx by
 former nginx developers.
endef

define Package/angie/conffiles
/etc/angie/
endef

define Package/angie
  $(Package/angie/default)
  TITLE += with SSL support
  DEPENDS:= \
    +USE_GLIBC:libcrypt-compat \
    +libopenssl \
    +ANGIE_PCRE:libpcre2 \
    +libpthread \
    +ANGIE_HTTP_GZIP:zlib
  VARIANT:=ssl
  DEFAULT_VARIANT:=1
  CONFLICTS:=angie-full
endef

Package/angie/description = $(Package/angie/default/description) \
  This variant is compiled with SSL support enabled. To enable additional \
  modules, select them in the Angie default configuration menu.

define Package/angie/config
  source "$(SOURCE)/Config_ssl.in"
endef

IsEnabled = $(or $(filter full,$(BUILD_VARIANT)),$(CONFIG_$(1)))
IsDisabled = $(if $(call IsEnabled,$(1)),,1)

config_files := angie.conf mime.types \
	$(if $(call IsEnabled,ANGIE_HTTP_PROMETHEUS),prometheus_all.conf) \
	$(if $(call IsEnabled,ANGIE_HTTP_CHARSET),koi-utf koi-win win-utf) \
	$(if $(call IsEnabled,ANGIE_HTTP_FASTCGI),fastcgi_params fastcgi.conf) \
	$(if $(call IsEnabled,ANGIE_HTTP_UWSGI),uwsgi_params) \
	$(if $(call IsEnabled,ANGIE_HTTP_SCGI),scgi_params)

define Package/angie/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/angie $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/etc/angie/module.d
	$(INSTALL_DIR) $(1)/etc/angie/conf.d
	$(INSTALL_DIR) $(1)/etc/angie/snippets
	$(INSTALL_CONF) $(PKG_INSTALL_DIR)/etc/angie/angie.conf $(1)/etc/angie/
	$(INSTALL_DATA) $(addprefix $(PKG_INSTALL_DIR)/etc/angie/,$(filter-out angie.conf,$(config_files))) $(1)/etc/angie/
	$(if $(call IsEnabled,ANGIE_HTTP_PROMETHEUS),$(INSTALL_CONF) ./files/prometheus.conf $(1)/etc/angie/conf.d/)
	$(if $(call IsEnabled,ANGIE_HTTP_AUTOINDEX),$(INSTALL_CONF) ./files/file-listing.conf $(1)/etc/angie/snippets/)
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/angie.init $(1)/etc/init.d/angie
endef

define Package/angie-full
  $(Package/angie/default)
  TITLE += with ALL config selected
  DEPENDS:= \
    +USE_GLIBC:libcrypt-compat \
    +libopenssl \
    +libpcre2 \
    +libpthread \
    +zlib
  PROVIDES:=angie
  VARIANT:=full
  CONFLICTS:=angie
endef

Package/angie-full/description = $(Package/angie/default/description) \
  This variant is compiled with ALL config selected.

Package/angie-full/install = $(Package/angie/install)

Package/angie-full/conffiles = $(Package/angie/conffiles)

# $(1) module name
# $(2) module additional dependency
# $(3) module so name (stripped of the final _module.so)
# $(4) module description
define BuildModule
  define Package/angie-mod-$(1)
    $(call Package/angie/default)
    DEPENDS:=+!PACKAGE_angie-full:angie +PACKAGE_angie-full:angie-full $(2)
    TITLE:=Angie $(1) module
  endef

  define Package/angie-mod-$(1)/description
    $(strip $(4))
  endef

  define Package/angie-mod-$(1)/install
	$(INSTALL_DIR) $$(1)/usr/lib/angie/modules
	$(INSTALL_DIR) $$(1)/etc/angie/module.d
	$(foreach m,$(3),
	  $(CP) $$(PKG_INSTALL_DIR)/usr/lib/angie/modules/$(m)_module.so $$(1)/usr/lib/angie/modules && \
	  echo "load_module /usr/lib/angie/modules/$(m)_module.so;" > $$(1)/etc/angie/module.d/$(m).module
	)
  endef

  $$(eval $$(call BuildPackage,angie-mod-$(1)))
endef

CONFIGURE_VARS += CONFIG_BIG_ENDIAN=$(CONFIG_BIG_ENDIAN)

CONFIGURE_ARGS += \
	--crossbuild=Linux::$(ARCH) \
	--prefix=/usr \
	--sbin-path=/usr/sbin/angie \
	--conf-path=/etc/angie/angie.conf \
	--modules-path=/usr/lib/angie/modules \
	--error-log-path=stderr \
	--pid-path=/var/run/angie.pid \
	--lock-path=/var/lock/angie.lock \
	--http-log-path=/var/log/angie/access.log \
	--http-client-body-temp-path=/var/lib/angie/body \
	--http-proxy-temp-path=/var/lib/angie/proxy \
	--http-fastcgi-temp-path=/var/lib/angie/fastcgi \
	--http-uwsgi-temp-path=/var/lib/angie/uwsgi \
	--http-scgi-temp-path=/var/lib/angie/scgi \
	--http-acme-client-path=/var/lib/angie/acme \
	--with-cc="$(TARGET_CC)" \
	--with-ld-opt="$(TARGET_LDFLAGS)" \
	--with-compat \
	--with-http_ssl_module \
	$(if $(call IsDisabled,ANGIE_HTTP_CACHE),--without-http-cache) \
	$(if $(call IsDisabled,ANGIE_PCRE),--without-pcre) \
	$(if $(call IsDisabled,ANGIE_HTTP_CHARSET),--without-http_charset_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_GZIP),--without-http_gzip_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_SSI),--without-http_ssi_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_USERID),--without-http_userid_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_ACCESS),--without-http_access_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_AUTH_BASIC),--without-http_auth_basic_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_AUTOINDEX),--without-http_autoindex_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_GEO),--without-http_geo_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_MAP),--without-http_map_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_SPLIT_CLIENTS),--without-http_split_clients_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_REFERER),--without-http_referer_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_REWRITE),--without-http_rewrite_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_PROXY),--without-http_proxy_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_FASTCGI),--without-http_fastcgi_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UWSGI),--without-http_uwsgi_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_SCGI),--without-http_scgi_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_GRPC),--without-http_grpc_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_MEMCACHED),--without-http_memcached_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_LIMIT_CONN),--without-http_limit_conn_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_LIMIT_REQ),--without-http_limit_req_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_EMPTY_GIF),--without-http_empty_gif_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_BROWSER),--without-http_browser_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_HASH),--without-http_upstream_hash_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_IP_HASH),--without-http_upstream_ip_hash_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_LEAST_CONN),--without-http_upstream_least_conn_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_RANDOM),--without-http_upstream_random_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_KEEPALIVE),--without-http_upstream_keepalive_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_ZONE),--without-http_upstream_zone_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_UPSTREAM_STICKY),--without-http_upstream_sticky_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_API),--without-http_api_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_METRIC),--without-http_metric_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_PROMETHEUS),--without-http_prometheus_module) \
	$(if $(call IsDisabled,ANGIE_HTTP_DOCKER),--without-http_docker_module) \
	$(if $(call IsEnabled,IPV6),--with-ipv6) \
	$(if $(call IsEnabled,ANGIE_HTTP_GZIP_STATIC),--with-http_gzip_static_module) \
	$(if $(call IsEnabled,ANGIE_STUB_STATUS),--with-http_stub_status_module) \
	$(if $(call IsEnabled,ANGIE_FLV),--with-http_flv_module) \
	$(if $(call IsEnabled,ANGIE_DAV),--with-http_dav_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_AUTH_REQUEST),--with-http_auth_request_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_ACME),--with-http_acme_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_QUIC),--with-http_v3_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_V2),--with-http_v2_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_REAL_IP),--with-http_realip_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_SECURE_LINK),--with-http_secure_link_module) \
	$(if $(call IsEnabled,ANGIE_HTTP_SUB),--with-http_sub_module) \
	$(if $(CONFIG_PACKAGE_angie-mod-stream),--with-stream=dynamic --with-stream_ssl_module --with-stream_ssl_preread_module) \
	$(if $(call IsEnabled,ANGIE_STREAM_REAL_IP),--with-stream_realip_module)

$(eval $(call BuildPackage,angie))
$(eval $(call BuildPackage,angie-full))
$(eval $(call BuildModule,stream,,ngx_stream,Add support for Angie request streaming.))
