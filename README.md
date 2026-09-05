Vooon's OpenWrt Feed
====================

This is my custom OpenWrt feed with extra packages I use on my systems.


Installation
------------

This repository is an OpenWrt feed with additional packages.

1. Add this line to `feeds.conf`:

```
src-git vooon https://github.com/vooon/my-openwrt-feed.git
```

2. Run feeds update and install:

```shell
./scripts/feeds update -a
./scripts/feeds install -a
```

Package Highlights
------------------

- Web and identity: `angie`, `lldap`, `authelia`
- Mail and notifications: `mox`, `gotify`, `gotify2telegram`,
  `gotify-alertmanager-plugin`
- Routing and overlays: `gobgp`, `nebula`, `nylon`, `pathosd`, `vpn-sticky`,
  `netifd-proto-dummy` (create dummy interfaces from `config interface …
  proto dummy`), `netifd-proto-fou` (FOU-encapsulated tunnels over an IPv6
  mesh via `fou-ip6gre` / `fou-ip6tnl` protos, with per-flow ECMP hashing)
- Traffic monitoring (eBPF/IPFIX observability) moved to the separate
  [`obserwrt`](https://github.com/vooon/obserwrt) feed
- DNS automation: `ddns-dhcp-sync`, `zoneomatic`
- Monitoring: `prometheus-node-exporter-ucode`, `frr-exporter`,
  `smokeping-prober`, `squid-exporter`, `unbound-exporter`, `rpcd-mod-bird`
  (ubus access to the BIRD control socket, incl. structured `bird status`
  and `bird set_ospf_cost` for runtime OSPF cost changes), `luci-app-bird`
  (OSPF/BGP overview page with OSPF cost control), `bpftop` (real-time view
  of running eBPF programs)
- Backup and virtualization: `proxmox-backup`, `pbs-helper`,
  `qemu-instance-init`, `rsync-sysupgrade`
- File synchronization: `inotify-rsync`
- Utilities: `envsubst`
