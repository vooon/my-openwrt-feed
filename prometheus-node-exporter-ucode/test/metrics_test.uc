'use strict';

/*
 * files/metrics.uc core: renders the template in its command line mode (no
 * uhttpd global) against the collectors in fixtures/collectors/, with mocked
 * uci / ubus and the collector directory redirected to the fixtures.
 */

import { describe, it, assert, mock, contains, not, regex } from 'utest';
import { pkg_path } from 'harness';

const TEMPLATE = pkg_path('files/metrics.uc');
const LIB = '/usr/share/ucode/node-exporter/lib';
const FIXTURES = pkg_path('test/fixtures/collectors');
const COLLECTORS = [ 'broken.uc', 'conf.uc', 'labels.uc', 'off.uc', 'throws.uc', 'values.uc' ];

const UCI = {
	'prometheus-node-exporter-ucode': {
		main: { '.type': 'prometheus-node-exporter-ucode', listen_port: '9101' },
		conf: { '.type': 'collector', '.name': 'conf', '.anonymous': false, opt: 'value' },
		off: { '.type': 'collector', disabled: '1' },
		// not a collector section, must not reach the collector
		labels: { '.type': 'other', opt: 'ignored' },
	},
};

const real_loadfile = global.loadfile;

/**
 * Run `prometheus-node-exporter-ucode <args>`.
 * @param {string[]} args  collectors to query, all when empty
 * @returns {object} `{ lines, warnings }`
 */
function scrape(args) {
	let warnings = [];
	let out = '', err = null;

	mock.global.patch('uci', { data: UCI });
	mock.global.patch('ubus', { data: { 'system:info': { uptime: 1234 } } });
	mock.global.patch('fs', { behavior: { lsdir: (path) => path == LIB ? COLLECTORS : null } });
	mock.global.patch_builtin('loadfile', (path, opts) =>
		real_loadfile(index(path, LIB) == 0 ? FIXTURES + substr(path, length(LIB)) : path, opts));
	mock.global.patch_builtin('warn', (...s) => push(warnings, join('', s)));
	global.ARGV = args;

	try {
		out = render(TEMPLATE) || '';
	} catch (e) {
		err = e;
	}

	mock.global.unpatch_builtin('warn');
	mock.global.unpatch_builtin('loadfile');
	mock.global.unpatch('fs');
	mock.global.unpatch('ubus');
	mock.global.unpatch('uci');
	delete global.handle_request;
	delete global.debug;

	if (err)
		die(err);

	return { lines: split(rtrim(out, '\n'), '\n'), warnings };
}

describe('metrics.uc', () => {
	it('renders label values, keeping zero and false', () => {
		let r = scrape([ 'labels' ]);

		assert.match(contains([
			'# HELP test_labels Label rendering',
			'# TYPE test_labels gauge',
			'test_labels{zero="0",num="5",yes="1",no="0",empty="",text="a\\"b\\\\c\\nd"} 1',
		]), r.lines);
	});

	it('renders values and declares each metric once', () => {
		let r = scrape([ 'values' ]);

		assert.match(contains([
			'# HELP test_values Value rendering',
			'# TYPE test_values gauge',
			'test_values{v="int"} 0',
			'test_values{v="double"} 1.5',
			'test_values{v="bool"} 1',
			'test_values{v="string"} 42',
			'test_values{v="inf"} +Inf',
			'test_values{v="nan"} NaN',
			'# TYPE test_total counter',
			'test_total 7',
		]), r.lines);
		assert.match(1, length(filter(r.lines, (l) => l == '# TYPE test_values gauge')));
		assert.match(not(contains([ regex(/v="(null|array)"/) ])), r.lines);
	});

	it('passes the uci options, ubus and raw() to a collector', () => {
		let r = scrape([ 'conf' ]);

		assert.match(contains([
			'test_config{opt="value",keys="opt"} 1',
			'test_raw 7',
			'test_ubus 1234',
			'node_scrape_collector_success{collector="conf"} 1',
		]), r.lines);
		// raw('') and raw(null) print nothing: the only blank line ends the header
		assert.match(1, length(filter(r.lines, (l) => l == '')));
	});

	it('ignores a config section that is not a collector', () => {
		let r = scrape([ 'conf', 'labels' ]);

		assert.match(not(contains([ regex(/ignored/) ])), r.lines);
	});

	it('reports failing and throwing collectors as unsuccessful', () => {
		let r = scrape([ 'broken', 'throws', 'labels' ]);

		assert.match(contains([ 'node_scrape_collector_success{collector="broken"} 0' ]), r.lines);
		assert.match(contains([ 'node_scrape_collector_success{collector="throws"} 0' ]), r.lines);
		assert.match(contains([ 'node_scrape_collector_success{collector="labels"} 1' ]), r.lines);
		assert.match(contains([ regex(/error running collector 'throws'/) ]), r.warnings);
	});

	it('runs every enabled collector by default', () => {
		let r = scrape([]);

		for (let name in [ 'broken', 'conf', 'labels', 'throws', 'values' ])
			assert.match(contains([ regex(regexp(`^node_scrape_collector_duration_seconds\\{collector="${name}"\\} `)) ]),
				r.lines, name);
	});

	it('skips a collector disabled in the config', () => {
		let r = scrape([]);

		assert.match(not(contains([ regex(/test_off|collector="off"/) ])), r.lines);
		assert.match(contains([ "collector 'off' is disabled\n" ]), r.warnings);
		assert.match(contains([ regex(/serving requests with 5 collectors/) ]), r.warnings);
	});

	it('answers 404 for an unknown or disabled collector', () => {
		assert.match(contains([ 'Status: 404 Collector nope not found' ]), scrape([ 'nope' ]).lines);
		assert.match(contains([ 'Status: 404 Collector off not found' ]), scrape([ 'off' ]).lines);
	});
});
