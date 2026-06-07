const std = @import("std");
const bpf = @import("./bpf_gen.zig");

pub fn main(init: std.process.Init) !void {
    std.debug.print("Checking imports...\n", .{});

    // Read version constants defined inside <bpf/libbpf.h>
    const major = bpf.LIBBPF_MAJOR_VERSION;
    const minor = bpf.LIBBPF_MINOR_VERSION;

    std.debug.print("Success! libbpf imports are working. Version: {d}.{d}\n", .{ major, minor });

    const ifindex = bpf.if_nametoindex("eth0");

    const xdp_obj = bpf.bpf_object__open_file("zig-out/bin/xdp.bpf.o", null) orelse return error.OpenFailed;
    defer bpf.bpf_object__close(xdp_obj);
    if (bpf.bpf_object__load(xdp_obj) != 0) return error.LoadFailed;
    const xdp_prog = bpf.bpf_object__find_program_by_name(xdp_obj, "xdp_pass") orelse return error.ProgNotFound;
    const xdp_link = bpf.bpf_program__attach_xdp(xdp_prog, @intCast(ifindex)) orelse return error.AttachFailed;
    defer _ = bpf.bpf_link__destroy(xdp_link);

    const tc_ingress_obj = bpf.bpf_object__open_file("zig-out/bin/tc_ingress.bpf.o", null) orelse return error.OpenFailed;
    defer bpf.bpf_object__close(tc_ingress_obj);
    if (bpf.bpf_object__load(tc_ingress_obj) != 0) return error.LoadFailed;
    const tc_ingress_prog = bpf.bpf_object__find_program_by_name(tc_ingress_obj, "tc_ingress_ok") orelse return error.ProgNotFound;
    const tc_ingress_link = bpf.bpf_program__attach_tcx(tc_ingress_prog, @intCast(ifindex), null) orelse return error.AttachFailed;
    defer _ = bpf.bpf_link__destroy(tc_ingress_link);

    try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(120), .awake);
}
