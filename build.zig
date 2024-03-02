const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "1brc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();

    const create_sample_exe = b.addExecutable(.{
        .name = "run-create-sample",
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    create_sample_exe.addCSourceFile(.{
        .file = .{ .path = "src/create-sample.c" },
        .flags = &[_][]const u8{ "-Wall", "-Wextra", "-Werror" },
    });
    create_sample_exe.linkLibC();

    b.installArtifact(exe);
    b.installArtifact(create_sample_exe);

    const run_cmd = b.addRunArtifact(exe);
    const run_create_sample_cmd = b.addRunArtifact(create_sample_exe);

    run_cmd.step.dependOn(b.getInstallStep());
    run_create_sample_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_create_sample_cmd.addArgs(args);
    }
}
