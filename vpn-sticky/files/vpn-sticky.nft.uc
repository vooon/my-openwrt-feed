{%
let uci = require("uci").cursor();
let daemon = uci.get_all("vpn-sticky", "daemon") || {};

let enabled = `${daemon.enabled ?? "1"}` != "0";

if (!enabled) {
	print("# vpn-sticky disabled\n");
	return;
}

/**
 * Parse a mark value given as hex ("0x70000000") or decimal.
 * @param {string} s
 * @returns {number}
 */
function parse_mark(s) {
	s = trim(`${s}`);
	return match(s, /^0[xX]/) ? hex(s) : int(s);
}

/**
 * @param {number} n
 * @returns {string}
 */
function fmt_mark(n) {
	return sprintf("0x%08x", n);
}

let mask = parse_mark(daemon.mark_mask ?? "0x70000000");
let mark_mask = fmt_mark(mask);
let keep_mask = fmt_mark(~mask & 0xffffffff);
let lan_ifs = [];
let ifaces = [];

if (type(daemon.lan_if) == "array")
	lan_ifs = daemon.lan_if;
else if (daemon.lan_if)
	lan_ifs = [ daemon.lan_if ];

let seen_lan_ifs = {};
let uniq_lan_ifs = [];
for (let lan_if in lan_ifs) {
	if (!lan_if || seen_lan_ifs[lan_if])
		continue;

	seen_lan_ifs[lan_if] = true;
	push(uniq_lan_ifs, lan_if);
}

/* no lan_if: replies arriving on any interface follow the sticky tunnel */
let reply_iif = length(uniq_lan_ifs)
	? `iifname { ${join(", ", map(uniq_lan_ifs, n => `"${n}"`))} } `
	: "";

uci.foreach("vpn-sticky", "iface", section => {
	let name = section.name ?? section[".name"];
	let mark = section.mark;
	let rule_pref = section.rule_pref;
	let route_table = section.route_table;

	if (!name || !mark || !rule_pref || !route_table)
		return;

	push(ifaces, { name, mark: fmt_mark(parse_mark(mark) & mask) });
});
-%}
# Re-creating the table inside one transaction keeps the replace atomic.
table inet vpn_sticky
delete table inet vpn_sticky

table inet vpn_sticky {
	chain prerouting {
		type filter hook prerouting priority -140; policy accept;
{% for (let iface in ifaces): %}
		iifname "{{ iface.name }}" ct direction original ct mark & {{ mark_mask }} == 0x0 ct mark set ct mark & {{ keep_mask }} | {{ iface.mark }}
{% endfor %}
{#
 # Copy only the sticky bits to the packet mark, keeping other users' bits
 # (pbr, fw4). One rule per mark: older kernels can't OR two registers.
 #}
{% for (let iface in ifaces): %}
		{{ reply_iif }}ct direction reply ct mark & {{ mark_mask }} == {{ iface.mark }} meta mark set meta mark & {{ keep_mask }} | {{ iface.mark }}
{% endfor %}
	}

	chain output {
		type route hook output priority -140; policy accept;
{% for (let iface in ifaces): %}
		ct direction reply ct mark & {{ mark_mask }} == {{ iface.mark }} meta mark set meta mark & {{ keep_mask }} | {{ iface.mark }}
{% endfor %}
	}
}
