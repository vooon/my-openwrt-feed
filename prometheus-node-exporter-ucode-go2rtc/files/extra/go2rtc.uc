import * as uclient from "uclient";
import * as log from "log";

const api_url = config["api_url"]
if (!api_url)
	return false;

let m_up = gauge("go2rtc_up");
let m_producer_info = gauge("go2rtc_producer_info");
let m_consumer_info = gauge("go2rtc_consumer_info");
let m_producer_rx = counter("go2rtc_producer_received_bytes_total");
let m_consumer_tx = counter("go2rtc_consumer_sent_bytes_total");

function get_streams_info(api_url) {

	let uc = uclient.new(`${api_url}/api/streams`, null, {
		error: (cb, code) => {
			log.ERR("uclient error code=%s url=%s\n", code, api_url);
			m_up({}, 0);
		},
	});

	if (!uc.connect()) {
		log.ERR("failed to connect.\n");
		return null;
	}

	let args = {
		headers: {
			"User-Agent": "prometheus-exporter/1.0",
			"Accept": "application/json",
		},
	};

	if (!uc.request("GET", args)) {
		log.ERR("failed to send request\n");
		return null;
	}

	let data = json(uc);

	return data;
}

//for (let iface in x) {
//
//	m_wg_iface_info({
//		name: iface,
//		public_key: wc["public_key"],
//		listen_port: wc["listen_port"],
//		fwmark: wc["fwmark"] || NaN,
//	}, 1);
//
//}
