include $(TOPDIR)/rules.mk

PKG_NAME:=netbird-dashboard
PKG_VERSION:=2.23.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/netbirdio/dashboard.git
PKG_MIRROR_HASH:=efc0cd0aa211f469e5022aae0a3c7c1ec51897edddf6e8963d09c259afefd63e
PKG_SOURCE_VERSION:=v${PKG_VERSION}

PKG_MAINTAINER:=Wesley Gimenes <wehagy@proton.me>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE

HOST_BUILD_DEPENDS:=node/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

IRONRDP_RELEASE:=v0.0.1
IRONRDP_WEB_JS_FILE:=ironrdp_web-$(IRONRDP_RELEASE).js
define Download/ironrdp-web-js
  URL:=https://github.com/netbirdio/IronRDP/releases/download/$(IRONRDP_RELEASE)/
  URL_FILE:=ironrdp_web.js
  FILE:=$(IRONRDP_WEB_JS_FILE)
  HASH:=7738339dbfc99fe1440b33f997256240b868522740925340bcec5b5b0d216302
endef

IRONRDP_WEB_WASM_FILE:=ironrdp_web_bg-$(IRONRDP_RELEASE).wasm
define Download/ironrdp-web-wasm
  URL:=https://github.com/netbirdio/IronRDP/releases/download/$(IRONRDP_RELEASE)/
  URL_FILE:=ironrdp_web_bg.wasm
  FILE:=$(IRONRDP_WEB_WASM_FILE)
  HASH:=046caa5d00ce0bbffe89182e1cb96f9c381e39f053d0664a0f8e1fa909d7b1f0
endef

define Package/netbird-dashboard
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=NetBird Management Dashboard
  URL:=https://netbird.io
  DEPENDS:=+uhttpd +envsubst
  ARCH:=all
endef

define Package/netbird-dashboard/description
  Dashboard for NetBird menegement server (static files).
endef

define Build/Compile
	cd $(PKG_BUILD_DIR); \
	npm install; \
	npm run build;
endef

define Package/netbird-dashboard/install
	$(INSTALL_DIR) $(1)/usr/share/netbird/

	# based on docker/init_react_envs.sh
	$(INSTALL_BIN) ./files/dashboard-entrypoint.sh $(1)/usr/share/netbird/

	# install static files
	$(CP) $(PKG_BUILD_DIR)/out $(1)/usr/share/netbird/www

	# install ironrdp files
	$(INSTALL_DIR) $(1)/usr/share/netbird/www/ironrdp-pkg
	$(INSTALL_DATA) $(DL_DIR)/$(IRONRDP_WEB_JS_FILE) $(1)/usr/share/netbird/www/ironrdp-pkg/ironrdp_web.js
	$(INSTALL_DATA) $(DL_DIR)/$(IRONRDP_WEB_WASM_FILE) $(1)/usr/share/netbird/www/ironrdp-pkg/ironrdp_web_bg.wasm

	# some files containes built-in env, which must be substituted
	( \
		grep -R -l AUTH_SUPPORTED_SCOPES $(1)/usr/share/netbird/www | \
		while IFS= read -r file; do \
			mv -v "$$$${file}" "$$$${file}.tmpl"; \
		done \
	)
endef

$(eval $(call Download,ironrdp-web-js))
$(eval $(call Download,ironrdp-web-wasm))
$(eval $(call BuildPackage,netbird-dashboard))
