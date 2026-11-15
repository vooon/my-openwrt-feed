// utest's built-in ubus proxy plus an `api` list. OpenWrt's ubus module does not
// exist on the test hosts, and utest can only generate a shim for an absent
// module when its proxy names the exports; files/metrics.uc imports
// `connect` from it.
const builtin = loadfile(getenv('UTEST_SRC') + '/utest/mock/proxy/ubus.uc', { raw_mode: true })();

return { ...builtin, api: [ 'connect' ] };
