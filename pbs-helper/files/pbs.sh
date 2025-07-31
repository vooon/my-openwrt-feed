#!/bin/sh

set -o pipefail

backup_log=/tmp/pbs-backup.log
if [ -z "$HOSTNAME" ]; then
	export HOSTNAME="$(uname -n)"
fi

. /etc/pbs.env

proxmox-backup-client backup --ns "$PBS_NAMESPACE" "$PBS_BACKUP_NAME.pxar:/" "$@" 2>&1 | tee $backup_log
rc=$?

if [ -z "$GOTIFY_URL" ]; then
	exit $rc
fi

if [ $rc -gt 0 ]; then
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
	-F "title=$HOSTNAME backup: $stat" \
	-F "message=\`\`\`\n$(cat $backup_log)\n\`\`\`" \
	-F "priority=$prio"
rc2=$?

[ $rc -gt 0 ] && exit $rc
exit $rc2
