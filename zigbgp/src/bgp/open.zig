const std = @import("std");

pub const BGP_VERSION: u8 = 4;
pub const AS_TRANS: u16 = 23456;
pub const MIN_MSG_LEN: usize = 10;

pub const OPT_PARAM_TL_LEN: usize = 2;
pub const OPT_PARAM_CAP_TYPE: u8 = 2;

pub const CAP_CODE_LENGTH_LEN: usize = 2;

pub const CAP_4_OCTET_AS_CODE: u8 = 65;
pub const CAP_ROUTE_REFRESH_CODE: u8 = 2;
pub const CAP_MULTIPROTOCOL_CODE: u8 = 1;

pub const CAP_4_OCTET_AS_LEN: usize = 4;
pub const CAP_ROUTE_REFRESH_LEN: usize = 0;
pub const CAP_MULTIPROTOCOL_LEN: usize = 4;

pub const CAP_MULTIPROTOCOL_IPV4_AFI: u16 = 1;
pub const CAP_MULTIPROTOCOL_IPV6_AFI: u16 = 2;
pub const CAP_MULTIPROTOCOL_UNICAST_SAFI: u8 = 1;

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
        if (version != BGP_VERSION) return error.UnsupportedVersion;

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
            pos += OPT_PARAM_TL_LEN;
            if (pos + param_len > opt_param_end) return error.InvalidLength; // bound check

            // check if param is capabilities
            if (param_type == OPT_PARAM_CAP_TYPE) {
                var cap_pos: usize = pos;
                const cap_end: usize = pos + param_len;

                while (cap_pos < cap_end) {
                    const cap_code = buf[cap_pos];
                    const cap_len = buf[cap_pos + 1];
                    cap_pos += CAP_CODE_LENGTH_LEN;
                    if (cap_pos + cap_len > cap_end) {
                        std.debug.print("cap_code: {d}, cap_pos: {d}, cap_len: {d}, cap_end: {d}\n", .{ cap_code, cap_pos, cap_pos, cap_end });
                        return error.InvalidLength; // bound check
                    }

                    switch (cap_code) {
                        CAP_4_OCTET_AS_CODE => { // 4-octet-AS
                            if (cap_len != CAP_4_OCTET_AS_LEN) return error.InvalidLength;
                            open.four_octet_as = std.mem.readInt(u32, buf[cap_pos..][0..CAP_4_OCTET_AS_LEN], .big);
                        },
                        CAP_ROUTE_REFRESH_CODE => { // route refresh
                            if (cap_len != CAP_ROUTE_REFRESH_LEN) return error.InvalidLength;
                            open.route_refresh = true;
                        },
                        CAP_MULTIPROTOCOL_CODE => { // multiprotocol
                            if (cap_len != CAP_MULTIPROTOCOL_LEN) return error.InvalidLength;
                            const afi = std.mem.readInt(u16, buf[cap_pos..][0..2], .big);
                            const safi = buf[cap_pos + 3]; // cap_pos+2 is reserved byte
                            if (afi == CAP_MULTIPROTOCOL_IPV4_AFI and safi == CAP_MULTIPROTOCOL_UNICAST_SAFI) open.mp_ipv4_unicast = true;
                            if (afi == CAP_MULTIPROTOCOL_IPV6_AFI and safi == CAP_MULTIPROTOCOL_UNICAST_SAFI) open.mp_ipv6_unicast = true;
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

    pub fn encode(self: Open, buf: []u8) !usize {
        if (buf.len < MIN_MSG_LEN) return error.BufferTooSmall;

        // write version
        buf[0] = BGP_VERSION;
        // write as
        std.mem.writeInt(u16, buf[1..3], self.my_as, .big);
        // write hold_time
        std.mem.writeInt(u16, buf[3..5], self.hold_time, .big);
        // write bgp id
        buf[5..9].* = self.bgp_id;
        // calc opt-param length
        var cap_len: usize = 0;
        if (self.four_octet_as) |_| cap_len += CAP_CODE_LENGTH_LEN + CAP_4_OCTET_AS_LEN;
        if (self.route_refresh) cap_len += CAP_CODE_LENGTH_LEN + CAP_ROUTE_REFRESH_LEN;
        if (self.mp_ipv4_unicast) cap_len += CAP_CODE_LENGTH_LEN + CAP_MULTIPROTOCOL_LEN;
        if (self.mp_ipv6_unicast) cap_len += CAP_CODE_LENGTH_LEN + CAP_MULTIPROTOCOL_LEN;
        const opt_param_len = if (cap_len > 0) cap_len + 2 else 0;
        buf[9] = @intCast(opt_param_len);
        if (opt_param_len == 0) return MIN_MSG_LEN; // no cap

        if (buf.len < MIN_MSG_LEN + opt_param_len) return error.BufferTooSmall;
        var pos: usize = MIN_MSG_LEN;
        // fill capabilities
        buf[pos] = OPT_PARAM_CAP_TYPE; // type capabilities
        buf[pos + 1] = @intCast(cap_len); // cap length
        pos += OPT_PARAM_TL_LEN;

        if (self.four_octet_as) |as| {
            buf[pos] = CAP_4_OCTET_AS_CODE;
            buf[pos + 1] = @intCast(CAP_4_OCTET_AS_LEN);
            std.mem.writeInt(u32, buf[pos + CAP_CODE_LENGTH_LEN ..][0..CAP_4_OCTET_AS_LEN], as, .big);
            pos += CAP_CODE_LENGTH_LEN + CAP_4_OCTET_AS_LEN;
        }
        if (self.route_refresh) {
            buf[pos] = CAP_ROUTE_REFRESH_CODE;
            buf[pos + 1] = @intCast(CAP_ROUTE_REFRESH_LEN);
            pos += CAP_CODE_LENGTH_LEN + CAP_ROUTE_REFRESH_LEN;
        }
        if (self.mp_ipv4_unicast) {
            buf[pos] = CAP_MULTIPROTOCOL_CODE;
            buf[pos + 1] = @intCast(CAP_MULTIPROTOCOL_LEN);
            std.mem.writeInt(u16, buf[pos + 2 ..][0..2], CAP_MULTIPROTOCOL_IPV4_AFI, .big);
            buf[pos + 4] = 0; // reserved
            buf[pos + 5] = CAP_MULTIPROTOCOL_UNICAST_SAFI;
            pos += CAP_CODE_LENGTH_LEN + CAP_MULTIPROTOCOL_LEN;
        }
        if (self.mp_ipv6_unicast) {
            buf[pos] = CAP_MULTIPROTOCOL_CODE;
            buf[pos + 1] = @intCast(CAP_MULTIPROTOCOL_LEN);
            std.mem.writeInt(u16, buf[pos + 2 ..][0..2], CAP_MULTIPROTOCOL_IPV6_AFI, .big);
            buf[pos + 4] = 0; // reserved
            buf[pos + 5] = CAP_MULTIPROTOCOL_UNICAST_SAFI;
            pos += CAP_CODE_LENGTH_LEN + CAP_MULTIPROTOCOL_LEN;
        }
        return MIN_MSG_LEN + opt_param_len;
    }
};

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
