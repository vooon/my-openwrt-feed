#!/bin/sh
# shellcheck shell=busybox
#
# Copyright (C) 2010 segal.di.ubi.pt
# Copyright (C) 2020 nbembedded.com
#
# This is free software, licensed under the GNU General Public License v2.
#

# arguments always the same, see init.d script
instance="$1"
mode="$2"
period="$3"
addressfamily="$4"
pinghosts="$5"
pingperiod="$6"
pingsize="$7"
forcedelay="$8"
interface="$9"
mmifacename="${10}"
unlockbands="${11}"
script="${12}"

log_tag="watchcat.$instance[$$]"

get_ping_size() {
	local ps="$1"
	case "$ps" in
	small)
		ps="1"
		;;
	windows)
		ps="32"
		;;
	standard)
		ps="56"
		;;
	big)
		ps="248"
		;;
	huge)
		ps="1492"
		;;
	jumbo)
		ps="9000"
		;;
	*)
		echo "Error: invalid ping_size. ping_size should be either: small, windows, standard, big, huge or jumbo" 1>&2
		echo "Corresponding ping packet sizes (bytes): small=1, windows=32, standard=56, big=248, huge=1492, jumbo=9000" 1>&2
		;;
	esac
	echo "$ps"
}

get_ping_family_flag() {
	local family="$1"
	case "$family" in
	any)
		family=""
		;;
	ipv4)
		family="-4"
		;;
	ipv6)
		family="-6"
		;;
	*)
		echo "Error: invalid address_family \"$family\". address_family should be one of: any, ipv4, ipv6" 1>&2
		;;
	esac
	echo "$family"
}

reboot_now() {
	reboot &

	[ "$forcedelay" -ge 1 ] && {
		sleep "$forcedelay"
		echo 1 > /proc/sys/kernel/sysrq
		echo b > /proc/sysrq-trigger # Will immediately reboot the system without syncing or unmounting your disks.
	}
}

watchcat_periodic() {
	sleep "$period" && reboot_now
}

watchcat_restart_modemmanager_iface() {
	[ "$2" -gt 0 ] && {
		logger -p daemon.info -t "$log_tag" "Resetting current-bands to 'any' on modem: \"$1\" now."
		/usr/bin/mmcli -m any --set-current-bands=any
	}
	logger -p daemon.info -t "$log_tag" "Reconnecting modem: \"$1\" now."
	/etc/init.d/modemmanager restart
	ifup "$1"
}

watchcat_restart_network_iface() {
	logger -p daemon.info -t "$log_tag" "Restarting network interface: \"$1\"."
	# ip link set "$1" down
	# ip link set "$1" up
	ifdown "$1"
	ifup "$2"
}

watchcat_run_script() {
	logger -p daemon.info -t "$log_tag" "Running script \"$1\" for network interface: \"$2\"."
	"$1" "$2"
	local rc=$?
	[ "$rc" -ne 0 ] && logger -p daemon.err -t "$log_tag" "Running script \"$1\" for network interface: \"$2\", failed, rc: $rc"
}

watchcat_restart_all_networks() {
	logger -p daemon.info -t "$log_tag" "Restarting networking now by running: /etc/init.d/network restart"
	/etc/init.d/network restart
}

watchcat_monitor_network() {
	local failure_period="$period"
	local ping_frequency_interval="$pingperiod"

	local time_now time_lastcheck time_lastcheck_withinternet
	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"

	[ "$time_now" -lt "$failure_period" ] && sleep "$((failure_period - time_now))"

	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"
	time_lastcheck="$time_now"
	time_lastcheck_withinternet="$time_now"

	local ping_size ping_family
	ping_size="$(get_ping_size "$pingsize")"
	ping_family="$(get_ping_family_flag "$addressfamily")"

	while true; do
		# account for the time ping took to return. With a ping time of 5s, ping might take more than that, so it is important to avoid even more delay.
		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_diff="$((time_now - time_lastcheck))"

		[ "$time_diff" -lt "$ping_frequency_interval" ] && sleep "$((ping_frequency_interval - time_diff))"

		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_lastcheck="$time_now"

		for host in $pinghosts; do
			local ping_rc
			if [ -n "$interface" ]; then
				# shellcheck disable=SC2086
				ping $ping_family -I "$interface" -s "$ping_size" -c 1 "$host" > /dev/null
				ping_rc="$?"
			else
				# shellcheck disable=SC2086
				ping $ping_family -s "$ping_size" -c 1 "$host" > /dev/null
				ping_rc="$?"
			fi


			if [ "$ping_rc" -eq 0 ]; then
				time_lastcheck_withinternet="$time_now"
			else
				if [ -n "$script" ]; then
					logger -p daemon.info -t "$log_tag" "Could not reach $host via \"$interface\" for \"$((time_now - time_lastcheck_withinternet))\" seconds. Running script after reaching \"$failure_period\" seconds"
				elif [ -n "$interface" ]; then
					logger -p daemon.info -t "$log_tag" "Could not reach $host via \"$interface\" for \"$((time_now - time_lastcheck_withinternet))\" seconds. Restarting \"$interface\" after reaching \"$failure_period\" seconds"
				else
					logger -p daemon.info -t "$log_tag" "Could not reach $host for \"$((time_now - time_lastcheck_withinternet))\" seconds. Restarting networking after reaching \"$failure_period\" seconds"
				fi
			fi
		done

		if [ "$((time_now - time_lastcheck_withinternet))" -ge "$failure_period" ]; then
			if [ -n "$script" ]; then
				watchcat_run_script "$script" "$interface"
			else
				if [ -n "$mmifacename" ]; then
					# XXX untested
					watchcat_restart_modemmanager_iface "$mmifacename" "$unlockbands"
				fi
				if [ -n "$interface" ]; then
					watchcat_restart_network_iface "$interface"
				else
					watchcat_restart_all_networks
				fi
			fi

			# XXX wtf ???
			# /etc/init.d/watchcat start
			# Restart timer cycle.
			time_lastcheck_withinternet="$time_now"
		fi

	done
}

watchcat_ping() {
	local failure_period="$period"
	local ping_frequency_interval="$pingperiod"

	local time_now time_lastcheck time_lastcheck_withinternet
	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"

	[ "$time_now" -lt "$failure_period" ] && sleep "$((failure_period - time_now))"

	time_now="$(cat /proc/uptime)"
	time_now="${time_now%%.*}"
	time_lastcheck="$time_now"
	time_lastcheck_withinternet="$time_now"

	local ping_size ping_family
	ping_size="$(get_ping_size "$pingsize")"
	ping_family="$(get_ping_family_flag "$addressfamily")"

	while true; do
		# account for the time ping took to return. With a ping time of 5s, ping might take more than that, so it is important to avoid even more delay.
		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_diff="$((time_now - time_lastcheck))"

		[ "$time_diff" -lt "$ping_frequency_interval" ] && sleep "$((ping_frequency_interval - time_diff))"

		time_now="$(cat /proc/uptime)"
		time_now="${time_now%%.*}"
		time_lastcheck="$time_now"

		for host in $pinghosts; do
			local ping_rc
			if [ -n "$interface" ]; then
				# shellcheck disable=SC2086
				ping $ping_family -I "$interface" -s "$ping_size" -c 1 "$host" > /dev/null
				ping_rc="$?"
			else
				# shellcheck disable=SC2086
				ping $ping_family -s "$ping_size" -c 1 "$host" > /dev/null
				ping_rc="$?"
			fi

			if [ "$ping_rc" -eq 0 ]; then
				time_lastcheck_withinternet="$time_now"
			else
				logger -p daemon.info -t "$log_tag" "Could not reach $host for $((time_now - time_lastcheck_withinternet)). Rebooting after reaching $failure_period"
			fi
		done

		[ "$((time_now - time_lastcheck_withinternet))" -ge "$failure_period" ] && reboot_now
	done
}

case "$mode" in
periodic_reboot)
	watchcat_periodic
	;;
ping_reboot)
	watchcat_ping
	;;
restart_iface|run_script)
	watchcat_monitor_network
	;;
*)
	echo "Error: invalid mode selected: $mode" 1>&2
	exit 128
	;;
esac
