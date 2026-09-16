'use strict';

// Regression test for the Mihomo collector using a mocked controller API.
let failures = 0;
let emitted = [];

function fail(msg) {
	warn("FAIL: ", msg, "\n");
	failures++;
}

function check(cond, msg) {
	if (!cond)
		fail(msg);
}

function metric(name, help) {
	return function(labels, value) {
		push(emitted, {name: name, labels: labels, value: value});
	};
}

const responses = {
	"/version": {meta: true, version: "1.19.0"},
	"/traffic": {up: 12, down: 34, upTotal: 1200, downTotal: 3400},
	"/memory": {inuse: 65536, oslimit: 0},
	"/connections": {
		uploadTotal: 1200,
		downloadTotal: 3400,
		memory: 65536,
		connections: [
			{
				id: "one",
				upload: 10,
				download: 20,
				rule: "MATCH",
				rulePayload: "",
				chains: ["Proxy A"],
				providerChains: ["Provider A"],
				metadata: {
					network: "tcp",
					type: "Tun",
					host: "example.com",
					destinationIP: "192.0.2.1",
					sourceIP: "192.0.2.2",
					sourcePort: "1234",
					destinationPort: "443",
				}
			},
		],
	},
	"/proxies": {
		proxies: {
			"Proxy A": {
				name: "Proxy A",
				type: "Shadowsocks",
				alive: true,
				history: [{time: "now", delay: 87}],
			},
		},
	},
};

function fetch_json(url, endpoint, secret) {
	return responses[endpoint];
}

let config = {
	api_url: "http://mihomo",
	fetch_json: fetch_json,
	per_connection: "0",
};

let gauge = metric;
let counter = metric;
let collector = loadfile("./files/extra/mihomo.uc", {
	strict_declarations: true,
	raw_mode: true,
});

if (!collector)
	fail("failed to load mihomo.uc");
else if (call(collector, null, {config, gauge, counter}) == false)
	fail("collector returned false");

function find(name, label, value) {
	for (let item in emitted)
		if (item.name == name && (label == null || item.labels[label] == value))
			return item;
	return null;
}

check(find("mihomo_up", "url", "http://mihomo").value == 1, "API is up");
check(find("mihomo_traffic_upload_bytes_per_second", null, null).value == 12, "upload rate");
check(find("mihomo_connection_download_bytes_by_node", "outbound_node", "Proxy A").value == 20,
	"download aggregation by node");
check(find("mihomo_connection_upload_bytes_by_destination", "destination", "example.com").value == 10,
	"upload aggregation by destination");
check(find("mihomo_proxy_latency_ms", "name", "Proxy A").value == 87, "proxy latency");

if (failures) {
	warn(failures + " assertion(s) failed\n");
	exit(1);
}

print("mihomo test OK\n");
