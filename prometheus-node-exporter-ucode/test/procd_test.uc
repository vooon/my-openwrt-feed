'use strict';

/*
 * procd collector: running, stopped, jailed and instance-less services
 * against a mocked `ubus call service list`.
 */

import { describe, it, assert, mock, spy } from 'utest';
import { run_collector, find, value } from 'harness';

const COLLECTOR = 'files/extra/procd.uc';
const LABELS = [ 'service', 'service_instance' ];

const SERVICES = {
	// running, new procd (incarnation), jailed
	dnsmasq: {
		instances: {
			cfg01411c: {
				running: true,
				pid: 2345,
				incarnation: 17,
				term_timeout: 5,
				jail: { name: 'dnsmasq', procfs: false, sysfs: false },
			},
		},
	},
	// stopped: no pid, has exit_code; old procd: no incarnation
	crashy: {
		instances: {
			instance1: { running: false, term_timeout: 5, exit_code: 1 },
		},
	},
	// two instances, one with a clean exit
	multi: {
		instances: {
			a: { running: true, pid: 100 },
			b: { running: false, exit_code: 0 },
		},
	},
	// service without instances
	firewall: {},
};

function collect(data) {
	return mock.inject('ubus', { data, strict: true }, (m_ubus) => {
		let conn = m_ubus.connect();
		let result = run_collector(COLLECTOR, { ubus: conn });

		result.calls = spy(conn).calls.call;
		return result;
	});
}

describe('procd collector', () => {
	it('asks procd for the verbose service list', () => {
		let r = collect({ 'service:list': SERVICES });

		assert.match(true, r.ok);
		assert.match([ [ 'service', 'list', { verbose: true } ] ], r.calls);
	});

	it('reports a running, jailed instance', () => {
		let r = collect({ 'service:list': SERVICES });
		let l = { service: 'dnsmasq', service_instance: 'cfg01411c' };

		assert.match(1, value(r, 'procd_service_running', l));
		assert.match(2345, value(r, 'procd_service_pid', l));
		assert.match(1, value(r, 'procd_service_jail', l));
		assert.match(17, value(r, 'procd_service_incarnation', l));
		assert.match(null, find(r, 'procd_service_exit_code', l));
	});

	it('emits no pid and no incarnation for a stopped instance of old procd', () => {
		let r = collect({ 'service:list': SERVICES });
		let l = { service: 'crashy', service_instance: 'instance1' };

		assert.match(0, value(r, 'procd_service_running', l));
		assert.match(1, value(r, 'procd_service_exit_code', l));
		assert.match(0, value(r, 'procd_service_jail', l));
		assert.match(null, find(r, 'procd_service_pid', l));
		assert.match(null, find(r, 'procd_service_incarnation', l));
	});

	it('reports each instance, including exit code 0', () => {
		let r = collect({ 'service:list': SERVICES });

		assert.match(100, value(r, 'procd_service_pid', { service: 'multi', service_instance: 'a' }));
		assert.match(0, value(r, 'procd_service_exit_code', { service: 'multi', service_instance: 'b' }));
	});

	it('labels every sample with service and service_instance only', () => {
		let r = collect({ 'service:list': SERVICES });

		assert.match(13, length(r.metrics));
		for (let m in r.metrics) {
			assert.match(LABELS, sort(keys(m.labels)), m.name);
			assert.match(true, m.value != null, m.name);
			assert.match(true, m.labels.service != 'firewall', 'instance-less service');
		}
	});

	it('fails when procd does not answer', () => {
		let r = collect({ 'service:list': null });

		assert.match(false, r.ok);
		assert.match([], r.metrics);
	});
});
