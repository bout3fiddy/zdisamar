const std = @import("std");

fn addSuiteRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_lib_module: *std.Build.Module,
    internal_module: *std.Build.Module,
    test_legacy_config_module: *std.Build.Module,
    test_cli_app_module: *std.Build.Module,
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
                .module = test_lib_module,
            },
            .{
                .name = "zdisamar_internal",
                .module = internal_module,
            },
            .{
                .name = "legacy_config",
                .module = test_legacy_config_module,
            },
            .{
                .name = "cli_app",
                .module = test_cli_app_module,
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
    const public_build_options = b.addOptions();
    public_build_options.addOption(bool, "enable_test_support", false);
    const test_build_options = b.addOptions();
    test_build_options.addOption(bool, "enable_test_support", true);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "build_options",
                .module = public_build_options.createModule(),
            },
        },
    });
    const test_lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "build_options",
                .module = test_build_options.createModule(),
            },
        },
    });
    const internal_module = b.createModule(.{
        .root_source_file = b.path("src/internal.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = test_lib_module,
            },
        },
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zdisamar",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

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
    const test_legacy_config_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/legacy_config/Adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = test_lib_module,
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

    const test_cli_app_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/cli/App.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = test_lib_module,
            },
            .{
                .name = "legacy_config",
                .module = test_legacy_config_module,
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
        .imports = &.{
            .{
                .name = "build_options",
                .module = public_build_options.createModule(),
            },
        },
    });

    const lib_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const run_unit_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-unit",
        "Run unit verification suite",
        "tests/unit/main.zig",
    );
    const run_integration_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-integration",
        "Run integration verification suite",
        "tests/integration/main.zig",
    );
    const run_integration_forward_model = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-integration-forward-model",
        "Run focused forward-model integration tests",
        "tests/integration/forward_model_integration_test.zig",
    );
    const run_golden_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-golden",
        "Run golden validation suite",
        "tests/golden/main.zig",
    );
    const run_perf_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-perf",
        "Run performance smoke suite",
        "tests/perf/main.zig",
    );
    const run_validation_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation",
        "Run compatibility and validation asset suite",
        "tests/validation/main.zig",
    );
    const run_validation_compatibility = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility",
        "Run fast DISAMAR compatibility smoke tests",
        "tests/validation/disamar_compatibility_smoke_test.zig",
    );
    const run_validation_compatibility_full = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-full",
        "Run full DISAMAR compatibility harness validation",
        "tests/validation/disamar_compatibility_harness_test.zig",
    );
    _ = run_validation_compatibility_full;
    const run_validation_o2a = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-o2a",
        "Run focused O2A forward-shape validation tests",
        "tests/validation/o2a_forward_shape_test.zig",
    );
    const run_validation_o2a_vendor = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-o2a-vendor",
        "Run O2A vendor reflectance assessment lane",
        "tests/validation/o2a_vendor_reflectance_assessment_test.zig",
    );
    _ = run_validation_o2a_vendor;

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(run_unit_suite);

    const transport_step = b.step("test-transport", "Run focused transport parity verification");
    transport_step.dependOn(run_unit_suite);
    transport_step.dependOn(run_integration_forward_model);
    transport_step.dependOn(run_validation_compatibility);
    transport_step.dependOn(run_validation_o2a);

    const test_suites_step = b.step("test-suites", "Run all verification suites");
    test_suites_step.dependOn(run_unit_suite);
    test_suites_step.dependOn(run_integration_suite);
    test_suites_step.dependOn(run_golden_suite);
    test_suites_step.dependOn(run_perf_suite);
    test_suites_step.dependOn(run_validation_suite);

    const test_step = b.step("test", "Run full verification baseline");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(test_suites_step);
}
