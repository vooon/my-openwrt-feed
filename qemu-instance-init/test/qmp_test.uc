'use strict';

/*
 * qemu.qmp (files/qmp.uc) tests against a real unix socket: the test plays
 * QEMU by accepting the connection and pre-writing its side of the
 * conversation before the client reads.
 */

import { describe, it, assert } from 'utest';
import * as socket from 'socket';
import * as fs from 'fs';
import * as qmp from '../files/qmp.uc';

const GREETING = '{"QMP": {"version": {"qemu": {"micro": 2, "minor": 1, "major": 10}}, "capabilities": ["oob"]}}\r\n';
const OK = '{"return": {}}\r\n';
const TMP = getenv('TMPDIR') || '/tmp';

let seq = 0;

/**
 * Connected client/server socket pair over a fresh unix socket path.
 * @param {string} [script] - data "QEMU" sends right away
 * @returns {object} { client, server, path }
 */
function pair(script) {
	let path = sprintf('%s/qmp-test-%d-%d.sock', TMP, time(), seq++);

	fs.unlink(path);

	/* AF_UNIX listen() defaults to SOCK_DGRAM; QEMU's QMP socket is a stream */
	let listener = socket.listen({ path: path }, null, { socktype: socket.SOCK_STREAM });
	let client = socket.connect({ path: path });
	let server = listener?.accept();

	listener?.close();
	fs.unlink(path);

	if (script)
		server?.send(script);

	return { client, server, path };
}

/**
 * Requests the client sent, decoded (one JSON object per line).
 * @param {any} server
 * @returns {any[]}
 */
function sent(server) {
	let data = server?.recv(65536);
	let out = [];

	if (type(data) != 'string')
		return out;

	// ucode-lsp disable-next-line nullable-argument   # data is a string (checked above)
	for (let l in split(data, '\n'))
		if (l != '')
			push(out, json(l));

	return out;
}

describe('session', () => {
	it('reads the greeting and negotiates capabilities', () => {
		let p = pair(GREETING + OK);
		let q = qmp.session(p.client, 500);

		assert.match(null, q.error);
		assert.match([ { execute: 'qmp_capabilities' } ], sent(p.server));
		q.close();
	});

	it('fails without a greeting', () => {
		let p = pair(OK);

		assert.match('no QMP greeting', qmp.session(p.client, 500).error);
	});

	it('times out when QEMU stays silent', () => {
		let p = pair();

		assert.match('timed out waiting for QEMU', qmp.session(p.client, 100).error);
	});

	it('reports a closed connection', () => {
		let p = pair();

		p.server?.close();
		assert.match('connection closed by QEMU', qmp.session(p.client, 500).error);
	});
});

describe('execute', () => {
	it('returns the result, skipping asynchronous events', () => {
		let p = pair(GREETING + OK +
			'{"timestamp": {"seconds": 1, "microseconds": 2}, "event": "POWERDOWN"}\r\n' +
			'{"return": {"status": "running", "running": true}}\r\n');
		let q = qmp.session(p.client, 500);
		let r = q.execute('query-status');

		assert.match({ ok: true, return: { status: 'running', running: true } }, r);
		assert.match([ { execute: 'qmp_capabilities' }, { execute: 'query-status' } ], sent(p.server));
		q.close();
	});

	it('passes arguments', () => {
		let p = pair(GREETING + OK + OK);
		let q = qmp.session(p.client, 500);

		assert.match(true, q.execute('block_resize', { device: 'root-img', size: 1024 }).ok);
		assert.match({ execute: 'block_resize', arguments: { device: 'root-img', size: 1024 } }, sent(p.server)[1]);
		q.close();
	});

	it('maps QMP errors to class: desc', () => {
		let p = pair(GREETING + OK +
			'{"error": {"class": "CommandNotFound", "desc": "The command block-flush has not been found"}}\r\n');
		let q = qmp.session(p.client, 500);

		assert.match({ ok: false, error: 'CommandNotFound: The command block-flush has not been found' },
			q.execute('block-flush'));
		q.close();
	});

	it('rejects malformed replies', () => {
		let p = pair(GREETING + OK + 'not json\r\n');
		let q = qmp.session(p.client, 500);

		assert.match({ ok: false, error: 'bad QMP message: not json' }, q.execute('query-status'));
		q.close();
	});
});

describe('guest agent', () => {
	it('resyncs with guest-sync-delimited, skipping stale replies', () => {
		/* a stale reply of an abandoned client, then ours behind 0xFF */
		let p = pair('{"return": 1}\n\xff{"return": 42}\n{"return": {}}\n');
		let q = qmp.agent_session(p.client, 500, 42);

		assert.match(null, q.error);
		assert.match({ ok: true, return: {} }, q.execute('guest-fsfreeze-thaw'));

		let data = p.server?.recv(65536);
		assert.match('\xff{ "execute": "guest-sync-delimited", "arguments": { "id": 42 } }\n' +
			'{ "execute": "guest-sync-delimited", "arguments": { "id": 42 } }\n' +
			'{ "execute": "guest-fsfreeze-thaw" }\n', data);
		q.close();
	});

	it('agent_open connects by path', () => {
		let path = sprintf('%s/qmp-test-agent-%d.sock', TMP, time());

		fs.unlink(path);

		let listener = socket.listen({ path: path }, null, { socktype: socket.SOCK_STREAM });
		let q = qmp.agent_open(path, 100, 7);	/* nobody answers: times out */

		listener?.close();
		fs.unlink(path);
		assert.match('guest agent not responding: timed out waiting for QEMU', q.error);
	});

	it('reports a guest without a running agent', () => {
		let p = pair();

		assert.match('guest agent not responding: timed out waiting for QEMU',
			qmp.agent_session(p.client, 100, 1).error);
	});
});

describe('open', () => {
	it('fails on a missing socket', () => {
		let path = `${TMP}/qmp-test-missing.sock`;
		let r = qmp.open(path, 100);

		assert.match(true, type(r.error) == 'string' && index(r.error, path) == 0, r.error);
	});
});
