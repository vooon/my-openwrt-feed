include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-meow
PKG_VERSION:=0.21.2
PKG_RELEASE:=1

# Sources come from the meow-rs upstream tarball; only the `openwrt/luci-app-meow`
# subtree is used. Local UCI-rename patches (meow -> meow-rs) live in patches/.
PKG_SOURCE:=meow-rs-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/meow-rs/meow-rs/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=92856addeffaa007a1fd3d175694be858f9b1a452342f8cc3a0b2dbdbe8c2b32

LUCI_TITLE:=meow-rs proxy web UI
LUCI_DESCRIPTION:=LuCI control panel for meow-rs, a mihomo-compatible rule-based tunneling proxy kernel. Embeds the built-in web dashboard served by the meow-rs REST API.
LUCI_DEPENDS:=+luci-base +meow-rs
LUCI_PKGARCH:=all

LUCI_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=MIT

include $(TOPDIR)/feeds/luci/luci.mk

# luci.mk's default Build/Prepare copies htdocs/root from ${CURDIR}. We instead
# extract the luci-app-meow subtree from the downloaded upstream tarball into
# PKG_BUILD_DIR, then apply the UCI-rename patches.
define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) --strip-components=3 \
		-xzf $(DL_DIR)/$(PKG_SOURCE) \
		meow-rs-$(PKG_VERSION)/openwrt/luci-app-meow
	$(Build/Patch)
endef

# luci.mk's install is gated on htdocs/root being present in ${CURDIR}; since
# they live in the extracted tarball instead, copy them explicitly.
define Package/luci-app-meow/install
	$(INSTALL_DIR) $(1)/www
	cp -pR $(PKG_BUILD_DIR)/htdocs/* $(1)/www/
	$(INSTALL_DIR) $(1)/
	cp -pR $(PKG_BUILD_DIR)/root/* $(1)/
endef

# call BuildPackage - OpenWrt buildroot signature