#!/bin/sh

tmp=/tmp/yota-status.tmp

error_exit() {
	echo '3GPP.RSSI=UNK' > $tmp
	printf 'MODEM ERROR'
	exit 1
}

wget http://10.0.0.1/status -qO $tmp || error_exit

sinr=$(awk -F'=' '/3GPP.SINR/ { print $2 }' $tmp)
rsrp=$(awk -F'=' '/3GPP.RSRP/ { print $2 }' $tmp)
#rssi=$(awk -F'=' '/3GPP.RSSI/ { print $2 }' /tmp/yota-status.tmp)

printf 'QLT %3d dB %4d dBm' $sinr $rsrp
