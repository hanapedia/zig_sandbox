const std = @import("std");
const linux = std.os.linux;

pub const NLMSGHDR_LEN = @sizeOf(linux.nlmsghdr);

/// Message read from netlink socket with parsed header
pub const Message = struct {
    header: linux.nlmsghdr,
    /// slice should point to caller's buffer
    data: []const u8,

    pub fn encode(self: Message, buf: []u8) !void {
        if (buf.len < NLMSGHDR_LEN + self.data.len) return error.BufferTooSmall;
        // write header. safe to memcpy since the header is an extern type
        @memcpy(buf[0..NLMSGHDR_LEN], std.mem.asBytes(&self.header));
        // write data
        @memcpy(buf[NLMSGHDR_LEN..][0..self.data.len], self.data);
    }

    /// duplicates the data from the buffer using the provided allocator
    /// data must be freed using deinit.
    pub fn decode(allocator: std.mem.Allocator, buf: []const u8) !Message {
        if (buf.len < NLMSGHDR_LEN) return error.BufferTooSmall;
        // decode header. safe since the header is extern type
        const header: linux.nlmsghdr = std.mem.bytesToValue(linux.nlmsghdr, buf[0..NLMSGHDR_LEN]);
        if (buf.len < header.len) return error.BufferTooSmall;
        // copy payload
        const data = try allocator.dupe(u8, buf[NLMSGHDR_LEN..][0 .. header.len - NLMSGHDR_LEN]);

        return Message{
            .header = header,
            .data = data,
        };
    }

    pub fn deinit(self: Message, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

test "Message.encode writes header and data correctly" {
    const payload = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const msg = Message{
        .header = .{
            .len = @intCast(NLMSGHDR_LEN + payload.len),
            .type = .RTM_GETLINK,
            .flags = 0x0301,
            .seq = 1,
            .pid = 0,
        },
        .data = &payload,
    };

    var buf: [NLMSGHDR_LEN + payload.len]u8 = undefined;
    try msg.encode(&buf);

    // header fields
    try std.testing.expectEqual(@as(u32, NLMSGHDR_LEN + payload.len), std.mem.readInt(u32, buf[0..4], .little));
    try std.testing.expectEqual(@as(u16, @intFromEnum(linux.NetlinkMessageType.RTM_GETLINK)), std.mem.readInt(u16, buf[4..6], .little));
    try std.testing.expectEqual(@as(u16, 0x0301), std.mem.readInt(u16, buf[6..8], .little));
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, buf[8..12], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, buf[12..16], .little));
    // payload
    try std.testing.expectEqualSlices(u8, &payload, buf[NLMSGHDR_LEN..]);
}

test "Message.encode returns error on buffer too small" {
    const payload = [_]u8{ 0x01, 0x02 };
    const msg = Message{
        .header = .{ .len = @intCast(NLMSGHDR_LEN + payload.len), .type = .RTM_GETLINK, .flags = 0, .seq = 0, .pid = 0 },
        .data = &payload,
    };
    var buf: [NLMSGHDR_LEN]u8 = undefined; // too small: missing payload space
    try std.testing.expectError(error.BufferTooSmall, msg.encode(&buf));
}

test "Message.decode parses header and data correctly" {
    const allocator = std.testing.allocator;
    const payload = [_]u8{ 0xAA, 0xBB };
    const total_len: u32 = @intCast(NLMSGHDR_LEN + payload.len);

    var buf: [NLMSGHDR_LEN + payload.len]u8 = undefined;
    std.mem.writeInt(u32, buf[0..4], total_len, .little);
    std.mem.writeInt(u16, buf[4..6], @intFromEnum(linux.NetlinkMessageType.RTM_GETROUTE), .little);
    std.mem.writeInt(u16, buf[6..8], 0x0101, .little);
    std.mem.writeInt(u32, buf[8..12], 42, .little);
    std.mem.writeInt(u32, buf[12..16], 99, .little);
    @memcpy(buf[NLMSGHDR_LEN..], &payload);

    const msg = try Message.decode(allocator, &buf);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(total_len, msg.header.len);
    try std.testing.expectEqual(linux.NetlinkMessageType.RTM_GETROUTE, msg.header.type);
    try std.testing.expectEqual(@as(u16, 0x0101), msg.header.flags);
    try std.testing.expectEqual(@as(u32, 42), msg.header.seq);
    try std.testing.expectEqual(@as(u32, 99), msg.header.pid);
    try std.testing.expectEqualSlices(u8, &payload, msg.data);
}

test "Message.decode returns error on buffer too small" {
    const allocator = std.testing.allocator;
    var buf: [NLMSGHDR_LEN - 1]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, Message.decode(allocator, &buf));
}

test "Message encode decode roundtrip" {
    const allocator = std.testing.allocator;
    const payload = [_]u8{ 0x10, 0x20, 0x30 };
    const original = Message{
        .header = .{
            .len = @intCast(NLMSGHDR_LEN + payload.len),
            .type = .RTM_NEWROUTE,
            .flags = 0x0500,
            .seq = 7,
            .pid = 1234,
        },
        .data = &payload,
    };

    var buf: [NLMSGHDR_LEN + payload.len]u8 = undefined;
    try original.encode(&buf);

    const decoded = try Message.decode(allocator, &buf);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(original.header.len, decoded.header.len);
    try std.testing.expectEqual(original.header.type, decoded.header.type);
    try std.testing.expectEqual(original.header.flags, decoded.header.flags);
    try std.testing.expectEqual(original.header.seq, decoded.header.seq);
    try std.testing.expectEqual(original.header.pid, decoded.header.pid);
    try std.testing.expectEqualSlices(u8, original.data, decoded.data);
}

