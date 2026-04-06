{%
let uci = require("uci").cursor();
let daemon = uci.get_all("vpn-sticky", "daemon") || {};

let enabled = `${daemon.enabled ?? "1"}` != "0";

if (!enabled) {
	print("# vpn-sticky disabled\n");
	return;
}

let lan_ifs = [];
let mark_mask = daemon.mark_mask ?? "0x70000000";
let ifaces = [];

if (type(daemon.lan_if) == "array")
	lan_ifs = daemon.lan_if;
else if (daemon.lan_if)
	lan_ifs = [ daemon.lan_if ];
else
	lan_ifs = [ "br-lan" ];

let seen_lan_ifs = {};
let uniq_lan_ifs = [];
for (let lan_if in lan_ifs) {
	if (!lan_if || seen_lan_ifs[lan_if])
		continue;

	seen_lan_ifs[lan_if] = true;
	push(uniq_lan_ifs, lan_if);
}

lan_ifs = length(uniq_lan_ifs) ? uniq_lan_ifs : [ "br-lan" ];

uci.foreach("vpn-sticky", "iface", section => {
	let name = section.name ?? section[".name"];
	let mark = section.mark;
	let rule_pref = section.rule_pref;
	let route_table = section.route_table;

	if (!name || !mark || !rule_pref || !route_table)
		return;

	push(ifaces, { name, mark });
});
-%}
table inet vpn_sticky {
	chain prerouting {
		type filter hook prerouting priority -140; policy accept;
{% for (let iface in ifaces): %}
		iifname "{{ iface.name }}" ct state new ct mark set {{ iface.mark }}
{% endfor %}
{% for (let lan_if in lan_ifs): %}
		iifname "{{ lan_if }}" ct state { established, related } ct mark & {{ mark_mask }} != 0x0 meta mark set ct mark
{% endfor %}
	}

	chain output {
		type route hook output priority -140; policy accept;
		ct state { established, related } ct mark & {{ mark_mask }} != 0x0 meta mark set ct mark
	}
}
