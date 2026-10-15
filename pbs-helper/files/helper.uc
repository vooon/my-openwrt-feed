'use strict';

/* pbs.helper - shared Proxmox Backup Server job runner for pbs-helper and
 * qemu-instance-init (installed as /usr/share/ucode/pbs/helper.uc).
 *
 * A job runs proxmox-backup-client, streams every output line to a logger
 * (ulog: syslog under cron, stderr on a terminal) and reports the result to
 * two independent, optional sinks:
 *   - Healthchecks: <hc_url>/start before, <hc_url>/<rc> after, with the log
 *     log report as the ping body;
 *   - Gotify: a Markdown message (JSON body with extras.client::display).
 * Either sink may be unset, and a failure of one never affects the other.
 *
 * Side effects go through injected dependencies (`deps.http`, `deps.run`,
 * `deps.logger`, `deps.sleep`) so the module is testable with the upstream
 * ucode build. The real HTTP transport (`http_request`) loads uloop/uclient
 * lazily, only when it is actually called.
 */

import { popen, readfile } from 'fs';

/* Backup output kept for the Healthchecks body / Gotify message: the head
 * (what is being backed up) and the tail (final status), dropping the
 * per-chunk upload lines in between. Together with the omission marker this
 * stays within Healthchecks' default 10 kB ping body limit. */
export const HEAD_BYTES = 3000;
export const TAIL_BYTES = 6900;

export const CA_FILES = [ '/etc/ssl/certs/ca-certificates.crt' ];

/* enum uclient_error_code (uclient.h) */
const UCLIENT_ERRORS = [
	'unknown error', 'connect failed', 'timed out',
	'invalid TLS certificate', 'TLS certificate name mismatch', 'missing TLS context',
];

/**
 * Quote a string for a POSIX shell command line.
 *
 * @param {string} s - the raw argument
 * @returns {string}
 */
export function shellquote(s) {
	return "'" + replace(s, "'", "'\\''") + "'";
};

/**
 * Read a proxmox_backup_server section into a server description. The
 * password itself is not read: proxmox-backup-client fetches it with
 * PBS_PASSWORD_CMD, so it never appears on a command line or in a file.
 *
 * @param {object} s - the section as returned by cursor.get_all()
 * @param {string} config - uci config name (e.g. 'pbs')
 * @param {string} section - section name
 * @returns {object} server (`error` set when unusable)
 */
export function server_config(s, config, section) {
	if (type(s) != 'object')
		return { error: `missing section '${section}' in /etc/config/${config}` };

	let srv = {
		config: config,
		section: section,
		repository: s.repository ?? '',
		fingerprint: s.fingerprint ?? '',
		namespace: s.namespace ?? '',
		gotify_url: s.gotify_url ?? '',
		gotify_app_token: s.gotify_app_token ?? '',
	};

	if (srv.repository == '')
		srv.error = `${config}.${section}: repository is not configured`;
	else if ((s.password ?? '') == '')
		srv.error = `${config}.${section}: password is not configured`;

	return srv;
};

/**
 * Build the proxmox-backup-client shell command for a server and argv.
 *
 * @param {object} srv - server from server_config()
 * @param {string[]} args - proxmox-backup-client arguments
 * @returns {string}
 */
export function backup_command(srv, args) {
	/* an inherited PBS_PASSWORD* would take precedence over _CMD */
	let cmd = 'unset PBS_PASSWORD PBS_PASSWORD_FD PBS_PASSWORD_FILE; ';

	cmd += 'PBS_REPOSITORY=' + shellquote(srv.repository) + ' ';
	cmd += 'PBS_PASSWORD_CMD=' + shellquote(`uci -q get ${srv.config}.${srv.section}.password`) + ' ';
	if (srv.fingerprint != '')
		cmd += 'PBS_FINGERPRINT=' + shellquote(srv.fingerprint) + ' ';

	cmd += 'exec proxmox-backup-client';
	for (let a in args)
		cmd += ' ' + shellquote(a);

	return cmd + ' 2>&1';
};

/**
 * Line collector keeping the first HEAD_BYTES and the last TAIL_BYTES of
 * output (lines longer than that are clipped).
 *
 * @returns {object} { add(line), text() }
 */
export function report_buffer() {
	let head = [], head_size = 0, head_open = true;
	let tail = [], sizes = [], tail_size = 0, omitted = 0;

	return {
		add: (line) => {
			if (type(line) != 'string')
				return;

			let n = length(line) + 1;

			if (head_open && head_size + n <= HEAD_BYTES) {
				push(head, line);
				head_size += n;
				return;
			}
			head_open = false;

			if (n > TAIL_BYTES) {
				line = substr(line, 0, TAIL_BYTES - 1);
				n = TAIL_BYTES;
			}

			push(tail, line);
			push(sizes, n);
			tail_size += n;

			while (tail_size > TAIL_BYTES) {
				shift(tail);
				tail_size -= shift(sizes) ?? 0;
				omitted++;
			}
		},
		text: () => {
			let out = [ ...head ];

			if (omitted > 0)
				push(out, `[... ${omitted} lines omitted ...]`);

			push(out, ...tail);

			return join('\n', out);
		},
	};
};

/**
 * Run a shell command, logging each output line and keeping a head+tail
 * report of the output (see report_buffer()).
 *
 * @param {string} cmd - shell command (stderr already redirected)
 * @param {object} logger - { info, warn, err }
 * @returns {object} { rc, report }
 */
export function run_logged(cmd, logger) {
	let p = popen(cmd, 'r');

	if (!p) {
		logger.err(`cannot run proxmox-backup-client`);
		return { rc: 127, report: '' };
	}

	let buf = report_buffer();

	for (;;) {
		let line = p.read('line');
		if (line == null || line == '')
			break;

		line = rtrim(line, '\n');
		logger.info(line);
		buf.add(line);
	}

	return { rc: p.close() ?? 127, report: buf.text() };
};

/**
 * Strip the path from a URL, for logging (ping URLs carry a secret UUID).
 *
 * @param {string} url
 * @returns {string}
 */
function url_origin(url) {
	let m = match(url, /^([a-z]+:\/\/[^\/]+)/);

	return m ? m[1] : '?';
}

/**
 * Real HTTP transport: one request through uclient on a private uloop run.
 * HTTPS certificates are verified against CA_FILES.
 *
 * @param {string} method - 'GET' / 'POST'
 * @param {string} url
 * @param {object} headers
 * @param {string} body
 * @param {number} [timeout_ms=10000]
 * @returns {object} { status, body, error }
 */
export function http_request(method, url, headers, body, timeout_ms) {
	let uloop = require('uloop');
	let uclient = require('uclient');
	let res = { status: 0, body: '', error: null };
	let cl;

	uloop.init();

	cl = uclient.new(url, null, {
		header_done: () => {
			res.status = cl?.status()?.status ?? 0;
		},
		data_read: () => {
			for (;;) {
				let d = cl?.read();
				if (!d)
					break;
				res.body += d;
			}
		},
		data_eof: () => {
			uloop.end();
		},
		error: (_cb, code) => {
			res.error = UCLIENT_ERRORS[code] ?? `uclient error ${code}`;
			uloop.end();
		},
	});

	if (!cl)
		return { status: 0, body: '', error: 'invalid URL' };

	if (substr(url, 0, 8) == 'https://' &&
	    !cl.ssl_init({ ca_files: CA_FILES, verify: true })) {
		cl.free();
		return { status: 0, body: '', error: 'TLS init failed (libustream-* SSL library missing?)' };
	}

	/* bounds the (blocking) connect too; uclient's default is 30 s */
	cl.set_timeout(timeout_ms ?? 10000);

	if (!cl.connect()) {
		cl.free();
		return { status: 0, body: '', error: 'connect failed' };
	}

	if (!cl.request(method, { headers: headers, post_data: body ?? '' })) {
		cl.free();
		return { status: 0, body: '', error: 'request failed' };
	}

	let timer = uloop.timer(timeout_ms ?? 10000, () => {
		res.error = 'timeout';
		uloop.end();
	});

	uloop.run();
	timer?.cancel();
	cl.free();

	return res;
};

/**
 * Whether a transport result is a successful (2xx) response.
 *
 * @param {object} r - result of deps.http()
 * @returns {boolean}
 */
function http_ok(r) {
	return r != null && r.error == null && r.status >= 200 && r.status < 300;
}

/**
 * Send a Healthchecks ping, retrying up to 3 times. No-op without URL.
 *
 * @param {object} deps - { http, logger, sleep }
 * @param {string} url - check ping URL (https://host/ping/<uuid>)
 * @param {string} path - '/start' or '/<rc>'
 * @param {string} [body] - ping body (log report)
 * @returns {boolean} true when sent or not configured
 */
export function hc_ping(deps, url, path, body) {
	if (!url)
		return true;

	let full = rtrim(url, '/') + path, r;

	for (let i = 0; i < 3; i++) {
		if (i > 0)
			deps.sleep(1000);

		r = deps.http('POST', full, {}, body ?? '');
		if (http_ok(r))
			return true;
	}

	deps.logger.err(`healthchecks ping ${path} to ${url_origin(url)} failed: ` +
		(r?.error ?? `HTTP ${r?.status}`));

	return false;
};

/**
 * Send a Gotify message rendered as Markdown. No-op without gotify_url.
 *
 * @param {object} deps - { http, logger }
 * @param {object} srv - server from server_config()
 * @param {string} title
 * @param {string} message - Markdown text
 * @param {number} priority
 * @returns {boolean} true when sent or not configured
 */
export function gotify_send(deps, srv, title, message, priority) {
	let base = srv.gotify_url;
	if (type(base) != 'string' || base == '')
		return true;

	/* JSON, not a form: Gotify reads `extras` only from a JSON body */
	let payload = sprintf('%J', {
		title: title,
		message: message,
		priority: priority,
		extras: { 'client::display': { contentType: 'text/markdown' } },
	});

	let r = deps.http('POST', rtrim(base, '/') + '/message', {
		'X-Gotify-Key': srv.gotify_app_token,
		'Content-Type': 'application/json',
	}, payload);

	if (http_ok(r))
		return true;

	deps.logger.err(`gotify notification to ${url_origin(base)} failed: ` +
		(r?.error ?? sprintf('HTTP %s %s', r?.status, r?.body)));

	return false;
};

/**
 * Run one backup job and report it to Healthchecks and Gotify.
 *
 * job: { name, srv, args, hc_url, wrap }
 *   name   - message title prefix, e.g. "host rootfs"
 *   srv    - server from server_config()
 *   args   - proxmox-backup-client arguments
 *   hc_url - Healthchecks ping URL (optional)
 *
 *   wrap   - optional fn(run): calls run([args]) (which runs
 *            proxmox-backup-client, with `args` instead of job.args when
 *            given, and returns { rc, report }) and returns that result, possibly
 *            with another rc and `notes` (strings shown before the report;
 *            a successful run with notes is reported at priority 5)
 *
 * Exit code: the backup's rc; 0 → 1 when a configured notification failed.
 *
 * @param {object} deps - { http, run, logger, sleep }
 * @param {object} job
 * @returns {number}
 */
export function run_job(deps, job) {
	hc_ping(deps, job.hc_url, '/start');

	deps.logger.note(`${job.name}: backup started`);

	let run = (args) => deps.run(backup_command(job.srv, args ?? job.args), deps.logger);
	let res = job.wrap ? job.wrap(run) : run();
	let rc = res.rc;
	let notes = '';
	let stat = 'successful', prio = 1, msg = 'Backup completed successfully.';

	for (let n in res.notes ?? [])
		notes += `- ${n}\n`;

	if (rc == 0) {
		deps.logger.note(`${job.name}: backup successful`);
		if (notes != '') {
			stat = 'successful, with warnings';
			prio = 5;
			msg += '\n\n' + notes;
		}
	}
	else {
		deps.logger.err(`${job.name}: backup failed rc=${rc}`);
		stat = `failed rc=${rc}`;
		prio = 9;
		msg = (notes != '' ? notes + '\n' : '') + '```\n' + res.report + '\n```\n';
	}

	let report = (notes != '' ? notes + '\n' : '') + res.report;

	/* independent sinks: always try both */
	let hc_ok = hc_ping(deps, job.hc_url, `/${rc}`, report);
	let gotify_ok = gotify_send(deps, job.srv, `${job.name} backup: ${stat}`, msg, prio);

	if (rc != 0)
		return rc;

	return (hc_ok && gotify_ok) ? 0 : 1;
};

/**
 * Real dependencies: ulog logger, uclient HTTP, popen runner.
 *
 * @param {object} log - the `log` module
 * @param {string} ident - syslog ident
 * @returns {object}
 */
export function default_deps(log, ident) {
	/* default channel: stdio on a terminal, syslog otherwise (cron) */
	log.ulog_open(null, 'daemon', ident);

	return {
		http: http_request,
		run: run_logged,
		sleep: sleep,
		logger: {
			info: (m) => log.INFO('%s', m),
			note: (m) => log.NOTE('%s', m),
			warn: (m) => log.WARN('%s', m),
			err: (m) => log.ERR('%s', m),
		},
	};
};

/**
 * The machine hostname ($HOSTNAME overrides, as pbs.sh did).
 *
 * @returns {string}
 */
export function hostname() {
	return getenv('HOSTNAME') || trim(readfile('/proc/sys/kernel/hostname') ?? 'unknown');
};
