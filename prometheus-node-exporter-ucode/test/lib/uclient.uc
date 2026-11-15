// Stand-in for the uclient module on hosts that don't have it, see ubus.uc.
// Program mode (a returned object), as files/http_client.uc require()s it.
return {
	new: function() {
		die('uclient: not mocked, use mock.global.patch()\n');
	},
};
