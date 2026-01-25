const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create shared modules
    const env_parser_mod = b.createModule(.{
        .root_source_file = b.path("src/env-parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const masking_mod = b.createModule(.{
        .root_source_file = b.path("src/masking.zig"),
        .target = target,
        .optimize = optimize,
    });

    const output_mod = b.createModule(.{
        .root_source_file = b.path("src/output.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add imports between modules
    env_parser_mod.addImport("masking.zig", masking_mod);
    output_mod.addImport("masking.zig", masking_mod);
    output_mod.addImport("env-parser.zig", env_parser_mod);
    cli_mod.addImport("env-parser.zig", env_parser_mod);
    cli_mod.addImport("masking.zig", masking_mod);
    cli_mod.addImport("output.zig", output_mod);

    // Main executable
    const exe = b.addExecutable(.{
        .name = "enever",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run enever");
    run_step.dependOn(&run_cmd.step);

}
