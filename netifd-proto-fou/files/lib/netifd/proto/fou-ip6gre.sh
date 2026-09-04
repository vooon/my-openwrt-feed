#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

. ../fou.sh

proto_fou_ip6gre_setup() {
	fou_common_setup "$1" ip6gre "" gre
}

proto_fou_ip6gre_teardown() {
	fou_common_teardown "$@"
}

proto_fou_ip6gre_init_config() {
	fou_common_init_config
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol fou-ip6gre
}