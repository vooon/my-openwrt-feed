'use strict';

/* Unit tests for utpl-wrapper.uc (the uwsd .ut template handler).  Run via
 * run_tests.sh, which creates a scratch DOCUMENT_ROOT and exports it (ucode
 * has no setenv(), so the runner must provide it).
 *
 * The wrapper is driven through a fake uwsd connection object that records the
 * reply(), so a test can assert what the rendered template observed in the
 * injected `request` global.
 *
 * The regression under test: browser requests arriving through HAProxy/Angie
 * (and every HTTP/2 hop) deliver header names in lower-case, so the wrapper
 * must key request.headers by the lower-cased name and look Content-Type /
 * Cookie up in that normalized form.  Previously it stored the wire casing but
 * read req.headers["Content-Type"], so a browser form POST left request.form
 * null while a direct curl (canonical casing) worked.
 */

import * as fs from 'fs';

import { onRequest, onBody } from '../files/utpl-wrapper.uc';

let failures = 0;
let count = 0;

/** Record a test result.
 *
 * @param {string} name - the test name
 * @param {boolean} ok - whether the assertion held
 * @param {?string} msg - failure detail
 */
function report(name, ok, msg) {
	count++;

	if (ok)
		printf('PASS  %s\n', name);
	else {
		failures++;
		printf('FAIL  %s: %s\n', name, msg ?? '');
	}
}

/** Assert that two values are equal after JSON serialization.
 *
 * Both sides are rendered with %J, so nested objects/arrays compare
 * structurally and an unset property compares equal to an explicit null.
 *
 * @param {string} name - the test name
 * @param {Object|Array|string|number|boolean} got - the observed value
 * @param {Object|Array|string|number|boolean} want - the expected value
 */
function eq(name, got, want) {
	let a = sprintf('%J', got);
	let b = sprintf('%J', want);

	report(name, a == b, sprintf('got %s, want %s', a, b));
}

/* --- fixture template ---------------------------------------------------- */

/* DOCUMENT_ROOT for the run, created by run_tests.sh.  The probe template
 * dumps what the wrapper injected so the test can assert on it. */
let root = getenv('DOCUMENT_ROOT');

if (root == null)
	die('DOCUMENT_ROOT is not set (run this via run_tests.sh)');

let probe = root + '/probe.ut';

fs.writefile(probe, '{%\n' +
	'print(sprintf("%J", {\n' +
	'	body: request.body,\n' +
	'	form: request.form,\n' +
	'	json: request.json,\n' +
	'	headers: request.headers,\n' +
	'	cookie: request.headers["cookie"],\n' +
	'	protocol: request.protocol,\n' +
	'}));\n' +
	'%}');

/** Drive one request through the wrapper and return what the probe saw.
 *
 * Mimics uwsd: onRequest() with the connection object, then onBody() chunks
 * followed by the empty-string EOF marker that triggers the reply.
 *
 * @param {string} method - the HTTP method
 * @param {Object} hdrs - request headers as sent on the wire (name -> value)
 * @param {string} body - the request body
 * @param {number} [version] - the HTTP version reported by conn.version()
 * @returns {Object} { headers, out } - reply headers plus the parsed probe JSON
 */
function request(method, hdrs, body, version) {
	let state = null;
	let reply_headers = null;
	let reply_body = null;
	let replied = false;

	let conn = {
		info: function() { return { peer_address: '192.0.2.10' }; },
		version: function() { return version ?? 1.1; },
		header: function() { return hdrs; },
		/* uwsd's request.data(): called with one argument it stashes the
		 * per-request state, called with none it returns it. */
		data: function(...args) {
			if (length(args))
				state = args[0];

			return state;
		},
		/** @param {Object} h - reply headers
		 *  @param {string} b - reply body */
		reply: function(h, b) {
			reply_headers = h;
			reply_body = b;
			replied = true;
		},
		close: function() {},
	};

	onRequest(conn, method, '/probe.ut');

	if (length(body))
		onBody(conn, body);

	onBody(conn, '');

	if (!replied)
		die('wrapper issued no reply');

	/** @type {Object} */
	let out = {};

	try {
		out = json(reply_body ?? '');
	} catch (e) {
		die(sprintf('probe output is not JSON: %s (%s)', reply_body, e));
	}

	return { headers: reply_headers ?? {}, out };
}

/* --- request.headers normalization --------------------------------------- */

/* A browser POST through HAProxy/Angie: lower-case header names on the wire.
 * This is the original bug -- request.form stayed null. */
let lower = request('POST', {
	'host': 'router.lan',
	'content-type': 'application/x-www-form-urlencoded',
	'content-length': '29',
	'cookie': 'sysauth=abc123',
}, 'username=default&password=rkn');

eq('lower-case content-type parses the form',
	lower.out.form, { username: [ 'default' ], password: [ 'rkn' ] });

eq('lower-case request keeps the raw body',
	lower.out.body, 'username=default&password=rkn');

eq('lower-case cookie is reachable as headers.cookie',
	lower.out.cookie, [ 'sysauth=abc123' ]);

/* A direct curl: canonical casing must keep working and must be normalized to
 * the same lower-case keys, so templates need only one spelling. */
let canonical = request('POST', {
	'Host': 'router.lan',
	'Content-Type': 'application/x-www-form-urlencoded',
	'Content-Length': '29',
	'Cookie': 'sysauth=abc123',
}, 'username=default&password=rkn');

eq('canonical content-type parses the form',
	canonical.out.form, { username: [ 'default' ], password: [ 'rkn' ] });

eq('canonical Cookie is normalized to headers.cookie',
	canonical.out.cookie, [ 'sysauth=abc123' ]);

eq('both casings yield identical request.headers',
	canonical.out.headers, lower.out.headers);

eq('request.headers is keyed lower-case with array values',
	lower.out.headers, {
		host: [ 'router.lan' ],
		'content-type': [ 'application/x-www-form-urlencoded' ],
		'content-length': [ '29' ],
		cookie: [ 'sysauth=abc123' ],
	});

/* Arbitrary mixed casing (some proxies send "Content-type"). */
let mixed = request('POST', {
	'CoNtEnT-TyPe': 'application/x-www-form-urlencoded',
	'COOKIE': 'a=b',
}, 'k=v');

eq('mixed-case content-type parses the form', mixed.out.form, { k: [ 'v' ] });
eq('mixed-case cookie is normalized', mixed.out.cookie, [ 'a=b' ]);

/* --- Content-Type parameters and media-type matching --------------------- */

let charset = request('POST', {
	'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
}, 'a=1&b=2');

eq('charset parameter does not defeat form parsing',
	charset.out.form, { a: [ '1' ], b: [ '2' ] });

let ctcase = request('POST', {
	'content-type': 'Application/X-WWW-Form-Urlencoded',
}, 'a=1');

eq('media type is matched case-insensitively', ctcase.out.form, { a: [ '1' ] });

/* A media type that merely starts with the form type must not be treated as a
 * form (the old substr(ctype, 0, 33) prefix test accepted this). */
let notform = request('POST', {
	'content-type': 'application/x-www-form-urlencoded-ish',
}, 'a=1');

eq('a longer look-alike media type is not parsed as a form',
	notform.out.form, null);

/* --- JSON bodies --------------------------------------------------------- */

let jsonreq = request('POST', {
	'content-type': 'application/json',
}, '{"user":"root","n":2}');

eq('lower-case application/json parses request.json',
	jsonreq.out.json, { user: 'root', n: 2 });

eq('json request leaves request.form unset', jsonreq.out.form, null);

let jsoncharset = request('POST', {
	'Content-Type': 'application/json; charset=utf-8',
}, '{"ok":true}');

eq('application/json with charset parses request.json',
	jsoncharset.out.json, { ok: true });

let suffix = request('POST', {
	'content-type': 'application/merge-patch+json',
}, '{"a":1}');

eq('a +json suffix media type parses request.json', suffix.out.json, { a: 1 });

let badjson = request('POST', {
	'content-type': 'application/json',
}, '{not json');

eq('malformed JSON leaves request.json unset', badjson.out.json, null);

/* --- HTTP/2 through the proxy -------------------------------------------- */

/* HTTP/2 lower-cases header names on the wire by protocol requirement. */
let h2 = request('POST', {
	'content-type': 'application/x-www-form-urlencoded',
	'cookie': 'sysauth_https=deadbeef',
}, 'id=7', 2.0);

eq('HTTP/2 form POST parses the form', h2.out.form, { id: [ '7' ] });
eq('HTTP/2 cookie lookup works', h2.out.cookie, [ 'sysauth_https=deadbeef' ]);
eq('HTTP/2 protocol string', h2.out.protocol, 'HTTP/2.0');

/* --- chunked body -------------------------------------------------------- */

/* uwsd delivers the body in arbitrary chunks; the accumulator must still see
 * one whole form body. */
let chunked = (function() {
	let state = null;
	let body = null;

	let conn = {
		info: function() { return { peer_address: '192.0.2.10' }; },
		version: function() { return 1.1; },
		header: function() { return { 'content-type': 'application/x-www-form-urlencoded' }; },
		/* uwsd's request.data(): called with one argument it stashes the
		 * per-request state, called with none it returns it. */
		data: function(...args) {
			if (length(args))
				state = args[0];

			return state;
		},
		/** @param {Object} h - reply headers
		 *  @param {string} b - reply body */
		reply: function(h, b) { body = b; },
		close: function() {},
	};

	onRequest(conn, 'POST', '/probe.ut');
	onBody(conn, 'username=def');
	onBody(conn, 'ault&password=');
	onBody(conn, 'rkn');
	onBody(conn, '');

	/** @type {Object} */
	let out = {};

	try {
		out = json(body ?? '');
	} catch (e) {
		die(sprintf('chunked probe output is not JSON: %s (%s)', body, e));
	}

	return out;
})();

eq('a chunked form body is accumulated and parsed',
	chunked.form, { username: [ 'default' ], password: [ 'rkn' ] });

/* --- no body / GET ------------------------------------------------------- */

let get = request('GET', { 'cookie': 'sysauth=zz' }, '');

eq('GET leaves form and json unset',
	[ get.out.form, get.out.json ], [ null, null ]);

eq('GET cookie lookup works', get.out.cookie, [ 'sysauth=zz' ]);

eq('response Content-Type defaults to text/html',
	get.headers['Content-Type'], 'text/html; charset=utf-8');

eq('response Status defaults to 200 OK', get.headers.Status, '200 OK');

/* --- cleanup ------------------------------------------------------------- */

fs.unlink(probe);

printf('\n%d test(s), %d failure(s)\n', count, failures);

exit(failures ? 1 : 0);
