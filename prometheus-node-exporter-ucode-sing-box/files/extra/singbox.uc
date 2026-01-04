let uloop = require("uloop");
let uclient = require("uclient");

// clash api url
const api_url = config["api_url"];
if (!api_url)
	return false;

// optional bearer secret
const secret = config["secret"];
// export each connection data, warning: label high cardinality!
const per_connection = config["per_connection"] == "1";

let m_up = gauge("singbox_up", "Sing-Box Clash API connected");
let m_version_info = gauge("singbox_version_info", "Sing-Box version");
let m_memory_used = gauge("singbox_memory_used_bytes", "Memory used [bytes]");
let m_connections_total = gauge("singbox_connections_total", "Total amount of connections");
let m_connections_total_up = counter("singbox_connections_total_upload_bytes_total", "Cumulative upload by all connections [bytes]");
let m_connections_total_dn = counter("singbox_connections_total_download_bytes_total", "Cumulative download by all connections [bytes]");
let m_connections_up = gauge("singbox_connections_upload_bytes_total", "Cumulative upload by type [bytes]");
let m_connections_dn = gauge("singbox_connections_download_bytes_total", "Cumulative download by type [bytes]");

// if detailed_connections enabled
let m_per_conn_up = gauge("singbox_perconn_upload_bytes_total", "Connection upload [bytes]");
let m_per_conn_dn = gauge("singbox_perconn_download_bytes_total", "Connection download [bytes]");


function fetch_json(api_url, secret, endpoint) {
	let data = '';

	const url = `${api_url}${endpoint}`;
	let headers = {
		"User-Agent": "prometheus-node-exporter-ucode/1.0",
		"Content-Type": "application/json",
	};
	if (secret)
		headers["Authorization"] = `Bearer ${secret}`;

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

const version = fetch_json(api_url, secret, "/version");
const connections = fetch_json(api_url, secret, "/connections");
if (!version || !connections) {
	m_up({url: api_url}, 0);
	return false;
}

m_up({url: api_url}, 1);
m_version_info({
	meta: version?.meta,
	premium: version?.premium,
	version: replace(version.version, "^sing-box\\ ", ""),
}, 1);

m_memory_used({}, connections.memory);
m_connections_total({}, length(connections.connections));
m_connections_total_up({}, connections.uploadTotal);
m_connections_total_dn({}, connections.downloadTotal);

let up_counter = {};
let dn_counter = {};

function add_bytes(store, key, value) {
	let old = store[key];
	if (!old)
		old = 0;

	store[key] = old + value;
}

for (let conn in connections.connections) {
	add_bytes(up_counter, conn.type, conn.upload);
	add_bytes(dn_counter, conn.type, conn.download);

	if (per_connection) {
		let labels = {
			id: conn.id,
			rule: conn.rule,
			host: conn.metadata.host,
			dns_mode: conn.metadata.dnsMode,
			network: conn.metadata.network,
			dest_ip: conn.metadata.destinationIP,
			dest_port: conn.metadata.destinationPort,
			src_ip: conn.metadata.sourceIP,
			src_port: conn.metadata.sourcePort,
			process_path: conn.metadata.processPath,
			type: conn.metadata.type,
		};

		m_per_conn_up(labels, conn.upload);
		m_per_conn_dn(labels, conn.download);
	}
}

for (let type, value in up_counter) {
	m_connections_up({type: type}, value);
}

for (let type, value in dn_counter) {
	m_connections_dn({type: type}, value);
}
