const std = @import("std");
const config = @import("../config.zig");

/// Speaker represents BGP Speaker.
pub const Speaker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,
    cfg: config.LocalConfig,
    // peers: std.ArrayList(*Peer), // TODO
    // rib: *Rib, // TODO
    server: ?std.Io.net.Server,
    accept_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, io: std.Io, local_cfg: config.LocalConfig) !Speaker {
        // TODO: init peers and rib
        return Speaker{
            .allocator = allocator,
            .io = io,
            .cfg = local_cfg,
            .server = null,
            .accept_thread = null,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(_: Self) void {}

    // TODO
    // pub fn addPeer(self: Self, peer_cfg: config.PeerConfig) !void {}

    pub fn start(self: *Self) !void {
        const address = try std.Io.net.IpAddress.parseIp4("0.0.0.0", self.cfg.listen_port);
        self.server = try address.listen(self.io, .{
            .reuse_address = true,
        });
        self.running.store(true, .seq_cst);
    }

    pub fn stop(self: *Self) void {
        if (self.server) |*s| s.deinit(self.io);
        self.running.store(false, .seq_cst);
    }
};
