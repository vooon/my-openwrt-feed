'use strict';

// Regression tests for the angie-mod-ucode example template.
//
// The template (examples/profiles.ut) is a ucode template that reads the
// "request" global and drives the "response" global (status/header), plus the
// legacy "uhttpd" API object.  This test mocks those globals, runs the
// template through loadfile() and asserts the recorded response calls.
//
// Body output of the template goes to stdout; all diagnostics/failures here
// go to stderr, so the shell driver can separate the two.

let failures = 0;

function fail(msg) {
	warn("FAIL: ", msg, "\n");
	failures++;
}

function check(cond, msg) {
	if (!cond)
		fail(msg);
}

// Run the template with the given headers (each value an array, matching the
// module's always-array request.headers).  Returns the recorded response
// object calls ({ status: [code, phrase] | null, headers: {...} }).
function run(headers) {
	let hdrs = {};

	for (let k in headers || {})
		hdrs[k] = [headers[k]];

	let request = {
		method: "GET",
		uri: "/profiles",
		query: null,
		script_name: "/profiles",
		remote_addr: "192.0.2.1",
		protocol: "HTTP/1.1",
		headers: hdrs,
	};

	let rec = { status: null, headers: {} };

	let response = {
		/** @param {string} code @param {?} phrase */
		status: function(code, phrase) { rec.status = [code, phrase]; },
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

	// legacy API; direct string passthrough is enough for the example
	let uhttpd = {
		urlencode: function(s) { return s; },
		urldecode: function(s) { return s; },
	};

	let func = loadfile("./examples/profiles.ut", { raw_mode: false });
	if (!func) {
		fail("cannot load examples/profiles.ut");
		return null;
	}

	call(func, null, { request, response, uhttpd });

	return rec;
}

// -- unauthenticated access ------------------------------------------------

let r = run({ "X-Username": "guest" });
check(r != null, "guest run returned a record");
if (r) {
	check(r.status != null && r.status[0] == 401,
	      "guest gets 401, got " + (r.status ? r.status[0] : "none"));
	check(r.headers["WWW-Authenticate"] == "Basic realm=\"vpn\"",
	      "guest gets WWW-Authenticate header");
}

// -- missing header treats caller as anonymous -----------------------------

r = run({});
check(r != null, "anonymous run returned a record");
if (r) {
	check(r.status != null && r.status[0] == 401,
	      "anonymous gets 401");
}

// -- matching user is allowed ----------------------------------------------

r = run({ "X-Username": "home" });
check(r != null, "home run returned a record");
if (r) {
	check(r.status == null || r.status[0] != 401,
	      "home user is not rejected");
	check(r.headers["Content-Type"] == "text/html; charset=utf-8",
	      "home page sets text/html content type");
}

if (failures) {
	warn(failures, " failure(s)\n");
	exit(1);
}

warn("profiles.ut: all assertions passed\n");