const std = @import("std");
const bpf = @import("./bpf_gen.zig");

pub fn main(init: std.process.Init) !void {
    std.debug.print("Checking imports...\n", .{});

    // Read version constants defined inside <bpf/libbpf.h>
    const major = bpf.LIBBPF_MAJOR_VERSION;
    const minor = bpf.LIBBPF_MINOR_VERSION;

    std.debug.print("Success! libbpf imports are working. Version: {d}.{d}\n", .{ major, minor });

    const obj = bpf.bpf_object__open_file("zig-out/bin/xdp.bpf.o", null) orelse return error.OpenFailed;
    defer bpf.bpf_object__close(obj);

    if (bpf.bpf_object__load(obj) != 0) return error.LoadFailed;

    const prog = bpf.bpf_object__find_program_by_name(obj, "xdp_pass") orelse return error.ProgNotFound;
    const fd = bpf.bpf_program__fd(prog);

    const ifindex = bpf.if_nametoindex("eth0");
    if (bpf.bpf_xdp_attach(@intCast(ifindex), fd, 0, null) != 0) return error.AttachFailed;

    try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(120), .awake);
}
