'use strict';

/*
 * vpn-sticky nft template tests: render files/vpn-sticky.nft.uc against
 * mocked uci configs and compare with the golden rulesets in expected/.
 *
 * UPDATE_GOLDEN=1 rewrites the golden files from the current output.
 */

import { describe, it, assert, mock } from 'utest';
import * as fs from 'fs';

const PKG_DIR = getenv('VS_PKG_DIR') || '.';
const TEMPLATE = `${PKG_DIR}/files/vpn-sticky.nft.uc`;
const EXPECTED = `${PKG_DIR}/test/expected`;

/* four tunnels, as in the shipped default config */
const WG_IFACES = {
	wg0: { '.type': 'iface', name: 'wg0', mark: '0x10000000', rule_pref: '12000', route_table: '5000' },
	wg1: { '.type': 'iface', name: 'wg1', mark: '0x20000000', rule_pref: '12001', route_table: '5001' },
	wg2: { '.type': 'iface', name: 'wg2', mark: '0x30000000', rule_pref: '12002', route_table: '5002' },
	wg3: { '.type': 'iface', name: 'wg3', mark: '0x40000000', rule_pref: '12003', route_table: '5003' },
};

/**
 * Build a uci data set for the vpn-sticky package.
 * @param {object} daemon  options of the `daemon` section
 * @param {object} ifaces  `iface` sections keyed by section name
 * @returns {object}
 */
function config(daemon, ifaces) {
	return {
		'vpn-sticky': {
			daemon: { '.type': 'daemon', ...daemon },
			...ifaces,
		},
	};
}

/**
 * Render the template with `data` as the uci database.
 * @param {object} data
 * @returns {string}
 */
function render_with(data) {
	let out = '', err = null;

	/* global.patch, not inject: the template require()s uci itself */
	mock.global.patch('uci', { data, strict: true });
	try {
		out = render(TEMPLATE) || '';
	} catch (e) {
		err = e;
	}
	mock.global.unpatch('uci');

	if (err)
		die(err);

	return out;
}

/**
 * Compare `out` with expected/<name>.nft (or rewrite it with UPDATE_GOLDEN=1).
 * @param {string} name
 * @param {string} out
 */
function assert_golden(name, out) {
	let path = `${EXPECTED}/${name}.nft`;

	if (getenv('UPDATE_GOLDEN') == '1')
		fs.writefile(path, out);

	assert.match(fs.readfile(path), out, `${name}.nft differs from rendered output`);
}

/**
 * Whether `s` contains `needle`.
 * @param {?string} s
 * @param {string} needle
 * @returns {boolean}
 */
function has(s, needle) {
	return s != null && index(s, needle) >= 0;
}

/**
 * Rendered ruleset lines containing `needle`.
 * @param {string} out
 * @param {string} needle
 * @returns {string[]}
 */
function rules_with(out, needle) {
	let rules = [];

	for (let l in split(out, '\n'))
		if (has(l, needle))
			push(rules, trim(l));

	return rules;
}

const SITE_A = config({
	enabled: '1',
	mark_mask: '0x70000000',
	lan_if: [ 'br-lan' ],
	target_prefix: [ '10.0.0.0/8' ],
}, WG_IFACES);

const SITE_B = config({
	enabled: '1',
	mark_mask: '0x70000000',
	target_prefix: [ '10.0.0.0/8' ],
	lan_if: [ 'br-lan.10', 'br-lan.20', 'br-lan.30', 'br-guest', 'br-iot', 'br-dmz', 'br-lab' ],
}, WG_IFACES);

const ANY_IIF = config({ mark_mask: '0x70000000' }, WG_IFACES);

describe('rendered rulesets (golden)', () => {
	it('site A: single lan_if', () => {
		assert_golden('site-a', render_with(SITE_A));
	});

	it('site B: many lan_if as an anonymous set', () => {
		assert_golden('site-b', render_with(SITE_B));
	});

	it('no lan_if: replies from any interface', () => {
		assert_golden('any-iif', render_with(ANY_IIF));
	});
});

describe('ruleset invariants', () => {
	for (let name, data in { site_a: SITE_A, site_b: SITE_B, any_iif: ANY_IIF }) {
		it(`${name}: replaces the table atomically`, () => {
			let out = render_with(data);
			let preamble = 'table inet vpn_sticky\ndelete table inet vpn_sticky\n';

			assert.match(true, has(out, preamble), 'missing create+delete preamble');
			assert.match(true, index(out, preamble) < index(out, 'table inet vpn_sticky {'),
				'preamble must precede the table body');
		});

		it(`${name}: conntrack marks only on unmarked original-direction packets`, () => {
			let rules = rules_with(render_with(data), 'ct mark set');

			for (let l in rules) {
				assert.match(true, has(l, 'ct direction original ct mark & 0x70000000 == 0x0 '), l);
				assert.match(true, has(l, 'ct mark set ct mark & 0x8fffffff | '), `unmasked: ${l}`);
			}

			assert.match(4, length(rules));
		});

		it(`${name}: packet marks only on reply-direction packets, masked`, () => {
			let rules = rules_with(render_with(data), 'meta mark set');

			for (let l in rules) {
				assert.match(true, has(l, 'ct direction reply '), `would mark toward local hosts: ${l}`);
				assert.match(true, has(l, 'meta mark set meta mark & 0x8fffffff | '), `unmasked: ${l}`);
			}

			/* one per iface in prerouting + one per iface in output */
			assert.match(8, length(rules));
		});
	}
});

describe('config handling', () => {
	it('enabled=0 renders no table', () => {
		assert.match('# vpn-sticky disabled\n',
			render_with(config({ enabled: '0' }, WG_IFACES)));
	});

	it('enabled defaults to on', () => {
		assert.match(true, has(render_with(config({}, WG_IFACES)), 'table inet vpn_sticky {'));
	});

	it('mark_mask defaults to 0x70000000', () => {
		let out = render_with(config({}, { wg0: WG_IFACES.wg0 }));

		assert.match(true, has(out, 'ct mark & 0x70000000 == 0x0 ct mark set ct mark & 0x8fffffff | 0x10000000'));
	});

	it('lan_if as a single string, duplicates and empties dropped', () => {
		let out = render_with(config({ lan_if: [ 'br-lan', '', 'br-guest', 'br-lan' ] }, { wg0: WG_IFACES.wg0 }));

		assert.match(true, has(out, 'iifname { "br-lan", "br-guest" } ct direction reply'));

		out = render_with(config({ lan_if: 'br-iot' }, { wg0: WG_IFACES.wg0 }));
		assert.match(true, has(out, 'iifname { "br-iot" } ct direction reply'));
	});

	it('decimal marks and a custom mask are normalized and masked', () => {
		let out = render_with(config({ mark_mask: '0x0f000000' }, {
			a: { '.type': 'iface', name: 'wg0', mark: '50331648', rule_pref: '1', route_table: '1' },   /* 0x03000000 */
			b: { '.type': 'iface', name: 'wg1', mark: '0x14000000', rule_pref: '2', route_table: '2' }, /* outside bit dropped */
		}));

		assert.match(true, has(out, 'iifname "wg0" ct direction original ct mark & 0x0f000000 == 0x0 ct mark set ct mark & 0xf0ffffff | 0x03000000'));
		assert.match(true, has(out, 'ct mark set ct mark & 0xf0ffffff | 0x04000000'));
		assert.match(true, has(out, 'ct mark & 0x0f000000 == 0x04000000 meta mark set meta mark & 0xf0ffffff | 0x04000000'));
	});

	it('incomplete iface sections are skipped, name falls back to section name', () => {
		let out = render_with(config({}, {
			wg9: { '.type': 'iface', mark: '0x10000000', rule_pref: '1', route_table: '1' },
			bad: { '.type': 'iface', name: 'wgX', mark: '0x20000000', route_table: '2' },
		}));

		assert.match(true, has(out, 'iifname "wg9" '));
		assert.match(false, has(out, 'wgX'));
		assert.match(false, has(out, '0x20000000'));
	});
});
