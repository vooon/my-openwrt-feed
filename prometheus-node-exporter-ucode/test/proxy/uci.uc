// utest's built-in uci proxy plus an `api` list. OpenWrt's uci module does not
// exist on the test hosts, and utest can only generate a shim for an absent
// module when its proxy names the exports; files/metrics.uc imports
// `cursor` from it.
const builtin = loadfile(getenv('UTEST_SRC') + '/utest/mock/proxy/uci.uc', { raw_mode: true })();

return { ...builtin, api: [ 'cursor' ] };
