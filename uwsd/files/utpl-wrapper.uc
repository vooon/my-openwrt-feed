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
 *   request.remote_addr, request.protocol, request.headers.<name> (array,
 *   keyed by the lower-cased header name), request.body, plus parsed
 *   request.json / request.form when the Content-Type asks for it;
 *   response.status()/set_header()/add_header();
 *   uhttpd.urlencode()/urldecode()/docroot; and the classic CGI globals
 *   (REQUEST_METHOD, REQUEST_URI, QUERY_STRING, SCRIPT_NAME, REMOTE_ADDR,
 *   SERVER_PROTOCOL).
 *
 * On top of that (not present in either uhttpd or angie-mod-ucode, so keep
 * their use to templates that only ever run here):
 *
 *   request.get_header(name) - first value of a header, any casing, else null
 *   request.get_cookie(name) - one cookie value from the Cookie header, else
 *                              null (cookie names stay case-sensitive)
 *
 * Both are named get_* rather than header()/cookie() so that a typo cannot
 * silently resolve to the request.headers dict instead of a value.
 *
 * uhttpd.urlencode()/urldecode() follow uhttpd's uh_urlencode()/uh_urldecode()
 * semantics, except that urldecode() also maps "+" to a space (it backs the
 * form and query-string parsing here).
 *
 * Request header names are lower-cased because the casing on the wire is
 * client- and proxy-dependent: a browser request arriving via HAProxy/Angie
 * (or any HTTP/2 hop) delivers "content-type", while curl sends
 * "Content-Type". Lower-casing makes lookups deterministic and matches how
 * angie-mod-ucode keys request.headers, so templates written against either
 * backend behave the same. Response headers keep the casing the template
 * chose.
 *
 * The compiled template is cached per file. Without the optional
 * ucode-mod-inotify plugin the cache entry is validated against the file's
 * mtime and size on every request, so editing the .ut on disk reloads it on
 * the next request (no server restart needed). When the plugin is installed,
 * DOCUMENT_ROOT is watched recursively, the whole cache is dropped as soon as
 * a .ut/.uc file changes and cache hits need no stat() at all -- this also
 * covers imported .uc modules, whose own mtime/size is not part of the
 * per-file key because they are compiled into the template. The plugin is
 * loaded with the runtime require() (not a compile-time import) so a build
 * without it is not a load-time error and simply falls back to the
 * mtime/size check.
 */

'use strict';

import * as fs from 'fs';

/**
 * Compiled-template cache: path -> { mtime, size, fn }.
 */
let cache = {};

/* -------------------------------------------------------------------------
 * Optional inotify-driven cache invalidation
 * ---------------------------------------------------------------------- */

/*
 * Watch mask letters as understood by the ucode inotify module / busybox
 * inotifyd: close-write, moved-to, create, delete, moved-from, delete-self
 * and move-self. The kernel cannot filter on a file name, so whole
 * directories are watched and events are filtered by suffix below.
 */
let WATCH_MASK = "wyndmDM";

/* Event flag values from <sys/inotify.h>. */
let IN_DELETE_SELF = 0x00000400;
let IN_MOVE_SELF   = 0x00000800;
let IN_Q_OVERFLOW  = 0x00004000;
let IN_ISDIR       = 0x40000000;

/* Watcher state; null when inotify is unavailable. */
let watcher = null;
let watcher_tried = false;

/**
 * Whether a name ends in the given suffix.
 * @param {string} s
 * @param {string} suffix
 * @returns {boolean}
 */
function ends_with(s, suffix) {
	let n = length(s);
	let m = length(suffix);

	return n >= m && substr(s, n - m) == suffix;
}

/**
 * Decide whether an inotify event should invalidate the template cache.
 *
 * Only events that can change the content or the set of .ut/.uc templates
 * count: a template child being written, created, deleted or renamed, a
 * watched directory disappearing, any subdirectory change (which may bring or
 * remove a whole template subtree) and queue overflow (something was missed).
 * @param {Object} ev an event as returned by inotify.read()
 * @returns {boolean}
 */
export function stale_event(ev) {
	let mask = ev.mask ?? 0;
	let name = ev.name;

	if (mask & IN_Q_OVERFLOW)
		return true;

	if (mask & (IN_DELETE_SELF | IN_MOVE_SELF))
		return true;

	if (type(name) != "string" || !length(name))
		return false;

	if (mask & IN_ISDIR)
		return true;

	return ends_with(name, ".ut") || ends_with(name, ".uc");
};

/**
 * Add an inotify watch for `dir` and every directory below it.
 * Symlinked directories are not followed (lstat), so a link loop cannot
 * recurse forever.
 * @param {Object} w watcher
 * @param {string} dir
 */
function watch_dirs(w, dir) {
	if (w.mod.add(w.fd, dir, WATCH_MASK) == null)
		return;

	for (let name in fs.lsdir(dir) ?? []) {
		let sub = dir + "/" + name;
		let st = fs.lstat(sub);

		if (st != null && st.type == "directory")
			watch_dirs(w, sub);
	}
}

/**
 * Try to set up an inotify watcher over `docroot`.
 *
 * require() is used instead of import so that a build without the optional
 * ucode-mod-inotify plugin still loads: the exception is caught and the
 * wrapper falls back to the mtime/size check.
 * @param {string} docroot
 * @returns {?Object} watcher object or null when inotify is unavailable
 */
function init_watcher(docroot) {
	let mod = null;
	let fd;

	try {
		mod = require("inotify");
	} catch (e) {
		return null;
	}

	if (mod == null || type(mod.add) != "function" || type(mod.read) != "function")
		return null;

	fd = mod.init();

	if (fd == null)
		return null;

	let w = { mod, fd, root: docroot };

	watch_dirs(w, docroot);

	return w;
}

/**
 * Lazily initialise the watcher on the first request, once.
 * @param {string} docroot
 */
function ensure_watcher(docroot) {
	if (watcher_tried)
		return;

	watcher_tried = true;
	watcher = init_watcher(docroot);
}

/**
 * Drain pending inotify events and drop the template cache if any of them
 * touched a .ut/.uc file, so the next lookup recompiles.
 * @param {Object} w watcher
 */
function poll_watcher(w) {
	let evs = w.mod.read(w.fd);
	let dirty = false;

	for (let ev in evs) {
		if (stale_event(ev)) {
			dirty = true;
			break;
		}
	}

	if (!dirty)
		return;

	cache = {};

	/* a directory may have appeared or vanished: refresh the watch set */
	watch_dirs(w, w.root);
}

/**
 * URL-decode a percent/plus encoded string.
 *
 * Unlike uhttpd's uh_urldecode(), "+" is translated to a space: this decoder
 * is also used for application/x-www-form-urlencoded bodies and query strings,
 * where "+" means space.
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
 * Percent-encode a string for use in a URL.
 *
 * Mirrors uhttpd's uh_urlencode(): the RFC 3986 unreserved characters
 * (A-Z a-z 0-9 "-" "_" "." "~") are passed through, every other byte becomes
 * "%" plus two lower-case hex digits. Encoding is byte-wise, so UTF-8 input
 * yields one escape per byte. Note that a space becomes "%20", not "+".
 * @param {string} s
 * @returns {string}
 */
function urlencode(s) {
	let out = "";

	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let b = ord(s, i);

		if (b == null)
			continue;

		if ((b >= 48 && b <= 57) ||		// 0-9
		    (b >= 65 && b <= 90) ||		// A-Z
		    (b >= 97 && b <= 122) ||		// a-z
		    c == "-" || c == "_" || c == "." || c == "~")
			out += c;
		else
			out += sprintf("%%%02x", b);
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
 * Return a compiled template closure for the given path.
 *
 * When the inotify watcher is active it has already dropped the cache on any
 * .ut/.uc change, so a cache hit can be returned as-is and the per-request
 * stat() is skipped entirely. Without inotify the entry is validated against
 * the file's mtime and size on every call, as before.
 * @param {string} path
 * @returns {?Function}
 */
function get_template(path) {
	let hit = cache[path];
	let st;
	let fn;

	if (hit != null && watcher != null)
		return hit.fn;

	st = fs.stat(path);

	if (st == null || st.type != "file")
		return null;

	if (hit && hit.mtime == st.mtime && hit.size == st.size)
		return hit.fn;

	fn = loadfile(path, { raw_mode: false });

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
 * Look up a request header by name, returning its first value.
 *
 * request.headers is keyed by the lower-cased header name (see
 * build_request()), so the name is lower-cased here too and callers may pass
 * any casing.
 * @param {Object} hdrs request.headers
 * @param {string} name
 * @returns {string}
 */
function get_hdr(hdrs, name) {
	let key = lc(name);
	let arr = exists(hdrs, key) ? hdrs[key] : null;

	if (type(arr) != "array" || !length(arr))
		return "";

	// ucode-lsp disable-next-line nullable-argument   # non-empty array above
	return arr[0] ?? "";
}

/**
 * Extract the bare media type of a Content-Type value: strip any
 * ";parameter" section plus surrounding whitespace and lower-case the result,
 * so "Application/JSON; charset=utf-8" becomes "application/json".
 *
 * Mirrors uc_http_media_type_is() in angie-mod-ucode, which compares the
 * media type case-insensitively and only up to the parameter delimiter.
 * @param {string} value raw Content-Type header value
 * @returns {string}
 */
function media_type(value) {
	let semi = index(value, ";");
	let bare = semi >= 0 ? substr(value, 0, semi) : value;

	return lc(trim(bare));
}

/**
 * Look up a single cookie value in the request's Cookie header(s).
 *
 * Cookie names are case-sensitive (unlike header names). The value is returned
 * verbatim, without percent-decoding: "+" is a legal cookie octet, so running
 * it through urldecode() would corrupt base64 session tokens. All Cookie
 * headers are searched, so a client splitting them across lines still works.
 * Returns null when the cookie is absent.
 * @param {Object} hdrs request.headers
 * @param {string} name cookie name
 * @returns {?string}
 */
function get_cookie(hdrs, name) {
	let arr = exists(hdrs, "cookie") ? hdrs["cookie"] : null;

	if (type(arr) != "array")
		return null;

	for (let line in arr) {
		if (type(line) != "string")
			continue;

		for (let pair in split(line, ";")) {
			let eq = index(pair, "=");

			if (eq < 0)
				continue;

			if (trim(substr(pair, 0, eq)) == name)
				return trim(substr(pair, eq + 1));
		}
	}

	return null;
}

/**
 * Convert response headers into the object uwsd's reply() expects.
 *
 * uwsd's reply() emits exactly one "Name: value" line per header key. A
 * repeated header (accumulated via add_header into an array) is therefore
 * expanded into additional "Name: value" lines by embedding a CRLF + the
 * header name in the value: uwsd writes string values raw, so each array
 * element becomes its own header line, mirroring angie-mod-ucode's
 * repeatable add_header().
 * @param {Object} headers
 * @returns {Object}
 */
function flatten_headers(headers) {
	let out = {};

	for (let name, value in headers) {
		if (name == null)
			continue;

		if (type(value) == "array") {
			let joined = "";
			let first = true;

			for (let v in value) {
				if (!first)
					joined += "\r\n" + name + ": ";
				joined += v;
				first = false;
			}

			out[name] = joined;
		} else {
			out[name] = value;
		}
	}

	return out;
}

/*
 * Default reason phrases for the status codes templates commonly emit. Only
 * needed because uwsd's reply() parses the Status header primarily to get the
 * code: it demands a digit triple followed by whitespace (script.c:
 * isdigit(p[0..2]) && isspace(p[3])) and otherwise ignores the header, replying
 * 200 OK. A phrase-less "302" therefore silently becomes a 200, so the wrapper
 * always appends a reason phrase (or at least the separating space).
 */
let REASONS = {
	"100": "Continue", "101": "Switching Protocols",
	"200": "OK", "201": "Created", "202": "Accepted",
	"203": "Non-Authoritative Information", "204": "No Content",
	"205": "Reset Content", "206": "Partial Content",
	"300": "Multiple Choices", "301": "Moved Permanently", "302": "Found",
	"303": "See Other", "304": "Not Modified", "305": "Use Proxy",
	"307": "Temporary Redirect", "308": "Permanent Redirect",
	"400": "Bad Request", "401": "Unauthorized", "402": "Payment Required",
	"403": "Forbidden", "404": "Not Found", "405": "Method Not Allowed",
	"406": "Not Acceptable", "407": "Proxy Authentication Required",
	"408": "Request Timeout", "409": "Conflict", "410": "Gone",
	"411": "Length Required", "412": "Precondition Failed",
	"413": "Payload Too Large", "414": "URI Too Long",
	"415": "Unsupported Media Type", "416": "Range Not Satisfiable",
	"417": "Expectation Failed", "422": "Unprocessable Entity",
	"426": "Upgrade Required", "428": "Precondition Required",
	"429": "Too Many Requests", "431": "Request Header Fields Too Large",
	"451": "Unavailable For Legal Reasons",
	"500": "Internal Server Error", "501": "Not Implemented", "502": "Bad Gateway",
	"503": "Service Unavailable", "504": "Gateway Timeout",
	"505": "HTTP Version Not Supported",
};

/**
 * Return the standard reason phrase for a status code, or "" when the code is
 * unknown (the status line then carries just the separating space, which is
 * still valid HTTP and still lets uwsd pick up the code).
 * @param {number|string} code
 * @returns {string}
 */
function reason_phrase(code) {
	let c = int(code);
	let reason = c != null ? REASONS[c] : null;

	return reason ?? "";
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

	// normalize header names and values (angie-mod-ucode exposes arrays keyed
	// by the lower-cased name)
	for (let name, value in conn.header()) {
		if (name != null && type(name) == "string" && value != null)
			// ucode-lsp disable-next-line incompatible-function-argument   # narrowed to string above
			push_hdr(hdrs, lc(name), value);
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

	// drop the cache if a .ut/.uc file changed since the last request
	// ucode-lsp disable-next-line nullable-argument   # guarded to "/www" above
	ensure_watcher(docroot);

	if (watcher != null)
		poll_watcher(watcher);

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
			let vals = exists(rec.headers, name) ? rec.headers[name] : null;

			// keep repeated headers repeatable: an array value becomes one
			// header line per element at reply time
			if (vals == null)
				vals = [];

			if (type(vals) != "array")
				vals = [ vals ];

			push(vals, value);
			rec.headers[name] = vals;
		},
	};

	let uhttpd = {
		/** @param {string} s @returns {string} */
		urlencode: function(s) { return urlencode(s); },
		/** @param {string} s @returns {string} */
		urldecode: function(s) { return urldecode(s); },
		docroot: docroot,
	};

	// convenience accessors on top of the normalized request.headers; not part
	// of the uhttpd API, but spelled out here so templates need not re-implement
	// the array unwrapping and casing dance. Named get_* so a typo cannot
	// silently resolve to the request.headers dict itself.
	/** @param {string} name @returns {?string} */
	req.get_header = function(name) {
		let v = get_hdr(req.headers, name);

		return length(v) ? v : null;
	};

	/** @param {string} name @returns {?string} */
	req.get_cookie = function(name) {
		return get_cookie(req.headers, name);
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

	// lightweight form/json parsing mirroring the C module. request.headers is
	// keyed by the lower-cased name, and the media type is compared without
	// its ";charset=..." parameters.
	ctype = media_type(get_hdr(req.headers, "content-type"));

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
	else if (ctype == "application/x-www-form-urlencoded") {
		req.form = parse_form(body);
	}

	if (tpl != null) {
		try {
			// render() captures the output of the wrapper; the cached loadfile
			// closure gets the per-request scope injected as globals via call().
			out = render(function() { call(tpl, null, scope); });
		} catch (e) {
			rec.status = 500;
			rec.phrase = "Internal Server Error";
			headers["Content-Type"] = "text/plain";
			out = "Template error: " + e;
		}
	}
	else {
		rec.status = 500;
		rec.phrase = "Internal Server Error";
		headers["Content-Type"] = "text/plain";
		out = "Template not found or failed to compile";
	}

	// Resolve the status line only once the template has run: response.status()
	// records into rec.status, so reading it any earlier would pin the reply to
	// 200 and silently drop a template's redirect, 304 or error status. A
	// phrase-less status() call still gets a standard reason phrase (and, for an
	// unknown code, at least the separating space) because uwsd only honors a
	// Status header whose fourth byte is whitespace.
	if (rec.status !== null) {
		let phrase = rec.phrase ?? reason_phrase(rec.status);

		headers["Status"] = phrase ? rec.status + " " + phrase : rec.status + " ";
	}
	else
		headers["Status"] = "200 OK";

	// likewise default the content type last, so response.set_header() wins
	headers["Content-Type"] = headers["Content-Type"] ?? "text/html; charset=utf-8";

	request.reply(flatten_headers(headers), out);
	request.close();
};
