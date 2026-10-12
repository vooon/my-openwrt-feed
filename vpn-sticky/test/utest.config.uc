return {
	// stand-in uci module for hosts without OpenWrt's uci.so
	lib_paths: [ 'lib' ],

	// the nft template require()s uci; the shim lets mock.inject() replace it
	mocks: {
		uci: null
	}
};
