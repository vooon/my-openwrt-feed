Vooon's OpenWRT Feed
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

- `lldap`, `authelia`: lightweight auth stack
- `mox`: self-hosted mail server
- `gotify`, `gotify2telegram`, `gotify-alertmanager-plugin`: notification tooling
- `proxmox-backup`, `pbs-helper`: backup client and helper scripts
- `qemu-instance-init`: procd init helper for QEMU VMs
- `inotify-rsync`: rsync on filesystem changes
- `ddns-dhcp-sync`, `zoneomatic`: DNS and DHCP sync/update helpers
- `prometheus-node-exporter-ucode`, `frr-exporter`: monitoring/exporter packages
- `watchcat-fix`, `envsubst`: utility packages
