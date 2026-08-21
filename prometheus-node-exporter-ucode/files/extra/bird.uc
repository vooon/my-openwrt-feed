// Prometheus collector for the BIRD routing daemon (bird_exporter parity)
//
// Consumes the structured snapshot from the "bird" rpcd ucode module
// (ubus call bird status), which runs outside the ujail and has direct
// access to the BIRD control socket.  All text parsing happens in
// /usr/share/rpcd/ucode/bird.uc using the same regexes as the old inline
// parser.  Metric names and labels mirror the upstream czerwonk/bird_exporter
// (new/default format).  This file only maps the structured JSON to gauges.

const socket = config.socket || "/run/bird.ctl";

const GENERIC_PROTOS = ["BGP", "OSPF", "Kernel", "Static", "Direct", "Babel", "RPKI"];

function is_generic(proto) {
	for (let i = 0; i < length(GENERIC_PROTOS); i++)
		if (GENERIC_PROTOS[i] == proto)
			return true;
	return false;
}

function proto_string(proto, ip_version) {
	if (proto == "OSPF")
		return ip_version == "6" ? "OSPFv3" : "OSPF";
	return proto;
}

const r = ubus.call("bird", "status", { socket: socket });

if (!r || r.protocols == null) {
	gauge("bird_socket_query_success", "Result of querying bird socket: 0 = failed, 1 = succeeded")(null, 0);
	gauge("bird_daemon_up", "Whether the BIRD daemon is up (1) or down (0)")(null, 0);
	return false;
}

gauge("bird_socket_query_success", "Result of querying bird socket: 0 = failed, 1 = succeeded")(null, 1);

const st = r.status || {};
gauge("bird_daemon_up", "Whether the BIRD daemon is up (1) or down (0)")(null, st.up ? 1 : 0);
gauge("bird_daemon_info", "Static information about BIRD")({
	router_id: st.router_id,
	version: st.version,
}, 1);
if (st.last_reboot != null)
	gauge("bird_last_reboot_timestamp_seconds", "Timestamp of the last BIRD reboot")(null, st.last_reboot);
if (st.last_reconfig != null)
	gauge("bird_last_reconfig_timestamp_seconds", "Timestamp of the last BIRD reconfiguration")(null, st.last_reconfig);
if (st.server_time != null)
	gauge("bird_server_time_timestamp_seconds", "Server time reported by BIRD")(null, st.server_time);

const g_router_id = st.router_id;

function emit_route_changes(labels, p) {
	let groups = [
		["import_updates", "update_import"],
		["import_withdraws", "withdraw_import"],
		["export_updates", "update_export"],
		["export_withdraws", "withdraw_export"],
	];

	for (let g = 0; g < length(groups); g++) {
		let c = p.changes[groups[g][0]];
		if (c == null)
			continue;
		let base = groups[g][1];

		gauge(`bird_protocol_changes_${base}_receive_count`, "Number of received updates")(labels, c.received);
		gauge(`bird_protocol_changes_${base}_reject_count`, "Number of rejected updates")(labels, c.rejected);
		gauge(`bird_protocol_changes_${base}_filter_count`, "Number of filtered updates")(labels, c.filtered);
		gauge(`bird_protocol_changes_${base}_accept_count`, "Number of accepted updates")(labels, c.accepted);
		gauge(`bird_protocol_changes_${base}_ignore_count`, "Number of ignored updates")(labels, c.ignored);

		if (p.v3) {
			gauge(`bird_protocol_changes_${base}_rx_limit_count`, "Number of updates reaching the RX limit")(labels, c.rx_limit);
			gauge(`bird_protocol_changes_${base}_limit_count`, "Number of updates reaching the limit")(labels, c.limit);
		}
	}
}

function emit_protocol(p) {
	let labels = {
		name: p.name,
		proto: proto_string(p.proto, p.ip_version),
		ip_version: p.ip_version,
		import_filter: p.import_filter,
		export_filter: p.export_filter,
	};

	gauge("bird_protocol_up", "Protocol is up")({
		name: p.name,
		proto: proto_string(p.proto, p.ip_version),
		ip_version: p.ip_version,
		import_filter: p.import_filter,
		export_filter: p.export_filter,
		state: p.state,
	}, p.up);
	gauge("bird_protocol_prefix_import_count", "Number of imported routes")(labels, p.imported);
	gauge("bird_protocol_prefix_export_count", "Number of exported routes")(labels, p.exported);
	gauge("bird_protocol_prefix_filter_count", "Number of filtered routes")(labels, p.filtered);
	gauge("bird_protocol_prefix_preferred_count", "Number of preferred routes")(labels, p.preferred);
	gauge("bird_protocol_uptime", "Uptime of the protocol in seconds")(labels, p.uptime || 0);

	emit_route_changes(labels, p);
}

function emit_ospf(o) {
	let prefix = o.ip_version == "6" ? "bird_ospfv3" : "bird_ospf";

	gauge(prefix + "_running", "State of OSPF: 0 = Alone, 1 = Running")({ name: o.protocol }, o.running ? 1 : 0);

	for (let a = 0; a < length(o.areas); a++) {
		let lbl = { name: o.protocol, area: o.areas[a].name };
		gauge(prefix + "_interface_count", "Number of interfaces in the area")(lbl, o.areas[a].interfaces);
		gauge(prefix + "_neighbor_count", "Number of neighbors in the area")(lbl, o.areas[a].neighbors);
		gauge(prefix + "_neighbor_adjacent_count", "Number of adjacent neighbors in the area")(lbl, o.areas[a].adjacent);
	}

	for (let i = 0; i < length(o.interfaces); i++)
		gauge(prefix + "_interface_cost", "OSPF interface cost (metric)")({
			name: o.protocol, interface: o.interfaces[i].interface,
		}, o.interfaces[i].cost);

	for (let n = 0; n < length(o.neighbors); n++) {
		let nb = o.neighbors[n];
		gauge(prefix + "_neighbor_up", "OSPF neighbor adjacency is Full (1) or not (0)")({
			name: o.protocol, interface: nb.interface, neighbor_rid: nb.rid,
			router_ip: nb.ip, local_rid: g_router_id,
		}, nb.state == "Full" ? 1 : 0);
	}
}

function emit_bfd(b) {
	for (let i = 0; i < length(b.sessions); i++) {
		let s = b.sessions[i];
		let lbl = { name: b.protocol, ip: s.ip, interface: s.interface };
		let up = s.up ? 1 : 0;

		gauge("bird_bfd_session_up", "Session is up")(lbl, up);
		gauge("bird_bfd_session_uptime_seconds", "Session uptime in seconds")(lbl, up ? (s.uptime || 0) : 0);
		gauge("bird_bfd_session_interval_seconds", "Session interval in seconds")(lbl, s.interval);
		gauge("bird_bfd_session_timeout_seconds", "Session timeout in seconds")(lbl, s.timeout);
	}
}

for (let i = 0; i < length(r.protocols); i++) {
	let p = r.protocols[i];

	if (!is_generic(p.proto))
		continue;

	emit_protocol(p);
}

for (let i = 0; i < length(r.ospf); i++)
	emit_ospf(r.ospf[i]);

for (let i = 0; i < length(r.bfd); i++)
	emit_bfd(r.bfd[i]);