Vooon's OpenWRT Feed
====================

That's may custom packages feed that contains some extra programs I use on some instances.


Installation
------------

This repository is an OpenWRT feed with extra packages.

1. Add this line to `feeds.conf`:
```
src-git vooon https://github.com/vooon/my-openwrt-feed.git
```

2. Run feeds update & install:
```shell
./scripts/feeds update -a
./scripts/feeds install -a
```

LLDAP + Authelia
----------------

SSO combo i found easiest to build and deploy.


Mox
---

Lightweight E-mail server with easy deploy for self-host.


Gotify
------

Push notification server supported by Proxmox.


Proxmox Backup Client
---------------------

Simple backup for services above...


QEMU Instance init
------------------

Helper script for qemu vm init.d.
