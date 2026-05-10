# ZigBGP — Implementation Guide

We build **top-down**: Speaker → Peer → message codec → RIB.
This lets you validate each layer against a real GoBGP peer as soon as possible.

---

## Validation setup

Run a GoBGP peer locally:

```bash
# gobgpd config (gobgp.toml)
[global.config]
  as = 65002
  router-id = "10.0.0.2"

[[neighbors]]
  [neighbors.config]
    neighbor-address = "127.0.0.1"
    peer-as = 65001

gobgpd -f gobgp.toml
gobgp neighbor   # watch session state
```

At each implementation milestone you should be able to observe the session
advancing from `Idle` → `Active` → `OpenSent` → `OpenConfirm` → `Established`.

---

## Step 1 — `config.zig` (library configuration types)

These are the only types the library consumer ever touches directly.

```zig
// src/config.zig
pub const LocalConfig = struct {
    as_number:   u32,
    router_id:   [4]u8,
    listen_port: u16 = 179,
};

pub const PeerConfig = struct {
    address:    std.net.Address,
    remote_as:  u32,
    hold_time:  u16 = 90,   // 0 = disable hold/keepalive timers
    passive:    bool = false,
};
```

**Why `[4]u8` for router_id?**  BGP identifies each speaker with a 32-bit
"BGP Identifier" sent in OPEN.  Conventionally it looks like an IPv4 address
(`10.0.0.1`) but it is just an opaque u32 in network byte order — any unique
value per AS works.

---

## Step 2 — `bgp/speaker.zig` (library entry point)

Start here.  The Speaker owns everything and defines the public API surface.
You can implement it as a stub first and flesh it out as you add layers.

### What Speaker must own

```zig
pub const Speaker = struct {
    allocator:    std.mem.Allocator,
    cfg:          config.LocalConfig,
    peers:        std.ArrayList(*Peer),   // heap-allocated, stable pointers
    rib:          Rib,
    server:       ?std.net.Server,
    accept_thread: ?std.Thread,
    running:      std.atomic.Value(bool),
};
```

### Why heap-allocate peers?

Peer threads hold a `*Peer` pointer.  If peers were stored by value in an
ArrayList the pointer would be invalidated every time the list grows.  Allocate
each Peer with `allocator.create(Peer)` and store pointers.

### Minimal API to implement first

```zig
pub fn init(allocator, local_cfg) Speaker
pub fn deinit(self) void
pub fn addPeer(self, peer_cfg) !void
pub fn start(self) !void      // spawn peer threads + accept thread
pub fn stop(self) void        // signal all threads, join them
```

### Accept thread

Listens on `cfg.listen_port` (default 179).  For Phase 1 you only need it to
`accept()` and log the incoming address — passive peer handling comes later.

```zig
const addr = std.net.Address.initIp4(.{0,0,0,0}, self.cfg.listen_port);
self.server = try addr.listen(.{ .reuse_address = true });
```

**Validation checkpoint**: after implementing this skeleton (no BGP messages yet),
running the binary should print the accept-thread startup log and GoBGP should
show the neighbor as `Active` (TCP connection refused → Active retry).

---

## Step 3 — `bgp/peer.zig` (per-peer session thread)

### Thread lifecycle

```zig
pub fn start(self: *Peer) !void {
    self.running.store(true, .release);
    self.thread = try std.Thread.spawn(.{}, run, .{self});
}
```

The `run` function loops: connect → session → error → wait → repeat.

### TCP connect

```zig
const stream = try std.net.tcpConnectToAddress(self.peer_cfg.address);
```

On failure, log and sleep 30 s before retrying.  FSM state during this loop is
`connect` (attempting) → `active` (failed, waiting to retry).

### Receive loop with poll

Use `std.posix.poll` with a 1-second timeout rather than blocking read.  This
lets you check timers on every iteration without needing threads or async I/O.

```zig
var fds = [_]std.posix.pollfd{
    .{ .fd = stream.handle, .events = std.posix.POLL.IN, .revents = 0 },
};
_ = try std.posix.poll(&fds, 1000);  // 1000 ms
// check timers regardless of poll result
if (fds[0].revents & std.posix.POLL.IN != 0) { /* read */ }
if (fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0) { /* error */ }
```

### Recv buffer management

BGP messages can be split across multiple TCP reads.  Keep a ring-less sliding
buffer:

```zig
recv_buf: [MAX_MSG_SIZE * 2]u8,  // double-buffered so a max message always fits
recv_len: usize,
```

After every read, attempt to parse as many complete messages as possible from
`recv_buf[0..recv_len]`.  When a message is consumed, shift remaining bytes to
the front with `std.mem.copyForwards`.

```
[  consumed msg  |  partial msg  |  empty space  ]
                  ↑ shift this to front
```

### Stop signal

```zig
running: std.atomic.Value(bool)
```

The poll loop checks `self.running.load(.acquire)` on every iteration.  When
`stop()` sets it false and closes the stream, the thread unblocks from poll and
exits cleanly.

**Validation checkpoint**: at this point your peer thread should TCP-connect to
GoBGP.  GoBGP will see the connection and immediately send an OPEN.  Your
thread will receive bytes — confirm with a hex dump log before implementing the
parser.

---

## Step 4 — `bgp/message.zig` (wire header)

The absolute minimum to make progress: parse the 19-byte header so you know
where each message ends.

```
[0..16]  marker = 0xFF × 16
[16..18] length (big-endian u16, includes the header itself)
[18]     type
```

Key validations:
- Marker must be all 0xFF (if not → NOTIFICATION: Message Header Error, subcode 1)
- `length >= 19` and `length <= 4096`
- `length <= bytes_available` (may need to wait for more data)

```zig
pub const HEADER_LEN: usize = 19;
pub const MAX_MSG_LEN: usize = 4096;

pub const MsgType = enum(u8) {
    open         = 1,
    update       = 2,
    notification = 3,
    keepalive    = 4,
    _,             // non-exhaustive: unknown types are legal to receive, must error
};
```

**Why `_` (non-exhaustive)?**  RFC 4271 §6.1: receiving an unknown type must
generate a NOTIFICATION (Bad Message Type).  The `_` variant lets you write
`switch` with an `else` branch that sends the NOTIFICATION rather than
panicking.

---

## Step 5 — `bgp/open.zig` (OPEN message)

### OPEN body layout (after header)

```
Version(1) | My-AS(2) | Hold-Time(2) | BGP-ID(4) | Opt-Parm-Len(1) | Opt-Params(N)
```

Minimum valid body: 10 bytes.

### Capability negotiation

Optional parameters are TLV with `type=2` (Capabilities).  Inside each
capability parameter: `cap-code(1) | cap-len(1) | cap-data(N)`.

**4-byte AS (RFC 6793)**: if the peer's AS number > 65535, it cannot fit in the
2-byte `My-AS` field.  The wire value is set to 23456 (`AS_TRANS`), and the real
AS is carried in capability 65 (4-octet AS).  Your decoder must check for this
and prefer the capability value.

```zig
pub fn asNumber(self: Open) u32 {
    return self.four_octet_as orelse self.my_as;
}
```

**Multiprotocol (RFC 4760)**: capability 1 announces which AFI/SAFI the peer
supports.  For IPv4 unicast: AFI=1, SAFI=1.  Log which AFIs the peer advertises;
for now you only need to handle IPv4 unicast.

### Validation on receive

1. `version == 4` → else NOTIFICATION: Unsupported Version Number
2. `remote_as == peer_cfg.remote_as` → else NOTIFICATION: Bad Peer AS
3. `hold_time == 0 || hold_time >= 3` → else NOTIFICATION: Unacceptable Hold Time

### Encoding your OPEN

Build the optional parameters block first (capabilities), then write the fixed
fields.  You know the lengths up front so a single fixed-size stack buffer is
enough — no allocation needed.

**Validation checkpoint**: GoBGP should transition to `OpenConfirm`.  If it
shows `OpenSent` your OPEN was received but GoBGP rejected it — check the
NOTIFICATION it sends back (decode it and log the error code).

---

## Step 6 — KEEPALIVE exchange

A KEEPALIVE is just a bare header with `type=4` and `length=19`.  No body.

Send one immediately after receiving and validating the peer's OPEN.  The peer
will send one back, completing the four-way handshake:

```
You          Peer
OPEN    →
         ←  OPEN
KEEPALIVE →
         ←  KEEPALIVE   ← session is Established here
```

After Established, send a KEEPALIVE every `hold_time / 3` seconds and reset the
hold timer each time you receive a KEEPALIVE or UPDATE.

### Timer implementation

Store deadlines as `?i64` (millisecond timestamp from `std.time.milliTimestamp()`):

```zig
hold_deadline: ?i64 = null,
ka_deadline:   ?i64 = null,

fn resetHoldTimer(self: *Peer) void {
    if (self.negotiated_hold == 0) { self.hold_deadline = null; return; }
    self.hold_deadline = std.time.milliTimestamp()
        + @as(i64, self.negotiated_hold) * 1000;
}

fn resetKaTimer(self: *Peer) void {
    const secs = @as(i64, self.negotiated_hold) / 3;
    self.ka_deadline = if (secs > 0)
        std.time.milliTimestamp() + secs * 1000
    else null;
}
```

Check both in `checkTimers()` which is called on every poll iteration.

**Validation checkpoint**: GoBGP shows `Established`.  You will see periodic
KEEPALIVE messages in each direction.  The session should stay up indefinitely.

---

## Step 7 — `bgp/notification.zig`

NOTIFICATION body: `error-code(1) | error-subcode(1) | data(N)`.

Define all error codes and subcodes as enums — this makes logs readable and
switch-exhaustiveness checking useful.

Key codes you will encounter early:
- `2/2` Open Message Error / Bad Peer AS
- `2/6` Open Message Error / Unacceptable Hold Time
- `4/0` Hold Timer Expired
- `6/2` Cease / Admin Shutdown

Always send a NOTIFICATION before dropping the TCP connection (except when the
connection is already broken).

---

## Step 8 — `bgp/update.zig` (UPDATE message)

### UPDATE body layout

```
Withdrawn-Len(2) | Withdrawn(N) | Attr-Len(2) | Path-Attrs(N) | NLRI(rest)
```

An UPDATE can carry withdrawn routes, new routes, or both.  If Attr-Len and
NLRI are both zero, it is a withdraw-only message.

### Prefix encoding (BGP NLRI format)

Prefixes are encoded as `prefix-len(1) | significant-octets`.  Only the octets
that contain non-zero bits are sent:

```
10.0.0.0/8   → [0x08, 0x0A]             (1 significant octet)
192.168.1.0/24 → [0x18, 0xC0, 0xA8, 0x01]  (3 significant octets)
0.0.0.0/0    → [0x00]                   (0 significant octets)
```

Decode: read `len`, compute `(len+7)/8` byte count, read that many bytes, zero-
pad to 4 bytes.

### Path attribute flags

```
bit 7 (0x80): Optional     (0 = well-known)
bit 6 (0x40): Transitive   (must be forwarded even if not recognised)
bit 5 (0x20): Partial      (set when transitive attr not fully processed)
bit 4 (0x10): Extended Len (1 = 2-byte length field instead of 1-byte)
```

Mandatory attributes for a valid UPDATE with NLRI:
- ORIGIN (type 1)
- AS_PATH (type 2)
- NEXT_HOP (type 3)

### AS_PATH segment format

```
type(1) | count(1) | ASN_0(4) | ASN_1(4) | ...
```

Types: `1=AS_SET`  `2=AS_SEQUENCE`.  For 4-byte ASNs the count field is the
number of 4-byte entries.

When computing AS_PATH length for best-path selection:
- AS_SEQUENCE contributes one per ASN
- AS_SET contributes 1 regardless of size

**Validation checkpoint**: with GoBGP advertising routes, you should see UPDATE
messages.  Log the decoded prefixes and next-hop and verify they match what
`gobgp global rib` shows.

---

## Step 9 — `rib/prefix.zig` and `rib/path_attr.zig`

These are pure data types with no threading concerns.  Implement and unit-test
them in isolation before wiring into the peer.

### Prefix unit tests to write

```zig
// encode/decode round-trip for /0, /8, /24, /32
// eql(): same network, different host bits → equal
// networkAddr(): mask applied correctly
```

### PathAttrs unit tests to write

```zig
// decode a hand-crafted byte slice, check all fields
// clone() produces independent allocations
// deinit() on cloned copy doesn't affect original
```

---

## Step 10 — `rib/rib.zig`

Wire up to the peer: on each UPDATE, call `rib.update()` for each NLRI prefix
and `rib.withdraw()` for each withdrawn prefix.  On session drop, call
`rib.withdrawAll(peer_addr)`.

### Route change callback

After Loc-RIB is updated, fire a callback so the application can react:

```zig
pub const RouteEvent = struct {
    prefix:    V4Prefix,
    is_withdraw: bool,
    entry:     ?RibEntry,  // null on withdraw
};

// Speaker field:
on_route_change: ?*const fn (RouteEvent) void = null,
```

This is the hook Phase 2 FIB installation will use.

---

## Common Pitfalls

**Big-endian everywhere.**  All multi-byte BGP fields are big-endian on the
wire.  Use `std.mem.readInt(u16, buf[0..2], .big)` and
`std.mem.writeInt(u16, buf[0..2], val, .big)` — never cast raw pointer.

**Length includes the header.**  `Header.length` is the total message size
including the 19-byte header, so the body starts at offset 19 and has length
`header.length - 19`.

**Partial reads.**  TCP is a stream — one `read()` call may return less than a
full BGP message.  Always accumulate into a buffer and only process when
`recv_len >= header.length`.

**Hold time = 0 is valid.**  Some implementations send hold_time=0 to opt out
of keepalives entirely.  Your timer logic must handle this (no timer started,
no NOTIFICATION on expiry).

**AS_TRANS.**  When you send an OPEN with a 4-byte AS > 65535, put 23456 in the
2-byte `My-AS` field and include the real AS in capability 65.  Likewise, when
decoding the peer's OPEN, always prefer capability 65 over the `My-AS` field.

**errdefer for partial allocations.**  `PathAttrs.decode` allocates `as_path`
segments and `communities` separately.  Use `errdefer attrs.deinit(allocator)`
at the top so any mid-parse error releases what was already allocated.

**Pointer stability.**  Store peers as `*Peer` (pointers), not `Peer` (values),
in the Speaker's peer list.  An ArrayList of values will reallocate and
invalidate pointers when it grows.
