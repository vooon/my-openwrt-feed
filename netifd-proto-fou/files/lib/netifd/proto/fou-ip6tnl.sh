#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

. ../fou.sh

proto_fou_ip6tnl_setup() {
	local cfg="$1"
	local mode ipproto

	json_get_vars mode

	case "${mode:-ip4ip6}" in
		ip6ip6)
			mode=ip6ip6
			ipproto=ipv6
		;;
		*)
			mode=ip4ip6
			ipproto=ipip
		;;
	esac

	fou_common_setup "$cfg" ip6tnl "$mode" "$ipproto"
}

proto_fou_ip6tnl_teardown() {
	fou_common_teardown "$@"
}

proto_fou_ip6tnl_init_config() {
	fou_common_init_config
	proto_config_add_string "mode"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol fou-ip6tnl
}