'use strict';

// Shared helpers of the node-exporter utest suites: run a collector the way
// files/metrics.uc does (loadfile() in raw mode with an injected scope) and
// record what it emits.

const PKG_DIR = getenv('NE_PKG_DIR') || '.';

/**
 * Absolute path of a file in the package.
 * @param {string} rel  path relative to the package directory
 * @returns {string}
 */
export function pkg_path(rel) {
	return `${PKG_DIR}/${rel}`;
};

function recorder(out, mtype) {
	return function(name, help) {
		let func;

		func = function(labels, value) {
			push(out, { name, type: mtype, labels: labels || {}, value });
			return func;
		};

		return func;
	};
}

/**
 * Run a collector and record its output.
 * @param {string} path   collector, relative to the package directory
 * @param {object} scope  scope members (config, ubus, fs, ...) added to, or
 *                        replacing, the recording gauge/counter/raw defaults
 * @returns {object} `{ ok, metrics: [ { name, type, labels, value } ], raw }`
 */
export function run_collector(path, scope) {
	let metrics = [], text = [];
	let func = loadfile(pkg_path(path), { strict_declarations: true, raw_mode: true });

	let rv = call(func, null, {
		config: {},
		gauge: recorder(metrics, 'gauge'),
		counter: recorder(metrics, 'counter'),
		raw: (s) => push(text, s),
		wsplit: (line) => split(line, /\s+/),
		nextline: (f) => rtrim(f.read('line'), '\n'),
		...(scope || {}),
	});

	return { ok: rv != false, metrics, raw: join('\n', text) };
};

/**
 * First recorded sample of `name` whose labels include all of `labels`.
 * @param {object} result  run_collector() result
 * @param {string} name
 * @param {object} [labels]
 * @returns {object} the sample, or null
 */
export function find(result, name, labels) {
	for (let m in result.metrics) {
		if (m.name != name)
			continue;

		let ok = true;
		for (let k, v in labels)
			if (m.labels[k] != v)
				ok = false;

		if (ok)
			return m;
	}

	return null;
};

/**
 * Value of the sample find() returns, null when there is none.
 * @param {object} result
 * @param {string} name
 * @param {object} [labels]
 */
export function value(result, name, labels) {
	return find(result, name, labels)?.value;
};

/**
 * Serve `responses` to files/http_client.uc for the duration of `cb`.
 *
 * utest's built-in uclient proxy has no free(), which fetch_json() calls, so
 * the connection is a small fake installed through the proxy's `new` behavior.
 *
 * @param {object} mock       utest's mock object
 * @param {object} responses  full URL -> reply (JSON encoded, status 200),
 *                            or `{ status }` / `{ error }`; a missing URL
 *                            fails like a refused connection
 * @param {function} cb       called with the array of `{ url, method, headers }`
 *                            requests, filled as they are made
 */
export function with_http(mock, responses, cb) {
	let requests = [];
	let rv, err = null;

	mock.global.patch('uloop', {});
	mock.global.patch('uclient', {
		behavior: {
			new: function(url, auth, cbs) {
				let reply = responses[url];
				let body = null;
				let uc;

				uc = {
					set_timeout: () => true,
					ssl_init: () => true,
					connect: () => true,
					request: function(method, opts) {
						push(requests, { url, method, headers: opts?.headers });

						if (reply == null || reply.error) {
							cbs.error(uc, reply?.error || 'CONNECT_FAILED');
							return true;
						}

						if (reply.status == null)
							body = sprintf('%J', reply);

						if (body != null)
							cbs.data_read(uc);
						cbs.data_eof(uc);
						return true;
					},
					read: function() {
						let chunk = body;
						body = null;
						return chunk;
					},
					status: () => ({ status: reply?.status || 200 }),
					free: () => null,
				};

				return uc;
			},
		},
	});

	try {
		rv = cb(requests);
	} catch (e) {
		err = e;
	}

	mock.global.unpatch('uclient');
	mock.global.unpatch('uloop');

	if (err)
		die(err);

	return rv;
};
