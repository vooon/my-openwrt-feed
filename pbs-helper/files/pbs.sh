#!/bin/sh

set -o pipefail

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

backup_log="$(mktemp -t pbs-backup.log.XXXXXX)"
gotify_resp="$(mktemp -t pbs-gotify.log.XXXXXX)"
atexit() {
	rm -f "$backup_log"
	rm -f "$gotify_resp"
}
trap atexit EXIT

if [ -z "$HOSTNAME" ]; then
	export HOSTNAME="$(uname -n)"
fi

config_load pbs

section="pbs_server"
if ! config_get enabled "$section" enabled; then
	echo "pbs-helper: missing '$section' section in /etc/config/pbs" >&2
	exit 2
fi
config_get_bool enabled "$section" enabled 0
[ "$enabled" -ne 0 ] || {
	echo "pbs-helper: disabled in /etc/config/pbs (option enabled '1')" >&2
	exit 0
}

config_get repository "$section" repository ""
config_get password "$section" password ""
config_get fingerprint "$section" fingerprint ""
config_get PBS_NAMESPACE "$section" namespace ""
config_get PBS_BACKUP_NAME "$section" backup_name "rootfs"
config_get PBS_PREFIX "$section" prefix "/"
config_get GOTIFY_URL "$section" gotify_url ""
config_get GOTIFY_APP_TOKEN "$section" gotify_app_token ""

[ -n "$repository" ] || {
	echo "pbs-helper: repository is not configured" >&2
	exit 2
}
[ -n "$password" ] || {
	echo "pbs-helper: password is not configured" >&2
	exit 2
}

export PBS_REPOSITORY="$repository"
export PBS_PASSWORD="$password"
[ -n "$fingerprint" ] && export PBS_FINGERPRINT="$fingerprint"

backup_args=""
append_backup_arg() {
	append backup_args "$1"
}
config_list_foreach "$section" backup_arg append_backup_arg

run_pbs_backup() {
	if [ -n "$PBS_NAMESPACE" ]; then
		proxmox-backup-client backup --ns "$PBS_NAMESPACE" "${PBS_BACKUP_NAME}.pxar:${PBS_PREFIX}" "$@" 2>&1 | tee "$backup_log"
	else
		proxmox-backup-client backup "${PBS_BACKUP_NAME}.pxar:${PBS_PREFIX}" "$@" 2>&1 | tee "$backup_log"
	fi
}

if [ -n "$backup_args" ]; then
	# shellcheck disable=SC2086
	run_pbs_backup $backup_args "$@"
else
	run_pbs_backup "$@"
fi
rc=$?

if [ -z "$GOTIFY_URL" ]; then
	exit $rc
fi

if [ $rc -ne 0 ]; then
	stat="failed rc=$rc"
	prio=9
	msg_md="$(printf '```\n%s\n```\n' "$(cat "$backup_log")")"
else
	stat="successful"
	prio=1
	msg_md="Backup completed successfully."
fi

json_init
json_add_string title "$HOSTNAME $PBS_BACKUP_NAME backup: $stat"
json_add_string message "$msg_md"
json_add_int priority "$prio"
json_add_object extras
json_add_object "client::display"
json_add_string contentType "text/markdown"
json_close_object
json_close_object

http_code="$(json_dump | curl -sS "$GOTIFY_URL/message" \
	-H "X-Gotify-Key: $GOTIFY_APP_TOKEN" \
	-H "Content-Type: application/json" \
	-X POST \
	--data-binary @- \
	-o "$gotify_resp" \
	-w '%{http_code}')"
rc2=$?

if [ "$rc2" -eq 0 ] && [ "${http_code#2}" = "$http_code" ]; then
	# Emulate curl --fail while preserving response body for diagnostics.
	rc2=22
fi
[ "$rc2" -ne 0 ] && [ -s "$gotify_resp" ] && cat "$gotify_resp" >&2

[ "$rc" -ne 0 ] && exit "$rc"
exit $rc2
