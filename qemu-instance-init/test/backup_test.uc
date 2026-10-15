'use strict';

/*
 * qemu.backup (files/backup.uc) tests: the fsfreeze / overlay snapshot /
 * commit flow against fake QMP and guest agent clients that record every
 * call into one ordered event log.
 */

import { describe, it, assert } from 'utest';
import { consistent_backup, recover } from '../files/backup.uc';

const OVERLAY = '/srv/vm/haos.pbs-overlay.qcow2';
const OK = { ok: true, return: {} };

let events = [], notes_logged = [];

/**
 * Whether a value is a string containing `needle`.
 * @param {any} s
 * @param {string} needle
 * @returns {boolean}
 */
function has(s, needle) {
	return type(s) == 'string' && index(s, needle) >= 0;
}

/**
 * Fake QMP / agent client. `script` maps a command to a result, or to an
 * array of results returned in order (the last one repeats).
 * @param {string} who - event prefix
 * @param {object} script
 * @returns {object}
 */
function fake_client(who, script) {
	return {
		execute: (cmd, args) => {
			push(events, `${who}:${cmd}`);

			let r = script[cmd];
			if (type(r) == 'array')
				return length(r) > 1 ? shift(r) : r[0];

			return r ?? OK;
		},
		set_timeout: () => null,
		close: () => { push(events, `${who}:close`); },
	};
}

/**
 * Dependencies with fake clients.
 * @param {object} [o] - { qmp, agent, qmp_error, agent_error, exists, unlink, offline, lvm }
 * @returns {object}
 */
function deps(o) {
	o ??= {};
	events = [];
	notes_logged = [];

	let log = (lvl) => (m) => { if (lvl == 'warn') push(notes_logged, m); };

	return {
		qmp_open: () => {
			push(events, 'qmp:open');
			return o.qmp_error ? { error: o.qmp_error } : fake_client('qmp', o.qmp ?? {});
		},
		agent_open: () => {
			push(events, 'agent:open');
			return o.agent_error ? { error: o.agent_error } : fake_client('agent', o.agent ?? {});
		},
		exists: () => type(o.exists) == 'array' ? (length(o.exists) > 1 ? shift(o.exists) : o.exists[0]) : (o.exists ?? false),
		offline_commit: (p) => { push(events, `qemu-img-commit:${p}`); return o.offline ?? true; },
		lvm: (args) => {
			push(events, `lvm:${join(' ', args)}`);

			let r = o.lvm?.[args[0]];
			if (type(r) == 'array')
				return length(r) > 1 ? shift(r) : r[0];

			return r ?? { rc: 0, out: '' };
		},
		unlink: (p) => { push(events, `unlink:${p}`); return o.unlink ?? true; },
		sleep: () => null,
		logger: { info: log('info'), note: log('note'), warn: log('warn'), err: log('err') },
	};
}

/**
 * Plan for a running instance.
 * @param {object} [o] - overrides
 * @returns {object}
 */
function plan(o) {
	return {
		running: true,
		qmp_socket: '/var/run/qemu.haos.qmp.sock',
		agent_socket: '/var/run/qemu.haos.qga.sock',
		fsfreeze: true,
		snapshot: true,
		device: 'root-img',
		overlay: OVERLAY,
		...(o ?? {}),
	};
}

/**
 * A backup callback recording itself (and the path it was asked to read,
 * when not the disk itself) and returning `rc`.
 * @param {number} rc
 * @returns {function}
 */
function backup(rc) {
	return (path) => {
		push(events, path ? `backup:${path}` : 'backup');
		return rc;
	};
}

/* query-block-jobs: running, then ready, then gone after the pivot */
const JOBS = [
	{ ok: true, return: [ { device: 'pbs-commit', ready: false } ] },
	{ ok: true, return: [ { device: 'pbs-commit', ready: true } ] },
	{ ok: true, return: [] },
];

const FROZEN_STATUS = { 'guest-fsfreeze-status': { ok: true, return: 'thawed' },
	'guest-fsfreeze-freeze': { ok: true, return: 2 }, 'guest-fsfreeze-thaw': { ok: true, return: 2 } };

describe('consistent_backup', () => {
	it('stopped instance: backs up directly', () => {
		let d = deps();
		let r = consistent_backup(d, plan({ running: false }), backup(0));

		assert.match({ rc: 0, notes: [] }, r);
		assert.match([ 'backup' ], events);
	});

	it('freeze, snapshot, thaw, backup, commit, pivot, remove overlay', () => {
		let d = deps({ agent: { ...FROZEN_STATUS }, qmp: { 'query-block-jobs': [ ...JOBS ] } });
		let r = consistent_backup(d, plan(), backup(0));

		assert.match({ rc: 0, notes: [] }, r);
		assert.match([
			'qmp:open',
			'agent:open', 'agent:guest-fsfreeze-status', 'agent:guest-fsfreeze-freeze',
			'qmp:blockdev-snapshot-sync',
			'agent:guest-fsfreeze-thaw', 'agent:close',
			'qmp:close',	/* not held during the backup */
			'backup',
			'qmp:open',
			'qmp:block-commit', 'qmp:query-block-jobs', 'qmp:query-block-jobs',
			'qmp:block-job-complete', 'qmp:query-block-jobs',
			`unlink:${OVERLAY}`, 'qmp:close',
		], events);
	});

	it('thaws a stale freeze before freezing', () => {
		let d = deps({ agent: { ...FROZEN_STATUS, 'guest-fsfreeze-status': { ok: true, return: 'frozen' } },
			qmp: { 'query-block-jobs': [ ...JOBS ] } });

		consistent_backup(d, plan(), backup(0));
		assert.match([ 'agent:open', 'agent:guest-fsfreeze-status', 'agent:guest-fsfreeze-thaw',
			'agent:guest-fsfreeze-freeze' ], slice(filter(events, (e) => has(e, 'agent:')), 0, 4));
	});

	it('fsfreeze without snapshot: freeze+thaw flush, then live backup', () => {
		let d = deps({ agent: { ...FROZEN_STATUS } });
		let r = consistent_backup(d, plan({ snapshot: false }), backup(0));

		assert.match(0, r.rc);
		assert.match([ 'agent:open', 'agent:guest-fsfreeze-status', 'agent:guest-fsfreeze-freeze',
			'agent:guest-fsfreeze-thaw', 'agent:close', 'backup' ], events);
	});

	it('no guest agent: snapshot still taken, noted', () => {
		let d = deps({ agent_error: 'guest agent not responding: timed out waiting for QEMU',
			qmp: { 'query-block-jobs': [ ...JOBS ] } });
		let r = consistent_backup(d, plan(), backup(0));

		assert.match(0, r.rc);
		assert.match([ 'fsfreeze skipped: guest agent not responding: timed out waiting for QEMU' ], r.notes);
		assert.match(true, index(events, 'qmp:blockdev-snapshot-sync') >= 0);
	});

	it('snapshot fails: thaws, backs up the live disk, no commit', () => {
		let d = deps({ agent: { ...FROZEN_STATUS },
			qmp: { 'blockdev-snapshot-sync': { ok: false, error: 'GenericError: Could not create file' } } });
		let r = consistent_backup(d, plan(), backup(0));

		assert.match(0, r.rc);
		assert.match([ 'snapshot failed, backing up the live disk: GenericError: Could not create file' ], r.notes);
		assert.match(true, index(events, 'agent:guest-fsfreeze-thaw') >= 0);
		assert.match(-1, index(events, 'qmp:block-commit'));
	});

	it('failed backup still commits and removes the overlay', () => {
		let d = deps({ qmp: { 'query-block-jobs': [ ...JOBS ] } });
		let r = consistent_backup(d, plan({ fsfreeze: false }), backup(5));

		assert.match(5, r.rc);
		assert.match(true, index(events, 'qmp:block-job-complete') > index(events, 'backup'));
		assert.match(true, index(events, `unlink:${OVERLAY}`) >= 0);
	});

	it('commit failure: rc 3, overlay kept, loud note', () => {
		let d = deps({ qmp: { 'block-commit': { ok: false, error: 'GenericError: Device is busy' } } });
		let r = consistent_backup(d, plan({ fsfreeze: false }), backup(0));

		assert.match(3, r.rc);
		assert.match(-1, index(events, `unlink:${OVERLAY}`));
		assert.match([ `ERROR: commit of ${OVERLAY} failed, the VM still writes to it (committed on the next backup or start): block-commit: GenericError: Device is busy` ],
			r.notes);
	});

	it('QMP unreachable for the commit: retried, overlay kept', () => {
		let d = deps({ qmp: {} });
		let opens = 0;

		d.qmp_open = () => {
			push(events, 'qmp:open');
			return ++opens == 1 ? { execute: () => OK, close: () => null } : { error: 'cannot connect' };
		};

		let r = consistent_backup(d, plan({ fsfreeze: false }), backup(0));

		assert.match(3, r.rc);
		assert.match(11, opens);
		assert.match(-1, index(events, `unlink:${OVERLAY}`));
		assert.match(true, has(r.notes[0], 'QMP: cannot connect'), r.notes);
	});

	it('thaw failure: retried, rc 4', () => {
		let d = deps({ agent: { ...FROZEN_STATUS, 'guest-fsfreeze-thaw': { ok: false, error: 'timed out waiting for QEMU' } },
			qmp: { 'query-block-jobs': [ ...JOBS ] } });
		let r = consistent_backup(d, plan(), backup(0));

		assert.match(4, r.rc);
		assert.match(5, length(filter(events, (e) => e == 'agent:guest-fsfreeze-thaw')));
		assert.match([ 'ERROR: guest filesystems may still be frozen, thaw failed: timed out waiting for QEMU' ], r.notes);
	});

	it('leftover overlay in use: committed first, then a fresh snapshot', () => {
		let d = deps({ exists: [ true, true, false ], qmp: {
			'query-block': { ok: true, return: [ { device: 'root-img', inserted: { file: OVERLAY } } ] },
			'query-block-jobs': [ ...JOBS, ...JOBS ],
		} });
		let r = consistent_backup(d, plan({ fsfreeze: false }), backup(0));

		assert.match({ rc: 0, notes: [] }, r);
		assert.match(2, length(filter(events, (e) => e == 'qmp:block-commit')));
		assert.match(true, index(events, 'qmp:blockdev-snapshot-sync') > index(events, `unlink:${OVERLAY}`));
	});

	it('leftover overlay not in use: never touched, live backup', () => {
		let d = deps({ exists: true, qmp: {
			'query-block': { ok: true, return: [ { device: 'root-img', inserted: { file: '/srv/vm/haos.qcow2' } } ] },
		} });
		let r = consistent_backup(d, plan({ fsfreeze: false }), backup(0));

		assert.match(0, r.rc);
		assert.match(-1, index(events, `unlink:${OVERLAY}`));
		assert.match(-1, index(events, 'qmp:blockdev-snapshot-sync'));
		assert.match(true, has(r.notes[0], 'not touching it'), r.notes);
	});

	it('LVM disk without backup_snapshot_dir: live backup, noted', () => {
		let d = deps();
		let r = consistent_backup(d, plan({ fsfreeze: false, overlay: null }), backup(0));

		assert.match([ 'backup' ], events);
		assert.match([ 'snapshot skipped: no backup_snapshot_dir for this disk, backing up the live disk' ], r.notes);
	});

	it('notes are logged as warnings', () => {
		let d = deps({ qmp_error: 'cannot connect' });

		consistent_backup(d, plan({ fsfreeze: false }), backup(0));
		assert.match([ 'backing up the live disk (crash-consistent at best)', 'snapshot skipped: QMP: cannot connect' ],
			notes_logged);
	});
});

describe('recover', () => {
	it('nothing to do without an overlay', () => {
		let d = deps({ exists: false });

		assert.match('', recover(d, plan({ running: false })));
		assert.match([], events);
	});

	it('stopped instance: qemu-img commit, then remove', () => {
		let d = deps({ exists: true });

		assert.match('', recover(d, plan({ running: false })));
		assert.match([ `qemu-img-commit:${OVERLAY}`, `unlink:${OVERLAY}` ], events);
	});

	it('offline commit failure keeps the overlay', () => {
		let d = deps({ exists: true, offline: false });

		assert.match(`qemu-img commit ${OVERLAY} failed`, recover(d, plan({ running: false })));
		assert.match([ `qemu-img-commit:${OVERLAY}` ], events);
	});

	it('running on the overlay: online commit, then remove', () => {
		let d = deps({ exists: true, qmp: {
			'query-block': { ok: true, return: [ { device: 'root-img', inserted: { file: OVERLAY } } ] },
			'query-block-jobs': [ ...JOBS ],
		} });

		assert.match('', recover(d, plan()));
		assert.match([ 'qmp:open', 'qmp:query-block', 'qmp:block-commit', 'qmp:query-block-jobs',
			'qmp:query-block-jobs', 'qmp:block-job-complete', 'qmp:query-block-jobs', 'qmp:close',
			`unlink:${OVERLAY}` ], events);
	});
});

describe('LVM snapshot', () => {
	const LV = '/dev/vg0/vm-unifi';
	const SNAP = '/dev/vg0/vm-unifi-pbs-snap';
	const LVS = { rc: 0, out: '  vg0|vm-unifi\n' };

	/**
	 * Plan for a running LVM instance.
	 * @param {object} [o]
	 * @returns {object}
	 */
	function lvm_plan(o) {
		return plan({ method: 'lvm', disk: LV, overlay: null, snapshot_size: '10%ORIGIN', ...(o ?? {}) });
	}

	it('freeze, lvcreate, thaw, back up the snapshot, lvremove', () => {
		/* exists: stale snapshot check (no), then removal check (yes) */
		let d = deps({ agent: { ...FROZEN_STATUS }, lvm: { lvs: LVS }, exists: [ false, true ] });
		let r = consistent_backup(d, lvm_plan(), backup(0));

		assert.match({ rc: 0, notes: [] }, r);
		assert.match([
			`lvm:lvs --noheadings --separator | -o vg_name,lv_name ${LV}`,
			'agent:open', 'agent:guest-fsfreeze-status', 'agent:guest-fsfreeze-freeze',
			'lvm:lvcreate -s -n vm-unifi-pbs-snap -l 10%ORIGIN vg0/vm-unifi',
			'agent:guest-fsfreeze-thaw', 'agent:close',
			`backup:${SNAP}`,
			'lvm:lvremove -f vg0/vm-unifi-pbs-snap',
		], events);
	});

	it('absolute size uses -L', () => {
		let d = deps({ lvm: { lvs: LVS } });

		consistent_backup(d, lvm_plan({ fsfreeze: false, snapshot_size: '4G' }), backup(0));
		assert.match(true, index(events, 'lvm:lvcreate -s -n vm-unifi-pbs-snap -L 4G vg0/vm-unifi') >= 0, events);
	});

	it('removes a stale snapshot first', () => {
		let d = deps({ lvm: { lvs: LVS }, exists: [ true, true ] });

		consistent_backup(d, lvm_plan({ fsfreeze: false }), backup(0));
		assert.match([ 'lvm:lvremove -f vg0/vm-unifi-pbs-snap', 'lvm:lvcreate -s -n vm-unifi-pbs-snap -l 10%ORIGIN vg0/vm-unifi' ],
			slice(filter(events, (e) => has(e, 'lvm:lv') && !has(e, 'lvm:lvs')), 0, 2));
	});

	it('lvcreate failure (no dm-snapshot): thaws, backs up the live LV', () => {
		let d = deps({ agent: { ...FROZEN_STATUS }, lvm: { lvs: LVS,
			lvcreate: { rc: 5, out: '  snapshot: Required device-mapper target(s) not detected in your kernel.\n' } } });
		let r = consistent_backup(d, lvm_plan(), backup(0));

		assert.match(0, r.rc);
		assert.match([ 'snapshot failed, backing up the live disk: lvcreate: snapshot: Required device-mapper target(s) not detected in your kernel.' ],
			r.notes);
		assert.match(true, index(events, 'agent:guest-fsfreeze-thaw') >= 0);
		assert.match(true, index(events, 'backup') >= 0);
		assert.match(-1, index(events, 'lvm:lvremove -f vg0/vm-unifi-pbs-snap'));
	});

	it('not an LV: live backup, noted', () => {
		let d = deps({ lvm: { lvs: { rc: 5, out: '  Failed to find logical volume "/srv/x"\n' } } });
		let r = consistent_backup(d, lvm_plan({ fsfreeze: false, disk: '/srv/x' }), backup(0));

		assert.match([ 'backup' ], filter(events, (e) => has(e, 'backup')));
		assert.match([ 'snapshot skipped: lvs /srv/x: Failed to find logical volume "/srv/x"' ], r.notes);
	});

	it('failed backup still removes the snapshot', () => {
		let d = deps({ lvm: { lvs: LVS }, exists: [ false, true ] });
		let r = consistent_backup(d, lvm_plan({ fsfreeze: false }), backup(7));

		assert.match(7, r.rc);
		assert.match(true, index(events, 'lvm:lvremove -f vg0/vm-unifi-pbs-snap') > index(events, `backup:${SNAP}`));
	});

	it('lvremove failure is retried and noted, backup result kept', () => {
		let d = deps({ lvm: { lvs: LVS, lvremove: { rc: 5, out: '  Logical volume vg0/vm-unifi-pbs-snap in use.\n' } },
			exists: [ false, true ] });
		let r = consistent_backup(d, lvm_plan({ fsfreeze: false }), backup(0));

		assert.match(0, r.rc);
		assert.match(3, length(filter(events, (e) => e == 'lvm:lvremove -f vg0/vm-unifi-pbs-snap')));
		assert.match([ 'could not remove the snapshot (removed on the next backup): lvremove vg0/vm-unifi-pbs-snap: Logical volume vg0/vm-unifi-pbs-snap in use.' ],
			r.notes);
	});

	it('no overlay recovery for LVM disks', () => {
		let d = deps({ exists: true });

		assert.match('', recover(d, lvm_plan({ running: false })));
		assert.match([], events);
	});
});
