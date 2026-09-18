include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-meow
PKG_VERSION:=0.21.2
PKG_RELEASE:=1

# Sources come from the meow-rs upstream tarball; only the `openwrt/luci-app-meow`
# subtree is used. Local UCI-rename patches (meow -> meow-rs) live in patches/.
PKG_SOURCE:=meow-rs-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/meow-rs/meow-rs/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=92856addeffaa007a1fd3d175694be858f9b1a452342f8cc3a0b2dbdbe8c2b32

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_ARCH:=all

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-meow
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=meow-rs proxy web UI
  URL:=https://github.com/meow-rs/meow-rs
  DEPENDS:=+luci-base +meow-rs
  PKGARCH:=all
endef

define Package/luci-app-meow/description
  LuCI control panel for meow-rs, a mihomo-compatible rule-based tunneling
  proxy kernel. Embeds the built-in web dashboard served by the meow-rs REST API.
endef

# Extract only the luci-app-meow subtree from the upstream tarball, apply the
# UCI-rename patches (meow -> meow-rs), then install htdocs and root.
define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) --strip-components=3 \
		-xzf $(DL_DIR)/$(PKG_SOURCE) \
		meow-rs-$(PKG_VERSION)/openwrt/luci-app-meow
	$(Build/Patch)
endef

define Build/Compile
endef

define Build/Install
endef

define Package/luci-app-meow/install
	$(INSTALL_DIR) $(1)/www
	cp -pR $(PKG_BUILD_DIR)/htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	cp -pR $(PKG_BUILD_DIR)/root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-meow))