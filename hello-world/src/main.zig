const std = @import("std");
const hello_world = @import("hello_world");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    const v = hello_world.mighFail(-32) catch 0;
    std.debug.print("replaced with catch {d}.\n", .{v});
    if (hello_world.mighFail(-32)) |y| {
        std.debug.print("printed because not error {d}.\n", .{y});
    } else |err| {
        switch (err) {
            error.Negative => std.debug.print("printed because error {t}.\n", .{err}),
            error.Another => std.debug.print("printed because error {t}.\n", .{err}),
        }
    }
    for (0..35) |i| {
        const div_3: u2 = @intFromBool(i % 3 == 0);
        const div_5 = @intFromBool(i % 5 == 0);
        switch (div_3 << 1 | div_5) {
            0b00 => std.debug.print("{d}\n", .{i}),
            0b01 => std.debug.print("buzz\n", .{}),
            0b10 => std.debug.print("fizz\n", .{}),
            0b11 => std.debug.print("fizzbuzz\n", .{}),
        }
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
