# netifd-proto-fou

FOU (Foo-over-UDP) encapsulated tunnels for OpenWrt/netifd, carrying traffic
over an IPv6 underlay mesh (OSPF over /127 ptp links and /128 "dummy" tunnel
endpoints, BGP-installed routes on top). The UDP outer header gives the mesh
per-flow ECMP hashing (see "Why FOU" below).

Packages:
- `netifd-proto-fou-lib` — shared helpers (`/lib/netifd/fou.sh`) + docs
- `netifd-proto-fou-ip6gre` — proto `fou-ip6gre` (GRE over IPv6, mixed IPv4+IPv6 payloads)
- `netifd-proto-fou-ip6tnl` — proto `fou-ip6tnl` (`mode ip4ip6` IPv4-in-IPv6 or `ip6ip6` IPv6-in-IPv6)

Both proto packages depend on `netifd-proto-fou-lib`; installing both causes
no file conflicts.

## Options (both protos)

| option    | type          | default       | description |
|-----------|---------------|---------------|-------------|
| `laddr`   | string        | —             | Local underlay address (spoke/hub /128). Required. |
| `peeraddr`| string        | —             | Remote underlay address (hub /128). Required on the spoke; omit (or use `listen 1`) on the hub. |
| `listen`  | bool          | 0             | Hub mode: register the FOU listener + device without a `remote`, decapsulating from any spoke. One section serves any number of spokes. |
| `port`    | int           | 5555          | FOU UDP port: `encap-dport` on the device and the `ip fou add` listener on this side. |
| `sport`   | string/int    | `auto`        | `encap-sport`. `auto` = the kernel derives a per-flow UDP source port → per-flow ECMP hash. A fixed port pinning the outer 4-tuple is also possible. |
| `ipproto` | int/name      | per mode      | FOU protocol. Defaults: `gre`/47, `ipip`/4, `ipv6`/41 for `fou-ip6gre`, `mode ip4ip6` and `mode ip6ip6` respectively. Override only if you know why. |
| `csum`    | bool          | 0             | Add `encap-csum` (UDP checksum) to the outer header. |
| `mtu`     | int           | kernel default| Device MTU (`ip link set`). For a 1500-byte link budget for the tunnel overhead (e.g. 1500 − (40 v6 + 8 UDP + GRE/…) ≈ 1400). |
| `ttl`     | int           | —             | Outer hop-limit/TTL. |
| `tos`     | int           | —             | Outer TOS/traffic-class. |
| `ipaddr`  | list          | —             | Overlay IPv4 address(es) netifd assigns to the tunnel device. |
| `ip6addr` | list          | —             | Overlay IPv6 address(es). |
| `mode`    | string        | `ip4ip6`      | *`fou-ip6tnl` only*: `ip4ip6` (IPv4-in-IPv6) or `ip6ip6` (IPv6-in-IPv6). |

## Examples

Spoke (mixed v4+v6 PBR egress device) and hub (one section, many spokes):

```
# spoke
config interface 'exit'
    option proto    'fou-ip6gre'
    option laddr    '2001:db8::2'
    option peeraddr '2001:db8::1'
    option port     '5555'
    list   ipaddr   '172.16.0.2/30'
    list   ip6addr  'fd00:0:0:1::2/64'

# hub
config interface 'fou_in'
    option proto   'fou-ip6gre'
    option listen  '1'
    option laddr   '2001:db8::1'
    option port    '5555'
    list   ipaddr  '172.16.0.1/30'
    list   ip6addr 'fd00:0:0:1::1/64'
```

`proto fou-ip6tnl` lookup:

```
config interface 'v4towardshub'
    option proto   'fou-ip6tnl'
    option laddr   '2001:db8::2'
    option peeraddr '2001:db8::1'
    option port    '5555'
    option mode    'ip4ip6'      # IPv4-in-IPv6; or 'ip6ip6'
    list   ipaddr  '172.16.1.2/30'
```

## Lifecycle

- **ifup**: `ip fou add port … ipproto … [local …]` (best-effort, both ends)
  → `ip link add <iface> type ip6gre|ip6tnl [mode …] local … [remote …] [ttl/tos] encap fou encap-sport [auto] encap-dport … [encap-csum]`
  → optional `ip link set mtu` → handed to netifd (`proto_init_update`); overlay
  IPs/routes come from the interface config.
- **ifdown**: `ip link del <iface>` + `ip fou del port …`.
- **Failure**: if the device cannot be created and is not already present,
  the proto reports `DEVICE_CREATE_FAIL` and `proto_block_restart` so the
  interface is retried; it also errors on a missing `laddr` or, outside
  `listen` mode, a missing `peeraddr`.

## Requirements

- `netifd-proto-fou-ip6gre`: `kmod-gre6 kmod-fou6 ip`
- `netifd-proto-fou-ip6tnl`: `kmod-ip6-tunnel kmod-fou6 ip`
  (`kmod-gre6`/`kmod-fou6` pull their transitive kernel deps).

## Why FOU

Plain GRE/IPIP over the mesh produce a constant outer `(spoke, hub)` pair, so
an ECMP mesh hashes every inner flow to the same path. FOU wraps the tunnel in
UDP and, with `encap-sport auto`, gives each flow its own outer source port —
the mesh then hashes per-flow and can load-balance/switch across equal-cost
paths. `fou-ip6gre` is the right choice when a single PBR device must carry
both IPv4 and IPv6 payloads (GRE demuxes the two inside one port); the
`fou-ip6tnl` modes are leaner single-family alternatives.

Tunnel endpoints must be the mesh-wide /128 addresses (routable via OSPF/BGP),
*not* `fe80::` link-local — the FOU outer has to be forwarded hop-to-hop by
the mesh for the IGP/ECMP decisions to matter.