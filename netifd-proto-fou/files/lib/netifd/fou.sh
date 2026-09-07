#!/bin/sh
# Shared helpers for the netifd FOU (Foo-over-UDP) tunnel protos
# (fou-ip6gre, fou-ip6tnl). Sourced from /lib/netifd/proto/*.sh, which
# netifd runs with cwd /lib/netifd/proto, so the relative `. ../fou.sh`
# resolves here.

fou_common_init_config() {
	no_device=1
	available=1
	proto_config_add_string "laddr"
	proto_config_add_string "peeraddr"
	proto_config_add_boolean "listen"
	proto_config_add_int "port"
	proto_config_add_string "sport"
	proto_config_add_int "ipproto"
	proto_config_add_boolean "csum"
	proto_config_add_int "mtu"
	proto_config_add_int "ttl"
	proto_config_add_int "tos"
	proto_config_add_array "ipaddr"
	proto_config_add_array "ip6addr"
	proto_config_add_string "netmask"
	proto_config_add_string "broadcast"
	proto_config_add_string "ptpaddr"
	proto_config_add_string "gateway"
	proto_config_add_string "ip6gw"
}

fou_common_setup() {
	local cfg="$1"
	local linktype="$2"
	local muxmode="$3"
	local dflt_ipproto="$4"
	local laddr peeraddr port sport ipproto csum mtu ttl tos listen
	local ipaddr ip6addr netmask broadcast ptpaddr gateway ip6gw addr mask
	local fou_af=""

	json_get_vars laddr peeraddr port sport ipproto csum mtu ttl tos listen \
		netmask broadcast ptpaddr gateway ip6gw
	json_get_values ipaddr ipaddr
	json_get_values ip6addr ip6addr

	[ -n "$laddr" ] || {
		proto_notify_error "$cfg" "MISSING_LOCAL_ADDRESS"
		proto_block_restart "$cfg"
		return
	}

	if [ "$listen" != "1" ] && [ -z "$peeraddr" ]; then
		proto_notify_error "$cfg" "MISSING_PEER_ADDRESS"
		proto_block_restart "$cfg"
		return
	fi

	port=${port:-5555}
	sport=${sport:-auto}
	[ -n "$ipproto" ] || ipproto="$dflt_ipproto"

	# This proto is an IPv6-underlay tunnel; iproute2's `ip fou` needs an
	# explicit -6, otherwise the local address is parsed as IPv4.
	local fou_af=""
	case "$laddr" in
		*:*) fou_af="-6" ;;
	esac

	# Register the FOU listener. Best effort: it may already be present on
	# this side or be owned by another tunnel; both ends register so return
	# traffic can be decapsulated too.
	ip fou add port "$port" ipproto "$ipproto" $fou_af ${laddr:+local "$laddr"} 2>/dev/null

	# Create the tunnel. If it already exists (e.g. leftover from a crashed
	# teardown or created elsewhere), keep it instead of failing the ifup.
	if ! ip link add "$cfg" type "$linktype" \
		${muxmode:+mode "$muxmode"} \
		local "$laddr" \
		${peeraddr:+remote "$peeraddr"} \
		${ttl:+ttl "$ttl"} \
		${tos:+tos "$tos"} \
		encap fou encap-sport "$sport" encap-dport "$port" \
		${csum:+encap-csum} \
		2>/dev/null &&
	   ! ip link show "$cfg" >/dev/null 2>&1; then
		proto_notify_error "$cfg" "DEVICE_CREATE_FAIL"
		proto_block_restart "$cfg"
		return
	fi

	[ -n "$mtu" ] && ip link set "$cfg" mtu "$mtu"

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

fou_common_teardown() {
	local cfg="$1"
	local ifname="${2:-$1}"
	local port laddr fou_af=""

	json_get_vars port laddr
	port=${port:-5555}

	ip link del "$ifname" 2>/dev/null

	# Match the family used in fou_common_setup.
	case "$laddr" in
		*:*) fou_af="-6" ;;
	esac
	ip fou del port "$port" $fou_af 2>/dev/null
}