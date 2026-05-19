const std = @import("std");
const config = @import("../config.zig");
const fsm = @import("./fsm.zig");
const msg = @import("./message.zig");
const open = @import("./open.zig");
const keepalive = @import("./keepalive.zig");
const update = @import("./update.zig");
const notification = @import("./notification.zig");

pub const MessageBody = union(enum) {
    open: open.Open,
    update: update.Update,
    notification: notification.Notification,
    keepalive,

    pub fn encode(self: MessageBody, buf: []u8) !usize {
        return switch (self) {
            .open => |o| o.encode(buf),
            .keepalive => 0,
            .update => |u| u.encode(buf),
            .notification => |n| n.encode(buf),
        };
    }

    pub fn toMessageTypeEnum(self: MessageBody) msg.MessageType {
        return switch (self) {
            .open => msg.MessageType.open,
            .keepalive => msg.MessageType.keepalive,
            .update => msg.MessageType.update,
            .notification => msg.MessageType.notification,
        };
    }
};

pub const Peer = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    peer_cfg: config.PeerConfig,
    local_cfg: config.LocalConfig,
    fsm: fsm.FSM,

    // tcp conn
    conn: std.Io.net.Stream,
    reader: std.Io.net.Stream.Reader,
    writer: std.Io.net.Stream.Writer,

    thread: std.Thread,

    // timers
    hold_deadline: ?i64 = null,
    keepalive_deadline: ?i64 = null,

    fn readMessage(self: Peer, reader: *std.Io.Reader) !struct { header: msg.Header, body: MessageBody } {
        var buf: [msg.MAX_MSG_LEN]u8 = undefined;
        // read header
        reader.readSliceAll(buf[0..msg.HEADER_LEN]) catch |err| {
            std.debug.print("Failed to read header bytes: {}\n", .{err});
            return err;
        };
        const header: msg.Header = msg.Header.decode(buf[0..msg.HEADER_LEN]) catch |err| {
            std.debug.print("Failed to decode header: {}\n", .{err});
            return err;
        };
        if (buf.len < header.length) return error.BufferTooSmall;

        // read body
        const body_length: usize = @as(usize, header.length) - msg.HEADER_LEN;
        reader.readSliceAll(buf[msg.HEADER_LEN..][0..body_length]) catch |err| {
            std.debug.print("Failed to read body bytes: {}\n", .{err});
            return err;
        };
        const body: MessageBody = switch (header.msg_type) {
            .open => .{ .open = open.Open.decode(buf[msg.HEADER_LEN..][0..body_length]) catch |err| {
                std.debug.print("Failed to decode open body: {}\n", .{err});
                return err;
            } },
            .keepalive => .{ .keepalive = {} },
            .update => .{ .update = update.Update.decode(buf[msg.HEADER_LEN..][0..body_length], self.allocator) catch |err| {
                std.debug.print("Failed to decode update body: {}\n", .{err});
                return err;
            } },
            .notification => .{ .notification = notification.Notification.decode(buf[msg.HEADER_LEN..][0..body_length], self.allocator) catch |err| {
                std.debug.print("Failed to decode notification body: {}\n", .{err});
                return err;
            } },
            else => return error.InvalidMessageType,
        };
        return .{ .header = header, .body = body };
    }

    pub fn writeMessage(_: Peer, writer: *std.Io.Writer, body: MessageBody) !usize {
        var buf: [msg.MAX_MSG_LEN]u8 = undefined;
        const body_len = try body.encode(buf[msg.HEADER_LEN..]);
        const header = msg.Header{ .length = @intCast(msg.HEADER_LEN + body_len), .msg_type = body.toMessageTypeEnum() };
        try header.encode(buf[0..]);
        try writer.writeAll(buf[0..header.length]);
        return header.length;
    }

    fn handleFSMAction(self: *Peer, action: fsm.FSMAction) !void {
        if (action.negotiated_hold_time) |_| {
            try self.resetHoldTimer();
        }
        if (action.send_keepalive) {
            try self.writeMessage(self.writer, .keepalive);
            self.resetKeepaliveTimer();
        }
        if (action.send_open) {
            try self.writeMessage(self.writer, .{ .open = open.OpenFromConfig(self.local_cfg, self.peer_cfg) });
        }
        if (action.send_notification) |n| {
            try self.writeMessage(self.writer, .{ .notification = n });
        }
        if (action.close_connection) {
            try self.conn.shutdown(self.io, .both);
        }
    }

    fn checkTimers(self: *Peer) !void {
        const now = std.Io.Clock.now(self.io).toSeconds();
        if (self.hold_deadline >= now) {
            // should send notification and close connection
            try self.handleFSMAction(self.fsm.handle(fsm.FSMEvent.hold_timer_expired));
        }
        if (self.keepalive_deadline >= now) {
            // send keep alive and reset timer
            try self.writeMessage(self.writer, .keepalive);
            self.resetKeepaliveTimer();
        }
    }

    /// resets the hold timer by adding negotiated hold time to now.
    /// diables timer (sets to null) if negotiated hold time is null.
    fn resetHoldTimer(self: *Peer) void {
        if (self.fsm.negotiated_hold_time) |n| {
            self.hold_deadline = std.Io.Clock.real.now(self.io).toSeconds() + n;
        } else {
            self.hold_deadline = null;
        }
    }

    /// resets the keepalive timer by adding negotiated hold time / 3 to now.
    /// diables timer (sets to null) if negotiated hold time is null.
    fn resetKeepaliveTimer(self: *Peer) void {
        if (self.fsm.negotiated_hold_time) |n| {
            self.keepalive_deadline = std.Io.Clock.real.now(self.io).toSeconds() + @divTrunc(n, 3);
        } else {
            self.keepalive_deadline = null;
        }
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

// Construct a minimal Peer for testing — readMessage only uses self.allocator.
fn testPeer(allocator: std.mem.Allocator) Peer {
    var p: Peer = undefined;
    p.allocator = allocator;
    return p;
}

// 16-byte all-0xFF BGP marker
const MARKER = [_]u8{0xFF} ** 16;

test "readMessage: KEEPALIVE" {
    // Header only: marker + length=19 + type=4
    const wire = MARKER ++ [_]u8{ 0x00, 0x13, 0x04 };
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    const result = try peer.readMessage(&reader);
    try std.testing.expectEqual(msg.MessageType.keepalive, result.header.msg_type);
    try std.testing.expectEqual(@as(u16, 19), result.header.length);
    // keepalive has no payload — just check the tag
    try std.testing.expectEqual(std.meta.Tag(MessageBody).keepalive, result.body);
}

test "readMessage: OPEN" {
    // Body: version=4, my_as=65001, hold_time=90, bgp_id=10.0.0.1, opt_param_len=0
    // Total length = 19 + 10 = 29 = 0x001D
    const wire = MARKER ++ [_]u8{
        0x00, 0x1D, 0x01, // length=29, type=OPEN
        0x04, // version=4
        0xFD, 0xE9, // my_as=65001
        0x00, 0x5A, // hold_time=90
        0x0A, 0x00, 0x00, 0x01, // bgp_id=10.0.0.1
        0x00, // opt_param_len=0
    };
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    const result = try peer.readMessage(&reader);
    try std.testing.expectEqual(msg.MessageType.open, result.header.msg_type);
    const o = result.body.open;
    try std.testing.expectEqual(@as(u16, 65001), o.my_as);
    try std.testing.expectEqual(@as(u16, 90), o.hold_time);
    try std.testing.expectEqual([4]u8{ 10, 0, 0, 1 }, o.bgp_id);
}

test "readMessage: NOTIFICATION (hold_timer_expired, no data)" {
    // Body: error_code=4, error_subcode=0
    // Total length = 19 + 2 = 21 = 0x0015
    const wire = MARKER ++ [_]u8{
        0x00, 0x15, 0x03, // length=21, type=NOTIFICATION
        0x04, 0x00, // hold_timer_expired, subcode=0
    };
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    const result = try peer.readMessage(&reader);
    defer result.body.notification.deinit(std.testing.allocator);
    try std.testing.expectEqual(msg.MessageType.notification, result.header.msg_type);
    const n = result.body.notification;
    try std.testing.expectEqual(notification.ErrorCode.hold_timer_expired, n.error_code);
    try std.testing.expectEqual(@as(u8, 0), n.error_subcode);
    try std.testing.expectEqual(@as(usize, 0), n.data.len);
}

test "readMessage: UPDATE (empty withdrawn, no path attrs, no NLRI)" {
    // Body: withdrawn_len=0, total_path_attr_len=0
    // Total length = 19 + 4 = 23 = 0x0017
    const wire = MARKER ++ [_]u8{
        0x00, 0x17, 0x02, // length=23, type=UPDATE
        0x00, 0x00, // withdrawn_len=0
        0x00, 0x00, // total_path_attr_len=0
    };
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    const result = try peer.readMessage(&reader);
    defer result.body.update.deinit(std.testing.allocator);
    try std.testing.expectEqual(msg.MessageType.update, result.header.msg_type);
    const u = result.body.update;
    try std.testing.expectEqual(@as(usize, 0), u.withdrawn.len);
    try std.testing.expectEqual(@as(usize, 0), u.nlri.len);
}

test "readMessage: unknown message type returns error" {
    const wire = MARKER ++ [_]u8{ 0x00, 0x13, 0xFF }; // type=255
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    try std.testing.expectError(error.InvalidMessageType, peer.readMessage(&reader));
}

test "readMessage: bad marker returns error" {
    var wire = MARKER ++ [_]u8{ 0x00, 0x13, 0x04 };
    wire[7] = 0x00; // corrupt one marker byte
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    try std.testing.expectError(error.InvalidMarker, peer.readMessage(&reader));
}

test "readMessage: truncated stream returns error" {
    // Only 10 bytes — less than HEADER_LEN=19
    const wire = [_]u8{0xFF} ** 10;
    var reader = std.Io.Reader.fixed(&wire);
    const peer = testPeer(std.testing.allocator);
    try std.testing.expectError(error.EndOfStream, peer.readMessage(&reader));
}

// ── writeMessage / readMessage round-trip tests ───────────────────────────────

test "round-trip: KEEPALIVE" {
    var out: [msg.MAX_MSG_LEN]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out);
    const peer = testPeer(std.testing.allocator);
    const written = try peer.writeMessage(&writer, .{ .keepalive = {} });
    var reader = std.Io.Reader.fixed(out[0..written]);
    const result = try peer.readMessage(&reader);
    try std.testing.expectEqual(msg.MessageType.keepalive, result.header.msg_type);
    try std.testing.expectEqual(@as(u16, msg.HEADER_LEN), result.header.length);
}

test "round-trip: OPEN" {
    const original = open.Open{
        .version = 4,
        .my_as = 65001,
        .hold_time = 90,
        .bgp_id = .{ 10, 0, 0, 1 },
    };
    var out: [msg.MAX_MSG_LEN]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out);
    const peer = testPeer(std.testing.allocator);
    const written = try peer.writeMessage(&writer, .{ .open = original });
    var reader = std.Io.Reader.fixed(out[0..written]);
    const result = try peer.readMessage(&reader);
    try std.testing.expectEqual(msg.MessageType.open, result.header.msg_type);
    const o = result.body.open;
    try std.testing.expectEqual(original.my_as, o.my_as);
    try std.testing.expectEqual(original.hold_time, o.hold_time);
    try std.testing.expectEqual(original.bgp_id, o.bgp_id);
}

test "round-trip: NOTIFICATION" {
    const original = notification.Notification{
        .error_code = .hold_timer_expired,
        .error_subcode = 0,
        .data = &.{},
    };
    var out: [msg.MAX_MSG_LEN]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out);
    const peer = testPeer(std.testing.allocator);
    const written = try peer.writeMessage(&writer, .{ .notification = original });
    var reader = std.Io.Reader.fixed(out[0..written]);
    const result = try peer.readMessage(&reader);
    defer result.body.notification.deinit(std.testing.allocator);
    try std.testing.expectEqual(msg.MessageType.notification, result.header.msg_type);
    const n = result.body.notification;
    try std.testing.expectEqual(original.error_code, n.error_code);
    try std.testing.expectEqual(original.error_subcode, n.error_subcode);
}
