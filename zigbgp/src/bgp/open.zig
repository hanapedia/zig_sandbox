const std = @import("std");

pub const AS_TRANS: u16 = 23456;
pub const MIN_MSG_LEN: usize = 10;
pub const CAP_4_OCTET_AS_LEN: usize = 4;
pub const CAP_ROUTE_REFRESH_LEN: usize = 0;
pub const CAP_MULTIPROTOCOL_LEN: usize = 4;

pub const Open = struct {
    version: u8, // protocol version
    my_as: u16,
    hold_time: u16,
    bgp_id: [4]u8,
    // capabilities
    four_octet_as: ?u32 = null, // capability code 65
    route_refresh: bool = false, // capability code 2
    mp_ipv4_unicast: bool = false, // capability code 1, AFI=1 SAFI=1
    mp_ipv6_unicast: bool = false, // capability code 1, AFI=2 SAFI=1

    /// Returns the real AS number: four_octet_as if present, otherwise my_as.
    pub fn asNumber(self: Open) u32 {
        if (self.four_octet_as) |as| return as;
        return @intCast(self.my_as);
    }

    /// Parse an OPEN message body (everything after the 19-byte BGP header). No allocation.
    pub fn decode(buf: []const u8) !Open {
        if (buf.len < MIN_MSG_LEN) return error.BufferTooSmall;
        // parse version
        const version = buf[0];
        if (version != 4) return error.UnsupportedVersion;

        // parse and assign basic fields
        var open = Open{
            .version = version,
            .my_as = std.mem.readInt(u16, buf[1..3], .big),
            .hold_time = std.mem.readInt(u16, buf[3..5], .big),
            .bgp_id = buf[5..9].*,
        };

        // parse capabilities
        const opt_param_len: usize = @intCast(buf[9]);
        if (buf.len < MIN_MSG_LEN + opt_param_len) return error.BufferTooSmall;
        if (opt_param_len == 0) return open;

        var pos: usize = MIN_MSG_LEN;
        const opt_param_end = pos + opt_param_len;
        while (pos < opt_param_end) {
            const param_type = buf[pos];
            const param_len = buf[pos + 1];
            pos += 2;
            if (pos + param_len > opt_param_end) return error.InvalidLength; // bound check

            // check if param is capabilities
            if (param_type == 2) {
                var cap_pos: usize = pos;
                const cap_end: usize = pos + param_len;

                while (cap_pos < cap_end) {
                    const cap_code = buf[cap_pos];
                    const cap_len = buf[cap_pos + 1];
                    cap_pos += 2;
                    if (cap_pos + cap_len > cap_end) return error.InvalidLength; // bound check

                    switch (cap_code) {
                        65 => { // 4-octet-AS
                            if (cap_len != CAP_4_OCTET_AS_LEN) return error.InvalidLength;
                            open.four_octet_as = std.mem.readInt(u32, buf[cap_pos .. cap_pos + CAP_4_OCTET_AS_LEN], .big);
                        },
                        2 => { // route reflesh
                            if (cap_len != CAP_ROUTE_REFRESH_LEN) return error.InvalidLength;
                            open.route_refresh = true;
                        },
                        1 => { // multiprotocol
                            if (cap_len != CAP_MULTIPROTOCOL_LEN) return error.InvalidLength;
                            const afi = std.mem.readInt(u16, buf[cap_pos .. cap_pos + 2], .big);
                            const safi = buf[cap_pos + 3]; // cap_pos+2 is reserved byte
                            if (afi == 1 and safi == 1) open.mp_ipv4_unicast = true;
                            if (afi == 2 and safi == 1) open.mp_ipv6_unicast = true;
                        },
                        //
                        else => {}, // skip unknown
                    }
                    cap_pos += cap_len;
                }
            }
            pos += param_len;
        }

        return open;
    }
};

// ── Implementation targets ────────────────────────────────────────────────────
//
// Make the tests below pass by implementing:
//
//   pub const AS_TRANS: u16 = 23456;  // placeholder AS when real AS > 65535 (RFC 6793)
//
//   pub const Open = struct {
//       version:         u8,
//       my_as:           u16,     // 2-byte wire value; may be AS_TRANS
//       hold_time:       u16,
//       bgp_id:          [4]u8,
//       // parsed capabilities
//       four_octet_as:   ?u32 = null,   // from capability code 65
//       route_refresh:   bool = false,  // capability code 2
//       mp_ipv4_unicast: bool = false,  // capability code 1, AFI=1 SAFI=1
//       mp_ipv6_unicast: bool = false,  // capability code 1, AFI=2 SAFI=1
//
//       /// Returns the real AS number: four_octet_as if present, otherwise my_as.
//       pub fn asNumber(self: Open) u32
//
//       /// Parse an OPEN message body (everything after the 19-byte BGP header).
//       /// No allocation — capabilities map to fixed boolean/optional fields.
//       pub fn decode(buf: []const u8) !Open
//
//       /// Write an OPEN message body into buf. Returns bytes written.
//       /// Writes capability 65 if four_octet_as is set.
//       /// Writes capability 2  if route_refresh is true.
//       /// Writes capability 1  for each mp_ipv4_unicast / mp_ipv6_unicast set.
//       pub fn encode(self: Open, buf: []u8) !usize
//   };
//
// OPEN body wire layout (RFC 4271 §4.2), follows the 19-byte BGP header:
//
//   Version(1) | My-AS(2) | Hold-Time(2) | BGP-ID(4) | Opt-Parm-Len(1) | Opt-Params(N)
//   minimum body: 10 bytes
//
// Optional parameters are TLV: type(1) | length(1) | value(N)
//   Only type=2 (Capabilities) is used.
//
// Each capability inside: cap-code(1) | cap-len(1) | cap-data(N)
//
// Capabilities:
//   code 1  Multiprotocol Extensions — AFI(2) + reserved(1) + SAFI(1)
//   code 2  Route Refresh            — no data
//   code 65 4-Octet AS Number        — ASN(4)
//
// Errors to define:
//   error.BufferTooSmall      — body shorter than 10 bytes
//   error.UnsupportedVersion  — version ≠ 4

// ── Tests ─────────────────────────────────────────────────────────────────────

test "decode: minimal OPEN with no optional parameters" {
    var buf = [_]u8{
        0x04, // version = 4
        0xFD, 0xE9, // my_as = 65001
        0x00, 0x5A, // hold_time = 90
        0x0A, 0x00, 0x00, 0x01, // bgp_id = 10.0.0.1
        0x00, // opt_parm_len = 0
    };
    const msg = try Open.decode(&buf);
    try std.testing.expectEqual(@as(u8, 4), msg.version);
    try std.testing.expectEqual(@as(u16, 65001), msg.my_as);
    try std.testing.expectEqual(@as(u16, 90), msg.hold_time);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 0, 0, 1 }, &msg.bgp_id);
    try std.testing.expectEqual(@as(?u32, null), msg.four_octet_as);
    try std.testing.expect(!msg.route_refresh);
    try std.testing.expect(!msg.mp_ipv4_unicast);
}

test "decode: hold_time = 0 is valid" {
    // RFC 4271 §4.2: hold_time = 0 explicitly disables keepalive timers.
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00, 0x00, // hold_time = 0
        0x0A, 0x00,
        0x00, 0x01,
        0x00,
    };
    const msg = try Open.decode(&buf);
    try std.testing.expectEqual(@as(u16, 0), msg.hold_time);
}

test "decode: error on wrong version" {
    var buf = [_]u8{
        0x03, // version = 3, must be 4
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x00,
    };
    try std.testing.expectError(error.UnsupportedVersion, Open.decode(&buf));
}

test "decode: error on buffer shorter than minimum body" {
    var buf = [_]u8{ 0x04, 0xFD, 0xE9, 0x00, 0x5A }; // 5 bytes, need ≥ 10
    try std.testing.expectError(error.BufferTooSmall, Open.decode(&buf));
}

test "decode: 4-octet AS capability (RFC 6793)" {
    // When a peer's AS > 65535 it puts AS_TRANS (23456) in my_as and
    // carries the real AS in capability code 65.
    var buf = [_]u8{
        0x04,
        0x5B, 0xA0, // my_as = AS_TRANS = 23456
        0x00, 0x5A,
        0x0A, 0x00,
        0x00, 0x02,
        0x08, // opt_parm_len = 8
        0x02, 0x06, // param: type=2 (capabilities), len=6
        0x41, 0x04, // cap code=65, cap len=4
        0x00, 0x02, 0x00, 0x01, // ASN = 131073
    };
    const msg = try Open.decode(&buf);
    try std.testing.expectEqual(@as(u16, 23456), msg.my_as);
    try std.testing.expectEqual(@as(u32, 131073), msg.four_octet_as.?);
}

test "asNumber: returns four_octet_as when capability 65 is present" {
    var buf = [_]u8{
        0x04,
        0x5B, 0xA0, // my_as = AS_TRANS
        0x00, 0x5A,
        0x0A, 0x00,
        0x00, 0x02,
        0x08, 0x02,
        0x06, 0x41,
        0x04,
        0x00, 0x02, 0x00, 0x01, // ASN = 131073
    };
    const msg = try Open.decode(&buf);
    try std.testing.expectEqual(@as(u32, 131073), msg.asNumber());
}

test "asNumber: falls back to my_as when capability 65 is absent" {
    var buf = [_]u8{
        0x04,
        0xFD, 0xE9, // my_as = 65001
        0x00, 0x5A,
        0x0A, 0x00,
        0x00, 0x01,
        0x00,
    };
    const msg = try Open.decode(&buf);
    try std.testing.expectEqual(@as(u32, 65001), msg.asNumber());
}

test "decode: route refresh capability (code 2)" {
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x04, // opt_parm_len = 4
        0x02, 0x02, // param: type=2, len=2
        0x02, 0x00, // cap code=2 (route refresh), cap len=0
    };
    const msg = try Open.decode(&buf);
    try std.testing.expect(msg.route_refresh);
}

test "decode: multiprotocol IPv4 unicast capability (code 1, AFI=1 SAFI=1)" {
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x08, // opt_parm_len = 8
        0x02, 0x06, // param: type=2, len=6
        0x01, 0x04, // cap code=1, cap len=4
        0x00, 0x01, 0x00, 0x01, // AFI=1 (IPv4), reserved=0, SAFI=1 (unicast)
    };
    const msg = try Open.decode(&buf);
    try std.testing.expect(msg.mp_ipv4_unicast);
    try std.testing.expect(!msg.mp_ipv6_unicast);
}

test "decode: multiprotocol IPv6 unicast capability (code 1, AFI=2 SAFI=1)" {
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x08,
        0x02,
        0x06,
        0x01,
        0x04,
        0x00, 0x02, 0x00, 0x01, // AFI=2 (IPv6), reserved=0, SAFI=1 (unicast)
    };
    const msg = try Open.decode(&buf);
    try std.testing.expect(!msg.mp_ipv4_unicast);
    try std.testing.expect(msg.mp_ipv6_unicast);
}

test "decode: unknown capability is silently skipped" {
    // RFC 5492 §4: a speaker MUST ignore unrecognised capabilities.
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x06, // opt_parm_len = 6
        0x02, 0x04, // param: type=2, len=4
        0xFF, 0x02, 0xDE, 0xAD, // unknown cap code=255, len=2, data=0xDEAD
    };
    _ = try Open.decode(&buf); // must not return an error
}

test "decode: multiple capabilities in one optional parameter" {
    // All three known capabilities packed into a single type-2 optional parameter.
    // Capabilities: route-refresh(2B) + 4-octet-AS(6B) + mp-ipv4(6B) = 14B
    // Opt param:    type(1) + len(1) + 14 = 16B  →  opt_parm_len = 0x10
    var buf = [_]u8{
        0x04,
        0xFD,
        0xE9,
        0x00,
        0x5A,
        0x0A,
        0x00,
        0x00,
        0x01,
        0x10, // opt_parm_len = 16
        0x02, 0x0E, // param: type=2, len=14
        0x02, 0x00, // route refresh
        0x41, 0x04, 0x00, 0x00, 0xFD, 0xE9, // 4-octet AS = 65001
        0x01, 0x04, 0x00, 0x01, 0x00, 0x01, // multiprotocol IPv4 unicast
    };
    const msg = try Open.decode(&buf);
    try std.testing.expect(msg.route_refresh);
    try std.testing.expectEqual(@as(u32, 65001), msg.four_octet_as.?);
    try std.testing.expect(msg.mp_ipv4_unicast);
}

test "encode/decode round-trip" {
    // Encode an Open, decode the result, verify all fields survive.
    const original = Open{
        .version = 4,
        .my_as = 23456, // AS_TRANS; real AS carried in four_octet_as
        .hold_time = 90,
        .bgp_id = .{ 10, 0, 0, 1 },
        .four_octet_as = 131073,
        .route_refresh = true,
        .mp_ipv4_unicast = true,
    };

    var buf: [256]u8 = undefined;
    const n = try original.encode(&buf);

    const decoded = try Open.decode(buf[0..n]);
    try std.testing.expectEqual(original.version, decoded.version);
    try std.testing.expectEqual(original.my_as, decoded.my_as);
    try std.testing.expectEqual(original.hold_time, decoded.hold_time);
    try std.testing.expectEqualSlices(u8, &original.bgp_id, &decoded.bgp_id);
    try std.testing.expectEqual(original.four_octet_as, decoded.four_octet_as);
    try std.testing.expectEqual(original.route_refresh, decoded.route_refresh);
    try std.testing.expectEqual(original.mp_ipv4_unicast, decoded.mp_ipv4_unicast);
}

test "encode: error on buffer too small" {
    const msg = Open{
        .version = 4,
        .my_as = 65001,
        .hold_time = 90,
        .bgp_id = .{ 10, 0, 0, 1 },
    };
    var buf: [4]u8 = undefined; // too small even for the fixed 10-byte body
    try std.testing.expectError(error.BufferTooSmall, msg.encode(&buf));
}
