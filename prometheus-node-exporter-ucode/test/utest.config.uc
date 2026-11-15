return {
	// harness.uc, and stand-ins for the modules missing on the test hosts
	lib_paths: [ 'lib' ],

	mocks: {
		fs: null,
		// OpenWrt-only modules, absent on the test hosts (see proxy/*.uc)
		ubus: { proxy: 'proxy/ubus.uc' },
		uci: { proxy: 'proxy/uci.uc' },
		// the HTTP collectors reach these through files/http_client.uc
		uclient: null,
		uloop: null
	}
};
