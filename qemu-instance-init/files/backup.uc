'use strict';

/* qemu.backup - make a running VM's disk stable while it is backed up
 * (installed as /usr/share/ucode/qemu/backup.uc, qemu-instance-init-pbs).
 *
 * consistent_backup(deps, plan, backup):
 *   1. fsfreeze  guest-fsfreeze-freeze through qemu-guest-agent (flushes the
 *                guest page cache and blocks writes)
 *   2. snapshot  LVM disks: `lvcreate -s` (needs kmod-dm-snapshot);
 *                qcow2 disks: QMP blockdev-snapshot-sync, guest writes go
 *                to a temporary qcow2 overlay, the base file stops changing
 *   3. thaw      right away, so the guest is frozen only for step 2
 *   4. backup()  reads the snapshot LV / the (now static) base file
 *   5. cleanup   LVM: lvremove; qcow2: block-commit the overlay back,
 *                block-job-complete pivots to the base, overlay deleted
 *
 * Without a snapshot, fsfreeze degrades to a freeze+thaw flush before the
 * live disk is read. Every step is best effort except the clean-up: thaw is
 * always attempted after a freeze, the commit always runs after a snapshot
 * (also when the backup failed), and the overlay is never deleted unless the
 * commit completed.
 *
 * recover() merges an overlay left behind (backup killed, or the VM stopped
 * during a backup): online through QMP when the VM runs on it, offline with
 * `qemu-img commit` when it is stopped. qemu.init runs it before start;
 * consistent_backup() runs it before taking a new snapshot.
 *
 * The QMP connection is closed while backup() runs: QEMU serves one QMP
 * client at a time, and `/etc/init.d/qemu stop` must still reach it.
 *
 * Side effects go through deps (qmp_open, agent_open, exists, unlink, sleep,
 * offline_commit, lvm, logger), so the flow is testable without QEMU.
 */

const JOB = 'pbs-commit';

/**
 * Freeze the guest filesystems. Thaws a stale freeze first.
 *
 * @param {object} agent - guest agent client
 * @param {object} logger
 * @param {string[]} notes
 * @returns {boolean} frozen
 */
function freeze(agent, logger, notes) {
	let st = agent.execute('guest-fsfreeze-status');
	if (st.ok && st.return == 'frozen') {
		logger.warn('guest filesystems were left frozen, thawing first');
		agent.execute('guest-fsfreeze-thaw');
	}

	let r = agent.execute('guest-fsfreeze-freeze');
	if (!r.ok) {
		push(notes, `fsfreeze failed, guest caches not flushed: ${r.error}`);
		logger.warn(`fsfreeze failed: ${r.error}`);
		return false;
	}

	logger.info(`froze ${r.return} guest filesystem(s)`);
	return true;
}

/**
 * Thaw the guest filesystems, retrying.
 *
 * @param {object} agent - guest agent client
 * @param {object} deps
 * @param {string[]} notes
 * @returns {boolean}
 */
function thaw(agent, deps, notes) {
	let r;

	for (let i = 0; i < 5; i++) {
		if (i > 0)
			deps.sleep(1000);

		r = agent.execute('guest-fsfreeze-thaw');
		if (r.ok) {
			deps.logger.info(`thawed ${r.return} guest filesystem(s)`);
			return true;
		}
	}

	push(notes, `ERROR: guest filesystems may still be frozen, thaw failed: ${r?.error}`);
	deps.logger.err(`thaw failed: ${r?.error}`);
	return false;
}

/**
 * State of our commit job, or null when it no longer exists.
 *
 * @param {object} q - QMP client
 * @returns {object} { job } / { error }
 */
function commit_job(q) {
	let r = q.execute('query-block-jobs');
	if (!r.ok)
		return { error: r.error };

	for (let j in r.return ?? [])
		if (j?.device == JOB)
			return { job: j };

	return { job: null };
}

/**
 * Merge the overlay back into the base disk and pivot to it.
 *
 * @param {object} q - QMP client
 * @param {object} deps
 * @param {object} plan
 * @returns {string} error, or '' on success
 */
function commit(q, deps, plan) {
	let r = q.execute('block-commit', { device: plan.device, 'job-id': JOB });
	if (!r.ok)
		return `block-commit: ${r.error}`;

	let waited = 0, limit = plan.commit_timeout_s ?? 3600;

	/* active commit: wait for "ready" (overlay drained), then pivot */
	for (;;) {
		let s = commit_job(q);
		if (s.error)
			return `query-block-jobs: ${s.error}`;
		if (s.job == null)
			return 'commit job vanished before it was ready';
		if (s.job.ready)
			break;
		if (++waited > limit)
			return `commit not ready after ${limit} s`;
		deps.sleep(1000);
	}

	r = q.execute('block-job-complete', { device: JOB });
	if (!r.ok)
		return `block-job-complete: ${r.error}`;

	for (waited = 0; ; waited++) {
		let s = commit_job(q);
		if (s.error)
			return `query-block-jobs: ${s.error}`;
		if (s.job == null)
			break;
		if (waited > 600)
			return 'commit did not finish after pivot';
		deps.sleep(1000);
	}

	return '';
}

/**
 * Name of the backup snapshot LV of an origin LV.
 *
 * @param {string} lv
 * @returns {string}
 */
function snap_name(lv) {
	return `${lv}-pbs-snap`;
}

/**
 * Trimmed output of a deps.lvm() result ('' when missing).
 *
 * @param {any} r
 * @returns {string}
 */
function out_of(r) {
	let o = r?.out;

	return type(o) == 'string' ? trim(o) : '';
}

/**
 * Resolve the VG and LV of a disk path through `lvs`.
 *
 * @param {object} deps
 * @param {string} disk - e.g. /dev/vg0/vm-unifi
 * @returns {object} { vg, lv } / { error }
 */
function lvm_origin(deps, disk) {
	let r = deps.lvm([ 'lvs', '--noheadings', '--separator', '|', '-o', 'vg_name,lv_name', disk ]);
	let m = match(out_of(r), /^\s*([^|\s]+)\s*\|\s*([^|\s]+)\s*$/);

	if (r.rc != 0 || !m)
		return { error: `lvs ${disk}: ${out_of(r)}` };

	// ucode-lsp disable-next-line nullable-argument   # both groups matched
	return { vg: m[1], lv: m[2] };
}

/**
 * Remove the backup snapshot LV (no-op when absent).
 *
 * @param {object} deps
 * @param {object} o - { vg, lv } of the origin
 * @returns {string} error, or ''
 */
function lvm_remove(deps, o) {
	let name = snap_name(o.lv);

	if (!deps.exists(`/dev/${o.vg}/${name}`))
		return '';

	let r;
	for (let i = 0; i < 3; i++) {
		if (i > 0)
			deps.sleep(2000);

		r = deps.lvm([ 'lvremove', '-f', `${o.vg}/${name}` ]);
		if (r.rc == 0)
			return '';
	}

	return `lvremove ${o.vg}/${name}: ${out_of(r)}`;
}

/**
 * Create the backup snapshot LV.
 *
 * @param {object} deps
 * @param {object} o - { vg, lv } of the origin
 * @param {string} size - lvcreate size: '10%ORIGIN' (-l) or '2G' (-L)
 * @returns {object} { path } / { error }
 */
function lvm_create(deps, o, size) {
	let name = snap_name(o.lv);
	let r = deps.lvm([ 'lvcreate', '-s', '-n', name,
		index(size, '%') >= 0 ? '-l' : '-L', size, `${o.vg}/${o.lv}` ]);

	if (r.rc != 0)
		return { error: `lvcreate: ${out_of(r)}` };

	return { path: `/dev/${o.vg}/${name}` };
}

/**
 * Active image file of a block device.
 *
 * @param {object} q - QMP client
 * @param {string} device
 * @returns {object} { file } / { error }
 */
function active_file(q, device) {
	let r = q.execute('query-block');
	if (!r.ok)
		return { error: r.error };

	for (let b in r.return ?? [])
		if (b?.device == device)
			return { file: b?.inserted?.file };

	return { error: `no block device ${device}` };
}

/**
 * Merge a leftover overlay back into the base disk (no-op without one).
 *
 * @param {object} deps
 * @param {object} plan - see consistent_backup(); `running` is required
 * @returns {string} error, or '' when there is nothing (left) to do
 */
export function recover(deps, plan) {
	if (!plan.overlay || !deps.exists(plan.overlay))
		return '';

	let log = deps.logger;

	if (!plan.running) {
		log.warn(`committing leftover ${plan.overlay} into the base disk (offline)`);
		if (!deps.offline_commit(plan.overlay))
			return `qemu-img commit ${plan.overlay} failed`;
	}
	else {
		let q = deps.qmp_open(plan.qmp_socket);
		if (q.error)
			return `QMP: ${q.error}`;

		let a = active_file(q, plan.device);
		if (a.error) {
			q.close();
			return `query-block: ${a.error}`;
		}

		if (a.file != plan.overlay) {
			q.close();
			return `${plan.overlay} exists but ${plan.device} runs on ${a.file}: not touching it`;
		}

		log.warn(`VM still runs on leftover ${plan.overlay}, committing it`);
		let err = commit(q, deps, plan);
		q.close();
		if (err)
			return err;
	}

	if (!deps.unlink(plan.overlay))
		return `could not remove ${plan.overlay}`;

	log.info(`leftover ${plan.overlay} committed and removed`);
	return '';
};

/**
 * Run backup() with the instance's disk made consistent as far as possible.
 *
 * plan: {
 *   running      - the VM is running (else backup() runs directly)
 *   qmp_socket   - QMP socket path
 *   agent_socket - guest agent socket path (fsfreeze)
 *   fsfreeze     - freeze guest filesystems through the agent
 *   snapshot     - take a snapshot for the backup
 *   method       - 'lvm' (snapshot LV) or 'overlay' (QEMU qcow2 overlay)
 *   disk         - the disk path (LVM: the origin LV)
 *   snapshot_size - LVM snapshot size for lvcreate (default 10%ORIGIN)
 *   device       - QEMU block device name of the disk (root-img)
 *   overlay      - path of the temporary qcow2 overlay (method overlay)
 * }
 *
 * @param {object} deps - { qmp_open, agent_open, exists, unlink, sleep, lvm,
 *                          offline_commit, logger }
 * @param {object} plan
 * @param {function} backup - backup(path): runs the backup reading `path`
 *                            (null: the disk itself), returns its exit code
 * @returns {object} { rc, notes }
 */
export function consistent_backup(deps, plan, backup) {
	let notes = [];
	let log = deps.logger;
	let err = '';

	if (!plan.running) {
		log.info('instance is not running, backing up the disk as is');
		return { rc: backup(null), notes };
	}

	let q = null, origin = null;
	if (plan.snapshot && plan.method == 'lvm') {
		origin = lvm_origin(deps, plan.disk);
		if (origin.error) {
			push(notes, `snapshot skipped: ${origin.error}`);
			origin = null;
		}
		else if ((err = lvm_remove(deps, origin)) != '') {
			push(notes, `snapshot skipped: stale snapshot: ${err}`);
			origin = null;
		}
	}
	else if (plan.snapshot) {
		if (!plan.overlay) {
			push(notes, 'snapshot skipped: no backup_snapshot_dir for this disk, backing up the live disk');
		}
		else if (deps.exists(plan.overlay) && (err = recover(deps, plan)) != '') {
			push(notes, `snapshot skipped: leftover overlay: ${err}`);
		}
		else {
			q = deps.qmp_open(plan.qmp_socket);
			if (q.error) {
				push(notes, `snapshot skipped: QMP: ${q.error}`);
				q = null;
			}
		}
	}

	let agent = null, frozen = false;
	if (plan.fsfreeze) {
		agent = deps.agent_open(plan.agent_socket);
		if (agent.error) {
			push(notes, `fsfreeze skipped: ${agent.error}`);
			agent = null;
		}
		else {
			/* freezing flushes all dirty data: allow it time */
			agent.set_timeout(60000);
			frozen = freeze(agent, log, notes);
			agent.set_timeout(10000);
		}
	}

	let snapped = false, snap_path = null;
	if (origin) {
		let r = lvm_create(deps, origin, plan.snapshot_size ?? '10%ORIGIN');

		if (r.error)
			push(notes, `snapshot failed, backing up the live disk: ${r.error}`);
		else {
			snapped = true;
			snap_path = r.path;
			log.info(`backing up LVM snapshot ${snap_path}`);
		}
	}
	else if (q) {
		let r = q.execute('blockdev-snapshot-sync', {
			device: plan.device,
			'snapshot-file': plan.overlay,
			format: 'qcow2',
		});

		if (r.ok) {
			snapped = true;
			log.info(`guest writes redirected to ${plan.overlay}`);
		}
		else
			push(notes, `snapshot failed, backing up the live disk: ${r.error}`);
	}

	let thaw_failed = frozen && !thaw(agent, deps, notes);
	agent?.close();

	q?.close();
	q = null;

	if (!snapped && !frozen)
		log.warn('backing up the live disk (crash-consistent at best)');

	let rc = backup(snap_path);

	if (snapped && origin) {
		err = lvm_remove(deps, origin);
		if (err)
			push(notes, `could not remove the snapshot (removed on the next backup): ${err}`);
	}
	else if (snapped) {
		err = '';

		for (let i = 0; i < 10; i++) {
			if (i > 0)
				deps.sleep(3000);

			q = deps.qmp_open(plan.qmp_socket);
			if (!q.error)
				break;

			err = `QMP: ${q.error}`;
			q = null;
		}

		if (q)
			err = commit(q, deps, plan);

		if (err) {
			push(notes, `ERROR: commit of ${plan.overlay} failed, the VM still writes to it ` +
				`(committed on the next backup or start): ${err}`);
			log.err(`commit failed: ${err}`);
			if (rc == 0)
				rc = 3;
		}
		else {
			log.info('overlay committed back into the base disk');
			if (!deps.unlink(plan.overlay))
				push(notes, `could not remove ${plan.overlay}`);
		}
	}

	q?.close();

	if (thaw_failed && rc == 0)
		rc = 4;

	for (let n in notes)
		log.warn(n);

	return { rc, notes };
};
