import { fetch_json } from "http_client.uc";

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

const version = fetch_json(api_url, "/version", secret);
const connections = fetch_json(api_url, "/connections", secret);
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
