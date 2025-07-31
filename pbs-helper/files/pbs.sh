#!/bin/sh

set -o pipefail

backup_log="$(mktemp -u -t pbs-backup.log.XXXXXX)"
atexit() {
	rm -f "$backup_log"
}
trap atexit EXIT

if [ -z "$HOSTNAME" ]; then
	export HOSTNAME="$(uname -n)"
fi

. /etc/pbs.env

: "${PBS_BACKUP_NAME:=rootfs}"
: "${PBS_PREFIX:=/}"

proxmox-backup-client backup --ns "$PBS_NAMESPACE" "${PBS_BACKUP_NAME}.pxar:${PBS_PREFIX}" "$@" 2>&1 | tee "$backup_log"
rc=$?

if [ -z "$GOTIFY_URL" ]; then
	exit $rc
fi

if [ $rc -ne 0 ]; then
	stat="failed rc=$rc"
	prio=9
else
	stat="successful"
	prio=1
fi

# . /usr/share/libubox/jshn.sh
# json_int
# json_add_string title "$HOSTNAME backup: $stat"
# json_add_string message "$(cat $backup_log)"
# json_add_int priotity $prio
# json_close_object

curl "$GOTIFY_URL/message" -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" -X POST \
	-F "title=$HOSTNAME $PBS_BACKUP_NAME backup: $stat" \
	-F "$(printf 'message=```\n%s\n```\n' "$(cat $backup_log)")" \
	-F "priority=$prio"
rc2=$?

[ $rc -ne 0 ] && exit $rc
exit $rc2
