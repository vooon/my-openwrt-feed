#!/bin/sh /etc/rc.common

USE_PROCD=1
START=99
STOP=1

# XXX TODO: detect arch
PROG=/usr/bin/qemu-system-x86_64

extra_command "backup" "run proxmox-backup-client"

_log() {
	local level="$1"
	shift
	local instance="$1"
	shift
	logger -s -t "qemu.$instance" -p "daemon.$level" "$level:" "$@"
}

log_error() {
	_log ERROR "$@"
}
log_warn() {
	_log WARN "$@"
}
log_info() {
	_log INFO "$@"
}
log_debug() {
	_log DEBUG "$@"
}

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
		log_warn "$section" "uuid is not set. Generated UUID5 from instance name: $uuid"
	fi

	procd_open_instance "$section"
	procd_set_param command "$PROG" -enable-kvm -cpu "$cpu_type" \
		-smp "$vcpus" -m "$ram" -uuid "$uuid"

	if [ ! -e "$root_disk" ]; then
		log_error "$section" "root disk: $root_disk: does not exist"
		procd_set_param error "root disk: $root_disk: does not exist"
	else
		if [ "$root_disk_type" = "qemu2" ]; then
			procd_append_param command -device virtio-scsi-pci,id=scsi
			# TODO
		fi
		if [ "$root_disk_type" = "lvm" ]; then
			procd_append_param command -device virtio-scsi-pci,id=scsi
			procd_append_param command -drive "id=root-img,format=raw,file=$root_disk,if=virtio,cache.direct=on"
		fi
	fi

	if [ -n "$net0_mac" ]; then
		procd_append_param command -device "virtio-net-pci,mac=$net0_mac,netdev=net0"
		procd_append_param command -netdev "bridge,br=$net0_bridge,id=net0"
	fi

	[ -n "$vnc" ] && procd_append_param command -vnc "$vnc"
	procd_append_param command -qmp "tcp:127.0.0.1:$qmp_port,server,nowait"

	config_list_foreach "$section" extra_args list_append_args

	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param respawn
	procd_set_param term_timeout "$term_timeout"
	procd_set_param pidfile "/var/run/qemu.$section.pid"

	procd_close_instance
}


_stop_instance_task(){
	local section="$1" qmp_port="$2" term_timeout="$3" qemu_pid="$4"

	local qemu_pid=$(cat $pidfile)
	log_info "$section" "sending 'system_powerdown' to VM with PID $qemu_pid."
	nc 127.0.0.1 "$qmp_port" <<-QMP
	{ "execute": "qmp_capabilities" }
	{ "execute": "system_powerdown" }
	QMP

	log_info "$section" "waiting VM to shutdown."
	local elapsed=0
	while [ "$elapsed" -lt "$term_timeout" ]; do
		if [ ! -e "/proc/$qemu_pid" ]; then
			log_info "$section" "VM process finished. elapsed: $elapsed"
			return
		fi

		log_debug "$section" "PID $qemu_pid present. elapsed: $elapsed"

		sleep 1s
		elapsed=$((elapsed + 1))
	done

	log_error "$section" "graceful VM termination timeout reached, giving up to procd"
}

stop_instance() {
	local section=$1

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = 1 ] || return

	local qmp_port term_timeout
	config_get qmp_port "$section" qmp_port 4444
	config_get term_timeout "$section" term_timeout 300

	local pidfile="/var/run/qemu.$section.pid"
	if [ ! -e "$pidfile" ]; then
		log_warn "$section" "pid file: $pidfile: does not exist. Is the instance already stopped?"
		return
	fi

	_stop_instance_task "$section" "$qmp_port" "$term_timeout" "$qemu_pid" &
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
	local instance="$1"

	config_load qemu
	if [ -z "$instance" ]; then
		config_foreach stop_instance instance
	else
		stop_instance "$instance"
	fi

	wait
}




backup() {
echo "QEMU: Sending 'block-flush' to VM with PID $(cat $qemu_pidfile)."
nc localhost $qemu_qmp_port <<QMP
{ "execute": "block-flush", "arguments": { "device": "drive0" } }
QMP

/srv/vm/pbs-vm.sh vm-unifi-os-server /dev/tiberium-vg0/vm-unifi-os-server
}
