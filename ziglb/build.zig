const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const client_zig_dep = b.dependency("client_zig", .{ .target = target, .optimize = optimize });
    const client_zig_mod = client_zig_dep.module("client_zig");

    const zigbgp_dep = b.dependency("zigbgp", .{ .target = target, .optimize = optimize });
    const zigbgp_mod = zigbgp_dep.module("zigbgp");

    const zio_dep = b.dependency("zio", .{ .target = target, .optimize = optimize });
    const zio_mod = zio_dep.module("zio");

    const operator_opts = std.Build.ExecutableOptions{
        .name = "ziglb-operator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/operator/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "client_zig", .module = client_zig_mod },
                .{ .name = "zio", .module = zio_mod },
            },
        }),
    };
    const operator = b.addExecutable(operator_opts);
    b.installArtifact(operator);
    const check_operator = b.addExecutable(operator_opts);

    const agent_opts = std.Build.ExecutableOptions{
        .name = "ziglb-agent",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/agent/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "client_zig", .module = client_zig_mod },
                .{ .name = "zigbgp", .module = zigbgp_mod },
                .{ .name = "zio", .module = zio_mod },
            },
        }),
    };
    const agent = b.addExecutable(agent_opts);
    b.installArtifact(agent);
    const check_agent = b.addExecutable(agent_opts);

    const run_operator = b.addRunArtifact(operator);
    run_operator.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_operator.addArgs(args);
    b.step("run-operator", "Run ziglb-operator").dependOn(&run_operator.step);

    const run_agent = b.addRunArtifact(agent);
    run_agent.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_agent.addArgs(args);
    b.step("run-agent", "Run ziglb-agent").dependOn(&run_agent.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = operator.root_module })).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = agent.root_module })).step);

    const check = b.step("check", "Check if operator and agent compiles");
    check.dependOn(&check_operator.step);
    check.dependOn(&check_agent.step);
}
