'use strict';
'require form';
'require network';

return network.registerProtocol('fou_ip6gre', {
	getI18n() {
		return _('FOU-encapsulated GRE over IPv6');
	},

	getIfname() {
		return this._ubus('l3_device') || this.sid;
	},

	getPackageName() {
		return 'netifd-proto-fou-ip6gre';
	},

	isFloating() {
		return true;
	},

	isVirtual() {
		return true;
	},

	getDevices() {
		return null;
	},

	containsDevice(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions(s) {
		var o;

		// -- general ---------------------------------------------------------------------

		o = s.taboption('general', form.Value, 'laddr', _('Local underlay address'), _('Local IPv6 underlay address (/128) used as the tunnel endpoint. Required.'));
		o.rmempty = false;
		o.datatype = 'ip6addr("nomask")';

		o = s.taboption('general', form.Flag, 'listen', _('Listen mode'), _('Hub mode: register the FOU listener and bring up the tunnel without a remote, decapsulating from any spoke. No reply is encapsulated back into the tunnel.'));
		o.default = o.disabled;

		o = s.taboption('general', form.Value, 'peeraddr', _('Remote underlay address'), _('Remote IPv6 underlay address (/128) to tunnel to. Required on a spoke; omitted (or <em>Listen mode</em>) on the hub.'));
		o.rmempty = false;
		o.datatype = 'ip6addr("nomask")';
		o.depends('listen', '0');

		o = s.taboption('general', form.Value, 'port', _('FOU UDP port'), _('UDP port used for encapsulation on this side.'));
		o.datatype = 'port';
		o.placeholder = '5555';

		o = s.taboption('general', form.Value, 'sport', _('Encapsulation source port'), _('Outer UDP source port. <code>auto</code> derives a per-flow source port for per-flow ECMP hashing; a fixed port pins the outer 4-tuple.'));
		o.placeholder = 'auto';

		o = s.taboption('general', form.Value, 'ipproto', _('FOU protocol'), _('Inner protocol number/name registered with the FOU listener. Defaults to GRE for this tunnel type.'));
		o.placeholder = 'gre';

		o = s.taboption('general', form.Flag, 'csum', _('UDP checksum'), _('Add a UDP checksum to the outer header.'));
		o.default = o.disabled;

		o = s.taboption('general', form.DynamicList, 'ipaddr', _('IPv4 address'), _('Overlay IPv4 addresses assigned to the tunnel device, in <code>address/prefix</code> notation.'));
		o.datatype = 'cidr4';

		o = s.taboption('general', form.DynamicList, 'ip6addr', _('IPv6 address'), _('Overlay IPv6 addresses assigned to the tunnel device, in <code>address/prefix</code> notation.'));
		o.datatype = 'cidr6';

		// -- advanced --------------------------------------------------------------------

		o = s.taboption('advanced', form.Value, 'mtu', _('MTU'), _('Device MTU, accounting for the tunnel overhead (IPv6 + UDP + GRE).'));
		o.datatype = 'max(9200)';
		o.placeholder = '1400';

		o = s.taboption('advanced', form.Value, 'ttl', _('Outer TTL'), _('Hop-limit of the encapsulating packets (optional).'));
		o.datatype = 'range(1,255)';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'tos', _('Outer TOS'), _('Type of service / traffic class of the encapsulating packets (optional).'));
		o.datatype = 'range(0,255)';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'gateway', _('IPv4 gateway'), _('Default IPv4 route installed on this interface (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'ip6gw', _('IPv6 gateway'), _('Default IPv6 route installed on this interface (optional).'));
		o.datatype = 'ip6addr("nomask")';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'broadcast', _('Broadcast address'), _('Broadcast address used for the configured IPv4 addresses (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'ptpaddr', _('Point-to-point peer address'), _('Peer address for point-to-point IPv4 addresses (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;
	}
});