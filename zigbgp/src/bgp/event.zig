const std = @import("std");
const prefix = @import("prefix.zig");

pub const EnqueueError = std.Io.Cancelable || std.mem.Allocator.Error;

pub const RouteEvent = struct {
    announce: []prefix.V4Prefix,
    withdraw: []prefix.V4Prefix,
};

pub const RouteEventQueue = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mu: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    events: std.ArrayList(RouteEvent) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) RouteEventQueue {
        return .{
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *RouteEventQueue) void {
        self.events.deinit(self.allocator);
    }

    /// dequeue pops a route from the events queue
    pub fn dequeue(self: *RouteEventQueue) std.Io.Cancelable!RouteEvent {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        // thread can wake up even when there are no data
        // go back to sleep in that case
        while (self.events.items.len == 0) {
            try self.cond.wait(self.io, &self.mu);
        }

        return self.events.orderedRemove(0);
    }

    /// enqueue adds a event to the queue and signals
    pub fn enqueue(self: *RouteEventQueue, event: RouteEvent) EnqueueError!void {
        try self.mu.lock(self.io);
        defer self.mu.unlock(self.io);

        try self.events.append(self.allocator, event);
        self.cond.signal(self.io);
    }
};
