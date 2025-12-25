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

define Package/netbird-dashboard
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=NetBird Management Dashboard
  URL:=https://netbird.io
  DEPENDS:=+gettext-full +uhttpd
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

	# some files containes built-in env, which must be substituted
	( \
		while IFS= read -r file; do \
			mv -v "$$$${file}" "$$$${file}.tmpl"; \
		done < <(grep -R -l AUTH_SUPPORTED_SCOPES $(1)/usr/share/netbird/www) \
	)
endef

$(eval $(call BuildPackage,netbird-dashboard))
