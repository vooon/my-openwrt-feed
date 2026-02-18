#!/bin/sh
# shellcheck shell=busybox

LOG_TAG=$(basename "$0")
enable_debug=0

. /lib/functions.sh

_log() {
	local level="$1"
	shift
	# local pid=$(readlink /proc/self)  # NOTE: $$ remains the same for subshells
	# logger -s -t "${LOG_TAG}[$$:$pid]" -p "daemon.$level" "$level:" "$@"
	logger -s -t "${LOG_TAG}[$$]" -p "daemon.$level" "$level:" "$@"
}

log_error() {
	_log err "$@"
}
log_warn() {
	_log warning "$@"
}
log_info() {
	_log info "$@"
}
log_debug() {
	[ "$enable_debug" -eq 0 ] && return
	_log debug "$@"
}

sync_host() {
	local host="$1"
	local update_url="$2" username="$3" password="$4"
	local origin="$5"
	local select_instance="$6" select_tag="$7"

	local name ip tag instance dns
	config_get name "$host" name
	config_get ip "$host" ip
	config_get tag "$host" tag
	config_get instance "$host" instance
	config_get_bool dns "$host" dns 0

	if [ "$dns" -eq 0 ]; then
		log_debug "option dns is off, skipping: $name"
		return
	fi

	if [ -n "$select_instance" ] && [ "$select_instance" != "$instance" ]; then
		log_debug "filter by instance: $name"
		return
	fi

	if [ -n "$select_tag" ] && ! list_contains tag "$select_tag"; then
		log_debug "filter by tag: $name"
		return
	fi

	# NOTE: possible to query if address needs update, like ddns.sh does,
	#       but zoneomatic compares addresses anyway...
	curl -fsS --connect-timeout 5 --max-time 15 \
		"$update_url" -u "$username:$password" -G \
		-d "hostname=$name.$origin" -d "myip=$ip"
	local rc=$?

	if [ $rc -ne 0 ]; then
		log_error "failed to update $name: rc: $rc"
	else
		log_info "updated address for: $name"
	fi
}

_sync_service_task() {
	config_load dhcp
	config_foreach sync_host host "$1" "$2" "$3" "$4" "$5" "$6"
}

sync_service() {
	local instance="$1"

	local enabled update_url username password origin dhcp_instance select_instance select_tag
	config_get_bool enabled "$instance" enabled
	config_get update_url "$instance" update_url
	config_get username "$instance" username
	config_get password "$instance" password
	config_get origin "$instance" origin
	config_get select_instance "$instance" select_instance
	config_get select_tag "$instance" select_tag

	if [ "$enabled" -eq 0 ]; then
		return
	fi

	log_info "syncing service: $instance"
	# run in subinterpreter because function needs to load another config
	( _sync_service_task "$update_url" "$username" "$password" "$origin" "$select_instance" "$select_tag" )
}

do_sync() {
	config_load ddns-dhcp-sync
	config_foreach sync_service service

	wait
}

main() {
	local noexit=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--noexit)
				noexit=1
				;;
			--debug)
				enable_debug=1
				;;
			*)
				echo "unknown option: $1"
				;;
		esac
		shift
	done

	# procd instance must be active to be notified by trigger
	if [ "$noexit" -ne 0 ]; then
		while true; do
			do_sync
			sleep 3600
		done
	else
		do_sync
	fi
}

main "$@"
