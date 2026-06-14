const std = @import("std");
const linux = std.os.linux;
const m = @import("message.zig");

pub const Request = struct {
    msg_type: linux.NetlinkMessageType,
    flags: u16,
    payload: []const u8,
};

pub const Response = struct {
    msgs: std.ArrayList(m.Message),

    pub fn init(_: std.mem.Allocator) Response {
        return .{ .msgs = .empty };
    }

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        for (self.msgs.items) |msg| msg.deinit(allocator);
        self.msgs.deinit(allocator);
    }
};

/// Netlink socket
pub const Socket = struct {
    fd: ?i32 = null,
    seq: u32 = 0,

    pub fn init() Socket {
        return Socket{};
    }

    pub fn open(self: *Socket) !void {
        const rc = linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            .ACCES => return error.PermissionDenied,
            .AFNOSUPPORT => return error.AddressFamilyNotSupported,
            .PROTONOSUPPORT => return error.ProtocolNotSupported,
            else => return error.Unexpected,
        }
        self.fd = @intCast(rc);
        errdefer self.close();

        var addr = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
        const bind_rc = linux.bind(self.fd.?, @ptrCast(&addr), @sizeOf(linux.sockaddr.nl));
        switch (linux.errno(bind_rc)) {
            .SUCCESS => {},
            .ADDRINUSE => return error.AddressInUse,
            else => return error.Unexpected,
        }
    }

    pub fn close(self: *Socket) void {
        if (self.fd) |fd| {
            _ = linux.close(fd);
            self.fd = null;
        }
    }

    /// send raw bytes buf to the netlink socket
    /// socket must be open before calling this method.
    pub fn send(self: *Socket, buf: []const u8, flags: u32) !void {
        const fd = self.fd orelse return error.SocketNotOpen;
        const rc = linux.sendto(fd, buf.ptr, buf.len, flags, null, 0);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            .CONNREFUSED => return error.ConnectionRefused,
            else => return error.Unexpected,
        }
    }

    /// read raw bytes from the netlink socket
    /// socket must be open before calling this method.
    /// call with linux.MSG.PEEK | linux.MSG.TRUNC first to get the message size without consuming the message.
    /// call again with the buffer of the message size to read the message.
    pub fn recv(self: *Socket, buf: []u8, flags: u32) !usize {
        const fd = self.fd orelse return error.SocketNotOpen;
        const rc = linux.recvfrom(fd, buf.ptr, buf.len, flags, null, null);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            .NOMEM => return error.SystemResources,
            else => return error.Unexpected,
        }
        return rc;
    }

    /// allocates buffer for the message and frees when done
    pub fn writeMessage(self: *Socket, allocator: std.mem.Allocator, msg_type: linux.NetlinkMessageType, flags: u16, payload: []const u8) !void {
        const msg = m.Message{
            .header = linux.nlmsghdr{
                .len = @intCast(m.NLMSGHDR_LEN + payload.len),
                .type = msg_type,
                .flags = flags,
                .seq = self.seq,
                .pid = 0,
            },
            .data = payload,
        };
        const buf = try allocator.alloc(u8, msg.header.len); // could be better to use bounded array
        defer allocator.free(buf);
        try msg.encode(buf);
        try self.send(buf, 0);
    }

    /// allocates Message.data using the provided allocator.
    /// caller must free Message using deinit.
    pub fn readMessage(self: *Socket, allocator: std.mem.Allocator) !m.Message {
        // peek and trunc
        var peek: [1]u8 = undefined;
        const msg_len = try self.recv(&peek, linux.MSG.PEEK | linux.MSG.TRUNC);
        // read
        const buf = try allocator.alloc(u8, msg_len);
        defer allocator.free(buf);
        _ = try self.recv(buf, 0);
        // decode copies data from buf. we can free buf
        return try m.Message.decode(allocator, buf);
    }

    /// main API to send request over netlink socket
    /// calls writeMessage & readMessage
    pub fn request(self: *Socket, allocator: std.mem.Allocator, req: Request) !Response {
        // send request
        self.seq += 1;
        try self.writeMessage(allocator, req.msg_type, req.flags, req.payload);

        var res = Response.init(allocator);
        errdefer res.deinit(allocator);
        // read response in loop since it could be multipart
        while (true) {
            var msg = try self.readMessage(allocator);
            errdefer msg.deinit(allocator);

            if (msg.header.seq != self.seq) return error.InvalidResponseSeq;
            // do not include multipart DONE message
            if (msg.header.type == .DONE) {
                msg.deinit(allocator);
                break;
            }

            try res.msgs.append(allocator, msg);

            // check for multipart header
            if (msg.header.flags & linux.NLM_F_MULTI == 0) break;
        }
        return res;
    }
};
