// SPDX-License-Identifier: LGPL-2.1+
/*
 * Pure helpers shared by rpcd-mod-bird and its test-suite.
 *
 * Everything in this file is deterministic string/array transformation:
 * no sockets, no files, no side effects.  It is loaded as a ucode module
 * (via `import ... from './birdconfig.uc'`) by the rpcd plugin `bird.uc` and
 * by the unit test runner in `test/`.
 *
 * Copyright (C) 2026 Vladimir Ermakov <vooon341@gmail.com>
 */

'use strict';

//// Small string helpers ////

/* Count occurrences of the single character @c in @s. */
function countChar(s, c)
{
	let n = 0;

	for (let i = 0; i < length(s); i++)
		if (substr(s, i, 1) == c)
			n++;

	return n;
}

/* Brace delta of a line: +1 per `{`, -1 per `}`.  Braces inside comments or
 * quoted strings are not handled (none appear in OSPF interface blocks). */
function braceDelta(line)
{
	return countChar(line, '{') - countChar(line, '}');
}

//// OSPF interface parser ////
// "show ospf interface <name>":
//   Interface %I/%d, Cost: %u (proto/ospf/ospf.c ospf_sh_iface)
// Optional `Type:` line (ptp/broadcast/nbma/...).
//
// Every field is optional: an interface without `Type:` yields `type == null`,
// without `Cost:` yields `cost == null` - never fail the whole parse.
export function parseOspfInterfaces(lines)
{
	let res = [];
	let ifa = null;

	for (let i = 0; i < length(lines); i++) {
		let l = replace(lines[i], /^[ \t]+/, '');
		let m;

		if ((m = match(l, /^Interface[ \t]+(\S+)/))) {
			ifa = { interface: m[1], type: null };
			push(res, ifa);
		} else if (ifa && (m = match(l, /^Type:[ \t]+(\S+)/))) {
			ifa.type = m[1];
		} else if (ifa && (m = match(l, /^Cost:[ \t]+(\d+)/))) {
			ifa.cost = +m[1];
		}
	}

	return res;
};

//// IP / prefix helpers ////

/* Parse a dotted-quad IPv4 address into 4 bytes.  Returns null unless every
 * group is a plain decimal in 0..255. */
function ipv4Bytes(s)
{
	let t = split(s, '.');
	if (length(t) != 4)
		return null;

	let b = [];

	for (let i = 0; i < 4; i++) {
		if (!match(t[i], /^[0-9]{1,3}$/))
			return null;

		let v = +t[i];
		if (v > 255)
			return null;

		push(b, v);
	}

	return b;
}

/* Convert a list of ":"-separated IPv6 hextet strings into bytes. */
function hextetsToBytes(groups)
{
	let b = [];

	for (let i = 0; i < length(groups); i++) {
		if (!match(groups[i], /^[0-9a-fA-F]{1,4}$/))
			return null;

		let v = int(groups[i], 16);
		push(b, (v >> 8) & 0xff);
		push(b, v & 0xff);
	}

	return b;
}

/* Parse an IPv6 address (with at most one "::") into 16 bytes. */
function ipv6Bytes(s)
{
	if (!length(s))
		return null;

	/* reject a second "::" compression */
	let d = index(s, '::');
	if (d >= 0 && index(substr(s, d + 2), '::') >= 0)
		return null;

	if (d >= 0) {
		let head = [];
		let tail = [];
		let l = substr(s, 0, d);
		let r = substr(s, d + 2);

		if (length(l))
			head = split(l, ':');
		if (length(r))
			tail = split(r, ':');

		let hb = hextetsToBytes(head);
		if (hb == null)
			return null;

		let tb = hextetsToBytes(tail);
		if (tb == null)
			return null;

		let missing = 8 - length(head) - length(tail);
		if (missing < 1)
			return null;

		let out = [];
		let i;

		for (i = 0; i < length(hb); i++)
			push(out, hb[i]);

		for (i = 0; i < missing; i++) {
			push(out, 0);
			push(out, 0);
		}

		for (i = 0; i < length(tb); i++)
			push(out, tb[i]);

		return (length(out) == 16) ? out : null;
	}

	let g = split(s, ':');
	if (length(g) != 8)
		return null;

	return hextetsToBytes(g);
}

/* Parse "<ip>" or "<ip>/<len>" into a comparable struct
 * `{ fam: 4|6, addr: byte[], len }`, or null when @p is not a plain IPv4/IPv6
 * address or prefix.  A bare address (no "/len") implies a host route. */
export function parsePrefix(p)
{
	if (p == null || !length(p))
		return null;

	let m = match(p, /^([^\/]+)\/([0-9]+)$/);
	let addr = p;
	let len = -1;

	if (m) {
		addr = m[1];
		len = +m[2];
	}

	let bytes = null;
	let fam = 0;

	if (index(addr, ':') >= 0) {
		fam = 6;
		bytes = ipv6Bytes(addr);
	}
	else if (index(addr, '.') >= 0) {
		fam = 4;
		bytes = ipv4Bytes(addr);
	}

	if (bytes == null)
		return null;

	if (len < 0)
		len = (fam == 4) ? 32 : 128;

	if (len > ((fam == 4) ? 32 : 128))
		return null;

	return { fam: fam, addr: bytes, len: len };
};

//// Route parser ////
// "show route [for <prefix>]" output (BIRD 3), nest/rt-show.c rt_show_rte():
//   header (rt-show.c L69):
//     <prefix> <dest> [<proto> <time>[ from <ip>]]<marker><info>
//     prefix = %N, dest = rta_dest_name() (unicast/blackhole/unreachable/
//              prohibited, nest/rt-attr.c L85), proto = protocol instance name
//     info   = get_route_info() or " (pref)" default:
//              BGP  " (pref/metric) [ASxxx...]"  proto/bgp/attrs.c bgp_get_route_info
//              OSPF " I (pref/metric)[/m2]"      proto/ospf/ospf.c ospf_get_route_info
//   next hops (rt-show.c L91/L94):
//     \tvia <gw> on <iface>[...]     when nh.gw is set (remote next hop)
//     \tdev <iface>[...]             when nh.gw is zero (local/connected route)
// Non-primary routes of the same network print with an empty <prefix> label.
const routeHeaderRe = /^\s*(\S*)\s+(unicast|blackhole|unreachable|prohibited)\s+\[(\S+)/;
/* cost is the route metric from the " (pref/metric)" header trailer */
const routeInfoRe = /\((\d+)(\/(\d+))?/;
const routeViaRe = /^[ \t]*via[ \t]+(\S+)[ \t]+on[ \t]+(\S+)/;
const routeDevRe = /^[ \t]*dev[ \t]+(\S+)/;
/* Verbose "show route ... all" extended attribute lines (nest/rt-attr.c
 * ea_show()).  The AS path attribute prints as "bgp_path:" on BIRD 2.x /
 * "as_path:" or "BGP.as_path:" on BIRD 3.x; the plain names cover both. */
const routeAsPathRe = /^[ \t]*[A-Za-z.]*(bgp_path|as_path)[ \t]*:[ \t]+(.+)$/;
const routePrefRe = /^[ \t]*preference:[ \t]+(\d+)/;
const routeMetricRe = /^[ \t]*(local_metric|ospf_metric1|ospf_metric2):[ \t]+(\d+)/;
const routeLocalPrefRe = /^[ \t]*bgp_local_pref:[ \t]+(\d+)/;

/* Parse cleaned "show route" output lines into route objects:
 *
 *   { prefix, primary, proto, preference, cost, local_pref, as_path,
 *     next_hops: [ { kind, addr, iface, cost, proto } ] }
 *
 * "primary" is "via" for remote next hops or "dev" for local/connected
 * (device-only) routes.  ECMP returns one next_hops entry per "via" line.
 * The header supplies "preference" and "cost"; the verbose "... all"
 * attribute lines refine them and fill "local_pref" (bgp_local_pref) and
 * "as_path" for BGP routes, while OSPF routes get their cost from
 * "local_metric"/"ospf_metric{N}"
 */
export function parseRoute(lines)
{
	let res = [];
	let cur = null;

	for (let i = 0; i < length(lines); i++) {
		let m = match(lines[i], routeHeaderRe);

		if (m) {
			let info = match(lines[i], routeInfoRe);
			let cost = null;
			let preference = null;

			if (info) {
				preference = +info[1];
				cost = (info[3] != null) ? +info[3] : +info[1];
			}

			cur = {
				prefix: m[1], primary: 'via',
				proto: m[3],
				preference: preference, cost: cost,
				local_pref: null, as_path: null,
				next_hops: [],
			};
			push(res, cur);
			continue;
		}

		if (!cur)
			continue;

		if ((m = match(lines[i], routeViaRe))) {
			push(cur.next_hops, {
				kind: 'via', addr: m[1], iface: m[2],
				cost: cur.cost, proto: cur.proto,
			});
			continue;
		}

		if ((m = match(lines[i], routeDevRe))) {
			push(cur.next_hops, {
				kind: 'dev', addr: null, iface: m[1],
				cost: cur.cost, proto: cur.proto,
			});
			continue;
		}

		if ((m = match(lines[i], routePrefRe))) {
			cur.preference = +m[1];
			continue;
		}

		if ((m = match(lines[i], routeMetricRe))) {
			cur.cost = +m[2];
			continue;
		}

		if ((m = match(lines[i], routeLocalPrefRe))) {
			cur.local_pref = +m[1];
			continue;
		}

		if ((m = match(lines[i], routeAsPathRe))) {
			let path = [];
			let toks = split(trim(m[2]), /[^0-9]+/);

			for (let j = 0; j < length(toks); j++)
				if (length(toks[j]))
					push(path, +toks[j]);

			if (length(path))
				cur.as_path = path;
		}
	}

	for (let i = 0; i < length(res); i++) {
		let hasVia = false;
		let hasDev = false;

		for (let j = 0; j < length(res[i].next_hops); j++)
			if (res[i].next_hops[j].kind == 'via')
				hasVia = true;
			else
				hasDev = true;

		res[i].primary = (hasDev && !hasVia) ? 'dev' : 'via';
	}

	return res;
};

/* Pick the AS path of the route whose prefix and protocol match @prefix/@proto
 * out of verbose "show route all" lines (each route prints its own attribute
 * block, so a plain "first line" would mis-attach the path when the primary
 * route of the network is e.g. OSPF).  Returns null when not found. */
export function routeAsPath(lines, prefix, proto)
{
	let routes = parseRoute(lines);

	for (let i = 0; i < length(routes); i++)
		if (routes[i].prefix == prefix && routes[i].proto == proto)
			return routes[i].as_path;

	return null;
};

function bytesEq(a, b)
{
	if (length(a) != length(b))
		return false;

	for (let i = 0; i < length(a); i++)
		if (a[i] != b[i])
			return false;

	return true;
}

/* True when network @e (longer-prefix, "covering") contains route/prefix @q:
 * e.len <= q.len and the first e.len bits of q match e. */
function netCovers(q, e)
{
	if (e.fam != q.fam)
		return false;
	if (e.len > q.len)
		return false;

	let by = e.len >> 3;
	let bits = e.len & 7;

	for (let i = 0; i < by; i++)
		if (q.addr[i] != e.addr[i])
			return false;

	if (bits) {
		let mask = 0xff << (8 - bits);
		if ((q.addr[by] & mask) != (e.addr[by] & mask))
			return false;
	}

	return true;
}

/* Return the route whose prefix equals @prefix (compared on normalized bits,
 * so "203.0.113.5" matches a table entry "203.0.113.5/32"), or null. */
export function exactRoute(routes, prefix)
{
	let q = parsePrefix(prefix);
	if (q == null)
		return null;

	for (let i = 0; i < length(routes); i++) {
		let r = parsePrefix(routes[i].prefix);

		if (r != null && r.fam == q.fam && r.len == q.len && bytesEq(r.addr, q.addr))
			return routes[i];
	}

	return null;
};

/* Return the route whose prefix is the longest one covering @prefix (the
 * best-match entry the table would use), or null when nothing covers it. */
export function bestCoveringRoute(routes, prefix)
{
	let q = parsePrefix(prefix);
	if (q == null)
		return null;

	let best = null;
	let bestLen = -1;

	for (let i = 0; i < length(routes); i++) {
		let r = parsePrefix(routes[i].prefix);

		if (r == null || r.fam != q.fam || (r.len > q.len) || (r.len <= bestLen))
			continue;

		if (!netCovers(q, r))
			continue;

		best = routes[i];
		bestLen = r.len;
	}

	return best;
};

//// BIRD config editor ////

/* Set the OSPF `cost` of `interface "<iface>"` in a BIRD config file to
 * @cost (integer 1..65535, the range BIRD enforces).
 *
 * Returns `{ ok: true, text }` with the derived config, or
 * `{ ok: false, error }`.  The original text is never modified in place.
 *
 * The interface block is located by an exact `interface "<iface>"` name
 * anywhere in the file (interface names are unique on a host, so no
 * protocol/area scoping is needed - this also edits the right block on hosts
 * running several OSPF instances).  Existing `cost` statements inside the
 * block are replaced; otherwise a `cost N;` line is inserted right after the
 * opening brace, mirroring the block indentation.  Re-applying the same cost
 * produces byte-identical output (idempotent).
 */
export function editOspfCost(text, iface, cost)
{
	if (iface == null || !length(iface))
		return { ok: false, error: 'interface name is empty' };

	if (cost == null || !match(trim(cost + ''), /^[0-9]+$/))
		return { ok: false, error: 'cost must be a non-negative integer' };

	cost = +cost;

	if (cost < 1 || cost > 65535)
		return { ok: false, error: 'cost must be in range 1-65535' };

	let lines = split(text, '\n');
	let n = length(lines);

	/* 1. locate the `interface "<iface>"` header (token-aligned). */
	let headIdx = -1;
	let q = '"' + iface + '"';

	for (let i = 0; i < n; i++) {
		let l = replace(lines[i], /^[ \t]+/, '');

		if (substr(l, 0, 10) != 'interface ')
			continue;

		if (substr(trim(substr(l, 10)), 0, length(q)) == q) {
			headIdx = i;
			break;
		}
	}

	if (headIdx < 0)
		return { ok: false, error: `interface "${iface}" not found in configuration` };

	/* 2. find the opening `{` (same or a following line). */
	let openIdx = headIdx;

	while (openIdx < n && index(lines[openIdx], '{') < 0)
		openIdx++;

	if (openIdx >= n)
		return { ok: false, error: `unable to locate opening brace of interface "${iface}"` };

	/* 3. brace balance just before the opening brace; scan the block for the
	 *    closing brace and any existing `cost` statement. */
	let parent = 0;

	for (let i = 0; i <= openIdx; i++)
		parent += braceDelta(lines[i]);

	parent -= braceDelta(lines[openIdx]);

	/* balance is `parent + 1` inside the block (the opening brace has been
	 * consumed); it returns to `parent` on the block's closing brace */
	let bal = parent + 1;
	let closeIdx = -1;
	let costIdx = -1;

	for (let i = openIdx + 1; i < n; i++) {
		bal += braceDelta(lines[i]);

		if (bal <= parent) {
			closeIdx = i;
			break;
		}

		if (costIdx < 0 &&
		    match(replace(lines[i], /^[ \t]+/, ''), /^cost[ \t]+[0-9]+[ \t]*;/))
			costIdx = i;
	}

	if (closeIdx < 0)
		return { ok: false, error: `unterminated interface "${iface}" block` };

	/* 4. rebuild. */
	let out = [];

	if (costIdx >= 0) {
		for (let i = 0; i < n; i++) {
			if (i == costIdx)
				push(out, replace(lines[i], /^([ \t]*cost[ \t]+)[0-9]+([ \t]*;)/, '$1' + cost + '$2'));
			else
				push(out, lines[i]);
		}
	}
	else {
		let ind = match(lines[openIdx], /^[ \t]*/)[0] + '\t';

		for (let i = 0; i <= openIdx; i++)
			push(out, lines[i]);

		push(out, ind + 'cost ' + cost + ';');

		for (let i = openIdx + 1; i < n; i++)
			push(out, lines[i]);
	}

	return { ok: true, text: join('\n', out) };
};