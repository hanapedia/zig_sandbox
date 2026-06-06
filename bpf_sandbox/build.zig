const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bpf_obj = b.addObject(.{
        .name = "prog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/xdp.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .bpfel,
                .os_tag = .freestanding,
                .abi = .none,
            }),
            .optimize = optimize,
        }),
    });
    bpf_obj.root_module.strip = true;

    const install_bpf_file = b.addInstallFile(
        bpf_obj.getEmittedBin(),
        "bin/xdp.bpf.o",
    );

    const options = std.Build.ExecutableOptions{
        .name = "loader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/loader.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    };
    const exe = b.addExecutable(options);
    exe.root_module.linkSystemLibrary("bpf", .{});
    exe.root_module.linkSystemLibrary("elf", .{});
    exe.root_module.linkSystemLibrary("z", .{});
    exe.root_module.linkSystemLibrary("c", .{});

    const bpf_bindings = b.addTranslateC(.{
        .root_source_file = b.path("src/bpf_headers.h"),
        .target = target,
        .optimize = optimize,
    });
    bpf_bindings.addIncludePath(.{ .cwd_relative = "/usr/include" });
    // const bpf_module = bpf_bindings.createModule();
    // exe.root_module.addImport("bpf", bpf_module);
    const install_generated_file = b.addInstallFile(
        bpf_bindings.getOutput(),
        "../src/bpf_gen.zig",
    );

    exe.step.dependOn(&install_bpf_file.step);
    exe.step.dependOn(&install_generated_file.step);

    b.installArtifact(exe);

    const exe_check = b.addExecutable(options);
    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the loader").dependOn(&run_cmd.step);
}
