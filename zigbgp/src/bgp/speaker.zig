const std = @import("std");
const config = @import("../config.zig");
const peer = @import("peer.zig");
const fsm = @import("fsm.zig");
const prefix = @import("prefix.zig");
const event = @import("event.zig");

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
        p.* = try peer.Peer.init(self.allocator, self.io, peer_cfg, self.cfg);
        try self.peers.append(self.allocator, p);
    }

    pub fn announce(self: *Self, px: []prefix.V4Prefix) event.Error!void {
        for (self.peers.items) |p| {
            try p.route_event_queue.enqueue(.{ .announce = px, .withdraw = &.{} });
        }
    }

    pub fn withdraw(self: *Self, px: []prefix.V4Prefix) event.Error!void {
        for (self.peers.items) |p| {
            try p.route_event_queue.enqueue(.{ .withdraw = px, .announce = &.{} });
        }
    }

    pub fn start(self: *Self) std.Io.Cancelable!void {
        std.debug.print("Speaker started.\n", .{});
        self.run() catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            else => std.debug.print("Speaker error: {}\n", .{err}),
        };
    }

    pub fn run(self: *Self) !void {
        const address = try std.Io.net.IpAddress.parseIp4("0.0.0.0", self.cfg.listen_port);
        self.server = try address.listen(self.io, .{
            .reuse_address = true,
        });
        self.running.store(true, .seq_cst);
        var peer_group = std.Io.Group.init;
        defer peer_group.cancel(self.io);
        for (self.peers.items) |p| {
            try peer_group.concurrent(self.io, peer.Peer.start, .{p});
        }
        try peer_group.await(self.io);
    }

    pub fn stop(self: *Self) void {
        if (self.server) |*s| s.deinit(self.io);
        for (self.peers.items) |p| {
            p.stop();
        }
        self.running.store(false, .seq_cst);
    }
};
