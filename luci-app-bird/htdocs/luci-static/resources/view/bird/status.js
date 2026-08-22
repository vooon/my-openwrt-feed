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


/* dynamic AS-path topology rendered with vis-network */

var topoScriptLoaded = false;
var topoScriptLoading = false;
var topoBoxEl = null;
var topoNet = null;

function loadTopoScript(cb) {
	if (topoScriptLoaded) {
		if (cb) cb(true);
		return;
	}
	if (topoScriptLoading)
		return;
	topoScriptLoading = true;

	var s = document.createElement('script');
	s.async = true;
	s.src = L.resource('bird/vis-network.min.js');
	s.onload = function() {
		topoScriptLoaded = true;
		topoScriptLoading = false;
		if (cb) cb(true);
	};
	s.onerror = function() {
		topoScriptLoading = false;
		if (cb) cb(false);
	};
	document.head.appendChild(s);
}

/* Build vis node/edge arrays from BGP AS paths.  Nodes are ASNs; an edge links
 * consecutive hops of every path plus this router's AS to its eBGP peers. */
function buildAsGraph(data) {
	var nodes = [];
	var edges = [];
	var seen = {};
	var byId = {};

	function node(id, label, group) {
		if (!(id in byId)) {
			byId[id] = nodes.length;
			nodes.push({ id: id, label: label, group: group });
		}
		return id;
	}

	function edge(a, b) {
		if (a == b)
			return;
		var k = a < b ? (a + '|' + b) : (b + '|' + a);
		if (seen[k])
			return;
		seen[k] = 1;
		edges.push({ from: a, to: b, length: 140 });
	}

	var localAs = null;
	for (var i = 0; i < (data.bgp || []).length; i++)
		if (data.bgp[i].local_as != null) {
			localAs = data.bgp[i].local_as;
			break;
		}
	var localId = 'as' + localAs;
	node(localId, localAs != null ? ('AS' + localAs) : _('us'), 'local');

	var paths = data.as_paths || [];
	for (var p = 0; p < paths.length; p++) {
		var arr = paths[p];
		var prev = null;

		for (var k = 0; k < arr.length; k++) {
			var id = 'as' + arr[k];
			node(id, 'AS' + arr[k], 'peer');
			if (prev != null)
				edge(prev, id);
			prev = id;
		}

		/* BIRD prefixes the AS_PATH with our direct eBGP peer (first element) */
		if (arr.length)
			edge(localId, 'as' + arr[0]);
	}

	return { nodes: nodes, edges: edges };
}

var topoOptions = {
	nodes: {
		shape: 'dot',
		font: { size: 14 },
		borderWidth: 2
	},
	groups: {
		local: { color: { background: '#16a085', border: '#12876e' }, size: 20, font: { size: 16, color: '#12876e' } },
		peer: { color: { background: '#8e44ad', border: '#7d3c9e' }, size: 14 }
	},
	edges: {
		color: '#b8c0c8',
		selectionWidth: 2
	},
	physics: {
		barnesHut: {
			gravitationalConstant: -3200,
			centralGravity: 0.25,
			springLength: 130,
			springConstant: 0.05
		},
		enabled: true,
		stabilization: { iterations: 200 }
	},
	interaction: { hover: true, dragNodes: true }
};

/* Returned before the element is attached to the DOM; real init happens in
 * updateTopo() afterwards (vis.Network needs the container in the document). */
function renderTopology(data) {
	if (!topoBoxEl)
		topoBoxEl = E('div', { 'style': 'height:520px;border:1px solid #ddd;border-radius:4px' });

	return E([], [
		E('h3', [ _('Topology') ]),
		topoBoxEl
	]);
}

function updateTopo(data) {
	try {
		if (!topoScriptLoaded) {
			loadTopoScript();
			topoBoxEl.innerHTML = '<p class="center" style="margin-top:6em"><em>' +
				_('Loading topology…') + '</em></p>';
			return;
		}

		if (typeof vis === 'undefined' || !data.status || data.status.up == null) {
			topoBoxEl.innerHTML = '';
			return;
		}

		var g = buildAsGraph(data);
		if (g.nodes.length < 2) {
			topoBoxEl.innerHTML = '';
			return;
		}

		var dataSet = {
			nodes: new vis.DataSet(g.nodes),
			edges: new vis.DataSet(g.edges)
		};

		if (!topoNet) {
			topoNet = new vis.Network(topoBoxEl, dataSet, topoOptions);
		} else {
			topoNet.setData(dataSet);
		}
	} catch (e) {
		topoBoxEl.innerHTML = '<p class="center"><em>' + _('Topology error: %h').format(e.message || e) + '</em></p>';
	}
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

				updateTopo(data);
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