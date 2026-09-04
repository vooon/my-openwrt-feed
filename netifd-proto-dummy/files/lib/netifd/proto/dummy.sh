#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_dummy_setup() {
	local cfg="$1"
	local macaddr

	json_get_vars macaddr

	# Create the device. If it already exists (e.g. left over from a crashed
	# teardown or created elsewhere), keep it instead of failing the ifup.
	if ! ip link add "$cfg" type dummy 2>/dev/null &&
	   ! ip link show "$cfg" >/dev/null 2>&1; then
		proto_notify_error "$cfg" "DEVICE_CREATE_FAIL"
		proto_block_restart "$cfg"
		return
	fi

	[ -n "$macaddr" ] && ip link set "$cfg" address "$macaddr"

	proto_init_update "$cfg" 1
	proto_send_update "$cfg"
}

proto_dummy_teardown() {
	local cfg="$1"
	local ifname="${2:-$1}"

	ip link del "$ifname" 2>/dev/null
}

proto_dummy_init_config() {
	no_device=1
	available=1
	proto_config_add_string "macaddr"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol dummy
}