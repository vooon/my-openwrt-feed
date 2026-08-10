// Self-contained regression test for the BMX7 collector.
//
// Mocks the "bmx7" ubus object and the gauge/counter metric helpers, loads
// files/extra/bmx7.uc and asserts that the emitted metric set is correct.
// Run via test.sh.

const STATUS_TXT =
"   shortId=abc123 nodeId=def456 name=node1 version=7.0-rev nodeKey=x linkKeys=y " +
"version=7.0-rev cv=1 revision=01234567 primaryIp=10.0.0.1 tun6Address=fd00::1 tun4Address=10.0.0.1 " +
"descSqn=1 lastDesc=2 ogmSqn=3 aggSize=4 aggMax=5 aggSend=6 uptime=1:02:03:04 cpu=1.2 mem=1024K " +
"rxBpP=100/50.0 txBpP=200/60.0 txQ=7/64 nbs=3 rts=5 nodes=2/1 descRefs=1/2\n";

const INTERFACES_TXT =
"   dev=wlan0 state=UP type=wifi phy=phy0 channel=36 rateMax=866M idx=1 localMac=aa:bb:cc:dd:ee:ff " +
"localIp=10.0.0.1 rts=3 helloSqn=10 rxBpP=100/50.0 txBpP=200/60.0 txTasks=0\n" +
"   dev=eth0 state=UP type=ethernet phy=--- channel=0 rateMax=1000M idx=2 localMac=11:22:33:44:55:66 " +
"localIp=10.0.0.2 rts=2 helloSqn=0 rxBpP=0/0.0 txBpP=0/0.0 txTasks=0\n";

const LINKS_TXT =
"   shortId=abc123 nodeId=def456 name=node1 linkKey=abc linkKeys=z dev=wlan0 nbLocalIp=10.0.0.2 " +
"localIp=10.0.0.1 rts=1 idx=1 rq=200 bestRq=255 tq=180 bestTq=240 rxRate=150000 txRate=150K " +
"wRxRate=150K wTxRate=150K wTxRateAvg=140K wTxRateEff=120K wTxThr=100K wTxThrAvg=90K wTxThrEff=80K " +
"cnt=5 mcs=7 mhz=5180 nss=2 sgi=1 chw=40 ht=1 vht=0 wSignal=-60 wNoise=-95 wSnr=35 aggSize=4 aggMax=8\n";

const ORIGINATORS_TXT =
"   shortId=def456 nodeId=def456 name=node1 assessedState=UP pref=65535 brcTo=100 signTo=100 tAPTo=100 " +
"nQTo=100 friend=1 recom=1 trustees=2 S=1 s=1 T=1 t=1 myIid=1 descSqn=5 descSqnMin=1 descSqnNext=6 " +
"nodeKey=x linkKeys=y primaryIp=10.0.0.2 dev=wlan0 myIdx=1 nbIdx=2\n";

const config = { socket: "/var/run/bmx7/sock" };

const ubus = {
	call: function(obj, method, args) {
		switch (args.command) {
		case "list status":
			return { code: 0, stdout: STATUS_TXT };
		case "list interfaces":
			return { code: 0, stdout: INTERFACES_TXT };
		case "list links":
			return { code: 0, stdout: LINKS_TXT };
		case "list originators":
			return { code: 0, stdout: ORIGINATORS_TXT };
		}
		return null;
	}
};

let emitted = [];

const gauge = function(name, help) {
	return function(labels, value) {
		push(emitted, { name: name, labels: labels, value: value });
	};
};
const counter = gauge;

let func = loadfile("./files/extra/bmx7.uc", { strict_declarations: true, raw_mode: true });
if (!func) {
	warn("failed to load bmx7.uc\n");
	exit(1);
}

call(func, null, { config, ubus, gauge, counter });

let failures = 0;

function find(name, labels) {
	for (let i = 0; i < length(emitted); i++) {
		let e = emitted[i];
		if (e.name != name)
			continue;
		if (labels) {
			let ok = true;
			for (let k in labels)
				if (e.labels[k] != labels[k]) {
					ok = false;
					break;
				}
			if (!ok)
				continue;
		}
		return e;
	}
	return null;
}

function check(name, labels, want) {
	let e = find(name, labels);
	if (!e) {
		warn("FAIL: metric not emitted: ", name, " ", labels, "\n");
		failures++;
		return;
	}
	if (e.value != want) {
		warn("FAIL: ", name, " ", labels, " = ", e.value, " want ", want, "\n");
		failures++;
	}
}

// daemon up + status
check("bmx7_up", null, 1);
check("bmx7_uptime_seconds", null, 93784);   // 1:02:03:04
check("bmx7_cpu_percent", null, 1.2);
check("bmx7_memory_bytes", null, 1048576);   // 1024K
check("bmx7_txqueue", null, 7);
check("bmx7_neighbors", null, 3);
check("bmx7_routes", null, 5);
check("bmx7_originators_total", null, 2);
check("bmx7_keys_total", null, 1);

// interfaces
check("bmx7_interface_rts", { dev: "wlan0" }, 3);
check("bmx7_interface_rate_max", { dev: "wlan0" }, 866000000);   // 866M
check("bmx7_interface_rx_bytes_per_second", { dev: "wlan0" }, 100);
check("bmx7_interface_tx_bytes_per_second", { dev: "wlan0" }, 200);

// links (umetric K/M/G parsing)
let l = { node_id: "def456", name: "node1", dev: "wlan0" };
check("bmx7_link_rq", l, 200);
check("bmx7_link_tq", l, 180);
check("bmx7_link_rx_rate", l, 150000);       // 150000 raw
check("bmx7_link_tx_rate", l, 150000);       // 150K
check("bmx7_link_wtx_rate_eff", l, 120000);  // 120K
check("bmx7_link_signal_dbm", l, -60);
check("bmx7_link_noise_dbm", l, -95);
check("bmx7_link_snr", l, 35);
check("bmx7_link_mhz", l, 5180);
check("bmx7_link_channel_width", l, 40);

// originators
let o = { node_id: "def456", name: "node1" };
check("bmx7_originator_pref", o, 65535);
check("bmx7_originator_trustees", o, 2);
check("bmx7_originator_friend", o, 1);
check("bmx7_originator_desc_sqn", o, 5);

// no NaN values anywhere
for (let i = 0; i < length(emitted); i++) {
	if (emitted[i].value == "NaN" || emitted[i].value == "Infinity") {
		warn("FAIL: invalid metric value: ", emitted[i].name, "\n");
		failures++;
	}
}

if (failures) {
	warn(failures, " assertion(s) failed\n");
	exit(1);
}

print("bmx7 collector test OK\n");