const std = @import("std");

const SuiteSteps = struct {
    compile_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

fn addTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zdisamar_module: *std.Build.Module,
    build_options_module: *std.Build.Module,
    step_name: []const u8,
    step_description: []const u8,
    root_source_file: []const u8,
) SuiteSteps {
    const test_module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = zdisamar_module,
            },
            .{
                .name = "build_options",
                .module = build_options_module,
            },
        },
    });

    const suite_tests = b.addTest(.{
        .root_module = test_module,
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
    const runtime_optimize: std.builtin.OptimizeMode = .ReleaseFast;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_test_support", false);
    const build_options_module = build_options.createModule();

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "build_options",
                .module = build_options_module,
            },
        },
    });
    const disamar_reference_support_module = b.createModule(.{
        .root_source_file = b.path("src/validation.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zdisamar",
        .root_module = lib_module,
    });
    b.installArtifact(lib);
    const c_api_module = b.createModule(.{
        .root_source_file = b.path("src/api/c.zig"),
        .target = target,
        .optimize = runtime_optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
            .{
                .name = "build_options",
                .module = build_options_module,
            },
        },
    });
    const c_api_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zdisamar_c",
        .root_module = c_api_module,
    });
    const c_api_install = b.addInstallArtifact(c_api_lib, .{});
    b.getInstallStep().dependOn(&c_api_install.step);

    const plot_spectrum_module = b.createModule(.{
        .root_source_file = b.path("src/validation/disamar_reference/plot_spectrum_cli.zig"),
        .target = target,
        .optimize = runtime_optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
            .{
                .name = "build_options",
                .module = build_options_module,
            },
        },
    });
    const plot_spectrum_exe = b.addExecutable(.{
        .name = "zdisamar-o2a-plot-spectrum",
        .root_module = plot_spectrum_module,
    });
    b.installArtifact(plot_spectrum_exe);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/disamar_reference_cli.zig"),
        .target = target,
        .optimize = runtime_optimize,
    });
    const cli_exe = b.addExecutable(.{
        .name = "zdisamar",
        .root_module = cli_module,
    });
    b.installArtifact(cli_exe);

    const unit_test_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "zdisamar",
                .module = lib_module,
            },
        },
    });
    const unit_tests = b.addTest(.{
        .root_module = unit_test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const internal_test_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/internal_root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "internal",
                .module = b.createModule(.{
                    .root_source_file = b.path("src/internal.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{
                            .name = "build_options",
                            .module = build_options_module,
                        },
                    },
                }),
            },
        },
    });
    const internal_tests = b.addTest(.{
        .root_module = internal_test_module,
    });
    const run_internal_tests = b.addRunArtifact(internal_tests);
    const test_unit_step = b.step("test-unit", "Run the unit-test harness under tests/unit");
    test_unit_step.dependOn(&run_unit_tests.step);
    test_unit_step.dependOn(&run_internal_tests.step);

    const validation_o2a = addTestStep(
        b,
        target,
        optimize,
        lib_module,
        build_options_module,
        "test-validation-o2a",
        "Run focused O2A forward-shape validation tests",
        "tests/validation/o2a_forward_shape_test.zig",
    );
    const validation_o2a_vendor = addTestStep(
        b,
        target,
        optimize,
        lib_module,
        build_options_module,
        "test-validation-o2a-vendor",
        "Run O2A vendor reflectance assessment lane",
        "tests/validation/o2a_vendor_reflectance_assessment_test.zig",
    );
    const validation_o2a_vendor_line_list = addTestStep(
        b,
        target,
        optimize,
        lib_module,
        build_options_module,
        "test-validation-o2a-vendor-line-list",
        "Run O2A vendor line-list helper smoke tests",
        "tests/validation/o2a_vendor_line_list_smoke_test.zig",
    );
    const validation_o2a_yaml_module = b.createModule(.{
        .root_source_file = b.path("tests/validation/o2a_yaml_parity_runtime_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "disamar_reference_support",
                .module = disamar_reference_support_module,
            },
        },
    });
    const validation_o2a_yaml_tests = b.addTest(.{
        .root_module = validation_o2a_yaml_module,
    });
    const run_validation_o2a_yaml = b.addRunArtifact(validation_o2a_yaml_tests);
    const validation_o2a_yaml = SuiteSteps{
        .compile_step = &validation_o2a_yaml_tests.step,
        .run_step = &run_validation_o2a_yaml.step,
    };
    const validation_o2a_yaml_step = b.step(
        "test-validation-o2a-yaml",
        "Run the YAML-driven O2A DISAMAR reference and CLI validation lane",
    );
    validation_o2a_yaml_step.dependOn(&run_validation_o2a_yaml.step);
    const transport_smoke = addTestStep(
        b,
        target,
        optimize,
        lib_module,
        build_options_module,
        "test-validation-o2a-transport-smoke",
        "Run a small exact O2A transport smoke test",
        "tests/validation/o2a_transport_smoke_test.zig",
    );

    const fmt_check_cmd = b.addFmt(.{
        .check = true,
        .paths = &.{ "build.zig", "src", "tests", "scripts" },
    });
    const fmt_check_step = b.step("fmt-check", "Verify Zig formatting without rewriting files");
    fmt_check_step.dependOn(&fmt_check_cmd.step);

    const plot_spectrum_install = b.addInstallArtifact(plot_spectrum_exe, .{});
    const o2a_plot_bundle_spectrum_run = b.addRunArtifact(plot_spectrum_exe);
    o2a_plot_bundle_spectrum_run.addArg("--output-dir");
    o2a_plot_bundle_spectrum_run.addArg("out/analysis/o2a/plot_bundle_tmp");
    const o2a_plot_bundle_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/o2a_plot_bundle.py",
        "--current-spectrum",
        "out/analysis/o2a/plot_bundle_tmp/generated_spectrum.csv",
        "--vendor-reference",
        "validation/o2a_with_cia_disamar_reference.csv",
        "--output-dir",
        "validation",
        "--canonical-command",
        "zig build o2a-plots",
    });
    o2a_plot_bundle_cmd.step.dependOn(&plot_spectrum_install.step);
    o2a_plot_bundle_cmd.step.dependOn(&o2a_plot_bundle_spectrum_run.step);
    const o2a_plot_bundle_step = b.step(
        "o2a-plot-bundle",
        "Generate the tracked O2A plot bundle under validation",
    );
    o2a_plot_bundle_step.dependOn(&o2a_plot_bundle_cmd.step);
    const o2a_plots_step = b.step(
        "o2a-plots",
        "Run the O2A forward path and regenerate the tracked O2A comparison plots",
    );
    o2a_plots_step.dependOn(&o2a_plot_bundle_cmd.step);

    const o2a_plot_bundle_test_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/o2a_plot_bundle_test.py",
    });
    const o2a_plot_bundle_test_step = b.step(
        "test-validation-o2a-plot-bundle",
        "Run the O2A plot bundle harness smoke test",
    );
    o2a_plot_bundle_test_step.dependOn(&o2a_plot_bundle_test_cmd.step);

    const python_forward_summary_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_forward_summary.py",
    });
    python_forward_summary_cmd.step.dependOn(&c_api_install.step);
    const python_forward_summary_step = b.step(
        "python-forward-summary",
        "Run the Python-defined DISAMAR O2A spectrum summary script",
    );
    python_forward_summary_step.dependOn(&python_forward_summary_cmd.step);

    const python_o2a_setup_roundtrip_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_o2a_setup_roundtrip.py",
        "--output",
        "out/ci/python_o2a_setup_roundtrip.json",
        "--library",
    });
    python_o2a_setup_roundtrip_cmd.addFileArg(c_api_lib.getEmittedBin());
    python_o2a_setup_roundtrip_cmd.step.dependOn(&c_api_install.step);
    const python_o2a_setup_roundtrip_step = b.step(
        "python-o2a-setup-roundtrip",
        "Verify typed Python O2A setup against the default parity entrypoint",
    );
    python_o2a_setup_roundtrip_step.dependOn(&python_o2a_setup_roundtrip_cmd.step);

    const python_atmosphere_budget_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_atmosphere_budget.py",
    });
    python_atmosphere_budget_cmd.step.dependOn(&c_api_install.step);
    const python_atmosphere_budget_step = b.step(
        "python-atmosphere-budget",
        "Answer atmospheric budget science questions through the Python wrapper",
    );
    python_atmosphere_budget_step.dependOn(&python_atmosphere_budget_cmd.step);

    const python_o2_line_diagnostics_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_o2_line_diagnostics.py",
    });
    python_o2_line_diagnostics_cmd.step.dependOn(&c_api_install.step);
    const python_o2_line_diagnostics_step = b.step(
        "python-o2-line-diagnostics",
        "Answer O2 line spectroscopy science questions through the Python wrapper",
    );
    python_o2_line_diagnostics_step.dependOn(&python_o2_line_diagnostics_cmd.step);

    const python_o2_o2_cia_diagnostics_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_o2_o2_cia_diagnostics.py",
    });
    python_o2_o2_cia_diagnostics_cmd.step.dependOn(&c_api_install.step);
    const python_o2_o2_cia_diagnostics_step = b.step(
        "python-o2-o2-cia-diagnostics",
        "Answer O2-O2 CIA science questions through the Python wrapper",
    );
    python_o2_o2_cia_diagnostics_step.dependOn(&python_o2_o2_cia_diagnostics_cmd.step);

    const python_instrument_response_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_instrument_response.py",
    });
    python_instrument_response_cmd.step.dependOn(&c_api_install.step);
    const python_instrument_response_step = b.step(
        "python-instrument-response",
        "Answer instrument response science questions through the Python wrapper",
    );
    python_instrument_response_step.dependOn(&python_instrument_response_cmd.step);

    const python_radiative_transfer_diagnostics_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_radiative_transfer_diagnostics.py",
    });
    python_radiative_transfer_diagnostics_cmd.step.dependOn(&c_api_install.step);
    const python_radiative_transfer_diagnostics_step = b.step(
        "python-radiative-transfer-diagnostics",
        "Answer radiative-transfer science questions through the Python wrapper",
    );
    python_radiative_transfer_diagnostics_step.dependOn(&python_radiative_transfer_diagnostics_cmd.step);

    const python_parameter_perturbation_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_parameter_perturbation.py",
    });
    python_parameter_perturbation_cmd.step.dependOn(&c_api_install.step);
    const python_parameter_perturbation_step = b.step(
        "python-parameter-perturbation",
        "Answer parameter perturbation science questions through the Python wrapper",
    );
    python_parameter_perturbation_step.dependOn(&python_parameter_perturbation_cmd.step);

    const python_plotting_library_smoke_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/python_plotting_library_smoke.py",
    });
    const python_plotting_library_smoke_step = b.step(
        "python-plotting-library-smoke",
        "Build inspectable Altair plots for the Python plotting package",
    );
    python_plotting_library_smoke_step.dependOn(&python_plotting_library_smoke_cmd.step);

    const no_inline_src_tests_cmd = b.addSystemCommand(&.{
        "scripts/check-no-inline-src-tests.sh",
    });
    const no_inline_src_tests_step = b.step(
        "check-no-inline-src-tests",
        "Fail when an inline test block reappears under src/",
    );
    no_inline_src_tests_step.dependOn(&no_inline_src_tests_cmd.step);

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(fmt_check_step);
    check_step.dependOn(no_inline_src_tests_step);
    check_step.dependOn(&lib.step);
    check_step.dependOn(&c_api_lib.step);
    check_step.dependOn(&plot_spectrum_exe.step);
    check_step.dependOn(&cli_exe.step);
    check_step.dependOn(&unit_tests.step);
    check_step.dependOn(&internal_tests.step);
    check_step.dependOn(validation_o2a.compile_step);
    check_step.dependOn(validation_o2a_vendor.compile_step);
    check_step.dependOn(validation_o2a_vendor_line_list.compile_step);
    check_step.dependOn(validation_o2a_yaml.compile_step);
    check_step.dependOn(&run_unit_tests.step);
    check_step.dependOn(&run_internal_tests.step);

    const test_fast_step = b.step("test-fast", "Run the fast O2A verification suites");
    test_fast_step.dependOn(&run_unit_tests.step);
    test_fast_step.dependOn(&run_internal_tests.step);
    test_fast_step.dependOn(validation_o2a.compile_step);
    test_fast_step.dependOn(validation_o2a_vendor_line_list.run_step);
    test_fast_step.dependOn(validation_o2a_yaml.run_step);

    const test_transport_step = b.step("test-transport", "Run focused O2A exact transport verification");
    test_transport_step.dependOn(validation_o2a.compile_step);
    test_transport_step.dependOn(validation_o2a_vendor.compile_step);
    test_transport_step.dependOn(transport_smoke.run_step);

    const test_step = b.step("test", "Run the retained O2A verification baseline");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_internal_tests.step);
    test_step.dependOn(validation_o2a.run_step);
    test_step.dependOn(validation_o2a_vendor.run_step);
    test_step.dependOn(validation_o2a_vendor_line_list.run_step);
    test_step.dependOn(validation_o2a_yaml.run_step);
    test_step.dependOn(o2a_plot_bundle_test_step);
}
