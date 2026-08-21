'use strict';
'require view';
'require rpc';
'require poll';
'require dom';
'require ui';

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

	res.push(ui.itemlist(E([]), items));

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
		[ _('Peer'), _('Peers AS'), _('Local AS'), _('IP'), _('State'), _('Imported'), _('Exported') ],
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