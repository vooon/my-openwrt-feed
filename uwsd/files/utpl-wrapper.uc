/**
 * utpl-wrapper.uc - uwsd handler that renders OpenWrt ucode templates (.ut)
 * the way angie-mod-ucode does, with compiled-template caching.
 *
 * Configure via a `run-script` backend:
 *
 *     backend templates {
 *         run-script /usr/share/uwsd/utpl-wrapper.uc {
 *             environment DOCUMENT_ROOT=/www;
 *         }
 *     }
 *
 *     listen 127.0.0.1:7080 {
 *         match-path / {
 *             use-backend templates;
 *         }
 *     }
 *
 * Each request URI is resolved against DOCUMENT_ROOT (a ".." path traversal
 * is rejected with 403) and the matching .ut file is executed with the same
 * request/response/uhttpd globals that angie-mod-ucode injects:
 *
 *   request.method, request.uri, request.query, request.script_name,
 *   request.remote_addr, request.protocol, request.headers.<Name> (array),
 *   request.body, plus parsed request.json / request.form when the
 *   Content-Type asks for it; response.status()/set_header()/add_header();
 *   uhttpd.urlencode()/urldecode(); and the classic CGI globals
 *   (REQUEST_METHOD, REQUEST_URI, QUERY_STRING, SCRIPT_NAME, REMOTE_ADDR,
 *   SERVER_PROTOCOL).
 *
 * The compiled template is cached per file and reused while the file's
 * mtime and size are unchanged; editing the .ut on disk reloads it on the
 * next request (no server restart needed).
 */

'use strict';

import * as fs from 'fs';

/**
 * Compiled-template cache: path -> { mtime, size, fn }.
 */
let cache = {};

/**
 * URL-decode a percent/plus encoded string.
 * @param {string} s
 * @returns {string}
 */
function urldecode(s) {
	let out = "";

	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);

		if (c == "+") {
			out += " ";
		} else if (c == "%" && i + 2 < length(s)) {
			let hi = int(substr(s, i + 1, 2), 16);
			out += sprintf("%c", hi);
			i += 2;
		} else {
			out += c;
		}
	}

	return out;
}

/**
 * Resolve the request URI (excluding query string) against the document
 * root, rejecting path traversal and non-.ut targets with null.
 * @param {string} docroot
 * @param {string} uri
 * @returns {?string}
 */
function resolve_template(docroot, uri) {
	let qmark = index(uri, "?");
	let pathonly = qmark >= 0 ? substr(uri, 0, qmark) : uri;
	let segments = filter(split(pathonly, '/'), length);
	let path = docroot;
	let base;

	if (pathonly == "/")
		return null;

	for (let i = 0; i < length(segments); i++) {
		let seg = segments[i];

		if (seg == "..")
			return null;

		path += "/" + seg;
	}

	base = segments[length(segments) - 1];
	if (base == null || substr(base, length(base) - 3) != ".ut")
		return null;

	// template must live inside DOCUMENT_ROOT
	path = fs.realpath(path);

	if (path == null)
		return null;

	if (substr(path, 0, length(docroot)) != docroot)
		return null;

	return path;
}

/**
 * Return a compiled template closure for the given path, compiling (and
 * caching) only when the file content changed since the last call.
 * @param {string} path
 * @returns {?Function}
 */
function get_template(path) {
	let st = fs.stat(path);
	let hit;

	if (st == null || st.type != "file")
		return null;

	hit = cache[path];

	if (hit && hit.mtime == st.mtime && hit.size == st.size)
		return hit.fn;

	let fn = loadfile(path, { raw_mode: false });

	if (fn == null)
		return null;

	cache[path] = { mtime: st.mtime, size: st.size, fn };

	return fn;
}

/**
 * Parse an application/x-www-form-urlencoded body into name -> array of
 * values.
 * @param {string} raw
 * @returns {Object}
 */
function parse_form(raw) {
	let form = {};

	for (let pair in split(raw, "&")) {
		let eq = index(pair, "=");
		let k = eq >= 0 ? substr(pair, 0, eq) : pair;
		let v = eq >= 0 ? substr(pair, eq + 1) : "";
		let vals;

		k = urldecode(k);
		v = urldecode(v);

		vals = exists(form, k) ? form[k] : null;
		if (vals == null) {
			vals = [];
			form[k] = vals;
		}

		// ucode-lsp disable-next-line nullable-argument   # guaranteed array above
		push(vals, v);
	}

	return form;
}

/**
 * Append a header value to a name -> array-of-values map.
 * @param {Object} hdrs
 * @param {string} name
 * @param {string} value
 */
function push_hdr(hdrs, name, value) {
	let arr = exists(hdrs, name) ? hdrs[name] : null;

	if (arr == null) {
		// ucode-lsp disable-next-line incompatible-function-argument   # hdrs value is array
		arr = [];
		hdrs[name] = arr;
	}

	// ucode-lsp disable-next-line nullable-argument   # guaranteed array above
	push(arr, value);
}

/**
 * Build the angie-mod-ucode request object from the uwsd connection object.
 * @param {Object} conn uwsd request/connection object
 * @param {string} method
 * @param {string} uri
 * @param {string} docroot
 * @returns {Object}
 */
function build_request(conn, method, uri, docroot) {
	let qmark = index(uri, "?");
	let path = qmark >= 0 ? substr(uri, 0, qmark) : uri;
	let query = qmark >= 0 ? substr(uri, qmark + 1) : null;
	let info = conn.info();
	let hdrs = {};
	let req = {
		method: method,
		uri: uri,
		script_name: path,
		remote_addr: info.peer_address,
		protocol: sprintf("HTTP/%3.1f", conn.version()),
		headers: hdrs,
		body: null,
	};

	if (query !== null)
		req.query = query;

	// normalize header values (angie-mod-ucode exposes arrays)
	for (let name, value in conn.header()) {
		if (name != null && type(name) == "string" && value != null)
			// ucode-lsp disable-next-line incompatible-function-argument   # narrowed to string above
			push_hdr(hdrs, name, value);
	}

	return req;
}

/**
 * Invoked when the header portion of an HTTP request is received.
 * @param {Object} request uwsd request/connection object
 * @param {string} method
 * @param {string} uri
 */
export function onRequest(request, method, uri) {
	let docroot;
	let path;

	if (method == null)
		method = "GET";

	if (uri == null)
		uri = "/";

	docroot = fs.realpath(getenv("DOCUMENT_ROOT") ?? "/www");

	if (docroot == null)
		docroot = "/www";

	// ucode-lsp disable-next-line incompatible-function-argument   # guarded to defaults above
	path = resolve_template(docroot, uri);

	if (path == null) {
		request.reply({
			"Status": "403 Forbidden",
			"Content-Type": "text/plain"
		}, "Forbidden");

		request.close();
		return;
	}

	let tpl = get_template(path);
	// ucode-lsp disable-next-line incompatible-function-argument   # uwsd passes strings
	let req = build_request(request, method, uri, docroot);
	let rec = { status: null, phrase: null, headers: {} };

	let response = {
		/** @param {number|string} code @param {?string} phrase */
		status: function(code, phrase) { rec.status = code; rec.phrase = phrase || null; },
		/** @param {string} name @param {string} value */
		set_header: function(name, value) { rec.headers[name] = value; },
		/** @param {string} name @param {string} value */
		add_header: function(name, value) {
			if (!exists(rec.headers, name))
				rec.headers[name] = value;
			else
				rec.headers[name] += "," + value;
		},
	};

	let uhttpd = {
		/** @param {string} s @returns {string} */
		urlencode: function(s) { return s; },
		/** @param {string} s @returns {string} */
		urldecode: function(s) { return urldecode(s); },
	};

	let scope = { request: req, response, uhttpd };

	scope.REQUEST_METHOD = method;
	scope.REQUEST_URI = uri;
	scope.SCRIPT_NAME = path;
	scope.REMOTE_ADDR = req.remote_addr;
	scope.SERVER_PROTOCOL = req.protocol;
	if (req.query !== null)
		scope.QUERY_STRING = req.query;

	// stash per-request state for onBody(); reply is issued on EOF
	request.data({
		tpl,
		req,
		rec,
		scope,
		body: "",
	});
};

/**
 * Invoked for each body chunk; an empty string signals end-of-body.
 * On EOF, renders the template and replies.
 * @param {Object} request uwsd request/connection object
 * @param {string} data chunk of request body ("" on EOF)
 */
export function onBody(request, data) {
	let state = request.data();
	/** @type {string} */
	let body;
	/** @type {string} */
	let ctype;
	/** @type {Array} */
	let ctarr;
	/** @type {?Function} */
	let tpl;
	/** @type {Object} */
	let scope;
	/** @type {Object} */
	let req;
	/** @type {Object} */
	let rec;
	/** @type {Object} */
	let headers;
	let out;

	if (state == null)
		return;

	if (length(data)) {
		// ucode-lsp disable-next-line nullable-argument   # state.body is a string accumulator
		state.body += data;
		return;
	}

	// narrow dynamic state fields into typed locals
	req = state.req;
	rec = state.rec;
	headers = rec.headers;
	scope = state.scope;
	tpl = state.tpl;
	// ucode-lsp disable-next-line incompatible-function-argument   # body accumulator is a string
	body = state.body;

	req.body = body;

	// lightweight form/json parsing mirroring the C module
	ctarr = req.headers["Content-Type"];
	ctype = (ctarr && length(ctarr)) ? ctarr[0] : "";

	headers["Content-Type"] = headers["Content-Type"] ?? "text/html; charset=utf-8";

	if (rec.status !== null)
		headers["Status"] = rec.status + (rec.phrase ? " " + rec.phrase : "");
	else
		headers["Status"] = "200 OK";

	// ucode-lsp disable-next-line incompatible-function-argument   # ctype is a string from the guard above
	if (ctype == "application/json" || (length(ctype) > 5 && substr(ctype, length(ctype) - 5) == "+json")) {
		if (length(body)) {
			try {
				// ucode-lsp disable-next-line incompatible-function-argument   # body is a string
				req.json = json(body);
			} catch (e) {
				// ignore malformed JSON, leave request.json unset
			}
		}
	}
	// ucode-lsp disable-next-line incompatible-function-argument   # ctype is a string from the guard above
	else if (substr(ctype, 0, 33) == "application/x-www-form-urlencoded") {
		req.form = parse_form(body);
	}

	if (tpl != null) {
		try {
			// render() captures the output of the wrapper; the cached loadfile
			// closure gets the per-request scope injected as globals via call().
			out = render(function() { call(tpl, null, scope); });
		} catch (e) {
			headers["Status"] = "500 Internal Server Error";
			headers["Content-Type"] = "text/plain";
			out = "Template error: " + e;
		}
	}
	else {
		headers["Status"] = "500 Internal Server Error";
		headers["Content-Type"] = "text/plain";
		out = "Template not found or failed to compile";
	}

	request.reply(headers, out);
	request.close();
};