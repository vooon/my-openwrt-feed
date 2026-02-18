qemu-instance-init
==================

https://openwrt.org/docs/guide-user/virtualization/qemu_host#init_script

A init script initially based on openwrt wiki, but ported to procd.
Also supports backup by `proxmox-backup-client`.

Runtime dependencies used by the script:
- `proxmox-backup-client`
- `curl`
- `uuidgen`
- `jshn`
- `socat`


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


Proxmox Backup Server configuration
-----------------------------------

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
| `gotify_url` 					| string 	| no 				| *(none)* | URL to Gotify server for notifications. Disabled if unset. |
| `gotify_app_token` 		| string 	| yes       | *(none)* | Gotify application token |
