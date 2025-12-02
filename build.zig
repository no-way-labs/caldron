const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build mitt app
    const mitt_exe = b.addExecutable(.{
        .name = "mitt",
        .root_source_file = b.path("apps/mitt/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(mitt_exe);

    // Run step for mitt
    const mitt_run = b.addRunArtifact(mitt_exe);
    mitt_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        mitt_run.addArgs(args);
    }
    const mitt_run_step = b.step("mitt", "Run the mitt app");
    mitt_run_step.dependOn(&mitt_run.step);

    // Default run step (runs mitt)
    const run_step = b.step("run", "Run the default app (mitt)");
    run_step.dependOn(&mitt_run.step);

    // Test step for mitt
    const mitt_tests = b.addTest(.{
        .root_source_file = b.path("apps/mitt/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_mitt_tests = b.addRunArtifact(mitt_tests);
    const test_step = b.step("test", "Run mitt tests");
    test_step.dependOn(&run_mitt_tests.step);
}
