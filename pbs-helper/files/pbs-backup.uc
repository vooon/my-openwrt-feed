#!/usr/bin/ucode
'use strict';

/* pbs-backup - back up this host's filesystem to Proxmox Backup Server.
 *
 * Reads /etc/config/pbs (section 'pbs_server'), runs
 *   proxmox-backup-client backup [--ns NS] <backup_name>.pxar:<prefix> \
 *       [backup_arg ...] [ARGV ...]
 * and reports to Healthchecks / Gotify (see pbs.helper). Output goes to
 * syslog (stderr when run on a terminal). Exit code: the backup's rc, or 1
 * when the backup worked but a configured notification failed.
 */

import { cursor } from 'uci';
import * as log from 'log';
// ucode-lsp disable-next-line UC3002   # installed as /usr/share/ucode/pbs/helper.uc
import * as pbs from 'pbs.helper';

const CONFIG = 'pbs';
const SECTION = 'pbs_server';

let deps = pbs.default_deps(log, 'pbs-backup');
let ctx = cursor();
let s = ctx ? ctx.get_all(CONFIG, SECTION) : null;

if (type(s) != 'object') {
	deps.logger.err(`missing '${SECTION}' section in /etc/config/${CONFIG}`);
	exit(2);
}

if (s.enabled != '1') {
	deps.logger.warn(`disabled in /etc/config/${CONFIG} (option enabled '1')`);
	exit(0);
}

let srv = pbs.server_config(s, CONFIG, SECTION);
if (srv.error) {
	deps.logger.err(srv.error);
	exit(2);
}

let backup_name = s.backup_name ?? 'rootfs';
let args = [ 'backup' ];

if (srv.namespace != '')
	push(args, '--ns', srv.namespace);

push(args, `${backup_name}.pxar:${s.prefix ?? '/'}`);

/* one proxmox-backup-client argument per list entry */
let extra = s.backup_arg;
if (type(extra) == 'string')
	extra = [ extra ];
if (type(extra) == 'array')
	push(args, ...extra);

push(args, ...ARGV);

exit(pbs.run_job(deps, {
	name: `${pbs.hostname()} ${backup_name}`,
	srv: srv,
	args: args,
	hc_url: s.hc_ping_url,
}));
