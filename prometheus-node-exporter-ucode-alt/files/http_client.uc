let uloop = require("uloop");
let uclient = require("uclient");

function fetch_json(api_url, endpoint, bearer_token='') {
	let data = '';

	const url = `${api_url}${endpoint}`;
	let headers = {
		"User-Agent": "prometheus-node-exporter-ucode/1.0",
		"Content-Type": "application/json",
	};
	if (bearer_token)
		headers["Authorization"] = `Bearer ${bearer_token}`;

	uloop.init();
	uc = uclient.new(url, null, {
		data_read: (cb) => {
			let chunk;
			while (length(chunk = uc.read()) > 0)
				data += chunk;
		},
		data_eof: (cb) => {
			uloop.end();
		},
		error: (cb, code) => {
			warn(`failed to get url: ${url}: ${code}\n`);
			data = null;
			uloop.end();
		}
	});

	if (!uc.set_timeout(5000)) {
		warn("failed to set timeout\n");
		uc.free();
		return null;
	}

	if (!uc.ssl_init({verify: false})) {
		warn("failed to initialize SSL\n");
		uc.free();
		return null;
	}

	if (!uc.connect()) {
		warn("failed to connect\n");
		uc.free();
		return null;
	}

	if (!uc.request("GET", {headers: headers})) {
		warn("failed to send request\n");
		uc.free();
		return null;
	}

	uloop.run();

	let status = uc.status();
	uc.free();

	if (data == null) {
		return null;
	}

	if (status.status != 200) {
		warn(`failed to get data: url: ${url}: ${status.status}\n`);
		return null;
	}

	return json(data);
}
