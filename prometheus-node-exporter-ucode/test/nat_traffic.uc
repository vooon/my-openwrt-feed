'use strict';

import * as real_fs from "fs";

const fixture = "./test/fixtures/nf_conntrack";
const collector_path = "./files/extra/nat_traffic.uc";

let failures = 0;

function fail(msg) {
	warn("FAIL: ", msg, "\n");
	failures++;
}

function check(cond, msg) {
	if (!cond)
		fail(msg);
}

// Capture metric emissions
let metrics = {};

function gauge(name, help) {
	let func;
	func = function(labels, value) {
		let key = name;
		if (labels && length(labels)) {
			let parts = [];
			for (let k in labels)
				push(parts, k + '="' + labels[k] + '"');
			key += "{" + join(",", parts) + "}";
		}
		metrics[key] = value;
		return func;
	};
	return func;
}

// Redirect /proc/net/nf_conntrack to the fixture file
const fs = {
	open: function(path) {
		return real_fs.open(path == "/proc/net/nf_conntrack" ? fixture : path);
	}
};

function wsplit(line) {
	return split(line, /\s+/);
}

function nextline(f) {
	return rtrim(f.read("line"), "\n");
}

let func;
try {
	func = loadfile(collector_path, { strict_declarations: true, raw_mode: true });
} catch(e) {
	fail("failed to load collector: " + e.message);
	exit(1);
}

if (call(func, null, { fs, gauge, wsplit, nextline, config: {} }) == false)
	fail("collector returned false — is the fixture file missing?");

// line1 (1234+5678=6912) + line2 (100+200=300) share src/dst => 7212
check(metrics['node_nat_traffic{src="192.168.1.2",dst="1.2.3.4"}'] == 7212,
	"aggregated src=192.168.1.2 dst=1.2.3.4 == 7212");
// line3 (300+400=700)
check(metrics['node_nat_traffic{src="192.168.1.3",dst="1.2.3.4"}'] == 700,
	"src=192.168.1.3 dst=1.2.3.4 == 700");
// line4 (60+120=180)
check(metrics['node_nat_traffic{src="192.168.1.2",dst="8.8.8.8"}'] == 180,
	"src=192.168.1.2 dst=8.8.8.8 == 180");

if (failures) {
	warn(failures + " assertion(s) failed\n");
	exit(1);
}

print("nat_traffic test OK\n");