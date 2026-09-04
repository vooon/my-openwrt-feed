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
}

fou_common_setup() {
	local cfg="$1"
	local linktype="$2"
	local muxmode="$3"
	local dflt_ipproto="$4"
	local laddr peeraddr port sport ipproto csum mtu ttl tos listen

	json_get_vars laddr peeraddr port sport ipproto csum mtu ttl tos listen

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

	# Register the FOU listener. Best effort: it may already be present on
	# this side or be owned by another tunnel; both ends register so return
	# traffic can be decapsulated too.
	ip fou add port "$port" ipproto "$ipproto" ${laddr:+local "$laddr"} 2>/dev/null

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
	proto_send_update "$cfg"
}

fou_common_teardown() {
	local cfg="$1"
	local ifname="${2:-$1}"
	local port

	json_get_vars port
	port=${port:-5555}

	ip link del "$ifname" 2>/dev/null
	ip fou del port "$port" 2>/dev/null
}