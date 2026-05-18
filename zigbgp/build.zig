const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module — re-exported by src/root.zig
    const mod = b.addModule("zigbgp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Demo executable (src/main.zig) that imports the library
    const options = std.Build.ExecutableOptions{
        .name = "zigbgp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigbgp", .module = mod },
            },
        }),
    };
    const exe = b.addExecutable(options);
    b.installArtifact(exe);

    const exe_check = b.addExecutable(options);
    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the demo").dependOn(&run_cmd.step);

    // Tests: run both the library module and the exe module
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module })).step);
}
