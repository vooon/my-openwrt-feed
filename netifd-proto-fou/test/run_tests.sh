#!/bin/sh
# Unit tests for the netifd fou tunnel protos (fou-ip6gre / fou-ip6tnl).
#
# Copies the plugin files into a temp /lib/netifd layout, stubs the netifd
# proto-shell helpers (json_get_vars / proto_*) and provides a fake `ip`
# that logs its argv, then asserts the exact commands issued per mode, the
# hub "listen" form, the failure paths and teardown.
#
# Usage: test/run_tests.sh

set -u

cd "$(dirname "$0")"

failures=0

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/lib/netifd/proto" "$sandbox/bin"

cp ../files/lib/netifd/fou.sh "$sandbox/lib/netifd/fou.sh"
cp ../files/lib/netifd/proto/fou-ip6gre.sh "$sandbox/lib/netifd/proto/"
cp ../files/lib/netifd/proto/fou-ip6tnl.sh "$sandbox/lib/netifd/proto/"

# --- fake `ip` ------------------------------------------------------------
cat > "$sandbox/bin/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$FAKE_IP_LOG"
case "$1" in
	fou)
		exit "${ip_fou_exit:-0}" ;;
	link)
		case "$2" in
			add)  exit "${ip_add_exit:-0}" ;;
			show) exit "${ip_show_exit:-0}" ;;
			*)    exit "${ip_other_exit:-0}" ;;
		esac
		;;
	*) exit "${ip_other_exit:-0}" ;;
esac
EOF
chmod +x "$sandbox/bin/ip"

FAKE_IP_LOG="$sandbox/ip.log"
export FAKE_IP_LOG
export PATH="$sandbox/bin:$PATH"

# exit-code knobs for the fake `ip`
ip_add_exit=0
ip_show_exit=0
ip_fou_exit=0
ip_other_exit=0
export ip_add_exit ip_show_exit ip_fou_exit ip_other_exit

# --- netifd proto-shell / json stubs --------------------------------------
json_get_vars() {
	local v
	for v in "$@"; do
		eval "$v=\"\${fake_$v:-}\""
	done
}
proto_config_add_string()  { __cfg_opts="$__cfg_opts $1"; }
proto_config_add_int()     { proto_config_add_string "$1"; }
proto_config_add_boolean() { proto_config_add_string "$1"; }
proto_init_update() { update_ifname="$1"; update_up="$2"; update_external="${3:-}"; }
proto_send_update() { update_sent="$1"; }
proto_notify_error() { proto_error="$1${2:+ $2}"; }
proto_block_restart() { proto_blocked="$1"; }

reset_state() {
	ip_add_exit=0; ip_show_exit=0; ip_fou_exit=0; ip_other_exit=0
	fake_laddr=""; fake_peeraddr=""; fake_port=""; fake_sport=""
	fake_csum=""; fake_mtu=""; fake_ttl=""; fake_tos=""; fake_ipproto=""
	fake_listen=""; fake_mode=""
	__cfg_opts=""
	update_ifname=""; update_up=""; update_sent=""
	proto_error=""; proto_blocked=""
	: > "$FAKE_IP_LOG"
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
	got="$(cat "$FAKE_IP_LOG")"
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

check() {
	local desc="$1"
	shift
	if "$@"; then
		pass "$desc"
	else
		fail "$desc"
	fi
}

# --- syntax checks (against the real files) --------------------------------
for f in ../files/lib/netifd/fou.sh \
         ../files/lib/netifd/proto/fou-ip6gre.sh \
         ../files/lib/netifd/proto/fou-ip6tnl.sh; do
	eval "sh -n \"$f\"" || { fail "sh -n $f"; continue; }
	pass "sh -n $(basename "$f")"
done

# --- load the plugins in INCLUDE_ONLY mode (cwd mirrors runtime) -----------
cd "$sandbox/lib/netifd/proto"
INCLUDE_ONLY=1
. ./fou-ip6gre.sh
. ./fou-ip6tnl.sh

# --- tests -----------------------------------------------------------------

# 0: init_config
reset_state
proto_fou_ip6gre_init_config
check "init_config: ip6gre no_device+available" \
	test "$no_device" = 1 -a "$available" = 1
check "init_config: ip6gre options" \
	test "$__cfg_opts" = " laddr peeraddr listen port sport ipproto csum mtu ttl tos"

reset_state
proto_fou_ip6tnl_init_config
check "init_config: ip6tnl no_device+available" \
	test "$no_device" = 1 -a "$available" = 1
check "init_config: ip6tnl adds mode" \
	test "$__cfg_opts" = " laddr peeraddr listen port sport ipproto csum mtu ttl tos mode"

# 1: ip6gre spoke
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
fake_port="5555"
proto_fou_ip6gre_setup t6g ""
expect_log "ip fou add port 5555 ipproto gre local 2001:db8::2
ip link add t6g type ip6gre local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555" \
	"ip6gre: creates FOU tunnel to the hub"
check "ip6gre: claims device" \
	test "$update_ifname" = t6g -a "$update_up" = 1 -a "$update_sent" = t6g
check "ip6gre: no error/block" \
	test -z "$proto_error" -a -z "$proto_blocked"

# 2: ip6gre with csum/mtu/ttl/tos/custom ports
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
fake_port="7000"
fake_sport="20000"
fake_csum="1"
fake_mtu="1400"
fake_ttl="64"
fake_tos="192"
proto_fou_ip6gre_setup t6g ""
expect_log "ip fou add port 7000 ipproto gre local 2001:db8::2
ip link add t6g type ip6gre local 2001:db8::2 remote 2001:db8::1 ttl 64 tos 192 encap fou encap-sport 20000 encap-dport 7000 encap-csum
ip link set t6g mtu 1400" \
	"ip6gre: honours csum/mtu/ttl/tos/port/sport"
check "ip6gre: claims device" \
	test "$update_sent" = t6g

# 3: ip6tnl mode ip4ip6 (default)
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
proto_fou_ip6tnl_setup t6n ""
expect_log "ip fou add port 5555 ipproto ipip local 2001:db8::2
ip link add t6n type ip6tnl mode ip4ip6 local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555" \
	"ip6tnl: default mode ip4ip6 (ipproto ipip)"
check "ip6tnl: claims device" \
	test "$update_sent" = t6n

# 4: ip6tnl mode ip6ip6
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
fake_mode="ip6ip6"
proto_fou_ip6tnl_setup t6n ""
expect_log "ip fou add port 5555 ipproto ipv6 local 2001:db8::2
ip link add t6n type ip6tnl mode ip6ip6 local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555" \
	"ip6tnl: mode ip6ip6 (ipproto ipv6)"

# 5: ipproto override
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
fake_ipproto="47"
proto_fou_ip6gre_setup t6g ""
expect_log "ip fou add port 5555 ipproto 47 local 2001:db8::2
ip link add t6g type ip6gre local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555" \
	"ip6gre: ipproto override honoured"

# 6: hub listen mode (no remote, one device for many spokes)
reset_state
fake_laddr="2001:db8::1"
fake_listen="1"
proto_fou_ip6gre_setup t6g ""
expect_log "ip fou add port 5555 ipproto gre local 2001:db8::1
ip link add t6g type ip6gre local 2001:db8::1 encap fou encap-sport auto encap-dport 5555" \
	"hub: listen mode omits remote"
check "hub: claims device" \
	test "$update_sent" = t6g

# 7: missing laddr
reset_state
fake_peeraddr="2001:db8::1"
proto_fou_ip6gre_setup t6g ""
check "missing laddr: block_restart + MISSING_LOCAL_ADDRESS" \
	test "$proto_error" = "t6g MISSING_LOCAL_ADDRESS" -a "$proto_blocked" = t6g
check "missing laddr: no update and no ip calls" \
	test -z "$update_sent" -a ! -s "$FAKE_IP_LOG"

# 8: missing peeraddr (spoke without listen)
reset_state
fake_laddr="2001:db8::2"
proto_fou_ip6gre_setup t6g ""
check "missing peeraddr: block_restart + MISSING_PEER_ADDRESS" \
	test "$proto_error" = "t6g MISSING_PEER_ADDRESS" -a "$proto_blocked" = t6g
check "missing peeraddr: no update and no ip calls" \
	test -z "$update_sent" -a ! -s "$FAKE_IP_LOG"

# 9: create failure -> DEVICE_CREATE_FAIL + block, no update
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
ip_add_exit=1
ip_show_exit=1
proto_fou_ip6gre_setup t6g ""
check "create fail: DEVICE_CREATE_FAIL + block_restart" \
	test "$proto_error" = "t6g DEVICE_CREATE_FAIL" -a "$proto_blocked" = t6g
check "create fail: no update" \
	test -z "$update_sent"
expect_log "ip fou add port 5555 ipproto gre local 2001:db8::2
ip link add t6g type ip6gre local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555
ip link show t6g" \
	"create fail: verifies via 'ip link show'"

# 10: pre-existing device keeps going
reset_state
fake_laddr="2001:db8::2"
fake_peeraddr="2001:db8::1"
ip_add_exit=1
ip_show_exit=0
proto_fou_ip6gre_setup t6g ""
check "pre-existing: no error, still claims" \
	test "$update_sent" = t6g -a -z "$proto_error" -a -z "$proto_blocked"
expect_log "ip fou add port 5555 ipproto gre local 2001:db8::2
ip link add t6g type ip6gre local 2001:db8::2 remote 2001:db8::1 encap fou encap-sport auto encap-dport 5555
ip link show t6g" \
	"pre-existing: keeps going"

# 11: teardown
reset_state
fake_port="5555"
proto_fou_ip6gre_teardown t6g t6g
expect_log "ip link del t6g
ip fou del port 5555" \
	"teardown: deletes tunnel device + fou listener"

reset_state
proto_fou_ip6tnl_teardown t6n ""
expect_log "ip link del t6n
ip fou del port 5555" \
	"teardown: falls back to interface name, default port"

# --- summary --------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
	echo "all tests passed"
	exit 0
fi

echo "FAILED: $failures test(s)" >&2
exit 1