'use strict';
'require view';
'require rpc';
'require poll';
'require dom';

var callGetBirdStatus = rpc.declare({
	object: 'bird',
	method: 'status'
});

function stateBadge(up, state) {
	if (up == 1)
		return E('span', { 'class': 'cbi-status-ok' }, [ _('Up') ]);
	else if (state)
		return E('span', { 'class': 'cbi-status-failed' }, [ _('Down') ]);
	return E('span', { 'class': 'cbi-status-down' }, [ _('Down') ]);
}

function renderDaemonHeader(s) {
	var res = [ E('h2', [ _('BIRD Status') ]) ];

	if (!s || s.up == null) {
		res.push(E('p', { 'class': 'center', 'style': 'margin-top:5em' }, [
			E('em', [ _('Unable to reach the BIRD daemon.') ])
		]));
		return res;
	}

	var items = [];

	if (s.version)
		items.push([ _('Daemon'), E('code', [ s.version ]) ]);
	if (s.router_id)
		items.push([ _('Router ID'), E('code', [ s.router_id ]) ]);
	if (s.hostname)
		items.push([ _('Hostname'), s.hostname ]);
	if (s.up != null)
		items.push([ _('State'), stateBadge(s.up, null) ]);

	var t = new L.ui.Table(
		[ _('Property'), _('Value') ],
		{ id: 'bird-daemon' },
		E('em', [ _('No data') ])
	);

	t.update(items);

	res.push(t.render());

	return res;
}

function renderOspf(o) {
	var res = [
		E('h3', [ _('OSPF "%h"', 'OSPF protocol heading').format(o.protocol) ])
	];

	/* areas */
	var t = new L.ui.Table(
		[ _('Area'), _('Interfaces'), _('Neighbors'), _('Adjacent') ],
		{ id: 'bird-ospf-areas-' + o.protocol },
		E('em', [ _('No areas') ])
	);

	t.update((o.areas || []).map(function(a) {
		return [ a.name || '-', [ +a.interfaces, +a.interfaces ], [ +a.neighbors, +a.neighbors ], [ +a.adjacent, +a.adjacent ] ];
	}));

	res.push(t.render());

	/* neighbors */
	var t2 = new L.ui.Table(
		[ _('Router ID'), _('State'), _('Interface'), _('Neighbor IP') ],
		{ id: 'bird-ospf-neighbors-' + o.protocol },
		E('em', [ _('No neighbors') ])
	);

	t2.update((o.neighbors || []).map(function(n) {
		var full = (n.state == 'Full');
		return [
			n.rid || '-',
			E('span', { 'class': full ? 'cbi-status-ok' : 'cbi-status-failed' }, [
				full ? _('Full') : (n.state + (n.position ? '/' + n.position : ''))
			]),
			n.interface || '-',
			n.ip || '-'
		];
	}));

	res.push(t2.render());

	/* interfaces */
	var t3 = new L.ui.Table(
		[ _('Interface'), _('Cost') ],
		{ id: 'bird-ospf-interfaces-' + o.protocol },
		E('em', [ _('No interfaces') ])
	);

	t3.update((o.interfaces || []).map(function(i) {
		return [ i.interface || '-', [ +i.cost, +i.cost ] ];
	}));

	res.push(t3.render());

	return res;
}

function renderBgp(bgp) {
	var res = [ E('h3', [ _('BGP') ]) ];

	var t = new L.ui.Table(
		[ _('Peer'), _('Neighbor'), _('Peer AS'), _('Local AS'), _('IP'), _('State'), _('Imported'), _('Exported') ],
		{ id: 'bird-bgp' },
		E('em', [ _('No BGP sessions') ])
	);

	t.update((bgp || []).map(function(b) {
		return [
			b.name || '-',
			b.neighbor || (b.state ? b.state : '-'),
			b.neighbor_as != null ? b.neighbor_as : '-',
			b.local_as != null ? b.local_as : '-',
			b.ip_version == '6' ? 'IPv6' : 'IPv4',
			stateBadge(b.up, b.state),
			[ +b.imported, +b.imported ],
			[ +b.exported, +b.exported ]
		];
	}));

	res.push(t.render());

	return res;
}

/* Dependency-free SVG force-directed topology (OSPF neighbors + BGP peers) */
function topologySeed() {
	var s = 20260821;
	return function() {
		s = (s * 9301 + 49297) % 233280;
		return s / 233280;
	};
}

/* AS-level graph built from each route's BGP AS_PATH: nodes are ASNs, edges
 * connect consecutive hops of each path and this router's AS to its direct
 * peers.  Reveals the transit structure instead of a flat peer star. */
function buildAsGraph(data) {
	var nodes = [];
	var links = [];
	var index = {};
	var seen = {};

	function node(id, label, type) {
		if (!(id in index)) {
			var n = { id: id, label: label, type: type, up: 1, x: 0, y: 0, vx: 0, vy: 0 };
			index[id] = n;
			nodes.push(n);
		}
		return index[id];
	}

	function edge(a, b) {
		var k = a.id + '|' + b.id;
		if (seen[k])
			return;
		seen[k] = 1;
		links.push({ source: a, target: b });
	}

	var localAs = null;
	for (var i = 0; i < (data.bgp || []).length; i++)
		if (data.bgp[i].local_as != null) {
			localAs = data.bgp[i].local_as;
			break;
		}

	var local = node('local', localAs != null ? ('AS' + localAs) : _('local'), 'local');

	var paths = data.as_paths || [];
	for (var p = 0; p < paths.length; p++) {
		var arr = paths[p];
		var prev = null;

		for (var k = 0; k < arr.length; k++) {
			var n = node('as/' + arr[k], 'AS' + arr[k], 'as');
			if (prev != null)
				edge(prev, n);
			prev = n;
		}

		/* the last ASN in a path is our direct eBGP peer */
		if (arr.length)
			edge(local, node('as/' + arr[arr.length - 1], 'AS' + arr[arr.length - 1], 'as'));
	}

	return { nodes: nodes, links: links };
}

function layoutTopology(g, W, H) {
	var rand = topologySeed();
	var n = g.nodes.length;

	for (var i = 0; i < n; i++) {
		g.nodes[i].x = W / 2 + (rand() - 0.5) * W * 0.8;
		g.nodes[i].y = H / 2 + (rand() - 0.5) * H * 0.8;
		g.nodes[i].vx = 0;
		g.nodes[i].vy = 0;
	}

	var k = Math.sqrt((W * H) / Math.max(n, 1)) * 0.9;
	var ITER = 200;

	for (var it = 0; it < ITER; it++) {
		/* repulsion */
		for (var a = 0; a < n; a++) {
			for (var b = a + 1; b < n; b++) {
				var A = g.nodes[a], B = g.nodes[b];
				var dx = A.x - B.x, dy = A.y - B.y;
				var d = Math.sqrt(dx * dx + dy * dy) || 0.1;
				var f = (k * k) / (d * d) * 0.5;
				var fx = dx / d * f, fy = dy / d * f;
				A.vx += fx; A.vy += fy;
				B.vx -= fx; B.vy -= fy;
			}
		}

		/* links pull to target distance */
		for (var li = 0; li < g.links.length; li++) {
			var l = g.links[li];
			var S = l.source, T = l.target;
			var dx = T.x - S.x, dy = T.y - S.y;
			var d = Math.sqrt(dx * dx + dy * dy) || 0.1;
			var f = (d - k) / d * 0.35;
			var fx = dx * f, fy = dy * f;
			S.x += fx; S.y += fy;
			T.x -= fx; T.y -= fy;
		}

		/* center gravity + integrate */
		for (var c = 0; c < n; c++) {
			var N = g.nodes[c];
			N.vx += (W / 2 - N.x) * 0.02;
			N.vy += (H / 2 - N.y) * 0.02;
			N.x += N.vx;
			N.y += N.vy;
			N.vx *= 0.8;
			N.vy *= 0.8;
		}
	}

	return g;
}

function svgEsc(s) {
	return String(s == null ? '' : s).replace(/[&<>"']/g, function(c) {
		return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
	});
}

function renderTopology(data) {
	if (!data.status || data.status.up == null)
		return [];

	var typeColors = {
		'local': '#16a085',
		'as': '#8e44ad'
	};

	var g = buildAsGraph(data);
	if (g.nodes.length < 2)
		return [];

	g = layoutTopology(g, 720, 480);

	var svg = '<svg viewBox="-60 -60 840 600" width="100%" style="min-height:480px">';

	for (var l = 0; l < g.links.length; l++) {
		var L0 = g.links[l];
		svg += '<line x1="' + L0.source.x + '" y1="' + L0.source.y + '" x2="' + L0.target.x + '" y2="' + L0.target.y +
			'" stroke="#c0c0c0" stroke-width="1"/>';
	}

	for (var i = 0; i < g.nodes.length; i++) {
		var N = g.nodes[i];
		var fill = N.up ? typeColors[N.type] : '#95a5a6';
		var r = (N.type == 'local' ? 9 : 6);
		svg += '<circle cx="' + N.x + '" cy="' + N.y + '" r="' + r +
			'" fill="' + fill + '" stroke="#ffffff" stroke-width="1.5"/>';
		svg += '<text x="' + N.x + '" y="' + (N.y + 16) + '" text-anchor="middle" ' +
			'font-size="' + (N.type == 'local' ? 12 : 10) + '">' + svgEsc(N.label || N.id) + '</text>';
	}

	svg += '</svg>';

	var box = E('div', { 'style': 'overflow:auto' });
	box.innerHTML = svg;

	var legend = E('div', { 'style': 'margin-top:1em;color:#666;font-size:12px' }, [
		E('span', { 'style': 'color:' + typeColors.local }, [ _('this AS') ]),
		' · ',
		E('span', { 'style': 'color:' + typeColors.as }, [ _('AS') ]),
		' · ',
		E('em', [ _('edges from BGP AS paths') ])
	]);

	return [
		E('h3', [ _('Topology') ]),
		box,
		legend
	];
}

function renderBfd(bfd) {
	var res = [ E('h3', [ _('BFD') ]) ];

	var t = new L.ui.Table(
		[ _('Protocol'), _('Peer'), _('Interface'), _('State'), _('Interval'), _('Timeout') ],
		{ id: 'bird-bfd' },
		E('em', [ _('No BFD sessions') ])
	);

	var rows = [];
	for (var i = 0; i < (bfd || []).length; i++) {
		var b = bfd[i];
		for (var j = 0; j < (b.sessions || []).length; j++) {
			var s = b.sessions[j];
			rows.push([
				b.protocol,
				s.ip,
				s.interface,
				stateBadge(s.up, null),
				s.interval != null ? s.interval : '-',
				s.timeout != null ? s.timeout : '-'
			]);
		}
	}

	t.update(rows);

	res.push(t.render());

	return res;
}

return view.extend({
	load() {
		return Promise.all([]);
	},

	renderStatus(data) {
		var res = renderDaemonHeader(data.status);

		if (!data.status || data.status.up == null)
			return E([], res);

		res = res.concat(renderBgp(data.bgp || []));

		for (var i = 0; i < (data.ospf || []).length; i++)
			res = res.concat(renderOspf(data.ospf[i]));

		res = res.concat(renderBfd(data.bfd || []));

		res = res.concat(renderTopology(data));

		return E([], res);
	},

	render() {
		poll.add(L.bind(function () {
			return callGetBirdStatus().then(L.bind(function(data) {
				dom.content(
					document.querySelector('#view'),
					this.renderStatus(data)
				);
			}, this));
		}, this), 5);

		return E([], [
			E('h2', [ _('BIRD Status') ]),
			E('p', { 'class': 'center', 'style': 'margin-top:5em' }, [
				E('em', [ _('Loading data…') ])
			])
		]);
	},

	handleReset: null,
	handleSaveApply: null,
	handleSave: null
});