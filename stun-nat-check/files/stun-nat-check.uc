#!/usr/bin/ucode --
// NAT mapping check: ask several STUN servers from ONE local UDP port and
// compare the external endpoints they report.
//
//   stun-nat-check [-p local_port] [-s host[:port]]... [-u user:pass]
//
// The same external endpoint for every server means the NAT keeps one
// mapping per local port (UDP hole punching can work); different endpoints
// mean a mapping per destination (it cannot). IPv4 only: that is where the
// NAT is.
//
// -s replaces the built-in public server list (repeat it; two servers on
// different addresses are the minimum). -u, or the STUN_NAT_CHECK_AUTH
// environment variable, answers servers that demand STUN long-term
// credentials (coturn `secure-stun`).

'use strict';

import * as socket from 'socket';
import { md5, sha1 } from 'digest';

const USAGE = 'usage: stun-nat-check [-p local_port] [-s host[:port]]... [-u user:pass]\n';

const DEFAULT_PORT = 40000;
const DEFAULT_SERVERS = [
	'stun.l.google.com:19302',
	'stun.cloudflare.com:3478',
	'stun.cloudflare.com:53',     // same host, other port: port-dependent mapping
	'stun.nextcloud.com:3478',
	'stun.sipnet.ru:3478',
];

const MAGIC = [ 0x21, 0x12, 0xa4, 0x42 ];
const BINDING_REQUEST = 0x0001;
const BINDING_SUCCESS = 0x0101;
const BINDING_ERROR = 0x0111;

const ATTR_MAPPED_ADDRESS = 0x0001;
const ATTR_USERNAME = 0x0006;
const ATTR_MESSAGE_INTEGRITY = 0x0008;
const ATTR_ERROR_CODE = 0x0009;
const ATTR_REALM = 0x0014;
const ATTR_NONCE = 0x0015;
const ATTR_XOR_MAPPED_ADDRESS = 0x0020;

const TIMEOUT_MS = 1000;
const TRIES = 3;
const AUTH_ROUNDS = 3;   // 401, then possibly 438 (stale nonce)

/**
 * Read a big-endian 16 bit value.
 *
 * @param {string} s
 * @param {number} o
 * @returns {number}
 */
function u16(s, o) {
	return (ord(s, o) << 8) | ord(s, o + 1);
}

/**
 * Encode a big-endian 16 bit value.
 *
 * @param {number} n
 * @returns {string}
 */
function p16(n) {
	return chr((n >> 8) & 0xff, n & 0xff);
}

/**
 * Encode one attribute, zero padded to a 32 bit boundary.
 *
 * @param {number} t
 * @param {string} v
 * @returns {string}
 */
function attr(t, v) {
	let s = p16(t) + p16(length(v)) + v;

	for (let n = (4 - (length(v) % 4)) % 4; n > 0; n--)
		s += chr(0);

	return s;
}

/**
 * Encode a message header; the transaction id ends in `id`, `seq`.
 *
 * @param {number} len
 * @param {number} id
 * @param {number} seq
 * @returns {string}
 */
function header(len, id, seq) {
	return p16(BINDING_REQUEST) + p16(len) + chr(MAGIC[0], MAGIC[1], MAGIC[2], MAGIC[3],
		0x73, 0x74, 0x75, 0x6e, 0x6e, 0x61, 0x74, 0x63, 0, 0, seq, id);
}

/**
 * HMAC-SHA1 (RFC 2104) on top of ucode-mod-digest.
 *
 * @param {string} key
 * @param {string} msg
 * @returns {string}
 */
function hmac_sha1(key, msg) {
	let ipad = '', opad = '';

	for (let i = 0; i < 64; i++) {
		let b = (i < length(key)) ? ord(key, i) : 0;

		ipad += chr(b ^ 0x36);
		opad += chr(b ^ 0x5c);
	}

	let inner = hexdec(sha1(ipad + msg) ?? '') ?? '';

	return hexdec(sha1(opad + inner) ?? '') ?? '';
}

/**
 * Build a Binding Request, signed with long-term credentials when the
 * server has sent its realm and nonce (RFC 5389, 10.2).
 *
 * @param {number} id
 * @param {number} seq
 * @param {?{user: string, pass: string, realm: string, nonce: string}} auth
 * @returns {string}
 */
function binding_request(id, seq, auth) {
	if (!auth)
		return header(0, id, seq);

	let body = attr(ATTR_USERNAME, auth.user) + attr(ATTR_REALM, auth.realm) +
	           attr(ATTR_NONCE, auth.nonce);
	let key = hexdec(md5(`${auth.user}:${auth.realm}:${auth.pass}`) ?? '') ?? '';

	// the length covers MESSAGE-INTEGRITY (4 + 20) while it is being signed
	let signed = header(length(body) + 24, id, seq) + body;

	return signed + attr(ATTR_MESSAGE_INTEGRITY, hmac_sha1(key, signed));
}

/**
 * Decode a STUN message: its type and the first value of each attribute.
 *
 * @param {string} r
 * @returns {?{type: number, attrs: object}}
 */
function parse(r) {
	if (length(r) < 20)
		return null;

	let end = min(20 + u16(r, 2), length(r));
	let attrs = {};

	for (let o = 20; o + 4 <= end; ) {
		let t = u16(r, o), l = u16(r, o + 2), v = o + 4;

		if (v + l > end)
			break;

		attrs[t] ??= substr(r, v, l);
		o = v + l + ((4 - (l % 4)) % 4);
	}

	return { type: u16(r, 0), attrs };
}

/**
 * Extract the mapped IPv4 endpoint from the attributes of a success response.
 *
 * @param {object} attrs
 * @returns {?{address: string, port: number}}
 */
function mapped_address(attrs) {
	for (let t in [ ATTR_XOR_MAPPED_ADDRESS, ATTR_MAPPED_ADDRESS ]) {
		let v = attrs[t];

		if (type(v) != 'string')
			continue;

		if (length(v) < 8 || ord(v, 1) != 1)
			continue;

		let key = (t == ATTR_XOR_MAPPED_ADDRESS) ? MAGIC : [ 0, 0, 0, 0 ];
		let a = [];

		for (let j = 0; j < 4; j++)
			push(a, ord(v, 4 + j) ^ key[j]);

		return {
			address: join('.', a),
			port: u16(v, 2) ^ ((key[0] << 8) | key[1]),
		};
	}

	return null;
}

/**
 * Send one request and wait for the response with the same transaction id.
 *
 * @param {object} sock
 * @param {object} dst
 * @param {string} req
 * @returns {?{type: number, attrs: object}}
 */
function transact(sock, dst, req) {
	for (let n = 0; n < TRIES; n++) {
		sock.send(req, 0, dst);

		// poll() lists the socket even on a timeout, with no event flags
		for (;;) {
			let ev = socket.poll(TIMEOUT_MS, sock);

			if (!((ev?.[0]?.[1] ?? 0) & socket.POLLIN))
				break;

			let r = sock.recv(1500);

			// not a late reply to an earlier request
			if (type(r) == 'string' && length(r) >= 20 && substr(r, 4, 16) == substr(req, 4, 16))
				return parse(r);
		}
	}

	return null;
}

/**
 * Ask one STUN server through `sock`, authenticating when it demands it.
 *
 * @param {object} sock
 * @param {object} dst
 * @param {number} id
 * @param {?{user: string, pass: string}} cred
 * @returns {{address: ?string, port: ?number, error: ?string}}
 */
function query(sock, dst, id, cred) {
	let auth = null;

	for (let seq = 0; seq <= AUTH_ROUNDS; seq++) {
		let res = transact(sock, dst, binding_request(id, seq, auth));

		if (!res)
			return { error: 'no answer' };

		if (res.type == BINDING_SUCCESS) {
			let m = mapped_address(res.attrs);

			return m ?? { error: 'no mapped address in the answer' };
		}

		if (res.type != BINDING_ERROR)
			return { error: sprintf('unexpected message type 0x%04x', res.type) };

		let ec = res.attrs[ATTR_ERROR_CODE];
		let code = (type(ec) == 'string' && length(ec) >= 4) ? (ord(ec, 2) & 7) * 100 + ord(ec, 3) : 0;
		let realm = res.attrs[ATTR_REALM], nonce = res.attrs[ATTR_NONCE];

		if (code != 401 && code != 438)
			return { error: `error ${code}` };

		if (!cred)
			return { error: 'authentication required (-u user:pass)' };

		// a 401 to a signed request means the credentials were refused
		if (type(realm) != 'string' || type(nonce) != 'string' || (auth && code == 401))
			return { error: 'authentication failed' };

		auth = { user: cred.user, pass: cred.pass, realm, nonce };
	}

	return { error: 'authentication failed' };
}

let port = DEFAULT_PORT;
let servers = [];
let auth_arg = getenv('STUN_NAT_CHECK_AUTH');

for (let i = 0; i < length(ARGV); i++) {
	let opt = ARGV[i];

	if (opt == '-h' || opt == '--help') {
		print(USAGE);
		exit(0);
	}

	let val = ARGV[++i];

	if (val == null || !(opt in [ '-p', '-s', '-u' ])) {
		warn(USAGE);
		exit(2);
	}

	if (opt == '-p')
		port = int(val);
	else if (opt == '-s')
		push(servers, val);
	else
		auth_arg = val;
}

if (type(port) != 'int' || port < 1 || port > 65535) {
	warn(USAGE);
	exit(2);
}

let cred = null;

if (auth_arg != null && auth_arg != '') {
	let sep = index(auth_arg, ':');

	if (sep < 1) {
		warn('credentials must be user:pass\n');
		exit(2);
	}

	cred = { user: substr(auth_arg, 0, sep), pass: substr(auth_arg, sep + 1) };
}

if (!length(servers))
	servers = DEFAULT_SERVERS;

let sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM);

if (!sock || !sock.bind({ address: '0.0.0.0', port })) {
	warn(`cannot bind UDP port ${port}: ${socket.error()}\n`);
	exit(1);
}

printf('local port %d\n', port);

let seen = {};
let answers = 0;

for (let i = 0; i < length(servers); i++) {
	let spec = servers[i];

	if (type(spec) != 'string')
		continue;

	let m = match(spec, /^([^:]+)(:([0-9]+))?$/);

	if (!m) {
		printf('%-28s bad server, expected host[:port]\n', spec);
		continue;
	}

	let ai = socket.addrinfo(m[1], m[3] ?? '3478', { family: socket.AF_INET, socktype: socket.SOCK_DGRAM });
	let dst = ai?.[0]?.addr;

	if (!dst) {
		printf('%-28s cannot resolve\n', spec);
		continue;
	}

	let res = query(sock, dst, i + 1, cred);

	if (res.error) {
		printf('%-28s %-15s %s\n', spec, dst.address, res.error);
		continue;
	}

	printf('%-28s %-15s -> %s:%d\n', spec, dst.address, res.address, res.port);
	seen[`${res.address}:${res.port}`] = true;
	answers++;
}

sock.close();

if (answers < 2) {
	print('need answers from at least two servers to decide\n');
	exit(1);
}

if (length(keys(seen)) == 1) {
	print('SAME external endpoint for every server: one mapping per local port, hole punching can work\n');
	exit(0);
}

print('DIFFERENT external endpoints: mapping per destination, hole punching will not work\n');
exit(3);
