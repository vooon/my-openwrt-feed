#!/usr/bin/env ucode

// SPDX-License-Identifier: LGPL-2.1+
/*
 * rpcd-mod-bird - expose the BIRD control socket via ubus
 *
 * ucode rpcd plugin replacing the former C plugin.  Registers a single
 * "bird" ubus object:
 *
 *   bird query   - raw "show"/command passthrough, returns { code, stdout }
 *   bird status  - read-only structured snapshot, returns a JSON object
 *                  describing the daemon, protocols, OSPF/BGP/BFD state
 *
 * The BIRD CLI is a line based protocol over a unix socket: on connect BIRD
 * sends a banner, the client sends a command followed by a newline and reads
 * the reply.  Every reply line starts with a four digit code followed by
 * either '-' (more lines) or a space (last line of the reply).
 *
 * The parser regexes intentionally mirror prometheus-node-exporter-ucode's
 * bird.uc (same ucode match()/POSIX engine) and are annotated with links to
 * the BIRD sources that generate the output they parse.
 *
 * Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
 */

'use strict';

import { connect, error as serr } from 'socket';
import { syslog, openlog } from 'log';

const DEFAULT_SOCKET = '/run/bird.ctl';

/* tag our messages with rpcd.bird; rpcd's own logs keep the "rpcd" process
 * tag from procd, so this only affects syslog() calls made by this plugin */
try { openlog('rpcd.bird', 0, 'daemon'); } catch (_) {};

function birdLog(sev, msg) {
	try { syslog(sev, msg); } catch (_) {}
}

//// Raw BIRD socket client (port of the former C bird_socket_query) ////

/* A BIRD reply is terminated by a line starting with a return code
 * (0000-0999, 8000-8999 or 9000-9999).  Returns 1 once such a line is the
 * last complete line of @data. */
function replyComplete(data) {
	/* only consider newline-terminated lines; ignore a trailing partial read */
	let nl = rindex(data, '\n');
	if (nl < 0)
		return false;

	let head = substr(data, 0, nl);
	let prev = rindex(head, '\n');
	let start = (prev < 0) ? 0 : prev + 1;
	let line = substr(data, start, nl - start);

	return line.length >= 4 &&
	       (line[0] == '0' || line[0] == '8' || line[0] == '9') &&
	       line[1] >= '0' && line[1] <= '9' &&
	       line[2] >= '0' && line[2] <= '9' &&
	       line[3] >= '0' && line[3] <= '9' &&
	       (line.length == 4 || line[4] == ' ');
}

/* Strip the per-line "<4 digit code><sep>" prefix and drop the trailing
 * status line.  Returns an array of cleaned lines. */
function cleanReply(data) {
	let res = [];
	let lines = split(data, '\n');

	for (let li = 0; li < length(lines); li++) {
		let line = lines[li];
		if (!line.length)
			continue;

		/* trailing status line starts with a code followed by a space/end */
		if (line.length >= 4 && (line[0] == '0' || line[0] == '8' || line[0] == '9') &&
		    line[1] >= '0' && line[1] <= '9' &&
		    line[2] >= '0' && line[2] <= '9' &&
		    line[3] >= '0' && line[3] <= '9' &&
		    (line.length == 4 || line[4] == ' '))
			break;

		/* strip "<code>-" or "<code> " prefix */
		if (line.length >= 5 && line[0] >= '0' && line[0] <= '9' &&
		    line[1] >= '0' && line[1] <= '9' &&
		    line[2] >= '0' && line[2] <= '9' &&
		    line[3] >= '0' && line[3] <= '9' &&
		    (line[4] == '-' || line[4] == ' '))
			line = substr(line, 5);

		push(res, line);
	}

	return res;
}

/* Connect, send @command, return cleaned reply lines (or null on error). */
function birdRaw(socket, command) {
	let sock = null;

	try {
		sock = connect(socket);

		if (sock == null) {
			birdLog('err', `bird: connect failed cmd='${command}' socket='${socket}': ${serr()}`);
			return null;
		}

		/* discard the banner BIRD sends on connect */
		let data = '';
		for (let i = 0; i < 8; i++) {
			let chunk = sock.recv(4096);
			if (chunk == null || !length(chunk)) {
				birdLog('err', `bird: banner/read failed cmd='${command}' socket='${socket}': ${serr()}`);
				sock.close();
				return null;
			}
			data += chunk;
			if (index(chunk, '\n') >= 0)
				break;
		}

		sock.send(command + '\n');

		let reply = '';
		for (let i = 0; i < 256; i++) {
			let chunk = sock.recv(4096);
			if (chunk == null || !length(chunk))
				break;
			reply += chunk;
			if (replyComplete(reply))
				break;
		}

		sock.close();
		return cleanReply(reply);
	}
	catch (e) {
		birdLog('err', `bird: query failed cmd='${command}' socket='${socket}': ${e} (${serr()})`);
		if (sock) {
			try { sock.close(); } catch (_) {}
		}
		return null;
	}
}

//// Shared value helpers ////

function birdNum(s) {
	if (s == null || s == '---' || !length(s))
		return null;
	return +s;
}

function tsToEpoch(s) {
	let m = match(s, /(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
	if (!m)
		return null;

	let e = timelocal({
		sec: +m[6], min: +m[5], hour: +m[4],
		mday: +m[3], mon: +m[2], year: +m[1],
	});

	return (e == null || e == -1) ? null : e;
}

function uptimeSeconds(s) {
	if (s == null)
		return null;

	let m = match(s, /^(\d+):(\d{2}):(\d{2})$/);
	if (m)
		return (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]);

	if (match(s, /^\d+$/))
		return clock()[0] - (+s);

	let e = tsToEpoch(s);
	return (e != null) ? clock()[0] - e : null;
}

//// Protocol detail parser ////
// Output format generated by nest/proto.c proto_cmd_show()/channel_show_info()
//   summary (cli_msg -2002):  https://github.com/CZ-NIC/bird/blob/master/nest/proto.c#L3021
//   detail (cli_msg -1006):   https://github.com/CZ-NIC/bird/blob/master/nest/proto.c#L2979
//   route totals:             https://github.com/CZ-NIC/bird/blob/master/nest/proto.c#L2938
//   route change stats:       https://github.com/CZ-NIC/bird/blob/master/nest/proto.c#L2944

const GENERIC_PROTOS = ['BGP', 'OSPF', 'Kernel', 'Static', 'Direct', 'Babel', 'RPKI'];

function isGeneric(proto) {
	for (let i = 0; i < length(GENERIC_PROTOS); i++)
		if (GENERIC_PROTOS[i] == proto)
			return true;
	return false;
}

function protoString(proto, ip_version) {
	if (proto == 'OSPF')
		return ip_version == '6' ? 'OSPFv3' : 'OSPF';
	return proto;
}

function newProto(name, proto, up, state, uptime, ip_version) {
	return {
		name: name,
		proto: proto,
		ip_version: ip_version,
		up: up,
		state: state,
		uptime: uptime,
		imported: 0, exported: 0, filtered: 0, preferred: 0,
		import_filter: '', export_filter: '',
		changes: {
			import_updates:   { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
			import_withdraws: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
			export_updates:   { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
			export_withdraws: { received: 0, rejected: 0, filtered: 0, ignored: 0, accepted: 0, rx_limit: 0, limit: 0 },
		},
		v3: false,
		/* optional protocol-specific info (BGP peer, OSPF status) */
		info: '',
	};
}

const protoRe = /^(\S+)[ \t]+(MRT|BGP|BFD|OSPF|RPKI|RIP|RAdv|Pipe|Perf|Direct|Babel|Device|Kernel|Static)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[0-9.]*|\S+)([ \t]+(.*))?$/;
const channelRe = /Channel[ \t]+ipv(4|6)/;
const routeFilteredRe = /^Routes:[ \t]+(\d+)[ \t]+imported,[ \t]+(\d+)[ \t]+filtered,[ \t]+(\d+)[ \t]+exported(,[ \t]+(\d+)[ \t]+preferred)?$/;
const routeSimpleRe = /^Routes:[ \t]+(\d+)[ \t]+imported,[ \t]+(\d+)[ \t]+exported(,[ \t]+(\d+)[ \t]+preferred)?$/;
const routeChangesRe = /^(Import|Export)[ \t]+(updates|withdraws):[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)[ \t]+(\d+|---)([ \t]+(\d+|---)[ \t]+(\d+|---))?$/;
const filterRe = /(Input|Output)[ \t]+filter:[ \t]+(.*)/;

// BGP peer detail (proto/bgp/bgp.c bgp_show_neighbor):
//   https://github.com/CZ-NIC/bird/blob/master/proto/bgp/bgp.c#L4157
const bgpReasonRe = /^BGP state:[ \t]+(\S+)/;
const bgpNeighborRe = /^Neighbor address:[ \t]+(\S+)/;
const bgpAsRe = /^Neighbor AS:[ \t]+(\d+)/;
const bgpLocalAsRe = /^Local AS:[ \t]+(\d+)/;

function parseProtocols(lines) {
	let res = [];
	let cur = null;

	for (let i = 0; i < length(lines); i++) {
		let line = lines[i];
		let l = length(line) ? replace(line, /^[ \t]+/, '') : '';

		if (!length(l)) {
			cur = null;
			continue;
		}

		let m = match(l, protoRe);
		if (m) {
			cur = newProto(m[1], m[2], m[4] == 'up' ? 1 : 0, m[7], uptimeSeconds(m[5]), '');
			cur.info = m[7];
			push(res, cur);
			continue;
		}

		if (!cur)
			continue;

		m = match(l, channelRe);
		if (m) {
			if (length(cur.ip_version)) {
				/* channel split: upstream bird.uc emits one row per channel */
				cur = newProto(cur.name, cur.proto, cur.up, cur.state, cur.uptime, m[1]);
				push(res, cur);
			} else {
				cur.ip_version = m[1];
			}
			continue;
		}

		m = match(l, routeFilteredRe);
		if (m) {
			cur.imported = +m[1]; cur.filtered = +m[2]; cur.exported = +m[3];
			if (m[5] != null)
				cur.preferred = +m[5];
			continue;
		}

		m = match(l, routeSimpleRe);
		if (m) {
			cur.imported = +m[1]; cur.exported = +m[2];
			if (m[4] != null)
				cur.preferred = +m[4];
			continue;
		}

		m = match(l, routeChangesRe);
		if (m) {
			let key = (m[1] == 'Import' ? 'import_' : 'export_') +
			          (m[2] == 'updates' ? 'updates' : 'withdraws');
			let c = cur.changes[key];
			c.received = birdNum(m[3]) || 0;
			c.rejected = birdNum(m[4]) || 0;
			c.filtered = birdNum(m[5]) || 0;
			c.ignored = birdNum(m[6]) || 0;
			if (m[9] != null) {
				c.rx_limit = birdNum(m[7]) || 0;
				c.limit = birdNum(m[9]) || 0;
				c.accepted = birdNum(m[10]) || 0;
				cur.v3 = true;
			} else {
				c.accepted = birdNum(m[7]) || 0;
			}
			continue;
		}

		m = match(l, filterRe);
		if (m) {
			if (m[1] == 'Input')
				cur.import_filter = m[2];
			else
				cur.export_filter = m[2];
			continue;
		}

		// optional BGP peer enrichment
		if (cur.proto == 'BGP') {
			if ((m = match(l, bgpReasonRe)))
				cur.state = m[1];
			else if ((m = match(l, bgpNeighborRe)))
				cur.neighbor = m[1];
			else if ((m = match(l, bgpAsRe)))
				cur.neighbor_as = +m[1];
			else if ((m = match(l, bgpLocalAsRe)))
				cur.local_as = +m[1];
		}
	}

	return res;
}

//// Daemon status parser ////
// "show status" output - see nest/cmds.c / sysdep/unix/unix.c
function parseStatus(lines) {
	let s = { version: null, router_id: null, hostname: null, server_time: null, last_reboot: null, last_reconfig: null };

	for (let i = 0; i < length(lines); i++) {
		let l = lines[i];
		let m;

		if ((m = match(l, /BIRD[ \t]+(\S+)/)))
			s.version = m[1];
		else if ((m = match(l, /Router[ \t]+ID[ \t]+is[ \t]+(\S+)/)))
			s.router_id = m[1];
		else if ((m = match(l, /Hostname[ \t]+is[ \t]+(\S+)/)))
			s.hostname = m[1];
		else if ((m = match(l, /Current[ \t]+server[ \t]+time[ \t]+is[ \t]+(.+)/)))
			s.server_time = tsToEpoch(trim(m[1]));
		else if ((m = match(l, /Last[ \t]+reboot[ \t]+on[ \t]+(.+)/)))
			s.last_reboot = tsToEpoch(trim(m[1]));
		else if ((m = match(l, /Last[ \t]+reconfiguration[ \t]+on[ \t]+(.+)/)))
			s.last_reconfig = tsToEpoch(trim(m[1]));
	}

	return s;
}

//// OSPF parser ////
// "show ospf <name>":
//   area block   \tArea: %R (%u) %s    https://github.com/CZ-NIC/bird/blob/master/proto/ospf/ospf.c#L814
//   counts       Number of interfaces/neighbors/adjacent neighbors
//                                   https://github.com/CZ-NIC/bird/blob/master/proto/ospf/ospf.c#L840
function parseOspfAreas(lines) {
	let areas = [];
	let cur = null;

	for (let i = 0; i < length(lines); i++) {
		let l = replace(lines[i], /^[ \t]+/, '');
		let m;

		if ((m = match(l, /^Area:[ \t]+\S+[ \t]+\((\S+)\)/))) {
			cur = { name: m[1], interfaces: 0, neighbors: 0, adjacent: 0 };
			push(areas, cur);
		} else if (cur && (m = match(l, /^Number[ \t]+of[ \t]+([^:]+):[ \t]+(\d+)/))) {
			if (m[1] == 'interfaces')
				cur.interfaces = +m[2];
			else if (m[1] == 'neighbors')
				cur.neighbors = +m[2];
			else if (m[1] == 'adjacent neighbors')
				cur.adjacent = +m[2];
		}
	}

	return areas;
}

// "show ospf interface <name>":
//   Interface %I/%d, Cost: %u (proto/ospf/ospf.c ospf_sh_iface)
function parseOspfInterfaces(lines) {
	let res = [];
	let ifa = null;

	for (let i = 0; i < length(lines); i++) {
		let l = replace(lines[i], /^[ \t]+/, '');
		let m;

		if ((m = match(l, /^Interface[ \t]+(\S+)/))) {
			ifa = { interface: m[1] };
			push(res, ifa);
		} else if (ifa && (m = match(l, /^Cost:[ \t]+(\d+)/))) {
			ifa.cost = +m[1];
		}
	}

	return res;
}

// "show ospf neighbors <name>":
//   header  <rid> <pri> <state>/<pos> <dtime> <iface> <ip>
//           https://github.com/CZ-NIC/bird/blob/master/proto/ospf/ospf.c#L782
//   row     "%-12R\t%3u\t%s/%s\t%6t\t%-10s %I"
//           https://github.com/CZ-NIC/bird/blob/master/proto/ospf/neighbor.c#L867
const ospfRawRe = /^(\S+)[ \t]+(\d+)[ \t]+(\S+)\/(\S+)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(\S+)$/;

function parseOspfNeighbors(lines) {
	let res = [];

	for (let i = 0; i < length(lines); i++) {
		let m = match(replace(lines[i], /^[ \t]+/, ''), ospfRawRe);
		if (!m)
			continue;

		push(res, {
			rid: m[1], priority: +m[2], state: m[3], position: m[4],
			interface: m[6], ip: m[7],
		});
	}

	return res;
}

//// BFD parser ////
// "show bfd sessions <name>":
//   proto/bfd/bfd.c (bfd_find_session / show facility)
const bfdRe = /^(\S+)[ \t]+(\S+)[ \t]+(Up|Down|Init)[ \t]+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[0-9.]*|\S+)[ \t]+([0-9.]+)[ \t]+([0-9.]+)$/;

function parseBfdSessions(lines) {
	let res = [];

	for (let i = 0; i < length(lines); i++) {
		let m = match(replace(lines[i], /^[ \t]+/, ''), bfdRe);
		if (!m)
			continue;

		push(res, {
			ip: m[1], interface: m[2],
			up: m[3] == 'Up' ? 1 : 0,
			uptime: uptimeSeconds(m[4]),
			interval: +m[5], timeout: +m[6],
		});
	}

	return res;
}

//// ubus methods ////

const methods = {
	query: {
		args: {
			command: '',
			socket: '',
		},
		call: function(request) {
			let socket = request.args.socket || DEFAULT_SOCKET;
			let lines = birdRaw(socket, request.args.command);

			if (lines == null)
				return { code: 1 };

			return { code: 0, stdout: join(lines, '\n') };
		}
	},

	status: {
		args: {
			socket: '',
		},
		call: function(request) {
			let socket = request.args.socket || DEFAULT_SOCKET;

			let protoLines = birdRaw(socket, 'show protocols all');
			if (protoLines == null)
				return { status: null };

			let out = { status: {}, protocols: [], ospf: [], bgp: [], bfd: [] };

			let statusLines = birdRaw(socket, 'show status');
			if (statusLines != null)
				out.status = parseStatus(statusLines);
			out.status.up = 1;

			let protos = parseProtocols(protoLines);
			out.protocols = protos;

			for (let i = 0; i < length(protos); i++) {
				let p = protos[i];

				if (p.proto == 'BFD') {
					let s = birdRaw(socket, 'show bfd sessions ' + p.name);
					if (s != null)
						push(out.bfd, { protocol: p.name, sessions: parseBfdSessions(s) });
					continue;
				}

				if (!isGeneric(p.proto))
					continue;

				if (p.proto == 'OSPF') {
					let ospf = { protocol: p.name, ip_version: p.ip_version,
						running: p.state == 'Running' ? 1 : 0,
						areas: [], interfaces: [], neighbors: [] };

					let areas = birdRaw(socket, 'show ospf ' + p.name);
					if (areas != null)
						ospf.areas = parseOspfAreas(areas);

					let ifaces = birdRaw(socket, 'show ospf interface ' + p.name);
					if (ifaces != null)
						ospf.interfaces = parseOspfInterfaces(ifaces);

					let neigh = birdRaw(socket, 'show ospf neighbors ' + p.name);
					if (neigh != null)
						ospf.neighbors = parseOspfNeighbors(neigh);

					push(out.ospf, ospf);
				}
				else if (p.proto == 'BGP') {
					push(out.bgp, {
						name: p.name,
						ip_version: p.ip_version,
						up: p.up,
						state: p.state,
						neighbor: p.neighbor || null,
						neighbor_as: p.neighbor_as || null,
						local_as: p.local_as || null,
						imported: p.imported,
						exported: p.exported,
						filtered: p.filtered,
						preferred: p.preferred,
						uptime: p.uptime,
					});
				}
			}

			return out;
		}
	},
};

return { bird: methods };