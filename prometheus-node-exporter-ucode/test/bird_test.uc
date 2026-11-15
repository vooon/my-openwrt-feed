'use strict';

/*
 * BIRD collector against the structured `ubus call bird status` snapshot of
 * rpcd-mod-bird (/usr/share/rpcd/ucode/bird.uc), using the canonical BIRD 3.x
 * 7-field route-change layout (route change stats carry RX limit / limit
 * columns; see nest/proto.c channel_show_stats).
 */

import { describe, it, assert, mock, contains } from 'utest';
import { run_collector, find, value } from 'harness';

const COLLECTOR = 'files/extra/bird.uc';

const status = {
	status: {
		version: "3.0.0",
		router_id: "10.0.0.1",
		hostname: "router1",
		server_time: 1705311005,
		last_reboot: 1705311005,
		last_reconfig: 1705311005,
		up: 1,
	},
	protocols: [
		{ name: "device1", proto: "Device", ip_version: "", up: 1, state: null, uptime: 4, imported: 0, exported: 0, filtered: 0, preferred: 0, import_filter: "", export_filter: "", v3: false, changes: {} },
		{ name: "direct1", proto: "Direct", ip_version: "4", up: 1, state: null, uptime: 12345, imported: 3, exported: 3, filtered: 1, preferred: 2, import_filter: "ACCEPT", export_filter: "ACCEPT", v3: false,
			changes: {
				import_updates:   { received: 10, rejected: 2,  filtered: 1, ignored: 0, accepted: 7,  rx_limit: 0, limit: 0 },
				import_withdraws: { received: 20, rejected: 0,  filtered: 0, ignored: 1, accepted: 19, rx_limit: 0, limit: 0 },
				export_updates:   { received: 30, rejected: 0,  filtered: 0, ignored: 0, accepted: 30, rx_limit: 0, limit: 0 },
				export_withdraws: { received: 40, rejected: 0,  filtered: 0, ignored: 0, accepted: 40, rx_limit: 0, limit: 0 },
			} },
		{ name: "kernel1", proto: "Kernel", ip_version: "4", up: 1, state: null, uptime: 12345, imported: 5, exported: 5, filtered: 0, preferred: 5, import_filter: "", export_filter: "", v3: false, changes: {} },
		{ name: "static1", proto: "Static", ip_version: "4", up: 1, state: null, uptime: 432, imported: 2, exported: 2, filtered: 0, preferred: 1, import_filter: "", export_filter: "", v3: false, changes: {} },
		{ name: "bgp1", proto: "BGP", ip_version: "4", up: 1, state: "Established", uptime: 12345, imported: 100, exported: 100, filtered: 0, preferred: 100, import_filter: "bgp-in", export_filter: "bgp-out", neighbor: "10.0.0.1", neighbor_as: 64512, local_as: 65000, v3: false, changes: {} },
		{ name: "bgp1", proto: "BGP", ip_version: "6", up: 1, state: "Established", uptime: 12345, imported: 50, exported: 50, filtered: 0, preferred: 50, import_filter: "bgp-in", export_filter: "bgp-out", v3: false, changes: {} },
		{ name: "ospf1", proto: "OSPF", ip_version: "4", up: 1, state: "Running", uptime: 12345, imported: 8, exported: 8, filtered: 0, preferred: 8, import_filter: "", export_filter: "", v3: false, changes: {} },
		{ name: "bfd1", proto: "BFD", ip_version: "", up: 1, state: null, uptime: 12345, imported: 0, exported: 0, filtered: 0, preferred: 0, import_filter: "", export_filter: "", v3: false, changes: {} },
	],
	ospf: [
		{ protocol: "ospf1", ip_version: "4", running: 1,
			areas: [
				{ name: "0", interfaces: 2, neighbors: 3, adjacent: 2 },
				{ name: "1", interfaces: 1, neighbors: 1, adjacent: 1 },
			],
			interfaces: [
				{ interface: "eth0", cost: 10 },
				{ interface: "eth1", cost: 100 },
			],
			neighbors: [
				{ rid: "10.0.0.2", priority: 1, state: "Full", position: "DR", interface: "eth0", ip: "192.0.2.2" },
				{ rid: "10.0.0.3", priority: 1, state: "2-Way", position: "Other", interface: "eth1", ip: "198.51.100.2" },
				{ rid: "10.0.0.4", priority: 1, state: "Init", position: "PtP", interface: "eth0", ip: "192.0.2.3" },
			] },
	],
	bgp: [],
	bfd: [
		{ protocol: "bfd1", sessions: [
			{ ip: "10.0.0.2", interface: "eth0", up: 1, uptime: 12345, interval: 1000, timeout: 3000 },
			{ ip: "10.0.0.3", interface: "eth1", up: 0, uptime: 62, interval: 1000, timeout: 3000 },
		] },
	],
};

function collect(data) {
	return mock.inject('ubus', { data, strict: true },
		(m_ubus) => run_collector(COLLECTOR, {
			ubus: m_ubus.connect(),
			config: { socket: '/run/bird.ctl' },
		}));
}

describe('bird collector', () => {
	it('reports the daemon status', () => {
		let r = collect({ 'bird:status': status });

		assert.match(1, value(r, "bird_socket_query_success", null), "bird_socket_query_success");
		assert.match(1, value(r, "bird_daemon_up", null), "bird_daemon_up");
		assert.match(contains({ router_id: "10.0.0.1", version: "3.0.0" }), find(r, "bird_daemon_info", null)?.labels);
		assert.match(1705311005, value(r, "bird_last_reboot_timestamp_seconds", null), "bird_last_reboot_timestamp_seconds");
		assert.match(1705311005, value(r, "bird_server_time_timestamp_seconds", null), "bird_server_time_timestamp_seconds");
	});

	it('reports the protocol prefix and route change counters', () => {
		let r = collect({ 'bird:status': status });

		let d = { name: "direct1", proto: "Direct", ip_version: "4", import_filter: "ACCEPT", export_filter: "ACCEPT" };
		assert.match(1, value(r, "bird_protocol_up", { name: "direct1", proto: "Direct", ip_version: "4" }), "bird_protocol_up");
		assert.match(3, value(r, "bird_protocol_prefix_import_count", d), "bird_protocol_prefix_import_count");
		assert.match(3, value(r, "bird_protocol_prefix_export_count", d), "bird_protocol_prefix_export_count");
		assert.match(1, value(r, "bird_protocol_prefix_filter_count", d), "bird_protocol_prefix_filter_count");
		assert.match(2, value(r, "bird_protocol_prefix_preferred_count", d), "bird_protocol_prefix_preferred_count");
		assert.match(10, value(r, "bird_protocol_changes_update_import_receive_count", d), "bird_protocol_changes_update_import_receive_count");
		assert.match(2, value(r, "bird_protocol_changes_update_import_reject_count", d), "bird_protocol_changes_update_import_reject_count");
		assert.match(1, value(r, "bird_protocol_changes_update_import_filter_count", d), "bird_protocol_changes_update_import_filter_count");
		assert.match(7, value(r, "bird_protocol_changes_update_import_accept_count", d), "bird_protocol_changes_update_import_accept_count");
		assert.match(0, value(r, "bird_protocol_changes_update_import_ignore_count", d), "bird_protocol_changes_update_import_ignore_count");
		assert.match(0, value(r, "bird_protocol_changes_withdraw_import_reject_count", d), "bird_protocol_changes_withdraw_import_reject_count");
		assert.match(0, value(r, "bird_protocol_changes_withdraw_import_filter_count", d), "bird_protocol_changes_withdraw_import_filter_count");
	});

	it('splits a dual-channel BGP protocol by IP version', () => {
		let r = collect({ 'bird:status': status });

		let b4 = { name: "bgp1", proto: "BGP", ip_version: "4", import_filter: "bgp-in", export_filter: "bgp-out" };
		let b6 = { name: "bgp1", proto: "BGP", ip_version: "6", import_filter: "bgp-in", export_filter: "bgp-out" };
		assert.match(100, value(r, "bird_protocol_prefix_import_count", b4), "bird_protocol_prefix_import_count");
		assert.match(50, value(r, "bird_protocol_prefix_import_count", b6), "bird_protocol_prefix_import_count");
	});

	it('reports OSPF areas, interfaces and neighbors', () => {
		let r = collect({ 'bird:status': status });

		assert.match(1, value(r, "bird_ospf_running", { name: "ospf1" }), "bird_ospf_running");
		assert.match(2, value(r, "bird_ospf_interface_count", { name: "ospf1", area: "0" }), "bird_ospf_interface_count");
		assert.match(3, value(r, "bird_ospf_neighbor_count", { name: "ospf1", area: "0" }), "bird_ospf_neighbor_count");
		assert.match(1, value(r, "bird_ospf_neighbor_adjacent_count", { name: "ospf1", area: "1" }), "bird_ospf_neighbor_adjacent_count");
		assert.match(10, value(r, "bird_ospf_interface_cost", { name: "ospf1", interface: "eth0" }), "bird_ospf_interface_cost");
		assert.match(100, value(r, "bird_ospf_interface_cost", { name: "ospf1", interface: "eth1" }), "bird_ospf_interface_cost");
		assert.match(1, value(r, "bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.2" }), "bird_ospf_neighbor_up");
		assert.match(0, value(r, "bird_ospf_neighbor_up", { name: "ospf1", interface: "eth1", neighbor_rid: "10.0.0.3" }), "bird_ospf_neighbor_up");
		assert.match(0, value(r, "bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.4" }), "bird_ospf_neighbor_up");
		assert.match(contains({ router_ip: "192.0.2.2", local_rid: "10.0.0.1" }), find(r, "bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.2" })?.labels);
	});

	it('reports BFD sessions', () => {
		let r = collect({ 'bird:status': status });

		assert.match(1, value(r, "bird_bfd_session_up", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }), "bird_bfd_session_up");
		assert.match(0, value(r, "bird_bfd_session_up", { name: "bfd1", ip: "10.0.0.3", interface: "eth1" }), "bird_bfd_session_up");
		assert.match(1000, value(r, "bird_bfd_session_interval_seconds", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }), "bird_bfd_session_interval_seconds");
		assert.match(3000, value(r, "bird_bfd_session_timeout_seconds", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }), "bird_bfd_session_timeout_seconds");
	});

	it('emits only finite values', () => {
		let r = collect({ 'bird:status': status });

		for (let m in r.metrics)
			assert.match(false, m.value == 'NaN' || m.value == 'Infinity', m.name);
	});
});
