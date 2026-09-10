'use strict';
'require form';
'require network';

return network.registerProtocol('dummy', {
	getI18n() {
		return _('Dummy interface');
	},

	getIfname() {
		return this._ubus('l3_device') || this.sid;
	},

	getPackageName() {
		return 'netifd-proto-dummy';
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

		o = s.taboption('general', form.DynamicList, 'ipaddr', _('IPv4 address'), _('Addresses assigned to the dummy interface, in <code>address/prefix</code> notation.'));
		o.datatype = 'cidr4';
		o.placeholder = _('192.168.99.1/24');

		o = s.taboption('general', form.DynamicList, 'ip6addr', _('IPv6 address'), _('IPv6 addresses assigned to the dummy interface, in <code>address/prefix</code> notation.'));
		o.datatype = 'cidr6';

		o = s.taboption('general', form.Value, 'macaddr', _('MAC address'), _('Hardware address assigned to the dummy device (optional).'));
		o.datatype = 'macaddr';
		o.optional = true;

		o = s.taboption('general', form.Value, 'gateway', _('IPv4 gateway'), _('Default IPv4 route installed on this interface (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;

		o = s.taboption('general', form.Value, 'ip6gw', _('IPv6 gateway'), _('Default IPv6 route installed on this interface (optional).'));
		o.datatype = 'ip6addr("nomask")';
		o.optional = true;

		// -- advanced --------------------------------------------------------------------

		o = s.taboption('advanced', form.Value, 'broadcast', _('Broadcast address'), _('Broadcast address used for the configured IPv4 addresses (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;

		o = s.taboption('advanced', form.Value, 'ptpaddr', _('Point-to-point peer address'), _('Peer address for point-to-point IPv4 addresses (optional).'));
		o.datatype = 'ip4addr("nomask")';
		o.optional = true;
	}
});