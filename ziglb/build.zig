const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const operator = b.addExecutable(.{
        .name = "ziglb-operator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/operator/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(operator);

    const agent = b.addExecutable(.{
        .name = "ziglb-agent",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/agent/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(agent);

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
}
