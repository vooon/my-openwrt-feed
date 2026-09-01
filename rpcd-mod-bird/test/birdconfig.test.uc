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

import { parseOspfInterfaces, editOspfCost } from '../src/birdconfig.uc';

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

//// summary ////

printf('\n%d tests, %d failures\n', count, failures);

if (failures)
	exit(1);

exit(0);