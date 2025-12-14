qemu-instance-init
==================

https://openwrt.org/docs/guide-user/virtualization/qemu_host#init_script

A init script initially based on openwrt wiki, but ported to procd.
Also supports backup by `proxmox-backup-client`.


Instance configuration
----------------------

```uci
config instance 'unifi'
	option enabled		'1'	# default 1
	option vcpus		'2'	# amount of cores, default 1
	option ram		'2G'	# amount of ram, default 512M
	option cpu_type		'host'	# cpu type, default host
	option uuid		'617c3275-5553-4980-9d48-789ab6c59abc'	# machine uuid, default generated from instance name
	option vnc		'none'	# -vnc option, default none
	option qmp_port		'4444'	# port to bind for QMP, **required**
	option root_disk	'/dev/vg0/vm-unifi-os-server'	# path to root disk device/file
	option root_disk_type	'lvm'			# type of the disk. currently qcow2 or lvm
	option net0_mac		'E2:F2:6A:01:9D:CA'	# mac for first virtio-net adapter, default - do not create port
	option net0_bridge	br-lan			# bridge for net0, default br-lan
	list extra_args ''				# any additional configuration arguments

	# pbs backup
	option backup 1
	option backup_client pbs_server
	# option backup_id "$hostname-$instance"
```
