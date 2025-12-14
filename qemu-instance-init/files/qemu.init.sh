#!/bin/sh /etc/rc.common

#set -x

START=99
STOP=1

EXTRA_COMMANDS="backup"
EXTRA_HELP="\tbackup\t\trun proxmox-backup for this vm"

qemu_pidfile="/var/run/qemu-unifi.pid"
qemu_logfile="/srv/log/qemu-unifi.log"
qemu_uuid="617c3275-5553-4980-9d48-789ab6c59abc"
qemu_qmp_port=4444

start() {
qemu-system-x86_64 -enable-kvm -cpu host -smp 2 -m 2G \
	-uuid $qemu_uuid \
	-device virtio-scsi-pci,id=scsi \
	-drive id=root-img,format=raw,file=/dev/tiberium-vg0/vm-unifi-os-server,if=virtio,cache.direct=on \
	-device virtio-net-pci,mac=E2:F2:6A:01:9D:CA,netdev=br0 \
	-netdev bridge,br=br-lan,id=br0 \
	-vnc none \
	-qmp tcp:127.0.0.1:$qemu_qmp_port,server,nowait \
	-daemonize &> $qemu_logfile

	# -device scsi-hd,drive=root-img \

#/usr/bin/pgrep qemu-system-x86_64 > $qemu_pidfile
/usr/bin/pgrep -f "qemu-system-x86_64.*$qemu_uuid" > $qemu_pidfile
echo "QEMU: Started VM with PID $(cat $qemu_pidfile)."
}

stop() {
echo "QEMU: Sending 'system_powerdown' to VM with PID $(cat $qemu_pidfile)."
nc localhost $qemu_qmp_port <<QMP
{ "execute": "qmp_capabilities" }
{ "execute": "system_powerdown" }
QMP

if [ -e $qemu_pidfile ]; then
	if [ -e /proc/$(cat $qemu_pidfile) ]; then
		echo "QEMU: Waiting for VM shutdown."
		while [ -e /proc/$(cat $qemu_pidfile) ]; do sleep 1s; done
		echo "QEMU: VM Process $(cat $qemu_pidfile) finished."
	else
		echo "QEMU: Error: No VM with PID $(cat $qemu_pidfile) running."
	fi

	rm -f $qemu_pidfile
else
	echo "QEMU: Error: $qemu_pidfile doesn't exist."
fi
}

backup() {
echo "QEMU: Sending 'block-flush' to VM with PID $(cat $qemu_pidfile)."
nc localhost $qemu_qmp_port <<QMP
{ "execute": "block-flush", "arguments": { "device": "drive0" } }
QMP

/srv/vm/pbs-vm.sh vm-unifi-os-server /dev/tiberium-vg0/vm-unifi-os-server
}
