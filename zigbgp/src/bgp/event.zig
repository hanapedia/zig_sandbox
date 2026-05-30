const std = @import("std");
const prefix = @import("prefix.zig");

pub const DEFAULT_QUEUE_SIZE: usize = 10;

pub const DeinitError = error{QueueNotDrained};

pub const Error = std.Io.QueueClosedError || std.Io.Cancelable;

pub const RouteEvent = struct {
    announce: []prefix.V4Prefix,
    withdraw: []prefix.V4Prefix,
};

pub const RouteEventQueue = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    queue: std.Io.Queue(RouteEvent),
    /// internal buffer for the io.Queue. Must access via the queue for thread safety.
    _events: []RouteEvent,
    len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) std.mem.Allocator.Error!RouteEventQueue {
        const events: []RouteEvent = try allocator.alloc(RouteEvent, DEFAULT_QUEUE_SIZE);
        return .{
            .allocator = allocator,
            .io = io,
            .queue = std.Io.Queue(RouteEvent).init(events),
            ._events = events,
        };
    }

    pub fn close(self: *RouteEventQueue) void {
        self.queue.close(self.io);
    }

    /// tris to deinit the internal buffer. Error if queue is not drained.
    pub fn deinit(self: *RouteEventQueue) DeinitError!void {
        if (self.len.load(.acquire) != 0) return error.QueueNotDrained;
        self.allocator.free(self._events);
    }

    /// deinit the internal buffer by forcifully draining
    pub fn deinitForce(self: *RouteEventQueue) DeinitError!void {
        while (self.len.load(.acquire) > 0) {
            _ = self.dequeue() catch break;
        }
        self.allocator.free(self._events);
    }

    /// dequeue pops a route from the events queue
    pub fn dequeue(self: *RouteEventQueue) Error!RouteEvent {
        const event = try self.queue.getOne(self.io);
        _ = self.len.fetchSub(1, .acq_rel);
        return event;
    }

    /// enqueue adds a event to the queue and signals
    pub fn enqueue(self: *RouteEventQueue, event: RouteEvent) Error!void {
        try self.queue.putOne(self.io, event);
        _ = self.len.fetchAdd(1, .acq_rel);
    }
};
