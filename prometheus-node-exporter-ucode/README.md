# prometheus-node-exporter-ucode

Lightweight Prometheus node exporter for OpenWrt, written in ucode.
Serves metrics via uhttpd on port `9101` (configurable).

A rewrite of the official [Prometheus node_exporter](https://github.com/prometheus/node_exporter)
tailored for constrained OpenWrt devices.

## Installation

The base package provides core system collectors:

```
opkg install prometheus-node-exporter-ucode
```

Extra collectors are installed as separate packages:

```
opkg install prometheus-node-exporter-ucode-babeld
opkg install prometheus-node-exporter-ucode-wifi
# etc.
```

## Configuration

`/etc/config/prometheus-node-exporter-ucode`:

```
config prometheus-node-exporter-ucode 'main'
    option listen_interface 'loopback'
    option listen_port '9101'
    option http_keepalive '70'
```

Per-collector options use `config collector '<name>'` sections.

### Scraping a subset of collectors

```
curl http://localhost:9101/metrics?collect=cpu&collect=meminfo
```

## Base Collectors

Included in the main package. Data sourced from `/proc` and `/sys`.

### conntrack

| Metric | Type | Description |
|--------|------|-------------|
| `node_nf_conntrack_entries` | gauge | Current number of conntrack entries |
| `node_nf_conntrack_entries_limit` | gauge | Maximum conntrack entries |

### cpu

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_cpu_seconds_total` | counter | `cpu`, `mode` | CPU time in seconds |
| `node_context_switches_total` | counter | | Context switches |
| `node_forks_total` | counter | | Forks |
| `node_intr_total` | counter | | Interrupts |
| `node_boot_time_seconds` | gauge | | Boot time (epoch) |
| `node_procs_running_total` | gauge | | Running processes |
| `node_procs_blocked_total` | gauge | | Blocked processes |

### entropy

| Metric | Type | Description |
|--------|------|-------------|
| `node_entropy_available_bits` | gauge | Bits of available entropy |
| `node_entropy_pool_size_bits` | gauge | Bits of entropy pool |

### filefd

| Metric | Type | Description |
|--------|------|-------------|
| `node_filefd_allocated` | gauge | Allocated file descriptors |
| `node_filefd_maximum` | gauge | Maximum file descriptors |

### loadavg

| Metric | Type | Description |
|--------|------|-------------|
| `node_load1` | gauge | 1-minute load average |
| `node_load5` | gauge | 5-minute load average |
| `node_load15` | gauge | 15-minute load average |

### meminfo

| Metric | Type | Description |
|--------|------|-------------|
| `node_memory_*_bytes` | gauge | Memory info from `/proc/meminfo` (dynamic names) |

### netclass

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_network_info` | gauge | `device`, `address`, ... | Network device info |
| `node_network_mtu_bytes` | gauge | `device` | MTU |
| `node_network_speed_bytes` | gauge | `device` | Link speed |
| `node_network_carrier` | gauge | `device` | Carrier status |
| `node_network_*` | gauge | `device` | Various `/sys/class/net` attributes |
| `node_network_carrier_*_changes_total` | counter | `device` | Carrier state changes |

### netdev

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_network_receive_bytes_total` | counter | `device` | Bytes received |
| `node_network_transmit_bytes_total` | counter | `device` | Bytes transmitted |
| `node_network_receive_packets_total` | counter | `device` | Packets received |
| `node_network_transmit_packets_total` | counter | `device` | Packets transmitted |
| `node_network_receive_errs_total` | counter | `device` | Receive errors |
| `node_network_transmit_errs_total` | counter | `device` | Transmit errors |
| `node_network_receive_drop_total` | counter | `device` | Receive drops |
| `node_network_transmit_drop_total` | counter | `device` | Transmit drops |

### selinux

| Metric | Type | Description |
|--------|------|-------------|
| `node_selinux_enabled` | gauge | SELinux enabled |
| `node_selinux_current_mode` | gauge | SELinux mode |

### time

| Metric | Type | Description |
|--------|------|-------------|
| `node_time_seconds` | gauge | System time (epoch) |
| `node_time_clocksource_available_info` | gauge | Available clocksources |
| `node_time_clocksource_current_info` | gauge | Current clocksource |

### uname

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_uname_info` | gauge | `sysname`, `nodename`, `release`, `version`, `machine` | System info |

## Extra Collectors

Installed as separate packages.

### babeld

Package: `prometheus-node-exporter-ucode-babeld`
Dependencies: `babeld`
Source: ubus (`babeld`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `babel_info` | gauge | `version`, `my_id`, `host` | Node info |
| `babel_neighbours_total` | gauge | — | Total neighbours |
| `babel_neighbour_rxcost` | gauge | `address`, `interface` | Receive cost |
| `babel_neighbour_txcost` | gauge | `address`, `interface` | Transmit cost |
| `babel_neighbour_hello_reach` | gauge | `address`, `interface` | Hello reachability |
| `babel_neighbour_uhello_reach` | gauge | `address`, `interface` | Unicast hello reachability |
| `babel_neighbour_rtt_seconds` | gauge | `address`, `interface` | RTT in seconds |
| `babel_neighbour_if_up` | gauge | `address`, `interface` | Interface is up |
| `babel_routes_total` | gauge | — | Total routes |
| `babel_route_metric` | gauge | `prefix`, `src_prefix`, `id`, `via` | Route metric |
| `babel_route_smoothed_metric` | gauge | `prefix`, `src_prefix`, `id`, `via` | Smoothed route metric |
| `babel_route_refmetric` | gauge | `prefix`, `src_prefix`, `id`, `via` | Reference metric |
| `babel_route_installed` | gauge | `prefix`, `src_prefix`, `id`, `via` | Route installed (0/1) |
| `babel_route_feasible` | gauge | `prefix`, `src_prefix`, `id`, `via` | Route feasible (0/1) |
| `babel_route_seqno` | gauge | `prefix`, `src_prefix`, `id`, `via` | Sequence number |
| `babel_route_age_seconds` | gauge | `prefix`, `src_prefix`, `id`, `via` | Route age |
| `babel_xroutes_total` | gauge | — | Total local xroutes |
| `babel_xroute_metric` | gauge | `prefix`, `src_prefix` | Local route metric |

### dnsmasq

Package: `prometheus-node-exporter-ucode-dnsmasq`
Dependencies: `dnsmasq`
Source: ubus (`dnsmasq.metrics`)

| Metric | Type | Description |
|--------|------|-------------|
| `dnsmasq_*_total` | gauge | Dynamic metrics from dnsmasq |

### go2rtc

Package: `prometheus-node-exporter-ucode-go2rtc`
Dependencies: `ucode-mod-uclient`, `ucode-mod-uloop`
Source: HTTP API

Configuration:
```
config collector 'go2rtc'
    option api_url 'http://127.0.0.1:1984'
```

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `go2rtc_up` | gauge | `url` | API reachable (0/1) |
| `go2rtc_producer_info` | gauge | `stream`, `format_name`, `protocol`, `remote_addr`, `user_agent` | Producer info |
| `go2rtc_consumer_info` | gauge | `stream`, `format_name`, `protocol`, `remote_addr`, `user_agent` | Consumer info |
| `go2rtc_producer_received_bytes_total` | counter | `stream`, `remote_addr` | Producer bytes received |
| `go2rtc_consumer_sent_bytes_total` | counter | `stream`, `remote_addr` | Consumer bytes sent |

### hwmon

Package: `prometheus-node-exporter-ucode-hwmon`
Source: `/sys/class/hwmon`

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_hwmon_chip_names` | gauge | `chip`, `chip_name` | Chip name annotation |
| `node_hwmon_sensor_label` | gauge | `chip`, `sensor`, `label` | Sensor label |
| `node_hwmon_temp_celsius` | gauge | `chip`, `sensor` | Temperature (input) |
| `node_hwmon_temp_crit_alarm_celsius` | gauge | `chip`, `sensor` | Temperature (critical alarm) |
| `node_hwmon_temp_crit_celsius` | gauge | `chip`, `sensor` | Temperature (critical) |
| `node_hwmon_temp_max_celsius` | gauge | `chip`, `sensor` | Temperature (max) |
| `node_hwmon_pwm` | gauge | `chip`, `sensor` | PWM control |

### ltq-dsl

Package: `prometheus-node-exporter-ucode-ltq-dsl`
Dependencies: `ltq-dsl-app`
Source: ubus (`dsl.metrics`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `dsl_info` | gauge | `atuc_vendor`, `chipset`, ... | DSL chipset info |
| `dsl_line_info` | gauge | `annex`, `standard`, `mode`, `profile` | DSL line info |
| `dsl_up` | gauge | `detail` | DSL link up (0/1) |
| `dsl_uptime_seconds` | gauge | — | DSL uptime |
| `dsl_line_attenuation_db` | gauge | `direction` | Line attenuation |
| `dsl_signal_attenuation_db` | gauge | `direction` | Signal attenuation |
| `dsl_signal_to_noise_margin_db` | gauge | `direction` | SNR margin |
| `dsl_aggregated_transmit_power_db` | gauge | `direction` | Transmit power |
| `dsl_latency_seconds` | gauge | `direction` | Interleave delay |
| `dsl_datarate` | gauge | `direction` | Data rate |
| `dsl_max_datarate` | gauge | `direction` | Attainable data rate |
| `dsl_error_seconds_total` | counter | `err`, `loc` | Error seconds |
| `dsl_errors_total` | counter | `err`, `loc` | Error counts |
| `dsl_erb_total` | counter | `counter` | ERB counters |

### netstat

Package: `prometheus-node-exporter-ucode-netstat`
Source: `/proc/net/netstat`, `/proc/net/snmp`

| Metric | Type | Description |
|--------|------|-------------|
| `node_netstat_*` | gauge | Dynamic metrics from netstat/snmp |

### odhcp6c

Package: `prometheus-node-exporter-ucode-odhcp6c`
Dependencies: `odhcp6c`
Source: ubus (`odhcp6c.<dev>.get_statistics`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_odhcp6c_*` | gauge | `dev` | DHCPv6 message counters |

### openwrt

Package: `prometheus-node-exporter-ucode-openwrt`
Source: ubus (`system.board`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_openwrt_info` | gauge | `board_name`, `id`, `model`, `release`, `revision`, `system`, `target` | OpenWrt system info |

### procd

Package: `prometheus-node-exporter-ucode-procd`
Source: ubus (`service.list`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `procd_service_running` | gauge | `procd_service`, `procd_instance` | Service is running (0/1) |
| `procd_service_pid` | gauge | `procd_service`, `procd_instance` | Service PID |
| `procd_service_exit_code` | gauge | `procd_service`, `procd_instance` | Stopped service exit code |

### realtek-poe

Package: `prometheus-node-exporter-ucode-realtek-poe`
Dependencies: `realtek-poe`
Source: ubus (`poe.info`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `realtek_poe_switch_info` | gauge | `mcu`, `firmware` | Switch info |
| `realtek_poe_switch_budget_watts` | gauge | — | Power budget |
| `realtek_poe_switch_consumption_watts` | gauge | — | Power consumption |
| `realtek_poe_port_priority` | gauge | `device` | Port priority |
| `realtek_poe_port_consumption_watts` | gauge | `device` | Port consumption |
| `realtek_poe_port_state` | gauge | `device`, `state` | Port state |
| `realtek_poe_port_mode` | gauge | `device`, `mode` | Port mode |

### singbox

Package: `prometheus-node-exporter-ucode-singbox`
Dependencies: `ucode-mod-uclient`, `ucode-mod-uloop`
Source: HTTP API (Clash compatible)

Configuration:
```
config collector 'singbox'
    option api_url 'http://127.0.0.1:9090'
    option secret 'your-clash-api-secret'
    option per_connection '0'
```

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `singbox_up` | gauge | `url` | Clash API reachable (0/1) |
| `singbox_version_info` | gauge | `meta`, `premium`, `version` | Version info |
| `singbox_memory_used_bytes` | gauge | — | Memory used |
| `singbox_connections_total` | gauge | — | Current connection count |
| `singbox_connections_total_upload_bytes_total` | counter | — | Cumulative upload |
| `singbox_connections_total_download_bytes_total` | counter | — | Cumulative download |
| `singbox_connections_upload_bytes_total` | gauge | `type` | Upload by connection type |
| `singbox_connections_download_bytes_total` | gauge | `type` | Download by connection type |
| `singbox_perconn_upload_bytes_total` | gauge | `id`, `rule`, `host`, ... | Per-connection upload (opt-in) |
| `singbox_perconn_download_bytes_total` | gauge | `id`, `rule`, `host`, ... | Per-connection download (opt-in) |

### snmp6

Package: `prometheus-node-exporter-ucode-snmp6`
Source: `/proc/net/snmp6`, `/proc/net/dev_snmp6`

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `snmp6_*` | counter | `device` | IPv6 SNMP counters |

### thermal

Package: `prometheus-node-exporter-ucode-thermal`
Source: `/sys/class/thermal`

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_thermal_zone_temp` | gauge | `zone`, `type`, `policy` | Zone temperature (°C) |
| `node_cooling_device_cur_state` | gauge | `name`, `type` | Current throttle state |
| `node_cooling_device_max_state` | gauge | `name`, `type` | Maximum throttle state |

### uci_dhcp_host

Package: `prometheus-node-exporter-ucode-uci_dhcp_host`
Source: UCI (`dhcp.host`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `dhcp_host_info` | gauge | `name`, `mac`, `ip` | DHCP static host entry |

### watchdog

Package: `prometheus-node-exporter-ucode-watchdog`
Source: `/sys/class/watchdog`

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `node_watchdog_bootstatus` | gauge | `name` | Boot status |
| `node_watchdog_fw_version` | gauge | `name` | Firmware version |
| `node_watchdog_nowayout` | gauge | `name` | No way out flag |
| `node_watchdog_timeleft_seconds` | gauge | `name` | Time left |
| `node_watchdog_timeout_seconds` | gauge | `name` | Timeout |
| `node_watchdog_pretimeout_seconds` | gauge | `name` | Pre-timeout |
| `node_watchdog_info` | gauge | `name`, `identity`, `state`, ... | Watchdog info |
| `node_watchdog_available` | gauge | `available`, `device` | Available governors |

### wifi

Package: `prometheus-node-exporter-ucode-wifi`
Dependencies: `ucode-mod-nl80211`
Source: ubus (`network.wireless.status`), nl80211

Configuration:
```
config collector 'wifi'
    option stations '1'
```

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `wifi_radio_info` | gauge | `radio`, `htmode`, `channel`, `country` | Radio info |
| `wifi_network_info` | gauge | `radio`, `ifname`, `ssid`, `bssid`, `mode` | Network info |
| `wifi_network_quality` | gauge | `radio`, `ifname` | Signal quality (%) |
| `wifi_network_bitrate` | gauge | `radio`, `ifname` | Average bitrate |
| `wifi_network_noise_dbm` | gauge | `radio`, `ifname` | Noise floor |
| `wifi_network_signal_dbm` | gauge | `radio`, `ifname` | Average signal |
| `wifi_stations_total` | counter | `radio`, `ifname` | Station count |
| `wifi_station_inactive_milliseconds` | gauge | `radio`, `ifname`, `mac` | Station inactive time |
| `wifi_station_receive_bytes_total` | counter | `radio`, `ifname`, `mac` | Station RX bytes |
| `wifi_station_transmit_bytes_total` | counter | `radio`, `ifname`, `mac` | Station TX bytes |
| `wifi_station_signal_dbm` | gauge | `radio`, `ifname`, `mac` | Station signal |

### wireguard

Package: `prometheus-node-exporter-ucode-wireguard`
Dependencies: `rpcd-mod-wireguard`
Source: ubus (`wireguard.status`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `wireguard_interface_info` | gauge | `name`, `public_key`, `listen_port`, `fwmark` | Interface info |
| `wireguard_peer_info` | gauge | `interface`, `public_key`, `description`, `endpoint`, ... | Peer info |
| `wireguard_latest_handshake_seconds` | gauge | `public_key` | Last handshake time |
| `wireguard_received_bytes_total` | gauge | `public_key` | Bytes received |
| `wireguard_sent_bytes_total` | gauge | `public_key` | Bytes sent |

## Writing a Custom Collector

Create a `.uc` file in `files/extra/`. The following are available in scope:

- `ubus` — connected ubus context
- `gauge(name, help)` — returns a function `(labels, value)` to emit a gauge
- `counter(name, help)` — returns a function `(labels, value)` to emit a counter
- `config` — UCI options from the collector's config section
- `fs` — ucode `fs` module
- `nextline(f)` — read one line from file handle
- `oneline(path)` — read first line of a file
- `wsplit(line)` — split on whitespace

Return `false` to signal failure. Example:

```javascript
const x = ubus.call("myservice", "status");
if (!x)
    return false;

gauge("myservice_up", "Service is up")(null, x.running ? 1 : 0);
gauge("myservice_clients", "Connected clients")(null, x.clients);
```

Then add to the Makefile:

```makefile
$(eval $(call Collector,myservice,My service collector,+myservice-dep))
```
