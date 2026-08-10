// Self-contained regression test for the BIRD collector.
//
// Mocks the "bird" ubus object and the gauge/counter metric helpers, loads
// files/extra/bird.uc and asserts that the emitted metric set matches the
// expected bird_exporter schema.  Run via test.sh.

const PROTO_TXT =
"Name       Proto       Table         State      Since         Info\n" +
"device1    Device      ---           up         00:00:04\n" +
"direct1    Direct      ---           up         2024-01-15 10:30:05\n" +
"  Channel ipv4:\n" +
"    State:          up\n" +
"    Table:          master4\n" +
"    Preference:     120\n" +
"    Input filter:   ACCEPT\n" +
"    Output filter:  ACCEPT\n" +
"    Routes:         3 imported, 1 filtered, 3 exported, 2 preferred\n" +
"    Route change stats:     received   rejected   filtered    ignored   accepted\n" +
"      Import updates:             10          2          1          0          7\n" +
"      Import withdraws:           20          0        ---          1          19\n" +
"      Export updates:            30          0          0        ---          30\n" +
"      Export withdraws:          40        ---        ---        ---          40\n" +
"kernel1    Kernel      master4       up         2024-01-15 10:30:05\n" +
"  Channel ipv4:\n" +
"    State:          up\n" +
"    Input filter:   ACCEPT\n" +
"    Output filter:  ACCEPT\n" +
"    Routes:         5 imported, 5 exported, 5 preferred\n" +
"static1    Static      master4       up         00:07:12\n" +
"  Channel ipv4:\n" +
"    Routes:         2 imported, 2 exported, 1 preferred\n" +
"bgp1       BGP         master4       up         2024-01-15 10:30:05\n" +
"  Description:    peer AS 64512\n" +
"  BGP state:      Established\n" +
"  Neighbor address: 10.0.0.1\n" +
"  Channel ipv4:\n" +
"    State:          up\n" +
"    Input filter:   bgp-in\n" +
"    Output filter:  bgp-out\n" +
"    Routes:         100 imported, 0 filtered, 100 exported, 100 preferred\n" +
"  Channel ipv6:\n" +
"    State:          up\n" +
"    Input filter:   bgp-in\n" +
"    Output filter:  bgp-out\n" +
"    Routes:         50 imported, 0 filtered, 50 exported, 50 preferred\n" +
"ospf1      OSPF        master4       up         2024-01-15 10:30:05 Running\n" +
"  Channel ipv4:\n" +
"    Routes:         8 imported, 8 exported, 8 preferred\n" +
"bfd1       BFD         ---           up         2024-01-15 10:30:05\n" +
"0000 OK\n";

const STATUS_TXT =
"BIRD 3.0.0\n" +
"Router ID is 10.0.0.1\n" +
"Hostname is router1\n" +
"Current server time is 2024-01-15 10:30:05\n" +
"Last reboot on 2024-01-15 10:30:05\n" +
"Last reconfiguration on 2024-01-15 10:30:05\n" +
"Daemon is up and running\n";

const OSPF_TXT =
"Area: 0.0.0.0 (0) Backbone\n" +
"    Number of interfaces:     2\n" +
"    Number of neighbors:      3\n" +
"    Number of adjacent neighbors:  2\n" +
"Area: 0.0.0.1 (1) Area1\n" +
"    Number of interfaces:     1\n" +
"    Number of neighbors:      1\n" +
"    Number of adjacent neighbors:  1\n";

const BFD_TXT =
" 10.0.0.2    eth0        Up          2024-01-15 10:30:05  1000.000  3000.000\n" +
" 10.0.0.3    eth1        Down        00:01:02  1000.000  3000.000\n";

const config = { socket: "/run/bird/bird.ctl" };

const ubus = {
	call: function(obj, method, args) {
		switch (args.command) {
		case "show protocols all":
			return { code: 0, stdout: PROTO_TXT };
		case "show status":
			return { code: 0, stdout: STATUS_TXT };
		case "show ospf ospf1":
			return { code: 0, stdout: OSPF_TXT };
		case "show bfd sessions bfd1":
			return { code: 0, stdout: BFD_TXT };
		}
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