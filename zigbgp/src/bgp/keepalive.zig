const std = @import("std");
const message = @import("message.zig");

/// encodes keepalive message into the buffer
pub fn encode(buf: []u8) !void {
    // keepalive must be just a header
    if (buf.len < message.HEADER_LEN) return error.BufferTooSmall;
    const h = message.Header{ .length = message.HEADER_LEN, .msg_type = .keepalive };
    try h.encode(buf);
}

/// validates the header
pub fn validate(header: message.Header) !void {
    if (header.length != message.HEADER_LEN) return error.UnexpectedBody;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "encode: produces a valid 19-byte BGP KEEPALIVE" {
    var buf = [_]u8{0} ** 19;
    try encode(&buf);

    // marker
    for (buf[0..16]) |b| try std.testing.expectEqual(@as(u8, 0xFF), b);
    // length = 19 in big-endian
    try std.testing.expectEqual(@as(u8, 0x00), buf[16]);
    try std.testing.expectEqual(@as(u8, 0x13), buf[17]);
    // type = 4 (KEEPALIVE)
    try std.testing.expectEqual(@as(u8, 0x04), buf[18]);
}

test "encode: error on buffer smaller than 19 bytes" {
    var buf = [_]u8{0} ** 18;
    try std.testing.expectError(error.BufferTooSmall, encode(&buf));
}

test "encode: accepts buffer larger than 19 bytes (only writes first 19)" {
    // The peer passes its full send buffer; encode must not reject it.
    var buf = [_]u8{0} ** 256;
    try encode(&buf);
    try std.testing.expectEqual(@as(u8, 0x04), buf[18]);
    // bytes beyond the header are untouched
    try std.testing.expectEqual(@as(u8, 0x00), buf[19]);
}

test "validate: accepts a correct KEEPALIVE header" {
    const h = message.Header{ .length = 19, .msg_type = .keepalive };
    try validate(h);
}

test "validate: error when length != 19 (unexpected body bytes)" {
    // A KEEPALIVE with any body is a protocol violation.
    const h = message.Header{ .length = 25, .msg_type = .keepalive };
    try std.testing.expectError(error.UnexpectedBody, validate(h));
}
