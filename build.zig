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
    const parity_support_module = b.createModule(.{
        .root_source_file = b.path("src/parity_support_root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zdisamar",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    const profile_module = b.createModule(.{
        .root_source_file = b.path("src/o2a/cli/profile.zig"),
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
    const profile_exe = b.addExecutable(.{
        .name = "zdisamar-o2a-forward-profile",
        .root_module = profile_module,
    });
    b.installArtifact(profile_exe);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/parity_cli_root.zig"),
        .target = target,
        .optimize = runtime_optimize,
    });
    const cli_exe = b.addExecutable(.{
        .name = "zdisamar",
        .root_module = cli_module,
    });
    b.installArtifact(cli_exe);

    const lib_tests = b.addTest(.{
        .root_module = lib_module,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

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
    const validation_o2a_vendor_profile = addTestStep(
        b,
        target,
        optimize,
        lib_module,
        build_options_module,
        "test-validation-o2a-vendor-profile",
        "Run O2A vendor profile and reporting smoke tests",
        "tests/validation/o2a_vendor_reflectance_profile_smoke_test.zig",
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
                .name = "parity_support",
                .module = parity_support_module,
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
        "Run the YAML-driven O2A parity and CLI validation lane",
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

    const profile_install = b.addInstallArtifact(profile_exe, .{});
    const profile_run = b.addRunArtifact(profile_exe);
    const o2a_forward_profile_step = b.step(
        "o2a-forward-profile",
        "Run the O2A forward profiler and emit summary artifacts",
    );
    o2a_forward_profile_step.dependOn(&profile_install.step);
    o2a_forward_profile_step.dependOn(&profile_run.step);

    const o2a_plot_bundle_profile_run = b.addRunArtifact(profile_exe);
    o2a_plot_bundle_profile_run.addArg("--output-dir");
    o2a_plot_bundle_profile_run.addArg("out/analysis/o2a/plot_bundle_tmp");
    o2a_plot_bundle_profile_run.addArg("--repeat");
    o2a_plot_bundle_profile_run.addArg("1");
    o2a_plot_bundle_profile_run.addArg("--write-spectrum");
    o2a_plot_bundle_profile_run.addArg("--plot-bundle-grid");
    const o2a_plot_bundle_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/o2a_plot_bundle.py",
        "--current-spectrum",
        "out/analysis/o2a/plot_bundle_tmp/generated_spectrum.csv",
        "--profile-summary",
        "out/analysis/o2a/plot_bundle_tmp/summary.json",
        "--vendor-reference",
        "validation/reference/o2a_with_cia_disamar_reference.csv",
        "--output-dir",
        "validation/compatibility/o2a_plots",
        "--canonical-command",
        "zig build o2a-plots",
    });
    o2a_plot_bundle_cmd.step.dependOn(&profile_install.step);
    o2a_plot_bundle_cmd.step.dependOn(&o2a_plot_bundle_profile_run.step);
    const o2a_plot_bundle_step = b.step(
        "o2a-plot-bundle",
        "Generate the tracked O2A plot bundle under validation/compatibility/o2a_plots",
    );
    o2a_plot_bundle_step.dependOn(&o2a_plot_bundle_cmd.step);
    const o2a_plots_step = b.step(
        "o2a-plots",
        "Run the O2A forward path and regenerate the tracked O2A comparison plots",
    );
    o2a_plots_step.dependOn(&o2a_plot_bundle_cmd.step);

    const o2a_vendor_reference_refresh_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/o2a_vendor_reference_refresh.py",
    });
    const o2a_vendor_reference_refresh_step = b.step(
        "o2a-vendor-reference-refresh",
        "Regenerate the tracked O2A vendor reference CSV from the vendored DISAMAR executable",
    );
    o2a_vendor_reference_refresh_step.dependOn(&o2a_vendor_reference_refresh_cmd.step);

    const o2a_plot_bundle_test_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/o2a_plot_bundle_test.py",
    });
    const o2a_plot_bundle_test_step = b.step(
        "test-validation-o2a-plot-bundle",
        "Run the O2A plot bundle harness smoke test",
    );
    o2a_plot_bundle_test_step.dependOn(&o2a_plot_bundle_test_cmd.step);

    const o2a_function_diff_test_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "scripts/testing_harness/o2a_function_diff_test.py",
    });
    const o2a_function_diff_test_step = b.step(
        "test-validation-o2a-function-diff",
        "Run the O2A function-diff harness smoke test",
    );
    o2a_function_diff_test_step.dependOn(&o2a_function_diff_test_cmd.step);

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(fmt_check_step);
    check_step.dependOn(&lib.step);
    check_step.dependOn(&profile_exe.step);
    check_step.dependOn(&cli_exe.step);
    check_step.dependOn(&lib_tests.step);
    check_step.dependOn(validation_o2a.compile_step);
    check_step.dependOn(validation_o2a_vendor.compile_step);
    check_step.dependOn(validation_o2a_vendor_profile.compile_step);
    check_step.dependOn(validation_o2a_vendor_line_list.compile_step);
    check_step.dependOn(validation_o2a_yaml.compile_step);
    check_step.dependOn(&run_lib_tests.step);

    const test_fast_step = b.step("test-fast", "Run the fast O2A verification suites");
    test_fast_step.dependOn(&lib_tests.step);
    test_fast_step.dependOn(validation_o2a.compile_step);
    test_fast_step.dependOn(validation_o2a_vendor_line_list.run_step);
    test_fast_step.dependOn(validation_o2a_yaml.run_step);

    const test_transport_step = b.step("test-transport", "Run focused O2A exact transport verification");
    test_transport_step.dependOn(validation_o2a.compile_step);
    test_transport_step.dependOn(validation_o2a_vendor.compile_step);
    test_transport_step.dependOn(transport_smoke.run_step);

    const test_step = b.step("test", "Run the retained O2A verification baseline");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(validation_o2a.run_step);
    test_step.dependOn(validation_o2a_vendor.run_step);
    test_step.dependOn(validation_o2a_vendor_profile.run_step);
    test_step.dependOn(validation_o2a_vendor_line_list.run_step);
    test_step.dependOn(validation_o2a_yaml.run_step);
    test_step.dependOn(o2a_plot_bundle_test_step);
    test_step.dependOn(o2a_function_diff_test_step);
}
