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
- Routing and overlays: `frr`, `gobgp`, `nebula`, `pathosd`, `vpn-sticky`
- DNS automation: `ddns-dhcp-sync`, `zoneomatic`
- Monitoring: `prometheus-node-exporter-ucode`, `frr-exporter`,
  `smokeping-prober`, `squid-exporter`, `unbound-exporter`
- Backup and virtualization: `proxmox-backup`, `pbs-helper`,
  `qemu-instance-init`, `rsync-sysupgrade`
- File synchronization: `inotify-rsync`
- Utilities: `envsubst`
