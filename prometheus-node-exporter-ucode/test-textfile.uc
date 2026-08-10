// Self-contained regression test for the textfile collector.
//
// Uses the real fs module, a temp directory created by test-textfile.sh
// (env TF_DIR), mocks gauge/raw, loads files/extra/textfile.uc and asserts
// the emitted metrics and raw passthrough.

import * as fs from "fs";
global.fs = fs;

let failures = 0;

function check(cond, msg) {
	if (!cond) {
		warn("FAIL: ", msg, "\n");
		failures++;
	}
}

// The collector needs the fs module to be resolvable as a global.
global.config = { directory: getenv("TF_DIR") || "/tmp/opencode/tf_test" };

let emitted = [];
let rawbuf = "";

global.gauge = function(name, help) {
	return function(labels, value) {
		push(emitted, { name: name, labels: labels, value: value });
	};
};
global.counter = global.gauge;
global.raw = function(s) {
	rawbuf += s;
};

include("files/extra/textfile.uc");

// mtime metrics for both .prom files
check(length(emitted) == 2, "expected 2 mtime metrics, got " + length(emitted));
let files = [];
for (let i = 0; i < length(emitted); i++) {
	check(emitted[i].name == "node_textfile_mtime_seconds", "mtime metric name");
	push(files, emitted[i].labels["file"]);
	check(emitted[i].value > 0, "mtime value positive");
}
check(files[0] == "a.prom" && files[1] == "b.prom", "sorted .prom files, got " + join(",", files));

// raw passthrough of both .prom files, in order
check(index(rawbuf, "# HELP my_metric_total") >= 0, "a.prom raw content present");
check(index(rawbuf, "my_metric_total 42") >= 0, "a.prom metric present");
check(index(rawbuf, "# HELP second") >= 0, "b.prom raw content present");
check(index(rawbuf, "second{label=\"x\"} 1") >= 0, "b.prom metric present");
check(index(rawbuf, "ignored") < 0, "non-.prom file ignored");

if (failures) {
	warn(failures, " assertion(s) failed\n");
	exit(1);
}

print("textfile collector test OK\n");