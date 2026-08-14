// Prometheus collector for the BIRD routing daemon (bird_exporter parity)
//
// Talks to the BIRD control socket through the "bird" rpcd module
// (ubus call bird query), which runs outside the ujail and has direct
// access to /run/bird/bird.ctl.  Metric names and labels mirror the
// upstream czerwonk/bird_exporter (new/default format).

const socket = config.socket || "/run/bird/bird.ctl";

let g_router_id = "";

const GENERIC_PROTOS = ["BGP", "OSPF", "Kernel", "Static", "Direct", "Babel", "RPKI"];

function is_generic(proto) {
	for (let i = 0; i < length(GENERIC_PROTOS); i++)
		if (GENERIC_PROTOS[i] == proto)
			return true;
	return false;
}

function bird_query(cmd) {
	const r = ubus.call("bird", "query", {
		command: cmd,
		socket: socket,
	});

	if (!r || r.code != 0 || r.stdout == null)
		return null;

	return split(r.stdout, "\n");
}

function bird_num(s) {
	if (s == null || s == "---" || !length(s))
		return null;

	return +s;
}

function ts_to_epoch(s) {
	let m = match(s, /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
	if (!m)
		return null;

	let e = timelocal({
		sec: +m[6],
		min: +m[5],
		hour: +m[4],
		mday: +m[3],
		mon: +m[2],
		year: +m[1],
	});

	return (e == null || e == -1) ? null : e;
}

function uptime_seconds(s) {
	if (s == null)
		return null;

	let m = match(s, /^(\d+):(\d{2}):(\d{2})$/);
	if (m)
		return (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]);

	if (match(s, /^\d+$/))
		return clock()[0] - (+s);

	let e = ts_to_epoch(s);
	return (e != null) ? clock()[0] - e : null;
}

function proto_string(proto, ip_version) {
	if (proto == "OSPF")
		return ip_version == "6" ? "OSPFv3" : "OSPF";
	return proto;
}

function new_proto(name, proto, up, state, uptime, ip_version) {
	return {
		name: name,
		proto: proto,
		ip_version: ip_version,
		up: up,
		state: state,
		uptime: uptime,
		imported: 0,
		exported: 0,
		filtered: 0,
		preferred: 0,
		import_filter: "",
		export_filter: "",
		import_updates: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
		import_withdraws: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
		export_updates: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
		export_withdraws: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
		v3: false,
	};
}

const protoRe = /^(\S+)[ \t]+(MRT|BGP|BFD|OSPF|RPKI|RIP|RAdv|Pipe|Perf|Direct|Babel|Device|Kernel|Static)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[0-9.]*|\S+)([ \t]+(.*))?$/;
const channelRe = /Channel[ \t]+ipv(4|6)/;
const routeFilteredRe = /^Routes:[ \t]+(\d+)[ \t]+imported,[ \t]+(\d+)[ \t]+filtered,[ \t]+(\d+)[ \t]+exported(,[ \t]+(\d+)[ \t]+preferred)?$/;
const routeSimpleRe = /^Routes:[ \t]+(\d+)[ \t]+imported,[ \t]+(\d+)[ \t]+exported(,[ \t]+(\d+)[ \t]+preferred)?$/;
const routeChangesRe = /^(Import|Export)[ \t]+(updates|withdraws):[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)([ \t]+(\d+|---)[ \t]+(\d+|---))?$/;
const filterRe = /(Input|Output)[ \t]+filter:[ \t]+(.*)/;

function parse_protocols(lines) {
	let res = [];
	let cur = null;

	for (let i = 0; i < length(lines); i++) {
		let line = lines[i];
		let l = length(line) ? replace(line, /^[ \t]+/, "") : "";

		if (!length(l)) {
			cur = null;
			continue;
		}

		let m = match(l, protoRe);
		if (m) {
			cur = new_proto(m[1], m[2], m[4] == "up" ? 1 : 0, m[7], uptime_seconds(m[5]), "");
			push(res, cur);
			continue;
		}

		if (!cur)
			continue;

		m = match(l, channelRe);
		if (m) {
			if (length(cur.ip_version)) {
				cur = new_proto(cur.name, cur.proto, cur.up, cur.state, cur.uptime, m[1]);
				push(res, cur);
			} else {
				cur.ip_version = m[1];
			}
			continue;
		}

		m = match(l, routeFilteredRe);
		if (m) {
			cur.imported = +m[1];
			cur.filtered = +m[2];
			cur.exported = +m[3];
			if (m[5] != null)
				cur.preferred = +m[5];
			continue;
		}

		m = match(l, routeSimpleRe);
		if (m) {
			cur.imported = +m[1];
			cur.exported = +m[2];
			if (m[4] != null)
				cur.preferred = +m[4];
			continue;
		}

		m = match(l, routeChangesRe);
		if (m) {
			let key = (m[1] == "Import" ? "import_" : "export_") +
			          (m[2] == "updates" ? "updates" : "withdraws");
			let c = cur[key];
			c.received = bird_num(m[3]) || 0;
			c.rejected = bird_num(m[4]) || 0;
			c.filtered = bird_num(m[5]) || 0;
			c.ignored = bird_num(m[6]) || 0;
			if (m[9] != null) {
				c.rx_limit = bird_num(m[7]) || 0;
				c.limit = bird_num(m[9]) || 0;
				c.accepted = bird_num(m[10]) || 0;
				cur.v3 = true;
			} else {
				c.accepted = bird_num(m[7]) || 0;
			}
			continue;
		}

		m = match(l, filterRe);
		if (m) {
			if (m[1] == "Input")
				cur.import_filter = m[2];
			else
				cur.export_filter = m[2];
		}
	}

	return res;
}

function emit_route_changes(labels, p) {
	let groups = [
		["import_updates", "update_import"],
		["import_withdraws", "withdraw_import"],
		["export_updates", "update_export"],
		["export_withdraws", "withdraw_export"],
	];

	for (let g = 0; g < length(groups); g++) {
		let c = p[groups[g][0]];
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

function emit_ospf(p) {
	let prefix = p.ip_version == "6" ? "bird_ospfv3" : "bird_ospf";

	gauge(prefix + "_running", "State of OSPF: 0 = Alone, 1 = Running")({ name: p.name },
		p.state == "Running" ? 1 : 0);

	let lines = bird_query("show ospf " + p.name);
	if (!lines)
		return;

	let areas = [];
	let cur = null;

	for (let i = 0; i < length(lines); i++) {
		let l = replace(lines[i], /^[ \t]+/, "");
		let m;

		if ((m = match(l, /^Area:[ \t]+\S+[ \t]+\((\S+)\)/))) {
			cur = { name: m[1], interfaces: 0, neighbors: 0, adjacent: 0 };
			push(areas, cur);
		} else if (cur && (m = match(l, /^Number[ \t]+of[ \t]+([^:]+):[ \t]+(\d+)/))) {
			if (m[1] == "interfaces")
				cur.interfaces = +m[2];
			else if (m[1] == "neighbors")
				cur.neighbors = +m[2];
			else if (m[1] == "adjacent neighbors")
				cur.adjacent = +m[2];
		}
	}

	for (let a = 0; a < length(areas); a++) {
		let lbl = { name: p.name, area: areas[a].name };
		gauge(prefix + "_interface_count", "Number of interfaces in the area")(lbl, areas[a].interfaces);
		gauge(prefix + "_neighbor_count", "Number of neighbors in the area")(lbl, areas[a].neighbors);
		gauge(prefix + "_neighbor_adjacent_count", "Number of adjacent neighbors in the area")(lbl, areas[a].adjacent);
	}

let ilines = bird_query("show ospf interface " + p.name);
	if (ilines) {
		let ifa = null;

		for (let i = 0; i < length(ilines); i++) {
			let l = replace(ilines[i], /^[ \t]+/, "");
			let m;

			if ((m = match(l, /^Interface[ \t]+(\S+)/))) {
				ifa = m[1];
			} else if (ifa && (m = match(l, /^Cost:[ \t]+(\d+)/))) {
				gauge(prefix + "_interface_cost", "OSPF interface cost (metric)")({ name: p.name, interface: ifa }, +m[1]);
			}
		}
	}

	let nlines = bird_query("show ospf neighbors " + p.name);
	if (nlines) {
		for (let i = 0; i < length(nlines); i++) {
			let l = replace(nlines[i], /^[ \t]+/, "");
			let m = match(l, /^(\S+)[ \t]+(\d+)[ \t]+(\S+)\/(\S+)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(\S+)$/);
			if (!m)
				continue;

			gauge(prefix + "_neighbor_up", "OSPF neighbor adjacency is Full (1) or not (0)")({
				name: p.name, interface: m[6], neighbor_rid: m[1], router_ip: m[7], local_rid: g_router_id,
			}, m[3] == "Full" ? 1 : 0);
		}
	}
}

const bfdRe = /^(\S+)[ \t]+(\S+)[ \t]+(Up|Down|Init)[ \t]+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[0-9.]*|\S+)[ \t]+([0-9.]+)[ \t]+([0-9.]+)$/;

function emit_bfd(p) {
	let lines = bird_query("show bfd sessions " + p.name);
	if (!lines)
		return;

	for (let i = 0; i < length(lines); i++) {
		let m = match(replace(lines[i], /^[ \t]+/, ""), bfdRe);
		if (!m)
			continue;

		let lbl = { name: p.name, ip: m[1], interface: m[2] };
		let up = m[3] == "Up" ? 1 : 0;

		gauge("bird_bfd_session_up", "Session is up")(lbl, up);
		gauge("bird_bfd_session_uptime_seconds", "Session uptime in seconds")(lbl, up ? (uptime_seconds(m[4]) || 0) : 0);
		gauge("bird_bfd_session_interval_seconds", "Session interval in seconds")(lbl, +m[5]);
		gauge("bird_bfd_session_timeout_seconds", "Session timeout in seconds")(lbl, +m[6]);
	}
}

function parse_status(lines) {
	let s = { version: null, router_id: null, server_time: null, last_reboot: null, last_reconfig: null };

	for (let i = 0; i < length(lines); i++) {
		let l = lines[i];
		let m;

		if ((m = match(l, /BIRD[ \t]+(\S+)/)))
			s.version = m[1];
		else if ((m = match(l, /Router[ \t]+ID[ \t]+is[ \t]+(\S+)/)))
			s.router_id = m[1];
		else if ((m = match(l, /Current[ \t]+server[ \t]+time[ \t]+is[ \t]+(.+)/)))
			s.server_time = ts_to_epoch(trim(m[1]));
		else if ((m = match(l, /Last[ \t]+reboot[ \t]+on[ \t]+(.+)/)))
			s.last_reboot = ts_to_epoch(trim(m[1]));
		else if ((m = match(l, /Last[ \t]+reconfiguration[ \t]+on[ \t]+(.+)/)))
			s.last_reconfig = ts_to_epoch(trim(m[1]));
	}

	return s;
}

const lines = bird_query("show protocols all");
if (!lines) {
	gauge("bird_socket_query_success", "Result of querying bird socket: 0 = failed, 1 = succeeded")(null, 0);
	gauge("bird_daemon_up", "Whether the BIRD daemon is up (1) or down (0)")(null, 0);
	return false;
}

gauge("bird_socket_query_success", "Result of querying bird socket: 0 = failed, 1 = succeeded")(null, 1);

const protos = parse_protocols(lines);

const status_lines = bird_query("show status");
if (status_lines) {
	let s = parse_status(status_lines);

	if (s.router_id != null)
		g_router_id = s.router_id;

	gauge("bird_daemon_up", "Whether the BIRD daemon is up (1) or down (0)")(null, 1);
	gauge("bird_daemon_info", "Static information about BIRD")({
		router_id: s.router_id,
		version: s.version,
	}, 1);
	if (s.last_reboot != null)
		gauge("bird_last_reboot_timestamp_seconds", "Timestamp of the last BIRD reboot")(null, s.last_reboot);
	if (s.last_reconfig != null)
		gauge("bird_last_reconfig_timestamp_seconds", "Timestamp of the last BIRD reconfiguration")(null, s.last_reconfig);
	if (s.server_time != null)
		gauge("bird_server_time_timestamp_seconds", "Server time reported by BIRD")(null, s.server_time);
} else {
	gauge("bird_daemon_up", "Whether the BIRD daemon is up (1) or down (0)")(null, 0);
}

for (let i = 0; i < length(protos); i++) {
	let p = protos[i];

	if (p.proto == "BFD") {
		emit_bfd(p);
		continue;
	}

	if (!is_generic(p.proto))
		continue;

	emit_protocol(p);

	if (p.proto == "OSPF")
		emit_ospf(p);
}