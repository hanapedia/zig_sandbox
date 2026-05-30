const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ziglb: operator + agent (pulls in client_zig and zigbgp transitively)
    const ziglb_dep = b.dependency("ziglb", .{ .target = target, .optimize = optimize });
    const operator = ziglb_dep.artifact("ziglb-operator");
    const agent = ziglb_dep.artifact("ziglb-agent");
    b.installArtifact(operator);
    b.installArtifact(agent);

    // zigbgp: demo binary
    const zigbgp_dep = b.dependency("zigbgp", .{ .target = target, .optimize = optimize });
    const zigbgp_exe = zigbgp_dep.artifact("zigbgp");
    b.installArtifact(zigbgp_exe);

    // run steps
    const run_operator = b.addRunArtifact(operator);
    run_operator.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_operator.addArgs(args);
    b.step("run-operator", "Run ziglb-operator").dependOn(&run_operator.step);

    const run_agent = b.addRunArtifact(agent);
    run_agent.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_agent.addArgs(args);
    b.step("run-agent", "Run ziglb-agent").dependOn(&run_agent.step);

    const run_zigbgp = b.addRunArtifact(zigbgp_exe);
    run_zigbgp.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_zigbgp.addArgs(args);
    b.step("run-zigbgp", "Run zigbgp demo").dependOn(&run_zigbgp.step);

    // check step for ZLS — compile without installing
    const check = b.step("check", "Check all packages compile");
    check.dependOn(&b.addInstallArtifact(operator, .{}).step);
    check.dependOn(&b.addInstallArtifact(agent, .{}).step);
    check.dependOn(&b.addInstallArtifact(zigbgp_exe, .{}).step);
}
