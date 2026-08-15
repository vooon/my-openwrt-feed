include $(TOPDIR)/rules.mk

PKG_NAME:=netobserv-ebpf-agent
PKG_VERSION:=1.12.0
PKG_RELEASE:=4

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/netobserv/netobserv-ebpf-agent.git
PKG_SOURCE_VERSION:=v${PKG_VERSION}-community

PKG_MAINTAINER:=Vladimir Ermakov <vooon341@gmail.com>
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:netobserv:netobserv-ebpf-agent

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/netobserv/netobserv-ebpf-agent/cmd

include $(INCLUDE_DIR)/package.mk
include ../../packages/lang/golang/golang-package.mk

define Package/netobserv-ebpf-agent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=NetObserv eBPF flow exporter (IPFIX)
  URL:=https://github.com/netobserv/netobserv-ebpf-agent
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

# Force the target kernel options this BPF agent requires (not merely gate
# package selection): full (non-reduced) debug info with BTF, plus eBPF events.
# Core eBPF (BPF, BPF_SYSCALL, BPF_JIT) is already enabled by OpenWrt kernel
# defaults; TC ingress/egress hooks for attachment must be set in the target
# kernel config (NET_CLS_ACT, NET_ACT_BPF, NET_CLS_BPF, NET_SCH_INGRESS).
define Package/netobserv-ebpf-agent/config
	select KERNEL_DEBUG_INFO
	select KERNEL_DEBUG_INFO_BTF
	select KERNEL_BPF_EVENTS
endef

define Package/netobserv-ebpf-agent/description
  eBPF-based flow exporter that attaches to TC hooks (ingress/egress) and
  generates bidirectional flow records. Flows are exported as IPFIX over
  UDP/TCP to a collector (EXPORT=ipfix+udp|ipfix+tcp), or Kafka/GRPC.
  Precompiled BPF bytecode is embedded for amd64/arm64/powerpc/s390.
  Requires a kernel with BPF and BTF (DEBUG_INFO_BTF) enabled.
endef

define Package/netobserv-ebpf-agent/conffiles
/etc/config/netobserv-ebpf-agent
endef

define Build/Compile
	$(call GoPackage/Build/Compile,$(GO_PKG_BUILD_PKG))
endef

define Package/netobserv-ebpf-agent/install
	$(call GoPackage/Package/Install/Bin,$(1))
	mv $(1)/usr/bin/cmd $(1)/usr/bin/netobserv-ebpf-agent

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/netobserv-ebpf-agent.conf $(1)/etc/config/netobserv-ebpf-agent

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/netobserv-ebpf-agent.init $(1)/etc/init.d/netobserv-ebpf-agent
endef

$(eval $(call BuildPackage,netobserv-ebpf-agent))
