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


Package overview
----------------

### Web and identity

| Package      | Description                                              |
|--------------|----------------------------------------------------------|
| `angie`      | Angie web server (nginx fork)                            |
| `lldap`      | Lightweight LDAP server for self-hosted SSO              |
| `authelia`   | Single Sign-On with multi-factor authentication          |

### Mail and notifications

| Package          | Description                                           |
|------------------|-------------------------------------------------------|
| `mox`            | Low-maintenance self-hosted mail server               |
| `gotify`         | Self-hosted real-time push notification server        |
| `gotify2telegram`| Gotify push forwarding plugin to Telegram             |

### Proxy, tunneling and overlays

| Package           | Description                                           |
|-------------------|-------------------------------------------------------|
| `mihomo-meta`     | mihomo (Clash Meta) rule-based proxy kernel in Go     |
| `meow-rs`         | mihomo-compatible rule-based proxy kernel in Rust     |
| `luci-app-meow`   | LuCI web panel + settings for meow-rs                 |
| `nebula`          | Scalable overlay networking                           |
| `nylon`           | Self-healing WireGuard mesh with Babel routing        |
| `vpn-sticky`      | Sticky VPN policy routing with connmark propagation   |

### Routing protocols

| Package            | Description                                         |
|--------------------|-----------------------------------------------------|
| `rpcd-mod-bird`    | ubus access to the BIRD control socket (status, OSPF cost) |
| `luci-app-bird`    | OSPF/BGP overview page with OSPF cost control       |
| `pathosd`          | Health-driven BGP Anycast announcer daemon          |
| `gobgp`            | GoBGP CLI                                           |

### DNS and network services

| Package           | Description                                          |
|-------------------|------------------------------------------------------|
| `ddns-dhcp-sync`  | Sync local DHCP static hosts with DDNS               |
| `zoneomatic`      | Simple DynDNS API server                             |

### Network interfaces and protocols

| Package                 | Description                                      |
|-------------------------|--------------------------------------------------|
| `netifd-proto-dummy`    | Create dummy interfaces from `config interface … proto dummy` |
| `luci-proto-dummy`      | LuCI UI for dummy interfaces                     |
| `netifd-proto-fou`      | Shared helpers for the netifd FOU tunnel protos  |
| `luci-proto-fou-ip6gre` | LuCI UI for FOU-encapsulated GRE over IPv6       |
| `luci-proto-fou-ip6tnl` | LuCI UI for FOU-encapsulated ip6tnl interfaces   |

### Monitoring and observability

| Package                          | Description                                    |
|----------------------------------|------------------------------------------------|
| `prometheus-node-exporter-ucode` | Prometheus node exporter written in ucode      |
| `frr-exporter`                   | Prometheus exporter for Free Range Routing     |
| `smokeping-prober`               | Prometheus smokeping prober                    |
| `squid-exporter`                 | Prometheus exporter for Squid                  |
| `unbound-exporter`               | Prometheus exporter for Unbound                |
| `bpftop`                         | Real-time view of running eBPF programs        |

### Backup and virtualization

| Package              | Description                                 |
|----------------------|---------------------------------------------|
| `proxmox-backup`     | Proxmox Backup Server client                |
| `pbs-helper`         | Proxmox Backup helper script                |
| `qemu-instance-init` | init.d helper for QEMU instances            |

### File synchronization

| Package         | Description                            |
|-----------------|----------------------------------------|
| `inotify-rsync` | Trigger rsync jobs on inotify events   |

### Libraries and utilities

| Package            | Description                              |
|--------------------|------------------------------------------|
| `ucode-mod-inotify`| ucode module for the Linux inotify API   |
| `ucode-mod-sqlite` | ucode module for the SQLite3 engine      |
| `envsubst`         | Environment variable substitution        |
| `rsync-sysupgrade` | Sysupgrade via rsync                     |

Note: eBPF/IPFIX traffic observability lives in the separate
[`obserwrt`](https://github.com/vooon/obserwrt) feed.