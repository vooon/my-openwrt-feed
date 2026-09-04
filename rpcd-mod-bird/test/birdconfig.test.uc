'use strict';

/* Unit tests for birdconfig.uc (pure BIRD parser/config editor) that ships
 * with rpcd-mod-bird.  Run via run_tests.sh.
 *
 * For each fixture the runner asserts:
 *   - the edited config matches the golden file byte-for-byte (so everything
 *     outside the edited interface block stays untouched), and
 *   - re-applying the same edit is a no-op (idempotent).
 * Where a cost already existed, an a->b->a round trip must restore the
 * original file exactly.
 *
 * Parser fixtures cover `Type:` present and absent (expects type == null).
 */

import * as fs from 'fs';

import { parseOspfInterfaces, editOspfCost, parsePrefix, parseRoute, routeAsPath, exactRoute, bestCoveringRoute } from '../src/birdconfig.uc';

let failures = 0;
let count = 0;

function report(name, ok, msg)
{
	count++;

	if (ok)
		printf('PASS  %s\n', name);
	else {
		failures++;
		printf('FAIL  %s: %s\n', name, msg ? msg : '');
	}
}

function read(name)
{
	let s = fs.readfile(name);

	return (s == null) ? '' : s;
}

/* Edit @iface/@cost in a fixture and compare to a golden file. */
function editMatch(name, fixture, iface, cost)
{
	let orig = read('fixtures/' + fixture);
	let exp = read('expected/' + name + '.out');
	let r = editOspfCost(orig, iface, cost);

	report(name + ' ok', r.ok, r.ok ? '' : r.error);
	report(name + ' text', r.ok && r.text == exp, r.ok ? 'golden mismatch' : 'edit failed');

	if (r.ok) {
		let r2 = editOspfCost(r.text, iface, cost);

		report(name + ' idempotent', r2.ok && r2.text == r.text, 're-edit changed output');
	}
	else {
		/* keep a (debug) copy of the actual output on disk for diffing */
		let n = replace(name, /[^a-zA-Z0-9._-]+/g, '_');
		fs.writefile('/tmp/birdconfig-actual-' + n + '.out', r.ok ? r.text : r.error);
	}
}

/* Round trip a, b on an interface that already carries a cost: changing the
 * cost and changing it back must reproduce the fixture byte-for-byte. */
function roundTrip(name, fixture, iface, a, b)
{
	let base = read('fixtures/' + fixture);

	let r1 = editOspfCost(base, iface, a);
	let r2 = r1.ok ? editOspfCost(r1.text, iface, b) : null;

	report(name, r1.ok && r2 && r2.ok && r2.text == base,
	       'round trip to original failed');
}

/* Assert an edit produces an expected outcome (ok flag + optional match). */
function expectEdit(name, text, iface, cost, wantOk, wantText)
{
	let r = editOspfCost(text, iface, cost);
	let gotOk = (r.ok == wantOk);
	let okText = (wantText == null) || (r.ok && r.text == wantText);

	report(name, gotOk && okText, `got ${r.ok} text?${r.text != null}`);
}

//// config editing ////

/* insertion (no previous cost statement) */
editMatch('no-cost.re25', 'no-cost.conf', 'awg1', 25);
editMatch('multi-ospf.re25', 'multi-ospf.conf', 'awg1', 25);
editMatch('braces-next-line.re25', 'braces-next-line.conf', 'awg1', 25);
editMatch('ospfv2.e10', 'ospfv2.conf', 'eth0', 10);

/* replacement (existing cost statement) */
editMatch('with-cost.re25', 'with-cost.conf', 'awg1', 25);
editMatch('multi-ospf.e33', 'multi-ospf.conf', 'eth2', 33);

/* round trips on editable (already present) costs */
roundTrip('with-cost roundtrip 25<->10', 'with-cost.conf', 'awg1', 25, 10);
roundTrip('multi-ospf eth2 roundtrip 33<->66', 'multi-ospf.conf', 'eth2', 33, 66);

/* negative cases */
let base = read('fixtures/no-cost.conf');

expectEdit('unknown interface', base, 'wan1', 25, false, null);
expectEdit('empty interface', base, '', 25, false, null);
expectEdit('zero cost', base, 'awg1', 0, false, null);
expectEdit('negative cost', base, 'awg1', -5, false, null);
expectEdit('non-integer cost', base, 'awg1', 'abc', false, null);
expectEdit('cost above range', base, 'awg1', 65536, false, null);
expectEdit('cost at upper bound', base, 'awg1', 65535, true, null);
expectEdit('cost at lower bound', base, 'awg1', 1, true, null);

//// interface parsing ////

let expIface = [
	{ interface: 'dummy0', type: 'broadcast', cost: 10 },
	{ interface: 'awg1', type: 'ptp', cost: 10 },
];
let gotIface = parseOspfInterfaces(split(read('fixtures/show-ospf-iface.txt'), '\n'));

report('parser ptp/broadcast types',
       sprintf('%J', gotIface) == sprintf('%J', expIface),
       sprintf('%J', gotIface));

let expNoType = [
	{ interface: 'eth0', type: null, cost: 10 },
];
let gotNoType = parseOspfInterfaces(split(read('fixtures/show-ospf-iface-notype.txt'), '\n'));

report('parser missing Type yields null',
       gotNoType[0].interface == 'eth0' && gotNoType[0].type == null &&
	       gotNoType[0].cost == 10,
       sprintf('%J', gotNoType));

//// prefix validation ////

function pf(name, p, want)
{
	let got = parsePrefix(p);
	let ok = false;

	if (got != null)
		ok = got.fam == want.fam && got.len == want.len &&
		     sprintf('%J', got.addr) == sprintf('%J', want.addr);

	report(name, ok, sprintf('%J', got));
}

pf('prefix v4 /24', '203.0.113.0/24', { fam: 4, len: 24, addr: [203, 0, 113, 0] });
pf('prefix v4 host', '203.0.113.7', { fam: 4, len: 32, addr: [203, 0, 113, 7] });
pf('prefix v6 /128', '2001:db8:10::1/128', { fam: 6, len: 128, addr: [0x20, 0x01, 0x0d, 0xb8, 0x00, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] });
pf('prefix v6 host', '2001:db8::1', { fam: 6, len: 128, addr: [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] });
pf('prefix v6 ::', '::', { fam: 6, len: 128, addr: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] });
pf('prefix v4 upper-range octet', '192.0.2.1/24', { fam: 4, len: 24, addr: [192, 0, 2, 1] });

report('prefix empty rejected', parsePrefix('') == null, 'accepted');
report('prefix garbage rejected', parsePrefix('not-an-ip') == null, 'accepted');
report('prefix v4 octet>255 rejected', parsePrefix('300.0.113.1') == null, 'accepted');
report('prefix v4 len>32 rejected', parsePrefix('203.0.113.1/33') == null, 'accepted');
report('prefix v6 len>128 rejected', parsePrefix('2001:db8::1/129') == null, 'accepted');
report('prefix bad len rejected', parsePrefix('203.0.113.1/host') == null, 'accepted');
report('prefix extra slash rejected', parsePrefix('203.0.113.1/24/25') == null, 'accepted');
report('prefix null rejected', parsePrefix(null) == null, 'accepted');

//// route parsing ////

function routeOf(lines)
{
	return parseRoute(split(read('fixtures/' + lines), '\n'));
}

function verbLines()
{
	return split(read('fixtures/show-route-all.txt'), '\n');
}

/* single BGP next hop, with a "from <peer>" source address and AS path */
let rVia = routeOf('show-route-via.txt');
let expVia = [
	{
		prefix: '198.51.100.0/24', primary: 'via', proto: 'peer_a',
		preference: 100, cost: 10, local_pref: null, as_path: null,
		next_hops: [
			{ kind: 'via', addr: 'fe80::aaaa', iface: 'awg_hub_a', cost: 10, proto: 'peer_a' },
		],
	},
];

report('route single via',
       sprintf('%J', rVia) == sprintf('%J', expVia),
       sprintf('%J', rVia));
report('route exact (host in /24)',
       exactRoute(rVia, '198.51.100.9') == null &&
	       exactRoute(rVia, '198.51.100.0/24') != null &&
	       exactRoute(rVia, '198.51.100.0/24').prefix == '198.51.100.0/24',
       sprintf('%J', exactRoute(rVia, '198.51.100.0/24')));

/* ECMP: one route, one "via" line per preferred next hop */
let rEcmp = routeOf('show-route-ecmp.txt');
let expEcmp = [
	{
		prefix: '2001:db8:10::1/128', primary: 'via', proto: 'mesh_v3',
		preference: 150, cost: 20, local_pref: null, as_path: null,
		next_hops: [
			{ kind: 'via', addr: 'fe80::aaaa', iface: 'awg_hub_a', cost: 20, proto: 'mesh_v3' },
			{ kind: 'via', addr: 'fe80::bbbb', iface: 'awg_hub_b', cost: 20, proto: 'mesh_v3' },
			{ kind: 'via', addr: 'fe80::cccc', iface: 'awg_hub_c', cost: 20, proto: 'mesh_v3' },
			{ kind: 'via', addr: 'fe80::dddd', iface: 'awg_hub_d', cost: 20, proto: 'mesh_v3' },
		],
	},
];

report('route ECMP all via hops',
       sprintf('%J', rEcmp) == sprintf('%J', expEcmp),
       sprintf('%J', rEcmp));
report('route ECMP count', length(rEcmp[0].next_hops) == 4,
       sprintf('%J', rEcmp[0].next_hops));
/* host query matches the /128; case is normalized during comparison */
report('route exact host v6',
       exactRoute(rEcmp, '2001:DB8:10::1') != null &&
	       exactRoute(rEcmp, '2001:DB8:10::1').prefix == '2001:db8:10::1/128',
       sprintf('%J', exactRoute(rEcmp, '2001:DB8:10::1')));

/* device route (local/connected loopback) */
let rDev = routeOf('show-route-dev.txt');
let expDev = [
	{
		prefix: '203.0.114.7/32', primary: 'dev', proto: 'direct1',
		preference: 200, cost: 200, local_pref: null, as_path: null,
		next_hops: [
			{ kind: 'dev', addr: null, iface: 'lo', cost: 200, proto: 'direct1' },
		],
	},
];

report('route dev (local/connected)',
       sprintf('%J', rDev) == sprintf('%J', expDev),
       sprintf('%J', rDev));
report('route dev primary', rDev[0].primary == 'dev',
       rDev[0].primary);

/* destination routes with no next hop (unreachable/blackhole) */
let rUnreach = routeOf('show-route-unreachable.txt');
report('route unreachable parsed',
       length(rUnreach) == 1 && rUnreach[0].prefix == '203.0.113.77/32' &&
	       rUnreach[0].proto == 'static1' && rUnreach[0].cost == 10 &&
	       length(rUnreach[0].next_hops) == 0,
       sprintf('%J', rUnreach));

/* several routes for the same network: only the primary carries the prefix
 * label, the others print an empty one */
let rMulti = routeOf('show-route-multipeer.txt');
report('route multipeer count', length(rMulti) == 3, sprintf('%J', rMulti));
report('route multipeer empty labels',
       length(rMulti[0].prefix) > 0 && length(rMulti[1].prefix) == 0 &&
	       length(rMulti[2].prefix) == 0 && rMulti[0].proto == 'peer_a' &&
	       rMulti[1].proto == 'peer_b',
       sprintf('prefixes %J', [rMulti[0].prefix, rMulti[1].prefix, rMulti[2].prefix]));

/* full-table scan: table headers and blank lines are ignored */
let rFull = routeOf('show-route-full.txt');
report('route full scan count', length(rFull) == 4, sprintf('%J', rFull));

/* best-match (longest covering prefix) selection used by the fallback */
report('route best-match /24', bestCoveringRoute(rFull, '192.0.2.55') != null &&
       bestCoveringRoute(rFull, '192.0.2.55').prefix == '192.0.2.0/24',
       sprintf('%J', bestCoveringRoute(rFull, '192.0.2.55')));
report('route best-match /32 dev', bestCoveringRoute(rFull, '203.0.114.7') != null &&
       bestCoveringRoute(rFull, '203.0.114.7').prefix == '203.0.114.7/32' &&
       bestCoveringRoute(rFull, '203.0.114.7').primary == 'dev',
       sprintf('%J', bestCoveringRoute(rFull, '203.0.114.7')));
report('route best-match default', bestCoveringRoute(rFull, '198.51.100.9') != null &&
       bestCoveringRoute(rFull, '198.51.100.9').prefix == '0.0.0.0/0',
       sprintf('%J', bestCoveringRoute(rFull, '198.51.100.9')));
report('route best-match v6', bestCoveringRoute(rFull, '2001:db8::1') != null &&
       bestCoveringRoute(rFull, '2001:db8::1').prefix == '2001:db8::/48',
       sprintf('%J', bestCoveringRoute(rFull, '2001:db8::1')));
report('route best-match none', bestCoveringRoute(rFull, '2001:db9::1') == null,
       sprintf('%J', bestCoveringRoute(rFull, '2001:db9::1')));
report('route exact on full scan', exactRoute(rFull, '203.0.114.7') != null,
       sprintf('%J', exactRoute(rFull, '203.0.114.7')));

/* verbose "show route ... all" attributes: AS path, OSPF cost / BGP local
 * preference are attached to the route that owns them */
let rVerb = routeOf('show-route-all.txt');
let expVerb = [
	{
		prefix: '192.0.2.0/24', primary: 'via', proto: 'peer_a',
		preference: 100, cost: 30, local_pref: 100, as_path: [64512, 64500],
		next_hops: [
			{ kind: 'via', addr: 'fe80::aaaa', iface: 'awg_hub_a', cost: 30, proto: 'peer_a' },
		],
	},
	{
		prefix: '', primary: 'via', proto: 'peer_b',
		preference: 100, cost: 30, local_pref: 90, as_path: [64512, 64500, 64501],
		next_hops: [
			{ kind: 'via', addr: 'fe80::aaaa', iface: 'awg_hub_a', cost: 30, proto: 'peer_b' },
		],
	},
	{
		prefix: '2001:db8:10::1/128', primary: 'via', proto: 'mesh_v3',
		preference: 150, cost: 20, local_pref: null, as_path: null,
		next_hops: [
			{ kind: 'via', addr: 'fe80::aaaa', iface: 'awg_hub_a', cost: 20, proto: 'mesh_v3' },
		],
	},
];

report('route verbose attrs',
       sprintf('%J', rVerb) == sprintf('%J', expVerb),
       sprintf('%J', rVerb));
report('route verbose cost from explicit metric',
       rVerb[0].cost == 30 && rVerb[2].cost == 20,
       sprintf('%J', rVerb));
report('route as_path association',
       routeAsPath(verbLines(), '192.0.2.0/24', 'peer_a') != null &&
	       sprintf('%J', routeAsPath(verbLines(), '192.0.2.0/24', 'peer_a')) ==
		       sprintf('%J', [64512, 64500]),
       sprintf('%J', routeAsPath(verbLines(), '192.0.2.0/24', 'peer_a')));
report('route as_path non-BGP', routeAsPath(verbLines(), '2001:db8:10::1/128', 'mesh_v3') == null,
       sprintf('%J', routeAsPath(verbLines(), '2001:db8:10::1/128', 'mesh_v3')));

//// summary ////

printf('\n%d tests, %d failures\n', count, failures);

if (failures)
	exit(1);

exit(0);