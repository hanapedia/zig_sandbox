const std = @import("std");
const linux = std.os.linux;

/// Netlink socket
const Socket = struct {
    fd: ?i32 = null,

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
        const fd: i32 = @intCast(rc);
        self.fd = fd;
        errdefer self.close();

        var addr = linux.sockaddr.nl{ .pid = 0, .groups = 0 };
        const bind_rc = linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.nl));
        switch (linux.errno(bind_rc)) {
            .SUCCESS => {},
            .ADDRINUSE => return error.AddressInUse,
            else => return error.Unexpected,
        }
    }

    pub fn close(self: *Socket) void {
        if (self.fd) |fd| linux.close(fd);
    }

    /// send raw bytes buf to the netlink socket
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
};
