#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_dummy_setup() {
	local cfg="$1"
	local macaddr ipaddr ip6addr gateway ip6gw netmask broadcast ptp
	local addr mask

	json_get_vars macaddr netmask broadcast ptpaddr gateway ip6gw
	json_get_values ipaddr ipaddr
	json_get_values ip6addr ip6addr

	# Create the device. If it already exists (e.g. left over from a crashed
	# teardown or created elsewhere), keep it instead of failing the ifup.
	if ! ip link add "$cfg" type dummy 2>/dev/null &&
	   ! ip link show "$cfg" >/dev/null 2>&1; then
		proto_notify_error "$cfg" "DEVICE_CREATE_FAIL"
		proto_block_restart "$cfg"
		return
	fi

	if [ -n "$macaddr" ]; then
		if ! ip link set "$cfg" address "$macaddr" 2>/dev/null; then
			# Report the bad MAC without taking the device down: the dummy
			# still works with the kernel-assigned MAC and the configured
			# addresses are still applied.
			proto_notify_error "$cfg" "INVALID_MACADDR"
		fi
	fi

	proto_init_update "$cfg" 1

	for addr in $ipaddr; do
		mask="${addr#*/}"
		[ "$mask" != "$addr" ] && mask="$mask" || mask="${netmask:-255.255.255.0}"
		proto_add_ipv4_address "${addr%%/*}" "$mask" "$broadcast" "$ptpaddr"
	done

	for addr in $ip6addr; do
		mask="${addr#*/}"
		[ "$mask" != "$addr" ] && mask="$mask" || mask="128"
		proto_add_ipv6_address "${addr%%/*}" "$mask" "" "" "" ""
	done

	[ -n "$gateway" ] && proto_add_ipv4_route "0.0.0.0" "0" "$gateway" "" ""
	[ -n "$ip6gw" ] && proto_add_ipv6_route "::" "0" "$ip6gw" "" "" "" ""

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
	proto_config_add_array "ipaddr"
	proto_config_add_array "ip6addr"
	proto_config_add_string "netmask"
	proto_config_add_string "broadcast"
	proto_config_add_string "ptpaddr"
	proto_config_add_string "gateway"
	proto_config_add_string "ip6gw"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol dummy
}