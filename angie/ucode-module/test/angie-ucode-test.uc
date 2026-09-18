#!/usr/bin/ucode
/**
 * angie-ucode-test — a standalone test tool for angie-mod-ucode templates.
 *
 * Renders an angie-mod-ucode template (.ut) without an angie build by mocking
 * the "request"/"response"/"uhttpd" globals that the C module injects at
 * request time.  This is the same machinery ucode's `render()` provides, wired
 * up so a template can be exercised from a shell the way angie would call it:
 *
 *     angie-ucode-test --method GET --uri /profiles \
 *         --header "X-Username: home" examples/profiles.ut
 *
 *     angie-ucode-test --method POST --content-type application/json \
 *         --json '{"name":"vovan"}' examples/api.ut
 *
 * The rendered status, response headers and body are printed to stdout.
 * Diagnostics/errors go to stderr, so the two can be separated by the caller.
 *
 * NOTE: ucode consumes its own command-line options before the script is
 * loaded, so pass a "--" separator before the tool's own options:
 *
 *     angie-ucode-test -- --method GET ...
 *
 * Options:
 *   --method <METHOD>       request.method (default: GET)
 *   --uri <URI>             request.uri (default: /)
 *   --query <QS>            request.query / QUERY_STRING (default: none)
 *   --header "Name: value"  add a request header (repeatable)
 *   --body <text>           request.body raw text
 *   --data <a=b&c=d>        request.body parsed as application/x-www-form-urlencoded
 *                           into request.form
 *   --json <json>           request.body parsed into request.json (and kept raw)
 *   --content-type <type>   Content-Type header (repeatable headers above also apply)
 *   -- file.ut              the template to render (last positional arg)
 */

let target = null;
let method = "GET";
let uri = "/";
let query = null;
let headers = {};
let body = null;
let content_type = null;
let data_arg = null;
let json_arg = null;

/**
 * Parse one "Name: value" header argument into the headers object.  Names are
 * lower-cased, matching how the C module keys request.headers.
 * @param {string} line
 */
function add_header(line) {
	let colon = index(line, ":");
	if (colon < 0) {
		die("--header expects \"Name: value\", got: " + line);
	}

	let name = lc(trim(substr(line, 0, colon)));
	let value = trim(substr(line, colon + 1));

	if (!exists(headers, name))
		headers[name] = [];

	// ucode-lsp disable-next-line incompatible-function-argument   # guaranteed array
	push(headers[name], value);
}

/**
 * Parse CLI arguments.  Positional args are collected into files; the last
 * one is treated as the template path (earlier ones are extra script files,
 * which ucode ignores here).
 * @param {Array} args
 * @returns {?string} the template file to render, or null
 */
function parse_args(args) {
	let files = [];

	for (let i = 0; i < length(args); i++) {
		let a = args[i];

		if (a == "--method") {
			method = args[++i];
		} else if (a == "--uri") {
			uri = args[++i];
		} else if (a == "--query") {
			query = args[++i];
		} else if (a == "--header") {
			add_header(args[++i]);
		} else if (a == "--body") {
			body = args[++i];
		} else if (a == "--data") {
			data_arg = args[++i];
		} else if (a == "--json") {
			json_arg = args[++i];
		} else if (a == "--content-type") {
			content_type = args[++i];
		} else if (a != "-" && substr(a, 0, 1) == "-") {
			warn("angie-ucode-test: unknown option: ", a, "\n");
		} else {
			push(files, a);
		}
	}

	if (length(files) == 0) {
		die("usage: angie-ucode-test [options] -- template.ut");
	}

	return files[length(files) - 1];
}

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
 * Parse an application/x-www-form-urlencoded body into name -> array of
 * values (mirroring the C module's request.form).
 * @param {string} raw
 * @returns {Object}
 */
function parse_form(raw) {
	let form = {};

	for (let pair in split(raw, "&")) {
		let eq = index(pair, "=");
		let k = eq >= 0 ? substr(pair, 0, eq) : pair;
		let v = eq >= 0 ? substr(pair, eq + 1) : "";

		k = urldecode(k);
		v = urldecode(v);

		/** @type {Array} */
		let vals = exists(form, k) ? form[k] : null;
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
 * Build the "request" object the C module would inject.
 * @param {string} req_method
 * @param {string} req_uri
 * @param {?string} req_query
 * @param {?string} req_data
 * @param {?string} req_json
 * @param {?string} req_body
 * @returns {Object}
 */
function build_request(req_method, req_uri, req_query, req_data, req_json, req_body) {
	let req = {
		method: req_method,
		uri: req_uri,
		script_name: req_uri,
		remote_addr: "127.0.0.1",
		protocol: "HTTP/1.1",
		headers: headers,
		body: req_body || "",
		// the C module always defines these, even for a body-less request
		form: {},
		files: {},
	};

	if (req_query !== null)
		req.query = req_query;

	if (req_data !== null) {
		req.body = req_data;
		req.form = parse_form(req_data);
	}

	if (req_json !== null) {
		req.body = req_json;
		req.json = json(req_json);
	}

	return req;
}

/**
 * Main: parse args, mock the globals, render the template, print the result.
 */
function main() {
	target = parse_args(ARGV);

	if (content_type !== null)
		add_header("Content-Type: " + content_type);
	else if (json_arg !== null)
		add_header("Content-Type: application/json");
	else if (data_arg !== null)
		add_header("Content-Type: application/x-www-form-urlencoded");

	let request = build_request(method, uri, query, data_arg, json_arg, body);

	let rec = { status: null, phrase: null, headers: {} };

	let response = {
		/** @param {number|string} code @param {?string} phrase */
		status: function(code, phrase) {
			rec.status = code;
			rec.phrase = phrase || null;
		},
		/** @param {string} name @param {string} value */
		set_header: function(name, value) { rec.headers[name] = [value]; },
		/** @param {string} name @param {string} value */
		add_header: function(name, value) {
			/** @type {Array} */
			let vals = exists(rec.headers, name) ? rec.headers[name] : null;
			if (vals == null) {
				vals = [];
				rec.headers[name] = vals;
			}
			// ucode-lsp disable-next-line nullable-argument   # guaranteed array above
			push(vals, value);
		},
	};

	let uhttpd = {
		/** @param {string} s @returns {string} */
		urlencode: function(s) { return s; },
		/** @param {string} s @returns {string} */
		urldecode: function(s) { return urldecode(s); },
	};

	let scope = { request, response, uhttpd };

	// CGI-style top-level globals, as the C module sets them
	scope.REQUEST_METHOD = method;
	scope.REQUEST_URI = uri;
	scope.SCRIPT_NAME = uri;
	scope.REMOTE_ADDR = "127.0.0.1";
	scope.SERVER_PROTOCOL = "HTTP/1.1";
	if (query !== null)
		scope.QUERY_STRING = query;

	if (target == null)
		die("no template file given");

	let out = render(target, scope);

	// print the simulated response
	printf("Status: %s%s\n", rec.status === null ? "200" : rec.status,
	       rec.phrase ? " " + rec.phrase : "");

	for (let n in rec.headers)
		for (let v in rec.headers[n])
			printf("%s: %s\n", n, v);

	print("\n");
	print(out);
}

main();