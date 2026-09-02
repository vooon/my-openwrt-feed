// SPDX-License-Identifier: ISC
/*
 * Runtime smoke test for the ucode inotify module (ucode-mod-inotify).
 *
 * Exercises the exported API end-to-end against the real kernel: init(),
 * add() with a busybox-style mask string, then read() after a file is created
 * and closed in a watched directory, asserting the events carry the watched
 * watch descriptor and the file name.
 *
 * Run from CI with the upstream ucode modules plus the inotify.so built from
 * this package on the module path:
 *   ucode -L <dir-with-upstream-and-inotify.so> test/inotify.uc
 */

import * as fs from 'fs';
import * as inotify from 'inotify';

let failures = 0;

function check(cond, msg) {
	if (!cond) {
		warn("FAIL: ", msg, "\n");
		failures++;
	}
}

const dir = sprintf('/tmp/ucode-mod-inotify-%d', clock()[0]);
fs.mkdir(dir);

let fd = inotify.init();
check(fd != null, "inotify.init() failed");
if (fd == null)
	exit(1);

let wd = inotify.add(fd, dir, 'wDMndc');
check(wd != null && wd > 0, "inotify.add() failed");

fs.writefile(dir + '/hello.txt', 'content');

let evs = [];
for (let i = 0; i < 200; i++) {
	evs = inotify.read(fd);
	if (length(evs))
		break;
	if (!sleep(0.01))
		system(['sleep', '0.01']);
}

let saw_wd = false;
let saw_create = false;
let saw_close = false;
let saw_name = false;

if (wd != null) {
	for (let e in evs) {
		if (e.wd != wd)
			continue;
		saw_wd = true;
		if (e.mask & 0x100)
			saw_create = true;
		if (e.mask & 0x8)
			saw_close = true;
		if (e.name == 'hello.txt')
			saw_name = true;
	}
}

check(length(evs) > 0, "no events captured");
check(saw_wd, "no events for the watched directory");
check(saw_create, "IN_CREATE event not seen");
check(saw_close, "IN_CLOSE_WRITE event not seen");
check(saw_name, "created file name not reported");

inotify.close(fd);
fs.unlink(dir + '/hello.txt');
fs.rmdir(dir);

if (failures) {
	warn(failures, " assertion(s) failed\n");
	exit(1);
}

print("inotify module smoke test OK\n");