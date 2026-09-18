// clash api url
const api_url = config["api_url"];
const fetch_json = config["fetch_json"];
if (!api_url || !fetch_json)
	return false;

// optional bearer secret
const secret = config["secret"];
// export each connection data, warning: label high cardinality!
const per_connection = config["per_connection"] == "1";

let m_up = gauge("mihomo_up", "Mihomo API connected");
let m_version = gauge("mihomo_version_info", "Mihomo version");
let m_traffic_up = gauge("mihomo_traffic_upload_bytes_per_second", "Current upload rate [bytes/s]");
let m_traffic_down = gauge("mihomo_traffic_download_bytes_per_second", "Current download rate [bytes/s]");
let m_traffic_up_total = counter("mihomo_traffic_upload_bytes_total", "Cumulative uploaded bytes");
let m_traffic_down_total = counter("mihomo_traffic_download_bytes_total", "Cumulative downloaded bytes");
let m_memory = gauge("mihomo_memory_used_bytes", "Memory in use [bytes]");
let m_connections = gauge("mihomo_connections_active_total", "Active connections");
let m_node_up = gauge("mihomo_connection_upload_bytes_by_node", "Upload by outbound node [bytes]");
let m_node_down = gauge("mihomo_connection_download_bytes_by_node", "Download by outbound node [bytes]");
let m_dest_up = gauge("mihomo_connection_upload_bytes_by_destination", "Upload by destination and outbound node [bytes]");
let m_dest_down = gauge("mihomo_connection_download_bytes_by_destination", "Download by destination and outbound node [bytes]");
let m_proxy_info = gauge("mihomo_proxy_info", "Mihomo proxy information");
let m_proxy_available = gauge("mihomo_proxy_available", "Whether a Mihomo proxy is available");
let m_proxy_latency = gauge("mihomo_proxy_latency_ms", "Latest Mihomo proxy latency [ms]");
let m_per_conn_up = gauge("mihomo_connection_upload_bytes", "Connection upload [bytes]");
let m_per_conn_down = gauge("mihomo_connection_download_bytes", "Connection download [bytes]");

const version = fetch_json(api_url, "/version", secret);
const traffic = fetch_json(api_url, "/traffic", secret);
const memory = fetch_json(api_url, "/memory", secret);
const connections = fetch_json(api_url, "/connections", secret);
const proxies = fetch_json(api_url, "/proxies", secret);

if (!version || !traffic || !memory || !connections || !proxies) {
	m_up({url: api_url}, 0);
	return false;
}

m_up({url: api_url}, 1);
m_version({meta: version.meta, version: version.version}, 1);
m_traffic_up({}, traffic.up);
m_traffic_down({}, traffic.down);
m_traffic_up_total({}, traffic.upTotal);
m_traffic_down_total({}, traffic.downTotal);
m_memory({}, memory.inuse);
m_connections({}, length(connections.connections));

let by_node = { up: {}, down: {} };
let by_destination = { up: {}, down: {} };

function add_bytes(store, key, value) {
	if (key == null || key == "")
		key = "unknown";

	let old = store[key];
	if (!old)
		old = 0;

	store[key] = old + value;
}

for (let conn in connections.connections) {
	let chain = "DIRECT";
	if (length(conn.chains) > 0)
		chain = conn.chains[length(conn.chains) - 1];

	let provider_chain = "";
	if (length(conn.providerChains) > 0)
		provider_chain = conn.providerChains[length(conn.providerChains) - 1];

	let destination = conn.metadata.host;
	if (!destination)
		destination = conn.metadata.destinationIP;

	add_bytes(by_node.up, chain, conn.upload);
	add_bytes(by_node.down, chain, conn.download);

	if (!(chain in by_destination.up)) {
		by_destination.up[chain] = {};
		by_destination.down[chain] = {};
	}

	add_bytes(by_destination.up[chain], destination, conn.upload);
	add_bytes(by_destination.down[chain], destination, conn.download);

	if (per_connection) {
		let labels = {
			id: conn.id,
			network: conn.metadata.network,
			type: conn.metadata.type,
			source_ip: conn.metadata.sourceIP,
			source_port: conn.metadata.sourcePort,
			destination_ip: conn.metadata.destinationIP,
			destination_port: conn.metadata.destinationPort,
			host: conn.metadata.host,
			rule: conn.rule,
			rule_payload: conn.rulePayload,
			chain: join(" > ", conn.chains),
			provider_chain: join(" > ", conn.providerChains),
			process: conn.metadata.process,
			process_path: conn.metadata.processPath,
		};

		m_per_conn_up(labels, conn.upload);
		m_per_conn_down(labels, conn.download);
	}
}

for (let node, value in by_node.up) {
	m_node_up({outbound_node: node}, value);
}

for (let node, value in by_node.down) {
	m_node_down({outbound_node: node}, value);
}

for (let node, destinations in by_destination.up) {
	for (let destination, value in destinations) {
		m_dest_up({destination: destination, outbound_node: node}, value);
	}
}

for (let node, destinations in by_destination.down) {
	for (let destination, value in destinations) {
		m_dest_down({destination: destination, outbound_node: node}, value);
	}
}

for (let name, proxy in proxies.proxies) {
	m_proxy_info({name: name, type: proxy.type, provider: proxy["provider-name"]}, 1);
	m_proxy_available({name: name}, proxy.alive ? 1 : 0);
	if (length(proxy.history) > 0)
		m_proxy_latency({name: name}, proxy.history[length(proxy.history) - 1].delay);
}
