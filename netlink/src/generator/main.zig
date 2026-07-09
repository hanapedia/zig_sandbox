const std = @import("std");
const nl = @import("netlink");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var gpa = std.heap.DebugAllocator(.{ .stack_trace_frames = 16 }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const specs = .{
        .{ @embedFile("specs/preprocessed/rt-link.json"), "src/generator/generated/rt-link.zig" },
        .{ @embedFile("specs/preprocessed/rt-addr.json"), "src/generator/generated/rt-addr.zig" },
        .{ @embedFile("specs/preprocessed/rt-route.json"), "src/generator/generated/rt-route.zig" },
        .{ @embedFile("specs/preprocessed/rt-rule.json"), "src/generator/generated/rt-rule.zig" },
        .{ @embedFile("specs/preprocessed/rt-neigh.json"), "src/generator/generated/rt-neigh.zig" },
    };

    inline for (specs) |entry| {
        const json_bytes, const out_path = entry;
        const parsed = try std.json.parseFromSlice(nl.spec.Spec, allocator, json_bytes, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const out_file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
        defer out_file.close(io);

        var buf: [4096]u8 = undefined;
        var writer = out_file.writer(io, &buf);
        try nl.generator.generate(allocator, &writer.interface, parsed.value);
        try writer.flush();
    }
}
