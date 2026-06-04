const std = @import("std");
const typed = @import("./typed.zig");
const watch = @import("./watch.zig");
const metav1 = @import("../proto/k8s/io/apimachinery/pkg/apis/meta/v1.pb.zig");

pub const DEFAULT_BUF_SIZE: usize = 10;

pub const DeinitError = error{QueueNotDrained};
pub const Error = std.Io.QueueClosedError || std.Io.Cancelable;

pub fn EventQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        io: std.Io,
        fifo: std.Io.Queue(*T),
        buffer: []*T,
        len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        pub fn init(allocator: std.mem.Allocator, io: std.Io) std.mem.Allocator.Error!EventQueue(T) {
            const buffer: []*T = try allocator.alloc(*T, DEFAULT_BUF_SIZE);
            return .{
                .allocator = allocator,
                .io = io,
                .fifo = std.Io.Queue(*T).init(buffer),
                .buffer = buffer,
            };
        }

        /// must be called before deinit
        pub fn close(self: *Self) void {
            self.fifo.close(self.io);
        }

        /// tries to deinit the internal buffer. Error if queue is not drained.
        pub fn deinit(self: *Self) DeinitError!void {
            if (self.len.load(.acquire) != 0) return error.QueueNotDrained;
            self.allocator.free(self.buffer);
        }

        /// deinit the internal buffer by forcifully draining
        pub fn deinitForce(self: *Self) void {
            while (self.len.load(.acquire) > 0) {
                _ = self.dequeue() catch break;
            }
            self.allocator.free(self.buffer);
        }

        /// dequeue pops a route from the events queue
        pub fn dequeue(self: *Self) Error!*T {
            const event = try self.fifo.getOne(self.io);
            _ = self.len.fetchSub(1, .acq_rel);
            return event;
        }

        /// enqueue adds a event to the queue and signals
        pub fn enqueue(self: *Self, event: *T) Error!void {
            try self.fifo.putOne(self.io, event);
            _ = self.len.fetchAdd(1, .acq_rel);
        }
    };
}

/// L must have following fields
///     metadata: ?k8s_io_apimachinery_pkg_apis_meta_v1.ListMeta = null,
///     items: std.ArrayList(Pod) = .empty,
pub fn ListerWatcher(comptime T: type, comptime L: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        io: std.Io,

        namespace: ?[]const u8 = null,

        typed_client: typed.TypedClient(T, L),
        // not owned
        fifo: *EventQueue(T),

        pub fn init(allocator: std.mem.Allocator, io: std.Io, namespace: ?[]const u8, client: typed.TypedClient(T, L), fifo: *EventQueue(T)) ListerWatcher(T, L) {
            return .{
                .allocator = allocator,
                .io = io,
                .namespace = namespace,
                .typed_client = client,
                .fifo = fifo,
            };
        }

        // starts lister watcher, where
        pub fn start(self: Self) std.Io.Cancelable!void {
            std.debug.print("ListerWatcher started.\n", .{});
            self.run() catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => std.debug.print("ListerWatcher error: {}\n", .{err}),
            };
        }

        fn run(self: Self) !void {
            var result = try self.typed_client.list(self.namespace, .{});
            defer result.deinit();
            // must be list result
            for (result.value.items.items) |t| { // value.items must be std.ArrayList(T)
                const obj = try self.allocator.create(T);
                errdefer self.allocator.destroy(obj);
                obj.* = try t.dupe(self.allocator); // must have dupe method. k8s protobuf types should have this.
                errdefer obj.deinit(self.allocator);
                try self.fifo.enqueue(obj);
            }
            const metadata: metav1.ListMeta = result.value.metadata orelse return error.NoMetadata;
            const rv: []const u8 = metadata.resourceVersion orelse return error.NoResourceVersion;

            var watcher: watch.Watcher(T) = try self.typed_client.watch(self.namespace, .{ .resourceVersion = rv });
            defer watcher.deinit();

            while (try watcher.next()) |event_val| {
                var ev = event_val;
                if (ev.event_type == .BOOKMARK) {
                    ev.deinit();
                    continue; // TODO: retry after connection timeout
                }
                const obj = try self.allocator.create(T);
                errdefer self.allocator.destroy(obj);
                obj.* = try ev.object().dupe(self.allocator);
                errdefer obj.deinit(self.allocator);
                try self.fifo.enqueue(obj);
                ev.deinit();
            }
        }
    };
}
