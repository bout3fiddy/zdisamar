const std = @import("std");

const SuiteSteps = struct {
    compile_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

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
) SuiteSteps {
    return addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        step_name,
        step_description,
        root_source_file,
        &.{},
    );
}

fn addSuiteRunStepWithArgs(
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
    filters: []const []const u8,
) SuiteSteps {
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
        .filters = filters,
    });
    const run_suite_tests = b.addRunArtifact(suite_tests);

    const suite_step = b.step(step_name, step_description);
    suite_step.dependOn(&run_suite_tests.step);
    return .{
        .compile_step = &suite_tests.step,
        .run_step = &run_suite_tests.step,
    };
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

    const bench_module = b.createModule(.{
        .root_source_file = b.path("tests/perf/bench_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
        },
    });
    const bench_exe = b.addExecutable(.{
        .name = "zdisamar-bench",
        .root_module = bench_module,
    });

    const o2a_vendor_dump_module = b.createModule(.{
        .root_source_file = b.path("tests/validation/o2a_vendor_reflectance_support.zig"),
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
        },
    });

    const o2a_vendor_dump_tool_module = b.createModule(.{
        .root_source_file = b.path("scripts/testing_harness/o2a_vendor_spectrum_dump.zig"),
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
                .name = "o2a_vendor_support",
                .module = o2a_vendor_dump_module,
            },
        },
    });
    const o2a_vendor_dump_exe = b.addExecutable(.{
        .name = "zdisamar-o2a-vendor-spectrum",
        .root_module = o2a_vendor_dump_tool_module,
    });

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
    const run_validation_asset_suite = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-assets",
        "Run non-compatibility validation asset suite",
        "tests/validation/main.zig",
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-lut-assets",
        "Run focused WP-08 LUT asset provenance and cache checks",
        "tests/validation/main.zig",
        &.{
            "generated LUT assets register typed cache entries and provenance labels",
            "consume-mode LUT execution records provenance without creating cache entries",
        },
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
    const run_validation_compatibility_transport_measurement = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-transport-measurement",
        "Run DISAMAR compatibility transport and measurement-space shards",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness executes transport and measurement-space parity cases against vendor anchors",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-retrieval",
        "Run DISAMAR compatibility retrieval shard",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness executes retrieval parity cases against vendor anchors",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-optics",
        "Run DISAMAR compatibility optics shard",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness executes optics parity cases against vendor anchors",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-rtm-controls",
        "Run DISAMAR compatibility RTM-controls harness check",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness execution honors RTM controls in prepared routes",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-asciihdf",
        "Run DISAMAR compatibility asciiHDF harness check",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness parses bounded vendor retrieval diagnostics from asciiHDF",
        },
    );
    const run_validation_compatibility_operational_measured_input = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-operational-measured-input",
        "Run DISAMAR compatibility operational measured-input classification proof",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness classifies operational measured-input S5P flows distinctly from synthetic scenes",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-compatibility-lut-parity",
        "Run WP-08 direct-vs-LUT compatibility parity checks",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness keeps Config_O2A_XsecLUT direct and generated runs within bounded parity",
            "compatibility harness keeps non-o2 LUT-backed NO2 parity within bounded tolerance",
        },
    );
    const run_validation_compatibility_full = addSuiteRunStepWithArgs(
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
        &.{
            "compatibility harness executes the full parity matrix against vendor anchors",
        },
    );
    const run_validation_cross_section_routes = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-cross-section-routes",
        "Run focused cross-section route validation proofs",
        "tests/validation/disamar_compatibility_harness_test.zig",
        &.{
            "compatibility harness routes explicit cross-section fixtures away from O2A defaults",
        },
    );
    const run_validation_cross_section_doas = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-cross-section-doas",
        "Run focused NO2 cross-section DOAS validation proof",
        "tests/validation/main.zig",
        &.{
            "doas validation routes a NO2 cross-section scene through explicit effective-xsec optics",
        },
    );
    const run_validation_cross_section_oe = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-cross-section-oe",
        "Run focused O3 cross-section OE validation proof",
        "tests/validation/main.zig",
        &.{
            "oe parity executes an O3 cross-section scene through the explicit LUT path",
        },
    );
    const run_validation_cross_section_parity = b.step(
        "test-validation-cross-section-parity",
        "Run focused WP-04 cross-section parity validation proofs",
    );
    run_validation_cross_section_parity.dependOn(run_validation_cross_section_routes.run_step);
    run_validation_cross_section_parity.dependOn(run_validation_cross_section_doas.run_step);
    run_validation_cross_section_parity.dependOn(run_validation_cross_section_oe.run_step);
    const validation_step = b.step("test-validation", "Run compatibility and validation asset suite");
    validation_step.dependOn(run_validation_asset_suite.run_step);
    validation_step.dependOn(run_validation_cross_section_parity);
    validation_step.dependOn(run_validation_compatibility_operational_measured_input.run_step);
    validation_step.dependOn(run_validation_compatibility_full.run_step);
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
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-o2a-adaptive",
        "Run focused O2A adaptive strong-line sampling validation",
        "tests/validation/o2a_forward_shape_test.zig",
        &.{
            "o2a adaptive strong-line sampling is used in execution when adaptive grid is enabled",
        },
    );
    _ = addSuiteRunStepWithArgs(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-o2a-controls",
        "Run focused O2A line-gas control and CIA sensitivity validation",
        "tests/validation/o2a_forward_shape_test.zig",
        &.{
            "o2a validation responds to line mixing, isotope selection, cutoff, and CIA toggles",
        },
    );
    _ = addSuiteRunStep(
        b,
        target,
        optimize,
        test_lib_module,
        internal_module,
        test_legacy_config_module,
        test_cli_app_module,
        "test-validation-line-gas",
        "Run focused line-gas family validation tests",
        "tests/validation/line_gas_family_validation_test.zig",
    );
    _ = addSuiteRunStep(
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

    const fmt_check_cmd = b.addFmt(.{
        .check = true,
        .paths = &.{ "build.zig", "src", "tests" },
    });
    const fmt_check_step = b.step("fmt-check", "Verify Zig formatting without rewriting files");
    fmt_check_step.dependOn(&fmt_check_cmd.step);

    const bench_run = b.addRunArtifact(bench_exe);
    bench_run.addArg("out/ci/bench/summary.json");
    const bench_step = b.step("bench", "Run the non-gating benchmark harness and emit summaries");
    bench_step.dependOn(&bench_run.step);

    const o2a_vendor_dump_run = b.addRunArtifact(o2a_vendor_dump_exe);
    const o2a_vendor_plot_cmd = b.addSystemCommand(&.{
        "python3",
        "scripts/testing_harness/plot_o2a_vendor_spectrum.py",
    });
    o2a_vendor_plot_cmd.step.dependOn(&o2a_vendor_dump_run.step);
    const o2a_vendor_plot_step = b.step(
        "o2a-vendor-plot",
        "Generate a fresh O2A vendor comparison CSV and plot",
    );
    o2a_vendor_plot_step.dependOn(&o2a_vendor_plot_cmd.step);

    const tidy_cmd = b.addSystemCommand(&.{
        "python3",
        "scripts/testing_harness/tidy.py",
        "--report",
        "out/ci/tidy/report.json",
    });
    const tidy_step = b.step("tidy", "Run architecture and policy checks");
    tidy_step.dependOn(&tidy_cmd.step);

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(fmt_check_step);
    check_step.dependOn(&lib.step);
    check_step.dependOn(&exe.step);
    check_step.dependOn(&lib_tests.step);
    check_step.dependOn(run_unit_suite.compile_step);
    check_step.dependOn(run_integration_suite.compile_step);
    check_step.dependOn(run_golden_suite.compile_step);
    check_step.dependOn(run_perf_suite.compile_step);
    check_step.dependOn(run_validation_asset_suite.compile_step);
    check_step.dependOn(run_validation_compatibility.compile_step);
    check_step.dependOn(run_validation_compatibility_full.compile_step);
    check_step.dependOn(run_unit_suite.run_step);

    const test_fast_step = b.step("test-fast", "Run the fast presubmit suites");
    test_fast_step.dependOn(run_unit_suite.run_step);
    test_fast_step.dependOn(run_integration_suite.run_step);

    const transport_step = b.step("test-transport", "Run focused transport parity verification");
    transport_step.dependOn(run_unit_suite.run_step);
    transport_step.dependOn(run_integration_forward_model.run_step);
    transport_step.dependOn(run_validation_compatibility_transport_measurement.run_step);
    transport_step.dependOn(run_validation_compatibility_operational_measured_input.run_step);
    transport_step.dependOn(run_validation_o2a.run_step);

    const test_suites_step = b.step("test-suites", "Run all verification suites");
    test_suites_step.dependOn(run_unit_suite.run_step);
    test_suites_step.dependOn(run_integration_suite.run_step);
    test_suites_step.dependOn(run_golden_suite.run_step);
    test_suites_step.dependOn(run_perf_suite.run_step);
    test_suites_step.dependOn(validation_step);

    const test_step = b.step("test", "Run full verification baseline");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(test_suites_step);
}
