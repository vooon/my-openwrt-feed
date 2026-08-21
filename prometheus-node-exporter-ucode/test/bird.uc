// Self-contained regression test for the BIRD collector.
//
// Mocks the "bird" ubus object (returning the structured snapshot that the
// rpcd ucode module produces for `bird status`), loads files/extra/bird.uc
// and asserts that the emitted metric set matches the expected
// bird_exporter schema.  Run via test.sh.
//
// The fixtures below mirror the ones the old inline parser consumed, but as
// the structured JSON emitted by /usr/share/rpcd/ucode/bird.uc, using the
// canonical BIRD 3.x 7-field route-change layout (route change stats carry
// RX limit / limit columns; see nest/proto.c channel_show_stats).

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

const config = { socket: "/run/bird.ctl" };

const ubus = {
	call: function(obj, method, args) {
		if (obj == "bird" && method == "status")
			return status;
		return null;
	}
};

let emitted = [];

const gauge = function(name, help) {
	return function(labels, value) {
		push(emitted, { name: name, labels: labels, value: value });
	};
};
const counter = gauge;

let func = loadfile("./files/extra/bird.uc", { strict_declarations: true, raw_mode: true });
if (!func) {
	warn("failed to load bird.uc\n");
	exit(1);
}

call(func, null, { config, ubus, gauge, counter });

let failures = 0;

function find(name, labels) {
	for (let i = 0; i < length(emitted); i++) {
		let e = emitted[i];
		if (e.name != name)
			continue;
		if (labels) {
			let ok = true;
			for (let k in labels)
				if (e.labels[k] != labels[k]) {
					ok = false;
					break;
				}
			if (!ok)
				continue;
		}
		return e;
	}
	return null;
}

function check(name, labels, want) {
	let e = find(name, labels);
	if (!e) {
		warn("FAIL: metric not emitted: ", name, " ", labels, "\n");
		failures++;
		return;
	}
	if (e.value != want) {
		warn("FAIL: ", name, " ", labels, " = ", e.value, " want ", want, "\n");
		failures++;
	}
}

function checkLabels(name, labels, want) {
	let e = find(name, labels);
	if (!e) {
		warn("FAIL: labeled metric not emitted: ", name, " ", labels, "\n");
		failures++;
		return;
	}
	for (let k in want)
		if (e.labels[k] != want[k]) {
			warn("FAIL: ", name, " label ", k, " = ", e.labels[k], " want ", want[k], "\n");
			failures++;
		}
}

// socket + daemon status
check("bird_socket_query_success", null, 1);
check("bird_daemon_up", null, 1);
checkLabels("bird_daemon_info", null, { router_id: "10.0.0.1", version: "3.0.0" });
check("bird_last_reboot_timestamp_seconds", null, 1705311005);
check("bird_server_time_timestamp_seconds", null, 1705311005);

// generic protocol metrics
let d = { name: "direct1", proto: "Direct", ip_version: "4", import_filter: "ACCEPT", export_filter: "ACCEPT" };
check("bird_protocol_up", { name: "direct1", proto: "Direct", ip_version: "4" }, 1);
check("bird_protocol_prefix_import_count", d, 3);
check("bird_protocol_prefix_export_count", d, 3);
check("bird_protocol_prefix_filter_count", d, 1);
check("bird_protocol_prefix_preferred_count", d, 2);
check("bird_protocol_changes_update_import_receive_count", d, 10);
check("bird_protocol_changes_update_import_reject_count", d, 2);
check("bird_protocol_changes_update_import_filter_count", d, 1);
check("bird_protocol_changes_update_import_accept_count", d, 7);
check("bird_protocol_changes_update_import_ignore_count", d, 0);
check("bird_protocol_changes_withdraw_import_reject_count", d, 0);
check("bird_protocol_changes_withdraw_import_filter_count", d, 0);

// BGP dual channel split
let b4 = { name: "bgp1", proto: "BGP", ip_version: "4", import_filter: "bgp-in", export_filter: "bgp-out" };
let b6 = { name: "bgp1", proto: "BGP", ip_version: "6", import_filter: "bgp-in", export_filter: "bgp-out" };
check("bird_protocol_prefix_import_count", b4, 100);
check("bird_protocol_prefix_import_count", b6, 50);

// OSPF
check("bird_ospf_running", { name: "ospf1" }, 1);
check("bird_ospf_interface_count", { name: "ospf1", area: "0" }, 2);
check("bird_ospf_neighbor_count", { name: "ospf1", area: "0" }, 3);
check("bird_ospf_neighbor_adjacent_count", { name: "ospf1", area: "1" }, 1);
check("bird_ospf_interface_cost", { name: "ospf1", interface: "eth0" }, 10);
check("bird_ospf_interface_cost", { name: "ospf1", interface: "eth1" }, 100);
check("bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.2" }, 1);
check("bird_ospf_neighbor_up", { name: "ospf1", interface: "eth1", neighbor_rid: "10.0.0.3" }, 0);
check("bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.4" }, 0);
checkLabels("bird_ospf_neighbor_up", { name: "ospf1", interface: "eth0", neighbor_rid: "10.0.0.2" }, { router_ip: "192.0.2.2", local_rid: "10.0.0.1" });

// BFD
check("bird_bfd_session_up", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }, 1);
check("bird_bfd_session_up", { name: "bfd1", ip: "10.0.0.3", interface: "eth1" }, 0);
check("bird_bfd_session_interval_seconds", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }, 1000);
check("bird_bfd_session_timeout_seconds", { name: "bfd1", ip: "10.0.0.2", interface: "eth0" }, 3000);

// no NaN values anywhere
for (let i = 0; i < length(emitted); i++) {
	if (emitted[i].value == "NaN" || emitted[i].value == "Infinity") {
		warn("FAIL: invalid metric value: ", emitted[i].name, " ", emitted[i].labels, "\n");
		failures++;
	}
}

if (failures) {
	warn(failures, " assertion(s) failed\n");
	exit(1);
}

print("bird collector test OK\n");