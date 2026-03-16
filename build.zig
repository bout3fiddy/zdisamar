const std = @import("std");

fn addSuiteRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_module: *std.Build.Module,
    retrieval_module: *std.Build.Module,
    legacy_config_module: *std.Build.Module,
    cli_app_module: *std.Build.Module,
    step_name: []const u8,
    step_description: []const u8,
    root_source_file: []const u8,
) *std.Build.Step {
    const suite_module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
            .{
                .name = "retrieval",
                .module = retrieval_module,
            },
            .{
                .name = "legacy_config",
                .module = legacy_config_module,
            },
            .{
                .name = "cli_app",
                .module = cli_app_module,
            },
        },
    });

    const suite_tests = b.addTest(.{
        .root_module = suite_module,
    });
    const run_suite_tests = b.addRunArtifact(suite_tests);

    const suite_step = b.step(step_name, step_description);
    suite_step.dependOn(&run_suite_tests.step);
    return &run_suite_tests.step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zdisamar",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    const retrieval_module = b.createModule(.{
        .root_source_file = b.path("src/retrieval/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
        },
    });

    const legacy_config_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/legacy_config/Adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
        },
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
            .{
                .name = "legacy_config",
                .module = legacy_config_module,
            },
        },
    });

    const cli_app_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/cli/App.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
            .{
                .name = "legacy_config",
                .module = legacy_config_module,
            },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zdisamar",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const run_unit_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        lib_module,
        retrieval_module,
        legacy_config_module,
        cli_app_module,
        "test-unit",
        "Run unit verification suite",
        "tests/unit/main.zig",
    );
    const run_integration_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        lib_module,
        retrieval_module,
        legacy_config_module,
        cli_app_module,
        "test-integration",
        "Run integration verification suite",
        "tests/integration/main.zig",
    );
    const run_golden_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        lib_module,
        retrieval_module,
        legacy_config_module,
        cli_app_module,
        "test-golden",
        "Run golden validation suite",
        "tests/golden/main.zig",
    );
    const run_perf_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        lib_module,
        retrieval_module,
        legacy_config_module,
        cli_app_module,
        "test-perf",
        "Run performance smoke suite",
        "tests/perf/main.zig",
    );
    const run_validation_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        lib_module,
        retrieval_module,
        legacy_config_module,
        cli_app_module,
        "test-validation",
        "Run compatibility and validation asset suite",
        "tests/validation/main.zig",
    );

    const test_suites_step = b.step("test-suites", "Run all verification suites");
    test_suites_step.dependOn(run_unit_suite);
    test_suites_step.dependOn(run_integration_suite);
    test_suites_step.dependOn(run_golden_suite);
    test_suites_step.dependOn(run_perf_suite);
    test_suites_step.dependOn(run_validation_suite);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(test_suites_step);
}
