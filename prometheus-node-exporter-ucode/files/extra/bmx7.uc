// Prometheus collector for the BMX7 mesh routing daemon.
//
// Talks to the BMX7 control socket through the "bmx7" rpcd module
// (ubus call bmx7 query), which runs outside the ujail and has direct
// access to /var/run/bmx7/sock.  Uses the "list <context>" commands which
// emit parseable "name=value" pairs.

const socket = config.socket || "/var/run/bmx7/sock";

function bmx_query(cmd) {
	const r = ubus.call("bmx7", "query", {
		command: cmd,
		socket: socket,
	});

	if (!r || r.code != 0 || r.stdout == null)
		return null;

	return r.stdout;
}

// Parse "name=value name=value ..." rows into an array of objects.
function parse_rows(text) {
	let rows = [];

	for (let i = 0; i < length(split(text, "\n")); i++) {
		let line = split(text, "\n")[i];
		let row = {};

		for (let j = 0; j < length(split(line, /[ \t]+/)); j++) {
			let tok = split(line, /[ \t]+/)[j];
			if (!length(tok))
				continue;

			let eq = index(tok, "=");
			if (eq < 1)
				continue;

			row[substr(tok, 0, eq)] = substr(tok, eq + 1);
		}

		if (length(keys(row)))
			push(rows, row);
	}

	return rows;
}

function num(s) {
	if (s == null || !length(s) || s == "---")
		return null;

	let m = match(s, /^-?[0-9]+(\.[0-9]+)?$/);
	return m ? +s : null;
}

// Parse BMX7 human metric values ("150K", "1.5M", "123G", "500").
function u_num(s) {
	if (s == null || !length(s) || s == "---")
		return null;

	let m = match(s, /^(-?[0-9]+(\.[0-9]+)?)([KMG])?$/);
	if (!m)
		return null;

	let mult = m[3] == "K" ? 1000 : m[3] == "M" ? 1000000 :
	           m[3] == "G" ? 1000000000 : 1;

	return (+m[1]) * mult;
}

// Parse "N/N" pairs returning the first value.
function slash_first(s) {
	if (s == null)
		return null;

	let m = match(s, /^([0-9]+)\//);
	return m ? +m[1] : null;
}

// Parse "N/<something>" pairs returning the second value.
function slash_second(s) {
	if (s == null)
		return null;

	let m = match(s, /^[0-9]+\/(.*)$/);
	return m ? +m[1] : null;
}

// Parse "NN:HH:MM:SS" into seconds.
function uptime_seconds(s) {
	if (s == null)
		return null;

	let m = match(s, /^(\d+):(\d{2}):(\d{2}):(\d{2})$/);
	if (m)
		return (+m[1]) * 86400 + (+m[2]) * 3600 + (+m[3]) * 60 + (+m[4]);

	return null;
}

// Parse "NNNK"/"NNNM"/"NNNG" into bytes.
function bytes(s) {
	if (s == null)
		return null;

	let m = match(s, /^([0-9.]+)([KMG]?)$/);
	if (!m)
		return null;

	let mult = m[2] == "K" ? 1024 : m[2] == "M" ? 1048576 :
	           m[2] == "G" ? 1073741824 : 1;

	return (+m[1]) * mult;
}

function emit_status(text) {
	let rows = parse_rows(text);
	if (!length(rows))
		return false;

	let s = rows[0];

	gauge("bmx7_info", "BMX7 node information")({
		node_id: s["nodeId"],
		short_id: s["shortId"],
		name: s["name"],
		version: s["version"],
		revision: s["revision"],
		primary_ip: s["primaryIp"],
		tun6_address: s["tun6Address"],
		tun4_address: s["tun4Address"],
	}, 1);
	gauge("bmx7_uptime_seconds", "BMX7 daemon uptime in seconds")(null, uptime_seconds(s["uptime"]));
	gauge("bmx7_cpu_percent", "BMX7 CPU load in percent")(null, num(s["cpu"]));
	gauge("bmx7_memory_bytes", "BMX7 memory usage in bytes")(null, bytes(s["mem"]));
	gauge("bmx7_txqueue", "BMX7 tx queue size")(null, slash_first(s["txQ"]));
	gauge("bmx7_tx_bucket_size", "BMX7 tx bucket size")(null, slash_second(s["txQ"]));
	gauge("bmx7_neighbors", "Number of neighbor nodes")(null, num(s["nbs"]));
	gauge("bmx7_routes", "Number of routes")(null, num(s["rts"]));
	gauge("bmx7_originators_total", "Number of known originators")(null, slash_first(s["nodes"]));
	gauge("bmx7_keys_total", "Number of known node keys")(null, slash_second(s["nodes"]));

	return true;
}

function emit_interfaces(text) {
	let rows = parse_rows(text);

	for (let i = 0; i < length(rows); i++) {
		let r = rows[i];
		let dev = r["dev"];
		if (!dev)
			continue;

		gauge("bmx7_interface_info", "BMX7 interface information")({
			dev: dev,
			state: r["state"],
			type: r["type"],
			phy: r["phy"],
			channel: r["channel"],
			local_mac: r["localMac"],
			local_ip: r["localIp"],
			idx: r["idx"],
		}, 1);
		gauge("bmx7_interface_rts", "Routes on the interface")({ dev: dev }, num(r["rts"]));
		gauge("bmx7_interface_rate_max", "Maximum interface rate")({ dev: dev }, u_num(r["rateMax"]));
		gauge("bmx7_interface_rx_bytes_per_second", "Interface receive bytes per second")({ dev: dev }, slash_first(r["rxBpP"]));
		gauge("bmx7_interface_tx_bytes_per_second", "Interface transmit bytes per second")({ dev: dev }, slash_first(r["txBpP"]));
		gauge("bmx7_interface_tx_tasks", "Open tx tasks on the interface")({ dev: dev }, num(r["txTasks"]));
	}
}

function emit_links(text) {
	let rows = parse_rows(text);

	for (let i = 0; i < length(rows); i++) {
		let r = rows[i];
		let node_id = r["nodeId"];
		let name = r["name"];
		let dev = r["dev"];
		if (!node_id && !name)
			continue;

		let lbl = { node_id: node_id, name: name, dev: dev };

		gauge("bmx7_link_info", "BMX7 link to a neighbor node")({
			short_id: r["shortId"],
			node_id: node_id,
			name: name,
			link_key: r["linkKey"],
			dev: dev,
			local_ip: r["localIp"],
			nb_local_ip: r["nbLocalIp"],
			nb_mac: r["nbMac"],
		}, 1);
		gauge("bmx7_link_rq", "Link receive quality")(lbl, num(r["rq"]));
		gauge("bmx7_link_best_rq", "Best link receive quality")(lbl, num(r["bestRq"]));
		gauge("bmx7_link_tq", "Link transmission quality")(lbl, num(r["tq"]));
		gauge("bmx7_link_best_tq", "Best link transmission quality")(lbl, num(r["bestTq"]));
		gauge("bmx7_link_rx_rate", "Link receive rate")(lbl, u_num(r["rxRate"]));
		gauge("bmx7_link_tx_rate", "Link transmit rate")(lbl, u_num(r["txRate"]));
		gauge("bmx7_link_wrx_rate", "Link wifi receive rate")(lbl, u_num(r["wRxRate"]));
		gauge("bmx7_link_wtx_rate", "Link wifi transmit rate")(lbl, u_num(r["wTxRate"]));
		gauge("bmx7_link_wtx_rate_avg", "Average wifi transmit rate")(lbl, u_num(r["wTxRateAvg"]));
		gauge("bmx7_link_wtx_rate_eff", "Effective wifi transmit rate")(lbl, u_num(r["wTxRateEff"]));
		gauge("bmx7_link_wtx_throughput", "Wifi transmit throughput")(lbl, u_num(r["wTxThr"]));
		gauge("bmx7_link_wtx_throughput_avg", "Average wifi transmit throughput")(lbl, u_num(r["wTxThrAvg"]));
		gauge("bmx7_link_wtx_throughput_eff", "Effective wifi transmit throughput")(lbl, u_num(r["wTxThrEff"]));
		gauge("bmx7_link_signal_dbm", "Link signal in dBm")(lbl, num(r["wSignal"]));
		gauge("bmx7_link_noise_dbm", "Link noise in dBm")(lbl, num(r["wNoise"]));
		gauge("bmx7_link_snr", "Link signal to noise ratio")(lbl, num(r["wSnr"]));
		gauge("bmx7_link_mcs", "Link MCS index")(lbl, num(r["mcs"]));
		gauge("bmx7_link_mhz", "Link frequency in MHz")(lbl, num(r["mhz"]));
		gauge("bmx7_link_nss", "Link spatial streams")(lbl, num(r["nss"]));
		gauge("bmx7_link_channel_width", "Link channel width in MHz")(lbl, num(r["chw"]));
		gauge("bmx7_link_aggregation_size", "Link aggregation size")(lbl, num(r["aggSize"]));
		gauge("bmx7_link_aggregation_max", "Link max aggregation size")(lbl, num(r["aggMax"]));
	}
}

function emit_originators(text) {
	let rows = parse_rows(text);

	for (let i = 0; i < length(rows); i++) {
		let r = rows[i];
		let node_id = r["nodeId"];
		let name = r["name"];
		if (!node_id && !name)
			continue;

		let lbl = { node_id: node_id, name: name };

		gauge("bmx7_originator_info", "BMX7 originator node information")({
			short_id: r["shortId"],
			node_id: node_id,
			name: name,
			primary_ip: r["primaryIp"],
			dev: r["dev"],
			state: r["assessedState"],
		}, 1);
		gauge("bmx7_originator_pref", "Originator preference value")(lbl, num(r["pref"]));
		gauge("bmx7_originator_broadcast_timeout", "Originator broadcast timeout")(lbl, num(r["brcTo"]));
		gauge("bmx7_originator_security_timeout", "Originator security timeout")(lbl, num(r["signTo"]));
		gauge("bmx7_originator_response_timeout", "Originator response timeout")(lbl, num(r["tAPTo"]));
		gauge("bmx7_originator_trustees", "Number of trustees")(lbl, num(r["trustees"]));
		gauge("bmx7_originator_friend", "Originator is a friend")(lbl, num(r["friend"]));
		gauge("bmx7_originator_recommended", "Originator is recommended")(lbl, num(r["recom"]));
		gauge("bmx7_originator_desc_sqn", "Originator description sequence number")(lbl, num(r["descSqn"]));
	}
}

const status = bmx_query("list status");
if (!status) {
	gauge("bmx7_up", "Whether the BMX7 daemon is up (1) or down (0)")(null, 0);
	return false;
}

gauge("bmx7_up", "Whether the BMX7 daemon is up (1) or down (0)")(null, 1);

emit_status(status);

const interfaces = bmx_query("list interfaces");
if (interfaces)
	emit_interfaces(interfaces);

const links = bmx_query("list links");
if (links)
	emit_links(links);

const originators = bmx_query("list originators");
if (originators)
	emit_originators(originators);