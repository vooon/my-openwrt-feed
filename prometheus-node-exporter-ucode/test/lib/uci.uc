// Stand-in for OpenWrt's uci module, see ubus.uc.
export function cursor() {
	die('uci: not mocked, use mock.inject() or mock.global.patch()\n');
};
