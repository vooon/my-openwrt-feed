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