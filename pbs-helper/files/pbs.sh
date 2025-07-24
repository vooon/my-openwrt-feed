#!/bin/sh

. /usr/share/libubox/jshn.sh
. /data/pbs.env

local backup_log=/tmp/pbs-backup.log

proxmox-backup-client backup --ns "$PBS_NAMESPACE" "$PBS_BACKUP_NAME.pxar:/" 2>&1 | tee $backup_log
rc=$?

if [ "$rc" -ge 0 ]; then
	stat="failed rc=$rc"
else
	stat="successful"
fi

json_init
json_add_string title "$HOSTNAME backup: $stat"
json_add_string message "$(cat $backup_log)"
json_close_object

json_dump

# todo call gotify
