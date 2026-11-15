'use strict';

/*
 * nat_traffic collector against the conntrack table in fixtures/nf_conntrack.
 */

import { describe, it, assert, mock } from 'utest';
import * as fs from 'fs';
import { run_collector, pkg_path, value } from 'harness';

const COLLECTOR = 'files/extra/nat_traffic.uc';
const CONNTRACK = fs.readfile(pkg_path('test/fixtures/nf_conntrack'));

function collect(data) {
	return mock.inject('fs', { data, strict: true },
		(m_fs) => run_collector(COLLECTOR, { fs: m_fs }));
}

describe('nat_traffic collector', () => {
	it('sums the bytes of both directions per src/dst pair', () => {
		let r = collect({ '/proc/net/nf_conntrack': CONNTRACK });

		assert.match(true, r.ok);
		// line 1 (1234+5678) and line 2 (100+200) share src and dst
		assert.match(7212, value(r, 'node_nat_traffic', { src: '192.168.1.2', dst: '1.2.3.4' }));
		assert.match(700, value(r, 'node_nat_traffic', { src: '192.168.1.3', dst: '1.2.3.4' }));
		assert.match(180, value(r, 'node_nat_traffic', { src: '192.168.1.2', dst: '8.8.8.8' }));
		assert.match(3, length(r.metrics));
	});

	it('fails without a conntrack table', () => {
		let r = collect({ '/proc/net/nf_conntrack': null });

		assert.match(false, r.ok);
	});
});
