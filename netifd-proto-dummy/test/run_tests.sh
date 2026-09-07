#!/bin/sh
# Unit tests for the netifd dummy-interface proto plugin.
#
# Loads files/lib/netifd/proto/dummy.sh with INCLUDE_ONLY=1, mocks the
# netifd proto-shell helpers (json_get_vars / proto_*) and provides a fake
# `ip` binary that logs its argv, then asserts the exact commands issued and
# the netifd protocol responses.
#
# Usage: test/run_tests.sh

set -u

cd "$(dirname "$0")"
SCRIPT="../files/lib/netifd/proto/dummy.sh"

failures=0

# --- sandbox with a fake `ip` ---------------------------------------------
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

IP_FAKE_LOG="$sandbox/ip.log"

cat > "$sandbox/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$IP_FAKE_LOG"
case "$2" in
	add)  exit "${ip_add_exit:-0}" ;;
	show) exit "${ip_show_exit:-0}" ;;
	set)  exit "${ip_set_exit:-0}" ;;
	*)    exit "${ip_other_exit:-0}" ;;
esac
EOF
chmod +x "$sandbox/ip"
export IP_FAKE_LOG
export PATH="$sandbox:$PATH"

# exit-code knobs for the fake `ip`, read per subcommand
ip_add_exit=0
ip_show_exit=0
ip_set_exit=0
ip_other_exit=0
export ip_add_exit ip_show_exit ip_set_exit ip_other_exit

# --- netifd proto-shell / json stubs --------------------------------------
json_get_vars() {
	local v
	for v in "$@"; do
		eval "$v=\"\${fake_$v:-}\""
	done
}

# json_get_values: for the ipaddr/ip6addr arrays, fake_<name> holds the
# space-separated list.
json_get_values() {
	local dest="$1"
	eval "$dest=\"\${fake_$2:-}\""
}
proto_config_add_string() { proto_config_added="$proto_config_added $1"; }
proto_config_add_array()   { proto_config_added="$proto_config_added $1"; }
proto_init_update() { update_ifname="$1"; update_up="$2"; update_external="${3:-}"; }
proto_send_update() { update_sent="$1"; }
proto_notify_error() { proto_error="$1${2:+ $2}"; }
proto_block_restart() { proto_blocked="$1"; }
proto_add_ipv4_address() { PROTO_IPADDR="${PROTO_IPADDR:+$PROTO_IPADDR }$1/$2/$3/$4"; }
proto_add_ipv6_address() { PROTO_IP6ADDR="${PROTO_IP6ADDR:+$PROTO_IP6ADDR }$1/$2/$3/$4/$5/$6"; }
proto_add_ipv4_route() { PROTO_ROUTE="${PROTO_ROUTE:+$PROTO_ROUTE }$1/$2/$3/$4///$5"; }
proto_add_ipv6_route() { PROTO_ROUTE6="${PROTO_ROUTE6:+$PROTO_ROUTE6 }$1/$2/$3/$4/$5/$6/$7"; }

reset_state() {
	ip_add_exit=0; ip_show_exit=0; ip_set_exit=0; ip_other_exit=0
	fake_macaddr=""; fake_ipaddr=""; fake_ip6addr=""
	fake_netmask=""; fake_broadcast=""; fake_ptpaddr=""
	fake_gateway=""; fake_ip6gw=""
	proto_config_added=""
	update_ifname=""; update_up=""; update_external=""; update_sent=""
	proto_error=""; proto_blocked=""
	PROTO_IPADDR=""; PROTO_IP6ADDR=""; PROTO_ROUTE=""; PROTO_ROUTE6=""
	: > "$IP_FAKE_LOG"
}

fail() {
	echo "FAILED: $1"
	failures=$((failures + 1))
}

pass() {
	echo "ok: $1"
}

expect_log() {
	local expected="$1"
	local desc="$2"
	local got
	got="$(cat "$IP_FAKE_LOG")"
	if [ "$got" = "$expected" ]; then
		pass "$desc"
	else
		fail "$desc"
		echo "  expected ip command(s):"
		echo "$expected" | sed 's/^/    /'
		echo "  got:"
		echo "$got" | sed 's/^/    /'
	fi
}

# --- syntax check ----------------------------------------------------------
if sh -n "$SCRIPT"; then
	pass "sh -n dummy.sh"
else
	fail "sh -n dummy.sh"
fi

# --- load the plugin in INCLUDE_ONLY mode ----------------------------------
INCLUDE_ONLY=1
. "$SCRIPT"

# --- tests -----------------------------------------------------------------

# 1: init_config dump
reset_state
proto_dummy_init_config
if [ "$no_device" = 1 ] && [ "$available" = 1 ]; then
	pass "init_config: no_device + available"
else
	fail "init_config: no_device + available (no_device=$no_device available=$available)"
fi
if [ "$proto_config_added" = " macaddr ipaddr ip6addr netmask broadcast ptpaddr gateway ip6gw" ]; then
	pass "init_config: declares macaddr/ipaddr/ip6addr/etc options"
else
	fail "init_config: declares macaddr/ipaddr/ip6addr/etc options (got '$proto_config_added')"
fi

# 2: plain create
reset_state
proto_dummy_setup dummy_vip ""
expect_log "ip link add dummy_vip type dummy" "create: runs 'ip link add <cfg> type dummy'"
if [ "$update_ifname" = dummy_vip ] && [ "$update_up" = 1 ] && [ "$update_sent" = dummy_vip ]; then
	pass "create: claims the device via proto_init_update/send"
else
	fail "create: claims the device via proto_init_update/send (ifname=$update_ifname up=$update_up sent=$update_sent)"
fi
if [ -z "$proto_error" ] && [ -z "$proto_blocked" ]; then
	pass "create: no error or block_restart"
else
	fail "create: no error or block_restart (error='$proto_error' blocked='$proto_blocked')"
fi

# 3: create honours macaddr + emits addresses
reset_state
fake_macaddr="00:11:22:33:44:55"
fake_ipaddr="192.168.1.2/24 10.0.0.1/8"
fake_ip6addr="fd00::1/128"
fake_ptpaddr="192.168.1.1"
proto_dummy_setup dummy_vip ""
expect_log "ip link add dummy_vip type dummy
ip link set dummy_vip address 00:11:22:33:44:55" "create: sets macaddr"
if [ "$PROTO_IPADDR" = "192.168.1.2/24//192.168.1.1 10.0.0.1/8//192.168.1.1" ] &&
   [ "$PROTO_IP6ADDR" = "fd00::1/128////" ]; then
	pass "create: re-emits ipaddr/ip6addr into the netifd update"
else
	fail "create: re-emits ipaddr/ip6addr into the netifd update (ipaddr='$PROTO_IPADDR' ip6addr='$PROTO_IP6ADDR')"
fi
if [ "$update_sent" = dummy_vip ]; then
	pass "create: still sends the update with addresses"
else
	fail "create: still sends the update with addresses (sent='$update_sent')"
fi

# 3b: bare address without prefix falls back to netmask
reset_state
fake_ipaddr="192.168.5.9"
fake_netmask="26"
proto_dummy_setup dummy_vip ""
if [ "$PROTO_IPADDR" = "192.168.5.9/26//" ]; then
	pass "create: bare v4 address uses 'netmask' option"
else
	fail "create: bare v4 address uses 'netmask' option (got '$PROTO_IPADDR')"
fi

# 3c: gateway delivered as default route
reset_state
fake_ipaddr="172.16.0.2/30"
fake_gateway="172.16.0.1"
fake_ip6gw="fd00::1"
proto_dummy_setup dummy_vip ""
if [ "$PROTO_ROUTE" = "0.0.0.0/0/172.16.0.1////" ] &&
   [ "$PROTO_ROUTE6" = "::/0/fd00::1////" ]; then
	pass "create: emits default (v4+v6) routes for gateway/ip6gw"
else
	fail "create: emits default (v4+v6) routes for gateway/ip6gw (route='$PROTO_ROUTE' route6='$PROTO_ROUTE6')"
fi

# 4: device already present -> keep it, still claim it
reset_state
ip_add_exit=1
ip_show_exit=0
proto_dummy_setup dummy_vip ""
expect_log "ip link add dummy_vip type dummy
ip link show dummy_vip" "pre-existing: falls back to 'ip link show'"
if [ "$update_sent" = dummy_vip ] && [ -z "$proto_error" ] && [ -z "$proto_blocked" ]; then
	pass "pre-existing: keeps going, no error"
else
	fail "pre-existing: keeps going, no error (sent='$update_sent' error='$proto_error' blocked='$proto_blocked')"
fi

# 5: hard failure -> notify error + block restart, no update
reset_state
ip_add_exit=1
ip_show_exit=1
proto_dummy_setup dummy_vip ""
if [ "$proto_error" = "dummy_vip DEVICE_CREATE_FAIL" ] &&
   [ "$proto_blocked" = dummy_vip ] &&
   [ -z "$update_sent" ]; then
	pass "failure: DEVICE_CREATE_FAIL + block_restart, no update"
else
	fail "failure: DEVICE_CREATE_FAIL + block_restart, no update (error='$proto_error' blocked='$proto_blocked' sent='$update_sent')"
fi

# 5b: invalid MAC (e.g. truncated/multicast) -> error surfaced, but the
#     device is still brought up and the addresses applied
reset_state
fake_macaddr="11:22:33:44:55"
ip_set_exit=1
fake_ipaddr="192.168.99.2/24"
proto_dummy_setup dummy_vip ""
if [ "$proto_error" = "dummy_vip INVALID_MACADDR" ] &&
   [ -z "$proto_blocked" ] &&
   [ "$update_sent" = dummy_vip ]; then
	pass "invalid macaddr: surfaces INVALID_MACADDR but still brings the device up"
else
	fail "invalid macaddr: surfaces INVALID_MACADDR but still brings the device up (error='$proto_error' blocked='$proto_blocked' sent='$update_sent')"
fi

# 6: teardown removes the device
reset_state
proto_dummy_teardown dummy_vip dummy_vip
expect_log "ip link del dummy_vip" "teardown: deletes the device by ifname"

reset_state
proto_dummy_teardown dummy_vip ""
expect_log "ip link del dummy_vip" "teardown: falls back to the interface name"

# --- summary --------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
	echo "all tests passed"
	exit 0
fi

echo "FAILED: $failures test(s)" >&2
exit 1