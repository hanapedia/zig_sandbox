# ZigBGP — Design

## Goals

A BGP speaker implemented as a **Zig library** targeting data-center / Kubernetes
workloads.  Consumers embed it by depending on the package and calling the API
from code — no config-file format, no CLI flags.

Scope for v0:
- eBGP session management (RFC 4271 FSM)
- IPv4 unicast route exchange (AFI 1, SAFI 1)
- In-memory RIB with best-path selection
- Route installation to Linux FIB via netlink (Phase 2)

---

## Library API

```zig
var speaker = try bgp.Speaker.init(allocator, .{
    .as_number = 65001,
    .router_id = .{ 10, 0, 0, 1 },
});
defer speaker.deinit();

try speaker.addPeer(.{
    .address   = try std.net.Address.parseIp("10.0.0.2", 179),
    .remote_as = 65002,
    .hold_time = 90,     // seconds; 0 = disable timers
    .passive   = false,  // actively connect
});

// Optional: install a route-change callback
speaker.onRouteChange = myHandler;

try speaker.start();
// caller decides how long to run
```

`Speaker.start()` is non-blocking: it spawns one thread per active peer and one
listener thread, then returns.  The caller remains in control of the main thread.

---

## Component Map

```
┌─────────────────────────────────────────────────────────┐
│  Application                                            │
│  (calls Speaker API, receives RIB callbacks)            │
└───────────────────────┬─────────────────────────────────┘
                        │ Speaker API
┌───────────────────────▼─────────────────────────────────┐
│  Speaker                                                │
│  - owns PeerList (one Peer per configured neighbor)     │
│  - owns RIB (shared, mutex-protected)                   │
│  - runs accept thread (passive connections)             │
└────────┬────────────────────────┬───────────────────────┘
         │ per-peer thread        │ RIB lock
┌────────▼──────────┐    ┌────────▼──────────────────────┐
│  Peer             │    │  RIB                          │
│  - owns FSM       │    │  - Adj-RIB-In (per peer)      │
│  - owns TCP stream│    │  - Loc-RIB   (best paths)     │
│  - hold/ka timers │    │  - best-path selection        │
│  - send/recv buf  │    │  - route-change callbacks     │
└────────┬──────────┘    └───────────────────────────────┘
         │
┌────────▼──────────────────────────────────────────────┐
│  BGP message codec (stateless pure functions)         │
│  message.zig  open.zig  update.zig  notification.zig  │
└───────────────────────────────────────────────────────┘
```

---

## Directory Layout

```
src/
├── bgp.zig              # public library root (re-exports Speaker, PeerConfig …)
├── config.zig           # LocalConfig, PeerConfig
├── bgp/
│   ├── message.zig      # BGP wire header
│   ├── open.zig         # OPEN message + capability negotiation
│   ├── update.zig       # UPDATE message (NLRI + path attributes)
│   ├── notification.zig # NOTIFICATION message + error codes
│   ├── fsm.zig          # pure FSM: State enum + transition helper
│   ├── peer.zig         # per-peer session thread
│   └── speaker.zig      # global coordinator
└── rib/
    ├── prefix.zig       # V4Prefix: NLRI encode/decode
    ├── path_attr.zig    # PathAttrs: decode / encode / clone
    └── rib.zig          # Adj-RIB-In + Loc-RIB
```

`build.zig` exposes the package as a module so downstream projects can do:

```zig
const bgp = b.dependency("zigbgp", .{}).module("zigbgp");
exe.root_module.addImport("bgp", bgp);
```

---

## Data Flow

### Session establishment

```
Peer thread                        Remote peer
    │
    ├─ TCP connect ──────────────────────────►
    ├─ send OPEN  ──────────────────────────►
    │                           ◄────────── OPEN
    ├─ validate OPEN
    ├─ send KEEPALIVE ──────────────────────►
    │                       ◄────────── KEEPALIVE
    └─ FSM → Established
```

### Route exchange

```
Remote peer                        Peer thread          RIB
    │
    ├─ UPDATE (announce) ──────────►
    │                               ├─ decode Update
    │                               ├─ rib.update() ──► Adj-RIB-In
    │                               │                   best-path selection
    │                               │                ──► Loc-RIB updated
    │                               │                ──► onRouteChange cb
    │
    ├─ UPDATE (withdraw) ──────────►
    │                               ├─ rib.withdraw() ─► remove from Adj-RIB-In
    │                               │                    re-run best path
    │
    ├─ session drop ───────────────►
    │                               └─ rib.withdrawAll() ─► remove all from peer
```

---

## BGP Message Wire Format

Every BGP message starts with a fixed 19-byte header:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                                                               |
+                        Marker (16 bytes = 0xFF×16)            +
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Length (u16 BE)      |    Type (u8)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`Length` includes the header itself.  Valid range: [19 .. 4096].

Type values: 1=OPEN  2=UPDATE  3=NOTIFICATION  4=KEEPALIVE

### OPEN body (10 bytes + optional parameters)

```
Version(1) | My-AS(2) | Hold-Time(2) | BGP-ID(4) | Opt-Parm-Len(1) | Opt-Params(N)
```

Optional parameters are TLV: `type(1) | length(1) | value(N)`.
Only type 2 (Capabilities) is relevant.

Each capability inside: `cap-code(1) | cap-len(1) | cap-data(N)`.

Capabilities we advertise and parse:

| Code | Name                      | Data                            |
|------|---------------------------|---------------------------------|
| 1    | Multiprotocol Extensions  | AFI(2) + reserved(1) + SAFI(1) |
| 2    | Route Refresh             | none                            |
| 65   | 4-Octet AS Number         | ASN(4)                          |

4-byte AS support (RFC 6793): if `my_as == 23456` (AS_TRANS) on the wire, the
real AS comes from capability 65.

### UPDATE body

```
Withdrawn-Routes-Len(2) | Withdrawn-Routes(N) | Path-Attr-Len(2) | Path-Attrs(N) | NLRI(rest)
```

Withdrawn routes and NLRI are lists of BGP-encoded prefixes:
`prefix-len(1) | significant-octets(0-4)` (only the non-zero octets are sent).

Path attributes are TLV:
`flags(1) | type(1) | length(1 or 2) | value(N)`.

Bit 4 of flags (0x10) = Extended Length → 2-byte length field instead of 1.

Attributes implemented:

| Code | Name             | Flags  | Value                       |
|------|------------------|--------|-----------------------------|
| 1    | ORIGIN           | 0x40   | 1 byte: 0=IGP 1=EGP 2=INC  |
| 2    | AS_PATH          | 0x40   | segments (see below)        |
| 3    | NEXT_HOP         | 0x40   | 4-byte IPv4                 |
| 4    | MED              | 0x80   | 4-byte u32                  |
| 5    | LOCAL_PREF       | 0x40   | 4-byte u32                  |
| 6    | ATOMIC_AGGREGATE | 0x40   | 0 bytes                     |
| 8    | COMMUNITIES      | 0xC0   | list of 4-byte values       |

AS_PATH segment: `type(1) | count(1) | ASN×count(4 each)`.
Types: 1=AS_SET  2=AS_SEQUENCE.
We use 4-byte ASNs throughout (RFC 6793).

### NOTIFICATION body

```
Error-Code(1) | Error-Subcode(1) | Data(N)
```

---

## FSM States and Transitions

Per RFC 4271 §8.  Simplified for active-mode eBGP:

```
Idle ──[start]──► Connect
Connect ──[TCP ok + OPEN sent]──► OpenSent
Connect ──[TCP fail]──► Active ──[retry]──► Connect
OpenSent ──[OPEN rx valid]──► OpenConfirm  (send KEEPALIVE)
OpenSent ──[error]──► Idle
OpenConfirm ──[KEEPALIVE rx]──► Established
Established ──[hold timeout / NOTIFICATION / TCP fail]──► Idle
```

---

## Peer Thread Design

Each peer runs in a dedicated `std.Thread`.  No async I/O is used; instead the
thread uses `std.posix.poll` with a 1-second timeout so timers are checked
without blocking indefinitely.

```
loop:
  TCP connect()
  send OPEN → FSM: connect → open_sent
  poll loop (1 s timeout):
    checkTimers()           # hold expiry, keepalive send
    if POLLIN:
      read into recv_buf
      processBuffer()       # parse complete messages, dispatch
    if POLLERR/POLLHUP:
      error → reset
  on any error:
    close stream
    rib.withdrawAll(peer_addr)
    FSM → idle
    sleep 30 s
    retry
```

### Timer rules

| Timer    | Start             | Reset                    | On expiry                       |
|----------|-------------------|--------------------------|---------------------------------|
| Hold     | after OPEN sent   | each KEEPALIVE/UPDATE rx | send NOTIFICATION, drop session |
| Keepalive| after OPEN sent   | after each send          | send KEEPALIVE, reset           |

Default hold = 90 s, keepalive = hold/3 = 30 s.
Negotiated hold = `min(local_hold, remote_hold)`.
Hold = 0 → both timers disabled (RFC 4271 §4.2).

---

## RIB Design

```
Adj-RIB-In:  ArrayList<{peer_addr, prefix, attrs}>
Loc-RIB:     AutoHashMap<{addr:u32, len:u8}, {peer_addr, prefix, attrs}>
```

`Adj-RIB-In` stores one entry per (peer, prefix) pair.  On each announce or
withdraw, best-path selection re-runs for the affected prefix and updates Loc-RIB.

Best-path selection order (simplified RFC 4271 §9.1.2):

1. Highest LOCAL_PREF (default 100 if absent)
2. Shortest AS_PATH length (AS_SETs count as 1)
3. Lowest MED
4. Lowest router-ID (tie-break)

The Loc-RIB entry is the source of truth for FIB installation (Phase 2).

---

## Thread Safety

| Resource  | Protection              |
|-----------|-------------------------|
| RIB       | `std.Thread.Mutex`      |
| Peer list | written only at startup, read-only after `start()` |
| Peer.stream | owned exclusively by peer thread |
| `running` flag | `std.atomic.Value(bool)` |

---

## Phase 2 Roadmap

| Feature | RFC / Notes |
|---------|-------------|
| FIB via netlink | `RTM_NEWROUTE` / `RTM_DELROUTE` on Linux |
| IPv6 unicast | MP_REACH_NLRI / MP_UNREACH_NLRI (type 14/15) |
| Passive peer mode | associate incoming TCP to configured peer |
| Route announcement | build UPDATE from Loc-RIB, send to peers |
| Import/export filters | per-peer route policies |
| Graceful restart | RFC 4724 |
| Route reflector | RFC 4456 (iBGP) |
