const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zio_dep = b.dependency("zio", .{ .target = target, .optimize = optimize });
    const zio_mod = zio_dep.module("zio");

    const zig_http_server_opts = std.Build.ExecutableOptions{
        .name = "zig-http-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zio", .module = zio_mod },
            },
        }),
    };
    const zig_http_server = b.addExecutable(zig_http_server_opts);
    b.installArtifact(zig_http_server);
    const check_zig_http_server = b.addExecutable(zig_http_server_opts);

    const check = b.step("check", "Check if zig_http_server compiles");
    check.dependOn(&check_zig_http_server.step);
}
