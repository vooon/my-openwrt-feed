const info = ubus.call("babeld", "get_info");
if (!info)
	return false;

gauge("babel_info", "babeld node information")({
	version: info.babeld_version,
	my_id: info.my_id,
	host: info.host,
}, 1);

const neighbours = ubus.call("babeld", "get_neighbours");
if (!neighbours)
	return false;

let m_neigh_rxcost = gauge("babel_neighbour_rxcost", "Babel neighbour receive cost");
let m_neigh_txcost = gauge("babel_neighbour_txcost", "Babel neighbour transmit cost");
let m_neigh_reach = gauge("babel_neighbour_hello_reach", "Babel neighbour hello reachability");
let m_neigh_ureach = gauge("babel_neighbour_uhello_reach", "Babel neighbour unicast hello reachability");
let m_neigh_rtt = gauge("babel_neighbour_rtt_seconds", "Babel neighbour RTT in seconds");
let m_neigh_up = gauge("babel_neighbour_if_up", "Babel neighbour interface is up");

let neigh_count = 0;
for (let family in ["IPv4", "IPv6"]) {
	for (let n in neighbours[family]) {
		let labels = {
			address: n.address,
			interface: n.dev,
		};

		m_neigh_rxcost(labels, n.rxcost);
		m_neigh_txcost(labels, n.txcost);
		m_neigh_reach(labels, n.hello_reach);
		m_neigh_ureach(labels, n.uhello_reach);
		m_neigh_rtt(labels, +n.rtt / 1000.0);
		m_neigh_up(labels, n.if_up ? 1 : 0);
		neigh_count++;
	}
}

gauge("babel_neighbours_total", "Total number of babel neighbours")(null, neigh_count);

const routes = ubus.call("babeld", "get_routes");
if (!routes)
	return false;

let m_route_metric = gauge("babel_route_metric", "Babel route metric");
let m_route_smoothed_metric = gauge("babel_route_smoothed_metric", "Babel route smoothed metric");
let m_route_refmetric = gauge("babel_route_refmetric", "Babel route reference metric");
let m_route_installed = gauge("babel_route_installed", "Babel route is installed");
let m_route_feasible = gauge("babel_route_feasible", "Babel route is feasible");
let m_route_seqno = gauge("babel_route_seqno", "Babel route sequence number");
let m_route_age = gauge("babel_route_age_seconds", "Babel route age in seconds");

let route_count = 0;
for (let family in ["IPv4", "IPv6"]) {
	for (let r in routes[family]) {
		let labels = {
			prefix: r.address,
			src_prefix: r.src_prefix,
			id: r.id,
			via: r.via,
		};

		m_route_metric(labels, r.route_metric);
		m_route_smoothed_metric(labels, r.route_smoothed_metric);
		m_route_refmetric(labels, r.refmetric);
		m_route_installed(labels, r.installed ? 1 : 0);
		m_route_feasible(labels, r.feasible ? 1 : 0);
		m_route_seqno(labels, r.seqno);
		m_route_age(labels, r.age);
		route_count++;
	}
}

gauge("babel_routes_total", "Total number of babel routes")(null, route_count);

const xroutes = ubus.call("babeld", "get_xroutes");
if (!xroutes)
	return false;

let m_xroute_metric = gauge("babel_xroute_metric", "Babel locally originated route metric");

let xroute_count = 0;
for (let family in ["IPv4", "IPv6"]) {
	for (let x in xroutes[family]) {
		m_xroute_metric({
			prefix: x.address,
			src_prefix: x.src_prefix,
		}, x.metric);
		xroute_count++;
	}
}

gauge("babel_xroutes_total", "Total number of babel xroutes")(null, xroute_count);
