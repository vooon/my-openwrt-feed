// Stand-in for the uloop module on hosts that don't have it, see ubus.uc.
// Program mode (a returned object), as files/http_client.uc require()s it.
function unmocked() {
	die('uloop: not mocked, use mock.global.patch()\n');
}

return {
	init: unmocked,
	timer: unmocked,
	run: unmocked,
	end: unmocked,
};
