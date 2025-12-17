#!/bin/sh
# shellcheck shell=busybox

LOG_TAG=$(basename "$0")

. /lib/functions.sh

_log() {
	local level="$1"
	shift
	logger -s -t "${LOG_TAG}[$$]" -p "daemon.$level" "$level:" "$@"
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

sync_host() {
	local host="$1"
	local update_url="$2" username="$3" password="$4"
	local origin="$5"
	local dhcp_instance="$6"

	local name ip instance dns
	config_get name "$host" name
	config_get ip "$host" ip
	config_get instance "$host" instance
	config_get_bool dns "$host" dns 0

	if [ "$dns" -eq 0 ]; then
		log_debug "option dns is off, skipping: $name"
		return
	fi

	if [ -n "$dhcp_instance" ] && [ "$dhcp_instance" != "$instance" ]; then
		log_debug "filter by instance: $name"
		return
	fi

	# NOTE: possible to query if address needs update, like ddns.sh does,
	#       but zoneomatic compares addresses anyway...
	curl "$update_url" -u "$username:$password" -G -d "hostname=$name.$origin" -d "myip=$ip"
	local rc=$?

	if [ $rc -ne 0 ]; then
		log_error "failed to update $name: rc: $rc"
	else
		log_info "updated address for: $name"
	fi
}

sync_service() {
	local instance="$1"

	local update_url username password origin dhcp_instance dhcp_instance
	config_get update_url "$instance" update_url
	config_get username "$instance" username
	config_get password "$instance" password
	config_get origin "$instance" origin
	config_get dhcp_instance "$instance" dhcp_instance

	config_load dhcp
	config_foreach sync_host host "$update_url" "$username" "$password" "$origin" "$dhcp_instance"
}

main() {
	config_load ddns-dhcp-sync
	config_foreach sync_service service
}

main "$@"
