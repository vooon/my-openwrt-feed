#!/usr/bin/ucode
'use strict';

/* qemu-qmp - run one QMP command against a QEMU instance.
 *
 * Usage: qemu-qmp <socket> <command> [<arguments as JSON object>]
 *
 * Prints the command's `return` value as JSON. Exit code 0 on success, 1 on
 * a QMP error / connection failure, 2 on bad usage.
 */

// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/qemu/qmp.uc
import * as qmp from 'qemu.qmp';

let path = ARGV[0], cmd = ARGV[1], args = null;

if (!path || !cmd) {
	warn('usage: qemu-qmp <socket> <command> [<arguments json>]\n');
	exit(2);
}

let args_json = ARGV[2];
if (args_json != null) {
	try {
		args = json(args_json);
	}
	catch (e) {
		warn(`qemu-qmp: arguments are not valid JSON: ${args_json}\n`);
		exit(2);
	}
}

let s = qmp.open(path, 5000);
if (s.error) {
	warn(`qemu-qmp: ${s.error}\n`);
	exit(1);
}

let r = s.execute(cmd, args);
s.close();

if (!r.ok) {
	warn(`qemu-qmp: ${cmd}: ${r.error}\n`);
	exit(1);
}

printf('%J\n', r.return);
exit(0);
