#!/bin/sh

set -o pipefail

backup_log="$(mktemp -t pbs-backup.log.XXXXXX)"
atexit() {
	rm -f "$backup_log"
}
trap atexit EXIT

if [ -z "$HOSTNAME" ]; then
	export HOSTNAME="$(uname -n)"
fi

. /etc/pbs.env
. /usr/share/libubox/jshn.sh

: "${PBS_BACKUP_NAME:=rootfs}"
: "${PBS_PREFIX:=/}"

if [ -n "$PBS_NAMESPACE" ]; then
	proxmox-backup-client backup --ns "$PBS_NAMESPACE" "${PBS_BACKUP_NAME}.pxar:${PBS_PREFIX}" "$@" 2>&1 | tee "$backup_log"
else
	proxmox-backup-client backup "${PBS_BACKUP_NAME}.pxar:${PBS_PREFIX}" "$@" 2>&1 | tee "$backup_log"
fi
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

msg_md="$(printf '```\n%s\n```\n' "$(cat "$backup_log")")"

json_init
json_add_string title "$HOSTNAME $PBS_BACKUP_NAME backup: $stat"
json_add_string message "$msg_md"
json_add_int priority "$prio"
json_add_object extras
json_add_object "client::display"
json_add_string contentType "text/markdown"
json_close_object
json_close_object

json_dump | curl -fsS "$GOTIFY_URL/message" \
	-H "X-Gotify-Key: $GOTIFY_APP_TOKEN" \
	-H "Content-Type: application/json" \
	-X POST \
	--data-binary @-
rc2=$?

[ "$rc" -ne 0 ] && exit "$rc"
exit $rc2
