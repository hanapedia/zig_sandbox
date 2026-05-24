const std = @import("std");
const config = @import("../config.zig");
const peer = @import("peer.zig");
const fsm = @import("fsm.zig");

/// Speaker represents BGP Speaker.
pub const Speaker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,
    cfg: config.LocalConfig,
    peers: std.ArrayList(*peer.Peer) = .empty,
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

    pub fn deinit(self: *Self) void {
        for (self.peers.items) |p| {
            p.stop();
            self.allocator.destroy(p);
        }
        self.peers.deinit(self.allocator);
    }

    pub fn addPeer(self: *Self, peer_cfg: config.PeerConfig) !void {
        const p = try self.allocator.create(peer.Peer);
        p.* = peer.Peer{ .allocator = self.allocator, .io = self.io, .peer_cfg = peer_cfg, .local_cfg = self.cfg, .fsm = fsm.FSM{
            .local_as = self.cfg.as_number,
            .router_id = self.cfg.router_id,
            .hold_time = peer_cfg.hold_time,
            .remote_as = peer_cfg.remote_as,
        } };
        try self.peers.append(self.allocator, p);
    }

    pub fn start(self: *Self) !void {
        const address = try std.Io.net.IpAddress.parseIp4("0.0.0.0", self.cfg.listen_port);
        self.server = try address.listen(self.io, .{
            .reuse_address = true,
        });
        for (self.peers.items) |p| {
            try p.start();
        }
        self.running.store(true, .seq_cst);
    }

    pub fn stop(self: *Self) void {
        if (self.server) |*s| s.deinit(self.io);
        for (self.peers.items) |p| {
            p.stop();
        }
        self.running.store(false, .seq_cst);
    }
};
