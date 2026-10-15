#!/usr/bin/ucode
'use strict';

/* qemu-backup - back up QEMU instances from /etc/config/qemu to Proxmox
 * Backup Server (`/etc/init.d/qemu backup [instance]` runs this).
 *
 * Usage: qemu-backup [instance]
 *
 * Every instance with `option backup '1'` (or just the named one) is backed
 * up as `--backup-type vm --backup-id <backup_id>` with disk0.img and the
 * optional pflash images, and reported to Healthchecks (per-instance
 * hc_ping_url) and Gotify (backup_server section) via pbs.helper. Output goes
 * to syslog as qemu.<instance> (stderr when run on a terminal).
 *
 * Exit code: 0 when every selected backup succeeded, else the last failure.
 */

import { cursor } from 'uci';
import { access } from 'fs';
import * as log from 'log';
// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/pbs/helper.uc
import * as pbs from 'pbs.helper';

const CONFIG = 'qemu';

let ctx = cursor();
if (!ctx)
	die('qemu-backup: cannot open uci\n');

let only = ARGV[0];
let host = pbs.hostname();
let rc = 0;

/**
 * Back up one instance section.
 *
 * @param {object} inst - instance section from cursor.get_all()
 * @returns {number} exit code (0 when skipped)
 */
function backup_instance(inst) {
	let name = inst['.name'];
	let deps = pbs.default_deps(log, `qemu.${name}`);

	if (inst.backup != '1') {
		if (only)
			deps.logger.warn(`backup is not enabled for this instance`);
		return 0;
	}

	let server = inst.backup_server ?? '';
	let srv = pbs.server_config(ctx.get_all(CONFIG, server), CONFIG, server);
	if (srv.error) {
		deps.logger.err(`pbs client unconfigured: ${srv.error}`);
		return 2;
	}

	let root_disk = inst.root_disk ?? '';
	if (root_disk == '' || !access(root_disk)) {
		deps.logger.err(`root disk: ${root_disk}: does not exist`);
		return 2;
	}

	let backup_id = inst.backup_id ?? `${host}-vm-${name}`;
	let args = [ 'backup', '--backup-type', 'vm', '--backup-id', backup_id ];

	if (srv.namespace != '')
		push(args, '--ns', srv.namespace);

	/* TODO: support multiple drives; ideally back up an LVM snapshot taken
	 * while the guest filesystems are frozen through the guest agent */
	push(args, `disk0.img:${root_disk}`);
	if (inst.uefi_code)
		push(args, `pflash0_code.img:${inst.uefi_code}`);
	if (inst.uefi_vars)
		push(args, `pflash0_efivars.img:${inst.uefi_vars}`);

	return pbs.run_job(deps, {
		name: `${host} ${backup_id}`,
		srv: srv,
		args: args,
		hc_url: inst.hc_ping_url,
	});
}

let found = false;

ctx.foreach(CONFIG, 'instance', (inst) => {
	if (only && inst['.name'] != only)
		return;

	found = true;

	let r = backup_instance(inst);
	if (r != 0)
		rc = r;
});

if (only && !found) {
	warn(`qemu-backup: no instance '${only}' in /etc/config/${CONFIG}\n`);
	exit(2);
}

exit(rc);
