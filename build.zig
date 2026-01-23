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

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests
    const integration_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add imports for integration tests
    integration_mod.addImport("env-parser", env_parser_mod);
    integration_mod.addImport("masking", masking_mod);
    integration_mod.addImport("output", output_mod);

    const integration_tests = b.addTest(.{
        .root_module = integration_mod,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // =========================================================================
    // NEW TEST SUITES
    // =========================================================================

    // Edge cases tests
    const edge_cases_mod = b.createModule(.{
        .root_source_file = b.path("tests/edge-cases.zig"),
        .target = target,
        .optimize = optimize,
    });
    edge_cases_mod.addImport("env-parser", env_parser_mod);
    edge_cases_mod.addImport("masking", masking_mod);
    edge_cases_mod.addImport("output", output_mod);

    const edge_cases_tests = b.addTest(.{
        .root_module = edge_cases_mod,
    });
    const run_edge_cases_tests = b.addRunArtifact(edge_cases_tests);
    const edge_cases_step = b.step("test-edge-cases", "Run edge case tests");
    edge_cases_step.dependOn(&run_edge_cases_tests.step);

    // CLI commands tests
    const cli_commands_mod = b.createModule(.{
        .root_source_file = b.path("tests/cli-commands.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_commands_mod.addImport("env-parser", env_parser_mod);
    cli_commands_mod.addImport("masking", masking_mod);
    cli_commands_mod.addImport("output", output_mod);
    cli_commands_mod.addImport("cli", cli_mod);

    const cli_commands_tests = b.addTest(.{
        .root_module = cli_commands_mod,
    });
    const run_cli_commands_tests = b.addRunArtifact(cli_commands_tests);
    const cli_commands_step = b.step("test-cli", "Run CLI command tests");
    cli_commands_step.dependOn(&run_cli_commands_tests.step);

    // Security tests
    const security_mod = b.createModule(.{
        .root_source_file = b.path("tests/security.zig"),
        .target = target,
        .optimize = optimize,
    });
    security_mod.addImport("env-parser", env_parser_mod);
    security_mod.addImport("masking", masking_mod);
    security_mod.addImport("output", output_mod);

    const security_tests = b.addTest(.{
        .root_module = security_mod,
    });
    const run_security_tests = b.addRunArtifact(security_tests);
    const security_step = b.step("test-security", "Run security tests");
    security_step.dependOn(&run_security_tests.step);

    // E2E tests
    const e2e_mod = b.createModule(.{
        .root_source_file = b.path("tests/e2e.zig"),
        .target = target,
        .optimize = optimize,
    });
    e2e_mod.addImport("env-parser", env_parser_mod);
    e2e_mod.addImport("masking", masking_mod);
    e2e_mod.addImport("output", output_mod);

    const e2e_tests = b.addTest(.{
        .root_module = e2e_mod,
    });
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    const e2e_step = b.step("test-e2e", "Run end-to-end tests");
    e2e_step.dependOn(&run_e2e_tests.step);

    // Performance tests
    const performance_mod = b.createModule(.{
        .root_source_file = b.path("tests/performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    performance_mod.addImport("env-parser", env_parser_mod);
    performance_mod.addImport("masking", masking_mod);
    performance_mod.addImport("output", output_mod);

    const performance_tests = b.addTest(.{
        .root_module = performance_mod,
    });
    const run_performance_tests = b.addRunArtifact(performance_tests);
    const performance_step = b.step("test-performance", "Run performance tests");
    performance_step.dependOn(&run_performance_tests.step);

    // =========================================================================
    // COMBINED TEST STEPS
    // =========================================================================

    // All tests (comprehensive)
    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
    all_tests_step.dependOn(&run_edge_cases_tests.step);
    all_tests_step.dependOn(&run_cli_commands_tests.step);
    all_tests_step.dependOn(&run_security_tests.step);
    all_tests_step.dependOn(&run_e2e_tests.step);
    all_tests_step.dependOn(&run_performance_tests.step);
}
