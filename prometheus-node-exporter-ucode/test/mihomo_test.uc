'use strict';

/*
 * Mihomo collector against a mocked controller API, through the real
 * files/http_client.uc on top of mocked uclient / uloop.
 */

import { describe, it, assert, mock, contains, regex } from 'utest';
import { run_collector, with_http, value } from 'harness';

const COLLECTOR = 'files/extra/mihomo.uc';
const API = 'http://mihomo';

const RESPONSES = {
	[`${API}/version`]: {meta: true, version: "1.19.0"},
	[`${API}/connections`]: {
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
	[`${API}/proxies`]: {
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

function collect(responses, config) {
	return with_http(mock, responses, (requests) => {
		let result = run_collector(COLLECTOR, {
			config: { api_url: API, per_connection: '0', ...(config || {}) },
		});

		result.requests = requests;
		return result;
	});
}

describe('mihomo collector', () => {
	it('reports traffic, memory, connections and proxy latency', () => {
		let r = collect(RESPONSES);

		assert.match(true, r.ok);
		assert.match(1, value(r, 'mihomo_up', { url: API }));
		assert.match(1200, value(r, 'mihomo_traffic_upload_bytes_total'));
		assert.match(3400, value(r, 'mihomo_traffic_download_bytes_total'));
		assert.match(65536, value(r, 'mihomo_memory_used_bytes'));
		assert.match(1, value(r, 'mihomo_connections_active_total'));
		assert.match(20, value(r, 'mihomo_connection_download_bytes_by_node', { outbound_node: 'Proxy A' }));
		assert.match(10, value(r, 'mihomo_connection_upload_bytes_by_destination', { destination: 'example.com' }));
		assert.match(87, value(r, 'mihomo_proxy_latency_ms', { name: 'Proxy A' }));
	});

	it('queries the three controller endpoints', () => {
		let r = collect(RESPONSES);

		assert.match([ `${API}/version`, `${API}/connections`, `${API}/proxies` ],
			map(r.requests, (req) => req.url));
	});

	it('sends the secret as a bearer token', () => {
		let r = collect(RESPONSES, { secret: 's3cret' });

		for (let req in r.requests)
			assert.match(contains({ Authorization: 'Bearer s3cret' }), req.headers, req.url);
	});

	// an idle controller reports "connections": null; the collector must not
	// throw nor silently drop the active-connection metric
	it('reports zero active connections for an idle controller', () => {
		let r = collect({
			...RESPONSES,
			[`${API}/connections`]: { uploadTotal: 1200, downloadTotal: 3400, memory: 65536, connections: null },
		});

		assert.match(true, r.ok);
		assert.match(1, value(r, 'mihomo_up', { url: API }));
		assert.match(0, value(r, 'mihomo_connections_active_total'));
	});

	it('reports the API as down when the controller does not answer', () => {
		let warnings = [];
		let r = mock.inject_builtin('warn', (...args) => push(warnings, join('', args)),
			() => collect({}));

		assert.match(false, r.ok);
		assert.match(0, value(r, 'mihomo_up', { url: API }));
		assert.match(contains([ regex(/failed to get url: http:\/\/mihomo\/version/) ]), warnings);
	});

	it('does nothing without an api_url', () => {
		let r = collect(RESPONSES, { api_url: null });

		assert.match(false, r.ok);
		assert.match([], r.metrics);
		assert.match([], r.requests);
	});
});
