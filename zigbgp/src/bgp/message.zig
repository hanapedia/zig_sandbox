const std = @import("std");

// Wire layout (RFC 4271 §4.1):
//
//   [0..16)  marker  — 16 bytes, all 0xFF
//   [16..18) length  — u16 big-endian; value includes the header itself
//   [18]     type    — u8
//
// Errors
//   error.BufferTooSmall  — buf shorter than HEADER_LEN
//   error.InvalidMarker   — any marker byte ≠ 0xFF
//   error.InvalidLength   — length < HEADER_LEN or length > MAX_MSG_LEN
//

pub const HEADER_LEN: usize = 19;
pub const MAX_MSG_LEN: usize = 4096;

pub const MessageType = enum(u8) {
    open = 1,
    update = 2,
    notification = 3,
    keepalive = 4,
    _,
};

pub const Header = struct {
    length: u16,
    msg_type: MessageType,

    pub fn decode(buf: []u8) !Header {
        if (buf.len < HEADER_LEN) return error.BufferTooSmall;

        // parse marker
        const marker = buf[0..16];
        if (!std.mem.allEqual(u8, marker, 0xFF)) return error.InvalidMarker;

        // parse length
        const length_bytes = buf[16..18];
        const length = std.mem.readInt(u16, length_bytes, .big);
        if (length < HEADER_LEN or length > MAX_MSG_LEN) return error.InvalidLength;

        // parse message type
        const msg_type = buf[18];

        return Header{
            .length = length,
            .msg_type = @enumFromInt(msg_type),
        };
    }

    pub fn encode(self: Header, buf: []u8) !void {
        if (buf.len < HEADER_LEN) return error.BufferTooSmall;

        // encode marker
        @memset(buf[0..16], 0xFF);

        // encode length
        std.mem.writeInt(u16, buf[16..18], self.length, .big);

        // encode type
        buf[18] = @intFromEnum(self.msg_type);
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "decode: valid KEEPALIVE header" {
    // KEEPALIVE is the simplest BGP message — a bare header with length=19, type=4.
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x00, 0x13, 0x04 };
    const h = try Header.decode(&buf);
    try std.testing.expectEqual(@as(u16, 19), h.length);
    try std.testing.expectEqual(MessageType.keepalive, h.msg_type);
}

test "decode: valid OPEN header" {
    // OPEN bodies are at least 10 bytes, so total length > 19.
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x00, 0x2D, 0x01 }; // length=45, type=OPEN
    const h = try Header.decode(&buf);
    try std.testing.expectEqual(@as(u16, 45), h.length);
    try std.testing.expectEqual(MessageType.open, h.msg_type);
}

test "decode: unknown type is accepted by the header decoder" {
    // The header decoder must NOT error on an unknown type — the peer layer is
    // responsible for sending NOTIFICATION(Bad Message Type) after inspecting
    // h.msg_type.  The non-exhaustive enum (_) lets callers handle it with else.
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x00, 0x13, 0xFF };
    const h = try Header.decode(&buf);
    try std.testing.expectEqual(@as(u8, 0xFF), @intFromEnum(h.msg_type));
}

test "decode: error on buffer shorter than HEADER_LEN" {
    var buf = [_]u8{0xFF} ** 10;
    try std.testing.expectError(error.BufferTooSmall, Header.decode(&buf));
}

test "decode: error on invalid marker (one byte corrupted)" {
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x00, 0x13, 0x04 };
    buf[7] = 0x00;
    try std.testing.expectError(error.InvalidMarker, Header.decode(&buf));
}

test "decode: error on length below minimum" {
    // length=18 is below the 19-byte minimum (header alone is 19 bytes)
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x00, 0x12, 0x04 };
    try std.testing.expectError(error.InvalidLength, Header.decode(&buf));
}

test "decode: error on length above maximum" {
    // length=4097 exceeds the 4096-byte BGP maximum
    var buf = ([1]u8{0xFF} ** 16) ++ [3]u8{ 0x10, 0x01, 0x02 };
    try std.testing.expectError(error.InvalidLength, Header.decode(&buf));
}

test "encode: writes correct marker, length, and type" {
    var buf = [_]u8{0} ** 19;
    const h = Header{
        .length = 19,
        .msg_type = .keepalive,
    };
    try h.encode(&buf);

    for (buf[0..16]) |b| try std.testing.expectEqual(@as(u8, 0xFF), b);
    try std.testing.expectEqual(@as(u8, 0x00), buf[16]); // length high byte
    try std.testing.expectEqual(@as(u8, 0x13), buf[17]); // length low byte (19 = 0x13)
    try std.testing.expectEqual(@as(u8, 0x04), buf[18]); // type = keepalive
}

test "encode: error on buffer shorter than HEADER_LEN" {
    var buf = [_]u8{0} ** 18;
    const h = Header{ .length = 19, .msg_type = .keepalive };
    try std.testing.expectError(error.BufferTooSmall, h.encode(&buf));
}

test "encode/decode round-trip" {
    var buf = [_]u8{0} ** 19;
    const original = Header{
        .length = 256,
        .msg_type = .update,
    };
    try original.encode(&buf);
    const decoded = try Header.decode(&buf);
    try std.testing.expectEqual(original.length, decoded.length);
    try std.testing.expectEqual(original.msg_type, decoded.msg_type);
}
