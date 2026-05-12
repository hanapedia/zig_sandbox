const std = @import("std");

const MIN_MSG_LEN: usize = 2;

pub const ErrorCode = enum(u8) {
    message_header = 1,
    open_message = 2,
    update_message = 3,
    hold_timer_expired = 4,
    fsm_error = 5,
    cease = 6,
    _,
};

pub const MsgHeaderSubcode = enum(u8) { not_synchronized = 1, bad_length = 2, bad_type = 3, _ };
pub const OpenSubcode = enum(u8) { unsupported_version = 1, bad_peer_as = 2, bad_bgp_id = 3, unsupported_opt_param = 4, unacceptable_hold_time = 6, _ };
pub const CeaseSubcode = enum(u8) { admin_shutdown = 2, peer_deconfigured = 3, admin_reset = 4, _ };

pub const Notification = struct {
    error_code: ErrorCode,
    error_subcode: u8,
    /// points into the source buffer
    data: []const u8,

    pub fn decode(buf: []const u8) !Notification {
        if (buf.len < MIN_MSG_LEN) return error.BufferTooSmall;
        return Notification{
            .error_code = @enumFromInt(buf[0]),
            .error_subcode = buf[1],
            .data = buf[MIN_MSG_LEN..],
        };
    }

    pub fn encode(self: Notification, buf: []u8) !usize {
        if (buf.len < self.data.len + MIN_MSG_LEN) return error.BufferTooSmall;
        buf[0] = @intFromEnum(self.error_code);
        buf[1] = self.error_subcode;
        @memcpy(buf[MIN_MSG_LEN .. self.data.len + MIN_MSG_LEN], self.data);
        return MIN_MSG_LEN + self.data.len;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "decode: hold timer expired (no data)" {
    var buf = [_]u8{
        0x04, // error_code = 4 (hold timer expired)
        0x00, // error_subcode = 0
    };
    const n = try Notification.decode(&buf);
    try std.testing.expectEqual(ErrorCode.hold_timer_expired, n.error_code);
    try std.testing.expectEqual(@as(u8, 0), n.error_subcode);
    try std.testing.expectEqual(@as(usize, 0), n.data.len);
}

test "decode: cease / admin shutdown with no data" {
    var buf = [_]u8{
        0x06, // error_code = 6 (cease)
        0x02, // error_subcode = 2 (admin shutdown)
    };
    const n = try Notification.decode(&buf);
    try std.testing.expectEqual(ErrorCode.cease, n.error_code);
    try std.testing.expectEqual(@as(u8, 2), n.error_subcode);
}

test "decode: notification with data bytes" {
    // Open message error / bad peer AS — data carries the offending AS bytes.
    var buf = [_]u8{
        0x02, // error_code = 2 (open message error)
        0x02, // error_subcode = 2 (bad peer AS)
        0xFD, 0xE9, // data = 65001 (the rejected AS)
    };
    const n = try Notification.decode(&buf);
    try std.testing.expectEqual(ErrorCode.open_message, n.error_code);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xFD, 0xE9 }, n.data);
}

test "decode: data is a slice into the source buffer (zero-copy)" {
    var buf = [_]u8{ 0x04, 0x00, 0xAB, 0xCD };
    const n = try Notification.decode(&buf);
    // data must point into buf, not a copy
    try std.testing.expectEqual(@intFromPtr(buf[2..].ptr), @intFromPtr(n.data.ptr));
}

test "decode: error on buffer shorter than 2 bytes" {
    var buf = [_]u8{0x04};
    try std.testing.expectError(error.BufferTooSmall, Notification.decode(&buf));
}

test "decode: unknown error code is preserved (non-exhaustive enum)" {
    var buf = [_]u8{ 0xFF, 0x00 };
    const n = try Notification.decode(&buf);
    try std.testing.expectEqual(@as(u8, 0xFF), @intFromEnum(n.error_code));
}

test "encode: hold timer expired (no data)" {
    var buf = [_]u8{0} ** 8;
    const n = Notification{ .error_code = .hold_timer_expired, .error_subcode = 0, .data = &.{} };
    const written = try n.encode(&buf);
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u8, 0x04), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[1]);
}

test "encode: cease with data" {
    var buf = [_]u8{0} ** 8;
    const n = Notification{
        .error_code = .cease,
        .error_subcode = 2,
        .data = &[_]u8{ 0xDE, 0xAD },
    };
    const written = try n.encode(&buf);
    try std.testing.expectEqual(@as(usize, 4), written);
    try std.testing.expectEqual(@as(u8, 0x06), buf[0]); // cease
    try std.testing.expectEqual(@as(u8, 0x02), buf[1]); // admin shutdown
    try std.testing.expectEqual(@as(u8, 0xDE), buf[2]);
    try std.testing.expectEqual(@as(u8, 0xAD), buf[3]);
}

test "encode: error on buffer too small" {
    var buf = [_]u8{0} ** 1; // need at least 2
    const n = Notification{ .error_code = .cease, .error_subcode = 0, .data = &.{} };
    try std.testing.expectError(error.BufferTooSmall, n.encode(&buf));
}

test "encode/decode round-trip" {
    const original = Notification{
        .error_code = .open_message,
        .error_subcode = 2,
        .data = &[_]u8{ 0xFD, 0xE9 },
    };
    var buf = [_]u8{0} ** 16;
    const written = try original.encode(&buf);
    const decoded = try Notification.decode(buf[0..written]);
    try std.testing.expectEqual(original.error_code, decoded.error_code);
    try std.testing.expectEqual(original.error_subcode, decoded.error_subcode);
    try std.testing.expectEqualSlices(u8, original.data, decoded.data);
}
