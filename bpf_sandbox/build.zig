const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    exe.step.dependOn(&install_generated_file.step);

    const xdp_obj = b.addObject(.{
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
    xdp_obj.root_module.strip = true;

    const install_xdp_file = b.addInstallFile(
        xdp_obj.getEmittedBin(),
        "bin/xdp.bpf.o",
    );
    exe.step.dependOn(&install_xdp_file.step);

    const tc_ingress_obj = b.addObject(.{
        .name = "prog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tc_ingress.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .bpfel,
                .os_tag = .freestanding,
                .abi = .none,
            }),
            .optimize = optimize,
        }),
    });
    tc_ingress_obj.root_module.strip = true;

    const install_tc_file = b.addInstallFile(
        tc_ingress_obj.getEmittedBin(),
        "bin/tc_ingress.bpf.o",
    );
    exe.step.dependOn(&install_tc_file.step);

    b.installArtifact(exe);

    const exe_check = b.addExecutable(options);
    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the loader").dependOn(&run_cmd.step);
}
