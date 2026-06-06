const std = @import("std");

pub const V4_PREFIX_LENGTH_LEN: usize = 1;
pub const V4_PREFIX_LENGTH_MAX: u8 = 32;

pub const PrefixDecodeError = error{
    BufferTooSmall,
    InvalidPrefixLen,
};

pub const PrefixEncodeError = error{BufferTooSmall};

pub const V4Prefix = struct {
    len: u8,
    addr: [4]u8,

    /// Number of prefix bytes on the wire.
    /// This is required since only significant bits of the prefix are encoded.
    pub fn octetsNeeded(self: V4Prefix) u8 {
        std.debug.print("len: {}\n", .{self.len});
        return std.math.divCeil(u8, self.len, 8) catch unreachable;
    }

    pub fn decode(buf: []const u8) PrefixDecodeError!struct { prefix: V4Prefix, consumed: usize } {
        if (buf.len < V4_PREFIX_LENGTH_LEN) return error.BufferTooSmall;

        var prefix = V4Prefix{ .len = buf[0], .addr = [_]u8{0} ** 4 };
        if (prefix.len > V4_PREFIX_LENGTH_MAX) return error.InvalidPrefixLen;

        // handle 0.0.0.0/0
        if (prefix.len == 0) return .{ .prefix = prefix, .consumed = V4_PREFIX_LENGTH_LEN };

        const octets_needed = prefix.octetsNeeded();
        if (buf.len < octets_needed + V4_PREFIX_LENGTH_LEN) return error.BufferTooSmall;
        @memcpy(prefix.addr[0..octets_needed], buf[V4_PREFIX_LENGTH_LEN .. V4_PREFIX_LENGTH_LEN + octets_needed]);

        return .{ .prefix = prefix, .consumed = V4_PREFIX_LENGTH_LEN + octets_needed };
    }

    pub fn encode(self: V4Prefix, buf: []u8) PrefixEncodeError!usize {
        const octets_needed = self.octetsNeeded();
        if (buf.len < V4_PREFIX_LENGTH_LEN + octets_needed) return error.BufferTooSmall;
        buf[0] = self.len;
        std.debug.print("octets_needed: {}\n", .{octets_needed});
        @memcpy(buf[V4_PREFIX_LENGTH_LEN .. V4_PREFIX_LENGTH_LEN + octets_needed], self.addr[0..octets_needed]);
        return V4_PREFIX_LENGTH_LEN + octets_needed;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "V4Prefix: octetsNeeded" {
    const p = V4Prefix{ .len = 0, .addr = .{ 0, 0, 0, 0 } };
    try std.testing.expectEqual(@as(u8, 0), p.octetsNeeded());
    try std.testing.expectEqual(@as(u8, 1), (V4Prefix{ .len = 1, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 1), (V4Prefix{ .len = 8, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 2), (V4Prefix{ .len = 9, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 3), (V4Prefix{ .len = 24, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
    try std.testing.expectEqual(@as(u8, 4), (V4Prefix{ .len = 32, .addr = .{ 0, 0, 0, 0 } }).octetsNeeded());
}

test "V4Prefix: decode 10.1.0.0/16" {
    // len=16 → 2 prefix bytes; consumed = 1 (len field) + 2 = 3
    const buf = [_]u8{ 0x10, 0x0A, 0x01 };
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 16), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 0, 0 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 3), r.consumed);
}

test "V4Prefix: decode default route 0.0.0.0/0" {
    // len=0 → 0 prefix bytes; consumed = 1
    const buf = [_]u8{0x00};
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 0), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 0, 0, 0, 0 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 1), r.consumed);
}

test "V4Prefix: decode 10.1.2.3/32" {
    // len=32 → 4 prefix bytes; consumed = 5
    const buf = [_]u8{ 0x20, 0x0A, 0x01, 0x02, 0x03 };
    const r = try V4Prefix.decode(&buf);
    try std.testing.expectEqual(@as(u8, 32), r.prefix.len);
    try std.testing.expectEqualSlices(u8, &[4]u8{ 10, 1, 2, 3 }, &r.prefix.addr);
    try std.testing.expectEqual(@as(usize, 5), r.consumed);
}

test "V4Prefix: encode 10.1.0.0/16" {
    const pref = V4Prefix{ .len = 16, .addr = .{ 10, 1, 0, 0 } };
    var buf = [_]u8{0} ** 8;
    const n = try pref.encode(&buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(u8, 0x10), buf[0]); // len=16
    try std.testing.expectEqual(@as(u8, 0x0A), buf[1]); // 10
    try std.testing.expectEqual(@as(u8, 0x01), buf[2]); // 1
}

test "V4Prefix: encode/decode round-trip" {
    const original = V4Prefix{ .len = 24, .addr = .{ 192, 168, 1, 0 } };
    var buf = [_]u8{0} ** 8;
    const n = try original.encode(&buf);
    const r = try V4Prefix.decode(buf[0..n]);
    try std.testing.expectEqual(original.len, r.prefix.len);
    try std.testing.expectEqualSlices(u8, &original.addr, &r.prefix.addr);
}

test "V4Prefix: error on prefix length > 32" {
    const buf = [_]u8{ 0x21, 0x0A }; // len=33
    try std.testing.expectError(error.InvalidPrefixLen, V4Prefix.decode(&buf));
}

test "V4Prefix: error on buffer too small for prefix data" {
    // len=24 → needs 3 prefix bytes, but only 1 byte follows the length field
    const buf = [_]u8{ 0x18, 0x0A };
    try std.testing.expectError(error.BufferTooSmall, V4Prefix.decode(&buf));
}
