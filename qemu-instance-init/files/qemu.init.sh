#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=1

# XXX TODO: detect arch
PROG=/usr/bin/qemu-system-x86_64

extra_command "backup" "run proxmox-backup-client"

list_append_args() {
	procd_append_param command "$1"
}

start_instance() {
	local section=$1

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = 1 ] || return

	local vcpus ram cpu_type uuid vnc qmp_port term_timeout
	local root_disk root_disk_type
	local net0_mac net0_bridge
	config_get vcpus "$section" vcpus 1
	config_get ram "$section" ram '512M'
	config_get cpu_type "$section" cpu_type 'host'
	config_get uuid "$section" uuid
	config_get vnc "$section" vnc 'none'
	config_get qmp_port "$section" qmp_port 4444
	config_get term_timeout "$section" term_timeout 300
	config_get root_disk "$section" root_disk
	config_get root_disk_type "$section" root_disk_type 'qcow2'
	config_get net0_mac "$section" net0_mac
	config_get net0_bridge "$section" net0_bridge 'br-lan'

	if [ -z "$uuid" ]; then
		uuid=$(uuidgen --md5 --namespace 5d762436-dc3c-45c4-9896-d078210eec5a --name "$section")
		echo "WARN:$section: uuid is not set. Generated UUID5 from instance name: $uuid"
	fi

	if [ ! -e "$root_disk" ]; then
		echo "ERROR:$section: root disk is not present: $root_disk"
		return
	fi

	procd_open_instance "$section"
	procd_set_param command "$PROG" -enable-kvm -cpu "$cpu_type" \
		-smp "$vcpus" -m "$ram" -uuid "$uuid"

	if [ "$root_disk_type" = "qemu2" ]; then
		procd_append_param command -device virtio-scsi-pci,id=scsi
		# TODO
	fi
	if [ "$root_disk_type" = "lvm" ]; then
		procd_append_param command -device virtio-scsi-pci,id=scsi
		procd_append_param command -drive "id=root-img,format=raw,file=$root_disk,if=virtio,cache.direct=on"
	fi

	if [ -n "$net0_mac" ]; then
		procd_append_param command -device "virtio-net-pci,mac=$net0_mac,netdev=net0"
		procd_append_param command -netdev "bridge,br=$net0_bridge,id=net0"
	fi

	[ -n "$vnc" ] && procd_append_param command -vnc "$vnc"
	procd_append_param command -qmp "tcp:127.0.0.1:$qmp_port,server,nowait"

	config_list_foreach "$instance" extra_args list_append_args

	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn
	procd_set_param term_timeout "$term_timeout"
	procd_set_param pidfile "/var/run/qemu.$section.pid"

	procd_close_instance
}

start_service() {
	local instance="$1"

	config_load qemu
	if [ -z "$instance" ]; then
		config_foreach start_instance instance
	else
		start_instance "$instance"
	fi
}

stop_service() {
	echo "stop 1"
	pgrep qemu
	echo "stop 2"
}


# start() {
# qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 2G \
# 	-uuid $qemu_uuid \
# 	-device virtio-scsi-pci,id=scsi \
# 	-drive id=root-img,format=raw,file=/dev/tiberium-vg0/vm-unifi-os-server,if=virtio,cache.direct=on \
# 	-device virtio-net-pci,mac=E2:F2:6A:01:9D:CA,netdev=br0 \
# 	-netdev bridge,br=br-lan,id=br0 \
# 	-vnc none \
# 	-qmp tcp:127.0.0.1:$qemu_qmp_port,server,nowait \
# 	-daemonize &> $qemu_logfile
# 
# 	# -device scsi-hd,drive=root-img \
# 
# #/usr/bin/pgrep qemu-system-x86_64 > $qemu_pidfile
# /usr/bin/pgrep -f "qemu-system-x86_64.*$qemu_uuid" > $qemu_pidfile
# echo "QEMU: Started VM with PID $(cat $qemu_pidfile)."
# }
# 
# stop() {
# echo "QEMU: Sending 'system_powerdown' to VM with PID $(cat $qemu_pidfile)."
# nc localhost $qemu_qmp_port <<QMP
# { "execute": "qmp_capabilities" }
# { "execute": "system_powerdown" }
# QMP
# 
# if [ -e $qemu_pidfile ]; then
# 	if [ -e /proc/$(cat $qemu_pidfile) ]; then
# 		echo "QEMU: Waiting for VM shutdown."
# 		while [ -e /proc/$(cat $qemu_pidfile) ]; do sleep 1s; done
# 		echo "QEMU: VM Process $(cat $qemu_pidfile) finished."
# 	else
# 		echo "QEMU: Error: No VM with PID $(cat $qemu_pidfile) running."
# 	fi
# 
# 	rm -f $qemu_pidfile
# else
# 	echo "QEMU: Error: $qemu_pidfile doesn't exist."
# fi
# }


backup() {
echo "QEMU: Sending 'block-flush' to VM with PID $(cat $qemu_pidfile)."
nc localhost $qemu_qmp_port <<QMP
{ "execute": "block-flush", "arguments": { "device": "drive0" } }
QMP

/srv/vm/pbs-vm.sh vm-unifi-os-server /dev/tiberium-vg0/vm-unifi-os-server
}
