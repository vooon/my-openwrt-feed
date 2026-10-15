qemu-instance-init
==================

https://openwrt.org/docs/guide-user/virtualization/qemu_host#init_script

A init script initially based on openwrt wiki, but ported to procd.
Two variants (mutually exclusive, install one):

- `qemu-instance-init` - the procd init script only. Depends on `uuidgen`
  and ucode (`ucode-mod-socket`): `/usr/libexec/qemu-qmp <socket> <command>
  [<json args>]` (module `qemu.qmp`) sends QMP commands, e.g.
  `system_powerdown` on stop.
- `qemu-instance-init-pbs` - the same init script plus backup by
  `proxmox-backup-client`: `/etc/init.d/qemu backup [instance]` (the command
  only exists in this variant) runs `/usr/libexec/qemu-backup`, a ucode script
  built on `pbs-helper`'s job runner (`pbs.helper`). Backup output goes to syslog as
  `qemu.<instance>` (stderr on a terminal); Healthchecks and Gotify reporting
  are independent and both optional.


Instance configuration
----------------------

```uci
config instance 'instance-name'
```

| Name                  | Type    | Required  | Default  | Description |
|-----------------------|---------|-----------|----------|-------------|
| `enabled`             | bool    | no        | 1        | Enable instance |
| `vcpus`               | string  | no        | 1        | Amount of vCPUs |
| `ram`                 | string  | no        | 512M     | Amount of RAM |
| `cpu_type`            | string  | no        | host     | CPU type |
| `uuid`                | string  | no        | *generated* | Machine UUID, may be generated |
| `vnc`                 | string  | no        | `none`   | Value for -vnc, e.g. `:0` |
| `qmp_socket`          | string  | no        | `/var/run/qemu.$instance.qmp.sock` | QMP unix socket path |
| `root_disk`           | string  | yes       | *(none)* | path to the root disk |
| `root_disk_type`      | string  | no        | qcow2    | type of the disk: `qcow2` or `lvm` |
| `uefi_code`           | string  | no        | *(none)* | path to `OMVF_CODE.fd` - required to enable UEFI |
| `uefi_vars`           | string  | no        | *(none)* | path to `OMVF_VARS.fd` |
| `net0_mac`            | string  | no        | *(none)* | Create virtio-net adapter port with this MAC |
| `net0_bridge`         | string  | no        | `br-lan` | Linux bridge, where port above should be connected to |
| `guest_agent`         | bool    | no        | 0        | Enable QEMU Guest Agent socket device |
| `guest_agent_socket`  | string  | no        | `/var/run/qemu.$instance.qga.sock` | Socket path for option above |
|-----------------------|---------|-----------|----------|-------------|
| `extra_args`          | []string | no       | []       | List of additional custom arguments. |
|-----------------------|---------|-----------|----------|-------------|
| `backup`              | bool    | no        | 0        | Enable backup for the instance |
| `backup_server`       | string  | yes*      | *(none)* | Backup server section name |
| `backup_id`           | string  | no        | `${hostname}-vm-${instance}` | Backup ID |
| `backup_snapshot`     | bool    | no        | 1        | Back up a running VM from a snapshot: LVM snapshot LV (`lvm`) or QEMU overlay (`qcow2`) |
| `backup_snapshot_size`| string  | no        | `10%ORIGIN` | `lvm`: snapshot size for `lvcreate` (`-l` with `%`, else `-L`, e.g. `4G`); must hold the guest's writes during a backup |
| `backup_snapshot_dir` | string  | no        | the disk's dir | `qcow2`: directory for the temporary overlay `<instance>.pbs-overlay.qcow2` |
| `backup_fsfreeze`     | bool    | no        | `guest_agent` | Freeze guest filesystems via qemu-guest-agent around the snapshot (or a freeze+thaw flush without one) |
| `hc_ping_url`         | string  | no        | *(none)* | [Healthchecks](https://healthchecks.io/docs/http_api/) ping URL for this instance's backup: `/start` before, `/<exit code>` after (head and tail of the backup log as body) |


Consistent backups of running VMs
---------------------------------

`qemu-instance-init-pbs` keeps the disk of a running instance stable while
`proxmox-backup-client` reads it (module `qemu.backup`):

1. `guest-fsfreeze-freeze` through qemu-guest-agent (`backup_fsfreeze`):
   the guest flushes its caches and stops writing;
2. snapshot (`backup_snapshot`):
   - `lvm` disks: `lvcreate -s` of the origin LV (`kmod-dm-snapshot`, pulled
     in by this package: OpenWrt's `kmod-dm` has `CONFIG_DM_SNAPSHOT=n`);
   - `qcow2` disks: QMP `blockdev-snapshot-sync`, guest writes go to a
     temporary qcow2 overlay in `backup_snapshot_dir`, the base file is static;
3. `guest-fsfreeze-thaw` right away - the guest is frozen only for step 2;
4. the snapshot LV / the base file is backed up (same `disk0.img` archive);
5. `lvremove`, or `block-commit` + `block-job-complete` merging the overlay
   back (then deleted).

Missing pieces degrade with a warning in the Gotify/Healthchecks report: no
agent → snapshot only (crash-consistent, but point in time); no snapshot →
freeze+thaw flush, then the live disk. A full LVM snapshot (too small
`backup_snapshot_size`) becomes invalid and fails that backup run.

A stale snapshot LV is removed by the next backup. An overlay left behind (backup killed, VM stopped during a backup) is merged
automatically: online by the next backup, offline (`qemu-img commit`) by
`/etc/init.d/qemu start`, which refuses to start the instance if that fails.

Proxmox Backup Server configuration
-----------------------------------

Used by `qemu-instance-init-pbs`. The password is passed to
`proxmox-backup-client` via `PBS_PASSWORD_CMD` (`uci -q get qemu.<section>.password`),
so it never appears on a command line.

https://pbs.proxmox.com/docs-1/backup-client.html#environment-variables

```uci
config proxmox_backup_server 'pbs_server'
```

| Name                  | Type    | Required  | Default  | Description |
|-----------------------|---------|-----------|----------|-------------|
| `repository` 					| string  | yes       | *(none)* | repository |
| `password` 						| string  | yes       | *(none)* | password |
| `fingerprint` 				| string  | no        | *(none)* | server certificate fingerprint |
| `namespace` 					| string  | no        | *(none)* | use namespace |
|-----------------------|---------|-----------|----------|-------------|
| `gotify_url` 					| string 	| no 				| *(none)* | URL to Gotify server for notifications (Markdown). Disabled if unset; independent of `hc_ping_url`. |
| `gotify_app_token` 		| string 	| yes       | *(none)* | Gotify application token |
