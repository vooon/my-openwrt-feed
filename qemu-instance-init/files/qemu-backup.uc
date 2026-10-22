#!/usr/bin/ucode
'use strict';

/* qemu-backup - back up QEMU instances from /etc/config/qemu to Proxmox
 * Backup Server (`/etc/init.d/qemu backup [instance]` runs this).
 *
 * Usage: qemu-backup [instance]
 *        qemu-backup --recover <instance>
 *
 * Every instance with `option backup '1'` (or just the named one) is backed
 * up as `--backup-type vm --backup-id <backup_id>` with disk0.img and the
 * optional pflash images, and reported to Healthchecks (per-instance
 * hc_ping_url) and Gotify (backup_server section) via pbs.helper. Output goes
 * to syslog as qemu.<instance> (stderr when run on a terminal).
 *
 * While a running instance is backed up, its disk is kept consistent (see
 * qemu.backup): guest filesystems frozen through qemu-guest-agent
 * (backup_fsfreeze, default: guest_agent) around a snapshot
 * (backup_snapshot, default on): an LVM snapshot LV for LVM disks
 * (backup_snapshot_size, default 10%ORIGIN; needs kmod-dm-snapshot), a QEMU
 * qcow2 overlay for qcow2 disks (backup_snapshot_dir, default the disk's
 * directory).
 *
 * --recover merges a snapshot overlay left behind by an interrupted backup
 * (qemu.init runs it before starting the instance).
 *
 * Exit code: 0 when every selected backup succeeded, else the last failure.
 */

import { cursor } from 'uci';
import { access, readfile, unlink, dirname, popen } from 'fs';
import * as log from 'log';
// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/pbs/helper.uc
import * as pbs from 'pbs.helper';
// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/qemu/qmp.uc
import * as qmp from 'qemu.qmp';
// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/qemu/backup.uc
import { consistent_backup, recover } from 'qemu.backup';

const CONFIG = 'qemu';

let ctx = cursor();
if (!ctx)
	die('qemu-backup: cannot open uci\n');

let recover_mode = ARGV[0] == '--recover';
let only = recover_mode ? ARGV[1] : ARGV[0];

if (recover_mode && !only) {
	warn('usage: qemu-backup --recover <instance>\n');
	exit(2);
}
let host = pbs.hostname();
let rc = 0;

/**
 * Whether the instance's QEMU process is running.
 *
 * @param {string} name - instance name
 * @returns {boolean}
 */
function is_running(name) {
	let pid = trim(readfile(`/var/run/qemu.${name}.pid`) ?? '');

	return pid != '' && access(`/proc/${pid}`) == true;
}

/**
 * uci boolean option with a default.
 *
 * @param {any} v - option value
 * @param {boolean} dflt
 * @returns {boolean}
 */
function bool(v, dflt) {
	if (v == null || v == '')
		return dflt;

	return v == '1' || v == 'on' || v == 'yes' || v == 'true';
}

/**
 * Consistency plan (see qemu.backup) for an instance.
 *
 * @param {object} inst - instance section
 * @returns {object}
 */
function consistency_plan(inst) {
	let name = inst['.name'];
	let root_disk = inst.root_disk ?? '';
	let lvm = (inst.root_disk_type ?? 'qcow2') == 'lvm';
	let snap_dir = lvm ? null : (inst.backup_snapshot_dir ?? dirname(root_disk));

	return {
		running: is_running(name),
		qmp_socket: inst.qmp_socket ?? `/var/run/qemu.${name}.qmp.sock`,
		agent_socket: inst.guest_agent_socket ?? `/var/run/qemu.${name}.qga.sock`,
		fsfreeze: bool(inst.backup_fsfreeze, bool(inst.guest_agent, false)),
		snapshot: bool(inst.backup_snapshot, true),
		method: lvm ? 'lvm' : 'overlay',
		disk: root_disk,
		snapshot_size: inst.backup_snapshot_size ?? '10%ORIGIN',
		device: 'root-img',	/* -drive id= in qemu.init */
		overlay: snap_dir ? `${snap_dir}/${name}.pbs-overlay.qcow2` : null,
	};
}

/**
 * Real dependencies of qemu.backup.
 *
 * @param {object} logger
 * @returns {object}
 */
function consistency_deps(logger) {
	return {
		qmp_open: (path) => qmp.open(path, 10000),
		agent_open: (path) => qmp.agent_open(path, 5000),
		exists: (path) => access(path) == true,
		unlink: (path) => unlink(path) == true,
		offline_commit: (path) => system([ 'qemu-img', 'commit', '-q', path ]) == 0,
		lvm: (args) => {
			/* ucode keeps its source files open across popen(); lvm
			 * would report each inherited descriptor on stderr */
			let cmd = 'LVM_SUPPRESS_FD_WARNINGS=1 lvm';
			for (let a in args)
				cmd += ' ' + pbs.shellquote(a);

			let p = popen(cmd + ' 2>&1', 'r');
			let out = p ? (p.read('all') ?? '') : '';
			let code = p ? (p.close() ?? 1) : 127;

			logger.info(`lvm ${join(' ', args)}: rc=${code}`);
			return { rc: code, out };
		},
		sleep: sleep,
		logger: logger,
	};
}

/**
 * Merge a leftover snapshot overlay of one instance.
 *
 * @param {object} inst - instance section
 * @returns {number} exit code
 */
function recover_instance(inst) {
	let deps = pbs.default_deps(log, `qemu.${inst['.name']}`);
	let err = recover(consistency_deps(deps.logger), consistency_plan(inst));

	if (err) {
		deps.logger.err(`recovery failed: ${err}`);
		return 1;
	}

	return 0;
}

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

	/* proxmox-backup-client arguments, reading disk0 from `disk` */
	let args_for = (disk) => {
		let args = [ 'backup', '--backup-type', 'vm', '--backup-id', backup_id ];

		if (srv.namespace != '')
			push(args, '--ns', srv.namespace);

		/* TODO: support multiple drives */
		push(args, `disk0.img:${disk}`);
		if (inst.uefi_code)
			push(args, `pflash0_code.img:${inst.uefi_code}`);
		if (inst.uefi_vars)
			push(args, `pflash0_efivars.img:${inst.uefi_vars}`);

		return args;
	};

	let plan = consistency_plan(inst);
	let cdeps = consistency_deps(deps.logger);

	return pbs.run_job(deps, {
		name: `${host} ${backup_id}`,
		srv: srv,
		args: args_for(root_disk),
		hc_url: inst.hc_ping_url,
		wrap: (run) => {
			let res;
			/* path: the snapshot LV to read instead of the disk, or null */
			let c = consistent_backup(cdeps, plan, (path) => {
				res = run(path ? args_for(path) : null);
				return res.rc;
			});

			res ??= { rc: c.rc, report: '' };
			res.rc = c.rc;
			res.notes = c.notes;
			return res;
		},
	});
}

let found = false;

ctx.foreach(CONFIG, 'instance', (inst) => {
	if (only && inst['.name'] != only)
		return;

	found = true;

	let r = recover_mode ? recover_instance(inst) : backup_instance(inst);
	if (r != 0)
		rc = r;
});

if (only && !found) {
	warn(`qemu-backup: no instance '${only}' in /etc/config/${CONFIG}\n`);
	exit(2);
}

exit(rc);
