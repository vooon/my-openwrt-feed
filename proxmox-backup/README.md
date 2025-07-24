Proxmox Backup Client
=====================

Documentation: https://pbs.proxmox.com/docs/backup-client.html

> [!NOTE]
> I have tested it only on x86_64 with glibc.


Helper script
-------------

A `pbs-helper` package contains helper script to use in cron jobs.
It can notify backup result via Gotify.

Add line like that to your Cron:

```cron
0 1 * * * /usr/bin/pbs.sh
```

Then configure options in `/etc/pbs.env`.
