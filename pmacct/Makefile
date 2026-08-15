include $(TOPDIR)/rules.mk

PKG_NAME:=pmacct
PKG_VERSION:=1.7.9
PKG_RELEASE:=5

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/pmacct/pmacct/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=cabffd8fba441050d87ddeb4af5bd236104b54275b7d107b185d4c7c81e386e0

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:pmacct:pmacct

PKG_FIXUP:=autoreconf
PKG_BUILD_PARALLEL:=1

# libcdada is a git submodule of pmacct not present in release tarballs.
# Pin the exact commit referenced by pmacct v$(PKG_VERSION) and build it
# in-tree (see src/external_libs/Makefile.am).
LIB_CDADA_COMMIT:=722edce044d2223681218deb2608c519cb35c118
LIB_CDADA_SOURCE:=libcdada-$(LIB_CDADA_COMMIT).tar.gz
LIB_CDADA_URL:=https://codeload.github.com/msune/libcdada/tar.gz/$(LIB_CDADA_COMMIT)?
LIB_CDADA_HASH:=cdeb26a93d583946d73da37888669e98a90ad0c949ebd475c51ec217cb347000

include $(INCLUDE_DIR)/package.mk

# Override the framework default (package.mk re-assigns Build/Prepare):
# unpack the bundled libcdada here since it is a git submodule absent from
# the pmacct release tarball.
define Build/Prepare
	$(call Build/Prepare/Default)
	rm -rf $(PKG_BUILD_DIR)/src/external_libs/libcdada
	$(TAR) -C $(PKG_BUILD_DIR)/src/external_libs -xzf $(DL_DIR)/$(LIB_CDADA_SOURCE)
	mv $(PKG_BUILD_DIR)/src/external_libs/libcdada-$(LIB_CDADA_COMMIT) \
		$(PKG_BUILD_DIR)/src/external_libs/libcdada
endef

define Download/libcdada
	FILE:=$(LIB_CDADA_SOURCE)
	URL:=$(LIB_CDADA_URL)
	HASH:=$(LIB_CDADA_HASH)
endef
$(eval $(call Download,libcdada))

define Package/pmacct
  SECTION:=net
  CATEGORY:=Network
  TITLE:=pmacct traffic accounting and sFlow/IPFIX export daemon
  URL:=https://github.com/pmacct/pmacct
  DEPENDS:=+libpcap +libstdcpp
endef

define Package/pmacct/description
  pmacctd is a lightweight libpcap-based traffic accounting daemon that can
  collect from one or more interfaces (e.g. WireGuard p2p tunnels) and export
  flows as sFlow (sfprobe) or NetFlow v9 / IPFIX (nfprobe) over UDP to a
  remote collector.
endef

define Package/pmacct/conffiles
/etc/config/pmacct
endef

CONFIGURE_ARGS += \
	--enable-l2

define Package/pmacct/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/pmacctd $(1)/usr/sbin/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/pmacct.conf $(1)/etc/config/pmacct

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/pmacct.init $(1)/etc/init.d/pmacct
endef

$(eval $(call BuildPackage,pmacct))
