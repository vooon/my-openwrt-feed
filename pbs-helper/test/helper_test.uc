'use strict';

/*
 * pbs.helper (files/helper.uc) tests. HTTP, the process runner, sleep and
 * the logger are injected mocks; run_logged() runs a real `sh -c` command.
 */

import { describe, it, assert } from 'utest';
import * as pbs from '../files/helper.uc';

/* state recorded by the current mock (reset by mock_deps) */
let calls = [], logs = [], sleeps = 0;

/**
 * Whether a value is a string starting with a prefix.
 * @param {any} s
 * @param {string} prefix
 * @returns {boolean}
 */
function starts(s, prefix) {
	return type(s) == 'string' && substr(s, 0, length(prefix)) == prefix;
}

/**
 * Mock dependencies. `responses` maps a URL prefix to a list of results
 * returned in order (the last one repeats); other URLs get HTTP 200.
 * @param {object} responses
 * @param {number} [rc=0] - backup exit code returned by run()
 * @returns {object}
 */
function mock_deps(responses, rc) {
	calls = [];
	logs = [];
	sleeps = 0;

	let log = (lvl) => (m) => push(logs, `${lvl}: ${m}`);

	return {
		http: (method, url, headers, body) => {
			push(calls, { method, url, headers, body });
			for (let prefix, list in responses) {
				if (type(list) == 'array' && starts(url, prefix))
					return length(list) > 1 ? shift(list) : list[0];
			}
			return { status: 200, body: '', error: null };
		},
		run: (cmd, logger) => {
			logger.info('pbc output');
			return { rc: rc ?? 0, report: 'line1\nline2' };
		},
		sleep: () => { sleeps++; },
		logger: { info: log('info'), note: log('note'), warn: log('warn'), err: log('err') },
	};
}

/**
 * Recorded request URLs.
 * @returns {any[]}
 */
function urls() {
	return map(calls, (c) => c?.url);
}

/**
 * Number of recorded requests whose URL starts with a prefix.
 * @param {string} prefix
 * @returns {number}
 */
function count_url(prefix) {
	let n = 0;

	for (let c in calls)
		if (starts(c?.url, prefix))
			n++;

	return n;
}

/**
 * Decoded JSON body of the n-th recorded request ({} when absent).
 * @param {number} n
 * @returns {object}
 */
function json_of(n) {
	let b = calls[n]?.body;

	if (type(b) != 'string')
		return {};

	// ucode-lsp disable-next-line UC2017   # b is the JSON text sent by gotify_send()
	return json(b) ?? {};
}

/**
 * Whether any log line contains a substring.
 * @param {string} s
 * @returns {boolean}
 */
function logged(s) {
	for (let l in logs)
		if (type(l) == 'string' && index(l, s) >= 0)
			return true;

	return false;
}

/**
 * A string of `n` copies of `ch`.
 * @param {string} ch
 * @param {number} n
 * @returns {string}
 */
function repeat(ch, n) {
	let s = '';

	for (let i = 0; i < n; i++)
		s += ch;

	return s;
}

const SRV = pbs.server_config({
	repository: 'backup@pbs@pbs.example:store',
	password: 's3cret',
	fingerprint: 'aa:bb',
	gotify_url: 'https://notify.example/',
	gotify_app_token: 'TOKEN',
}, 'pbs', 'pbs_server');

/* gotify not configured */
const SRV_HC_ONLY = pbs.server_config({ repository: 'r', password: 'p' }, 'qemu', 'pbs_server');

const HC = 'https://hc.example/ping/uuid';

describe('server_config', () => {
	it('accepts a complete section', () => {
		assert.match(null, SRV.error);
	});

	it('rejects a missing section, repository or password', () => {
		assert.match(true, pbs.server_config(null, 'pbs', 's').error != null);
		assert.match(true, pbs.server_config({ password: 'x' }, 'pbs', 's').error != null);
		assert.match(true, pbs.server_config({ repository: 'r' }, 'pbs', 's').error != null);
	});
});

describe('backup_command', () => {
	let cmd = pbs.backup_command(SRV, [ 'backup', 'root.pxar:/', "--exclude=it's here" ]);

	it('quotes for the shell', () => {
		assert.match("'abc'", pbs.shellquote('abc'));
		assert.match("'a'\\''b'", pbs.shellquote("a'b"));
		assert.match(true, index(cmd,
			"exec proxmox-backup-client 'backup' 'root.pxar:/' '--exclude=it'\\''s here' 2>&1") > 0, cmd);
	});

	it('passes the password by uci command, never inline', () => {
		assert.match(true, index(cmd, "PBS_PASSWORD_CMD='uci -q get pbs.pbs_server.password'") >= 0, cmd);
		assert.match(true, index(cmd, 's3cret') < 0, cmd);
		assert.match(0, index(cmd, 'unset PBS_PASSWORD PBS_PASSWORD_FD PBS_PASSWORD_FILE;'), cmd);
	});

	it('sets repository and fingerprint', () => {
		assert.match(true, index(cmd, "PBS_REPOSITORY='backup@pbs@pbs.example:store'") > 0, cmd);
		assert.match(true, index(cmd, "PBS_FINGERPRINT='aa:bb'") > 0, cmd);
	});
});

describe('run_logged', () => {
	it('logs each line and returns rc and report', () => {
		let lines = [];
		let res = pbs.run_logged("printf 'a\\nb\\n'; exit 3", { info: (m) => push(lines, m), err: () => null });

		assert.match(3, res.rc);
		assert.match([ 'a', 'b' ], lines);
		assert.match('a\nb', res.report);
	});

	it('keeps the head and the tail, drops the middle', () => {
		let res = pbs.run_logged("i=0; while [ $i -lt 2000 ]; do echo line-$i-xxxxxxxxxx; i=$((i+1)); done",
			{ info: () => null, err: () => null });
		let r = type(res.report) == 'string' ? res.report : '';

		assert.match(true, length(r) > 0 && length(r) <= 10000, length(r));
		assert.match('line-0-xxxxxxxxxx\n', substr(r, 0, 18));
		assert.match('line-1999-xxxxxxxxxx', substr(r, -20));
		assert.match(true, match(r, /\n\[\.\.\. [0-9]+ lines omitted \.\.\.\]\n/) != null, 'omission marker');
	});
});

describe('report_buffer', () => {
	it('short output is kept whole, without a marker', () => {
		let b = pbs.report_buffer();

		for (let l in [ 'a', 'b', 'c' ])
			b.add(l);

		assert.match('a\nb\nc', b.text());
	});

	it('counts omitted lines exactly', () => {
		let b = pbs.report_buffer();
		let line = 'x' + repeat('y', 99);	/* 100 chars + newline */

		for (let i = 0; i < 200; i++)
			b.add(sprintf('%03d%s', i, substr(line, 3)));

		/* head: 29 lines (29 * 101 <= 3000), tail: 68 lines (68 * 101 <= 6900) */
		let text = b.text();
		let out = (type(text) == 'string' ? split(text, '\n') : null) ?? [];
		assert.match(29 + 1 + 68, length(out));
		assert.match('[... 103 lines omitted ...]', out[29]);
		assert.match('000', substr(out[0] ?? '', 0, 3));
		assert.match('199', substr(out[length(out) - 1] ?? '', 0, 3));
	});

	it('clips a single huge line', () => {
		let b = pbs.report_buffer();

		b.add(repeat('z', 20000));
		let text = b.text();
		let n = type(text) == 'string' ? length(text) : -1;

		assert.match(true, n > 0 && n <= pbs.TAIL_BYTES + 64, n);
	});
});

describe('run_job reporting', () => {
	it('success: hc start, hc rc with log report, gotify markdown', () => {
		let d = mock_deps({});

		assert.match(0, pbs.run_job(d, { name: 'h rootfs', srv: SRV, args: [], hc_url: HC + '/' }));
		assert.match([ HC + '/start', HC + '/0', 'https://notify.example/message' ], urls());
		assert.match('line1\nline2', calls[1]?.body);

		let h = calls[2]?.headers;
		assert.match('TOKEN', h?.['X-Gotify-Key']);
		assert.match('application/json', h?.['Content-Type']);

		let g = json_of(2);
		assert.match('text/markdown', g?.extras?.['client::display']?.contentType);
		assert.match('h rootfs backup: successful', g?.title);
		assert.match(1, g?.priority);
		assert.match(true, logged('info: pbc output'));
	});

	it('failure: rc passes through, gotify carries the log', () => {
		let d = mock_deps({}, 5);

		assert.match(5, pbs.run_job(d, { name: 'h vm', srv: SRV, args: [], hc_url: HC }));
		assert.match(HC + '/5', calls[1]?.url);

		let g = json_of(2);
		assert.match('h vm backup: failed rc=5', g?.title);
		assert.match(9, g?.priority);
		assert.match('```\nline1\nline2\n```\n', g?.message);
	});
});

describe('run_job wrap and notes', () => {
	it('wrap runs around the backup and may add notes', () => {
		let d = mock_deps({});
		let order = [];

		let rc = pbs.run_job(d, { name: 'h vm', srv: SRV, args: [], hc_url: HC, wrap: (run) => {
			push(order, 'before');
			let r = run();
			push(order, 'after');
			r.notes = [ 'fsfreeze skipped: agent not responding' ];
			return r;
		} });

		assert.match(0, rc);
		assert.match([ 'before', 'after' ], order);
		assert.match('- fsfreeze skipped: agent not responding\n\nline1\nline2', calls[1]?.body);

		let g = json_of(2);
		assert.match('h vm backup: successful, with warnings', g?.title);
		assert.match(5, g?.priority);
		assert.match('Backup completed successfully.\n\n- fsfreeze skipped: agent not responding\n', g?.message);
	});

	it('wrap can fail a successful backup', () => {
		let d = mock_deps({});

		let rc = pbs.run_job(d, { name: 'h vm', srv: SRV, args: [], hc_url: HC, wrap: (run) => {
			let r = run();
			r.rc = 3;
			r.notes = [ 'ERROR: commit failed' ];
			return r;
		} });

		assert.match(3, rc);
		assert.match(HC + '/3', calls[1]?.url);

		let g = json_of(2);
		assert.match(9, g?.priority);
		assert.match('- ERROR: commit failed\n\n```\nline1\nline2\n```\n', g?.message);
	});
});

describe('healthchecks and gotify are independent', () => {
	it('healthchecks down: retried, gotify still sent', () => {
		let d = mock_deps({ 'https://hc.example/': [ { status: 0, error: 'connect failed' } ] });

		assert.match(1, pbs.run_job(d, { name: 'h', srv: SRV, args: [], hc_url: HC }));
		assert.match(6, count_url('https://hc.example/'), 'two pings, three tries each');
		assert.match(1, count_url('https://notify.example/'));
		assert.match(true, logged('healthchecks ping /0 to https://hc.example failed'), logs);
		assert.match(false, logged('/ping/uuid'), 'ping UUID must not be logged');
	});

	it('gotify down: healthchecks unaffected, gotify not retried', () => {
		let d = mock_deps({ 'https://notify.example/': [ { status: 401, body: '{"error":"Unauthorized"}', error: null } ] });

		assert.match(1, pbs.run_job(d, { name: 'h', srv: SRV, args: [], hc_url: HC }));
		assert.match([ HC + '/start', HC + '/0', 'https://notify.example/message' ], urls());
		assert.match(true, logged('HTTP 401 {"error":"Unauthorized"}'), logs);
	});

	it('only gotify configured', () => {
		let d = mock_deps({});

		assert.match(0, pbs.run_job(d, { name: 'h', srv: SRV, args: [], hc_url: null }));
		assert.match([ 'https://notify.example/message' ], urls());
	});

	it('only healthchecks configured', () => {
		let d = mock_deps({});

		assert.match(0, pbs.run_job(d, { name: 'h', srv: SRV_HC_ONLY, args: [], hc_url: HC }));
		assert.match([ HC + '/start', HC + '/0' ], urls());
	});

	it('neither configured: no requests', () => {
		let d = mock_deps({});

		assert.match(0, pbs.run_job(d, { name: 'h', srv: SRV_HC_ONLY, args: [], hc_url: '' }));
		assert.match([], urls());
	});

	it('healthchecks recovers on retry', () => {
		let d = mock_deps({ 'https://hc.example/': [ { status: 503, body: '', error: null }, { status: 200, body: '', error: null } ] });

		assert.match(true, pbs.hc_ping(d, HC, '/start'));
		assert.match(1, sleeps);
	});
});
