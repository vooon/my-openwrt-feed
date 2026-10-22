'use strict';

/* qemu.qmp - minimal QEMU Machine Protocol and guest agent client
 * (installed as /usr/share/ucode/qemu/qmp.uc).
 *
 *   let s = qmp.open('/var/run/qemu.vm.qmp.sock', 5000);
 *   if (s.error) ...;
 *   let r = s.execute('query-status');   // { ok, return } / { ok: false, error }
 *   s.close();
 *
 * open() reads the server greeting and negotiates capabilities. Asynchronous
 * events received while waiting for a reply are skipped.
 *
 * agent_open() talks to qemu-guest-agent's virtio-serial socket instead: no
 * greeting, resynchronised with guest-sync-delimited (0xFF-delimited).
 */

import * as socket from 'socket';

/**
 * Wrap a connected QMP stream socket (greeting not yet read).
 *
 * @param {object} conn - connected socket
 * @param {number} timeout_ms - per-read timeout
 * @returns {object} { next(), execute(cmd, args), set_timeout(ms), close() }
 */
export function client(conn, timeout_ms) {
	let buf = '';

	/* next message: { msg } or { error } on timeout / EOF / bad JSON */
	let next = () => {
		for (;;) {
			let nl = index(buf, '\n');

			if (nl >= 0) {
				let line = trim(substr(buf, 0, nl));
				buf = substr(buf, nl + 1);

				if (line == '')
					continue;

				let msg = null;
				try {
					msg = json(line);
				}
				catch (e) {
					return { error: `bad QMP message: ${line}` };
				}

				return { msg };
			}

			/* poll() returns [ [ sock, revents ] ], revents 0 on timeout */
			let ready = socket.poll(timeout_ms, conn);
			if (!ready?.[0]?.[1])
				return { error: 'timed out waiting for QEMU' };

			let data = conn.recv(4096);
			if (!data)
				return { error: 'connection closed by QEMU' };

			/* guest-sync-delimited prefixes its reply with 0xFF */
			buf += replace(data, '\xff', '');
		}
	};

	return {
		next: next,

		execute: (cmd, args) => {
			let req = { execute: cmd };
			if (args != null)
				req.arguments = args;

			if (conn.send(sprintf('%J\n', req)) == null)
				return { ok: false, error: `send failed: ${socket.error()}` };

			for (;;) {
				let r = next();
				if (r?.error)
					return { ok: false, error: r?.error };

				let msg = r?.msg;
				if (type(msg) != 'object')
					continue;

				if ('return' in msg)
					return { ok: true, return: msg.return };

				if ('error' in msg)
					return { ok: false, error: sprintf('%s: %s', msg.error?.class, msg.error?.desc) };

				/* {"event": ...}: not ours */
			}
		},

		set_timeout: (ms) => {
			timeout_ms = ms;
		},

		close: () => {
			conn.close();
		},
	};
};

/**
 * Read the greeting and leave capabilities negotiation mode.
 *
 * @param {object} conn - connected socket
 * @param {number} timeout_ms
 * @returns {object} the client, or { error }
 */
export function session(conn, timeout_ms) {
	let q = client(conn, timeout_ms);
	let g = q.next();

	if (g.error || type(g.msg?.QMP) != 'object') {
		q.close();
		return { error: g.error ?? 'no QMP greeting' };
	}

	let r = q.execute('qmp_capabilities');
	if (!r.ok) {
		q.close();
		return { error: `qmp_capabilities: ${r.error}` };
	}

	return q;
};

/**
 * Connect to a QMP unix socket and negotiate capabilities.
 *
 * @param {string} path - QMP socket path
 * @param {number} [timeout_ms=5000]
 * @returns {object} the client, or { error }
 */
export function open(path, timeout_ms) {
	timeout_ms ??= 5000;

	let conn = socket.connect({ path: path }, null, null, timeout_ms);
	/* socket.error() reads like a DNS failure here, so don't show it */
	if (!conn)
		return { error: `${path}: cannot connect (is the instance running?)` };

	return session(conn, timeout_ms);
};

/**
 * Resynchronise a connected guest agent stream.
 *
 * @param {object} conn - connected socket
 * @param {number} timeout_ms
 * @param {number} [sync_id] - guest-sync id (default: from the clock)
 * @returns {object} the client, or { error }
 */
export function agent_session(conn, timeout_ms, sync_id) {
	let q = client(conn, timeout_ms);
	let c = clock();
	let id = sync_id ?? ((c?.[0] ?? 0) % 1000000) * 1000000 + int((c?.[1] ?? 0) / 1000);

	/* 0xFF makes the agent drop any partial input left by a previous client.
	 * Current agents also answer the stray byte with a "JSON parse error"
	 * reply, which is skipped below like any reply that is not our sync. */
	let req = { execute: 'guest-sync-delimited', arguments: { id: id } };
	if (conn.send(sprintf('\xff%J\n', req)) == null) {
		q.close();
		return { error: `send failed: ${socket.error()}` };
	}

	/* replies to earlier, abandoned requests may still be queued: skip them
	 * (sending the sync once keeps the stream in step afterwards) */
	for (let tries = 0; tries < 8; tries++) {
		let r = q.next();

		if (r.error) {
			q.close();
			return { error: `guest agent not responding: ${r.error}` };
		}

		if (r.msg?.return == id)
			return q;
	}

	q.close();
	return { error: 'guest agent out of sync' };
};

/**
 * Connect to a qemu-guest-agent socket and resynchronise the stream.
 * Fails (timeout) when no agent is running in the guest.
 *
 * @param {string} path - guest agent socket path
 * @param {number} [timeout_ms=5000]
 * @param {number} [sync_id] - guest-sync id (default: from the clock)
 * @returns {object} the client, or { error }
 */
export function agent_open(path, timeout_ms, sync_id) {
	timeout_ms ??= 5000;

	let conn = socket.connect({ path: path }, null, null, timeout_ms);
	if (!conn)
		return { error: `${path}: cannot connect (is the instance running?)` };

	return agent_session(conn, timeout_ms, sync_id);
};
