const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build hello-world app
    const hello_world_exe = b.addExecutable(.{
        .name = "hello-world",
        .root_source_file = b.path("apps/hello-world/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(hello_world_exe);

    // Run step for hello-world
    const hello_world_run = b.addRunArtifact(hello_world_exe);
    hello_world_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        hello_world_run.addArgs(args);
    }
    const hello_world_run_step = b.step("hello-world", "Run the hello-world app");
    hello_world_run_step.dependOn(&hello_world_run.step);

    // Default run step (runs hello-world for now)
    const run_step = b.step("run", "Run the default app (hello-world)");
    run_step.dependOn(&hello_world_run.step);
}
