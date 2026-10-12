// Stand-in for OpenWrt's uci module on hosts that don't have it (CI, host
// ucode builds): utest only shims modules it finds on disk. Inside
// mock.inject('uci', ...) every call goes to utest's uci proxy instead.
// Program mode (a returned object) so require() loads it like the native one.
return {
	cursor: function() {
		die('uci: not mocked, wrap the call in mock.inject()\n');
	},
};
