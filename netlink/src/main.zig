const std = @import("std");
const nl = @import("netlink");

const linux = std.os.linux;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    // test socket
    // try testSocket(allocator);

    // test generator
    try testGenerator(allocator, io);
}

fn testSocket(allocator: std.mem.Allocator) !void {
    var s = nl.socket.Socket.init();
    try s.open();
    defer s.close();
    const payload = std.mem.zeroes(linux.ifinfomsg);
    var res = try s.request(
        allocator,
        nl.socket.Request{
            .msg_type = .RTM_GETLINK,
            .flags = linux.NLM_F_REQUEST | linux.NLM_F_DUMP,
            .payload = std.mem.asBytes(&payload),
        },
    );
    defer res.deinit(allocator);
    for (res.msgs.items) |msg| {
        std.debug.print("msg: {}\n", .{msg.data.len});
    }
}

fn testGenerator(allocator: std.mem.Allocator, io: std.Io) !void {
    const json_text = @embedFile("generator/specs/preprocessed/rt-link.json");
    const parsed = try std.json.parseFromSlice(nl.spec.Spec, allocator, json_text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    std.debug.print("name: {s}\n", .{parsed.value.name});

    const file = try std.Io.Dir.cwd().createFile(io, "generated.zig", .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);

    try nl.generator.generate(allocator, &writer.interface, parsed.value);
    try writer.flush();
}
