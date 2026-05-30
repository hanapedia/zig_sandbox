const std = @import("std");

pub const StaticIPAllocator = struct {
    pool: std.AutoHashMap([4]u8, bool),

    pub fn init(allocator: std.mem.Allocator) !StaticIPAllocator {
        var pool = std.AutoHashMap([4]u8, bool).init(allocator);
        try pool.put(.{ 10, 128, 0, 1 }, false);
        try pool.put(.{ 10, 128, 0, 2 }, false);
        try pool.put(.{ 10, 128, 0, 3 }, false);
        try pool.put(.{ 10, 128, 0, 4 }, false);
        try pool.put(.{ 10, 128, 0, 5 }, false);

        return .{ .pool = pool };
    }

    pub fn deinit(self: *StaticIPAllocator) void {
        self.pool.deinit();
    }

    pub fn alloc(self: *StaticIPAllocator) ![4]u8 {
        var it = self.pool.keyIterator();
        while (it.next()) |k| {
            if (self.pool.get(k.*) orelse true) continue;
            try self.pool.put(k.*, true);
            return k.*;
        }
        return error.EmptyPool;
    }

    pub fn dealloc(self: *StaticIPAllocator, k: [4]u8) !void {
        _ = self.pool.get(k) orelse return error.UnmanagedIP;
        try self.pool.put(k, false);
    }
};

test "alloc returns an IP from the pool" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    const ip = try ipam.alloc();
    try std.testing.expect(
        std.mem.eql(u8, &ip, &[_]u8{ 10, 128, 0, 1 }) or
        std.mem.eql(u8, &ip, &[_]u8{ 10, 128, 0, 2 }) or
        std.mem.eql(u8, &ip, &[_]u8{ 10, 128, 0, 3 }) or
        std.mem.eql(u8, &ip, &[_]u8{ 10, 128, 0, 4 }) or
        std.mem.eql(u8, &ip, &[_]u8{ 10, 128, 0, 5 }),
    );
}

test "alloc does not return the same IP twice" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    const ip1 = try ipam.alloc();
    const ip2 = try ipam.alloc();
    try std.testing.expect(!std.mem.eql(u8, &ip1, &ip2));
}

test "alloc returns EmptyPool when all IPs are in use" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    for (0..5) |_| _ = try ipam.alloc();
    try std.testing.expectError(error.EmptyPool, ipam.alloc());
}

test "dealloc frees IP back to pool" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    for (0..5) |_| _ = try ipam.alloc();
    try ipam.dealloc(.{ 10, 128, 0, 1 });
    _ = try ipam.alloc();
}

test "dealloc returns UnmanagedIP for unknown address" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    try std.testing.expectError(error.UnmanagedIP, ipam.dealloc(.{ 192, 168, 0, 1 }));
}

test "dealloc allows re-alloc of freed IP" {
    var ipam = try StaticIPAllocator.init(std.testing.allocator);
    defer ipam.deinit();

    for (0..5) |_| _ = try ipam.alloc();
    try ipam.dealloc(.{ 10, 128, 0, 3 });

    // pool has exactly one free IP, so alloc must return it
    const ip = try ipam.alloc();
    try std.testing.expectEqualSlices(u8, &[_]u8{ 10, 128, 0, 3 }, &ip);
}
