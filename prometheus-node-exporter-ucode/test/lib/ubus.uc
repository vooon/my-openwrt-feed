// Stand-in for OpenWrt's ubus module, which does not exist on the test hosts:
// the shim utest generates (see proxy/ubus.uc) falls back to it for calls made
// outside of mock.inject() / mock.global.patch().
export function connect() {
	die('ubus: not mocked, use mock.inject() or mock.global.patch()\n');
};
