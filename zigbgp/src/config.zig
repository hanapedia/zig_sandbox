const std = @import("std");

pub const LocalConfig = struct {
    as_number: u32,
    router_id: [4]u8,
    listen_port: ?u16 = null,
};

pub const PeerConfig = struct {
    /// must include port
    address: std.Io.net.IpAddress,
    remote_as: u32,
    hold_time: u16 = 90,
    passive: bool = false,
};
