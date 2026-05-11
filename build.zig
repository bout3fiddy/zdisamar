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
    const enable_ztracy = b.option(
        bool,
        "enable-ztracy",
        "Enable full Tracy profile zones in the trace executable",
    ) orelse false;
    const trace_optimize = b.option(
        std.builtin.OptimizeMode,
        "trace-optimize",
        "Optimization mode for the LABOS bottleneck trace executable",
    ) orelse runtime_optimize;

    const ztracy_stub_module = b.createModule(.{
        .root_source_file = b.path("src/forward_model/tracy_stub.zig"),
        .target = target,
        .optimize = optimize,
    });
    const trace_ztracy_dependency = b.dependency("ztracy", .{
        .enable_ztracy = enable_ztracy,
        .enable_fibers = false,
        .on_demand = false,
        .callstack = 8,
    });
    const trace_ztracy_module = if (enable_ztracy)
        trace_ztracy_dependency.module("root")
    else
        ztracy_stub_module;

    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_test_support", false);
    build_options.addOption(bool, "enable_ztracy", false);
    const build_options_module = build_options.createModule();

    const trace_build_options = b.addOptions();
    trace_build_options.addOption(bool, "enable_test_support", false);
    trace_build_options.addOption(bool, "enable_ztracy", enable_ztracy);
    const trace_build_options_module = trace_build_options.createModule();

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "build_options",
                .module = build_options_module,
            },
            .{
                .name = "ztracy",
                .module = ztracy_stub_module,
            },
        },
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
            .{
                .name = "ztracy",
                .module = ztracy_stub_module,
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
        .root_source_file = b.path("src/validation/o2a_plot_spectrum_cli.zig"),
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
            .{
                .name = "ztracy",
                .module = ztracy_stub_module,
            },
        },
    });
    const plot_spectrum_exe = b.addExecutable(.{
        .name = "zdisamar-o2a-plot-spectrum",
        .root_module = plot_spectrum_module,
    });
    b.installArtifact(plot_spectrum_exe);

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
                        .{
                            .name = "ztracy",
                            .module = ztracy_stub_module,
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

    const labos_kernel_bench_module = b.createModule(.{
        .root_source_file = b.path("tests/perf/labos_kernel_bench.zig"),
        .target = target,
        .optimize = runtime_optimize,
        .imports = &.{
            .{
                .name = "internal",
                .module = b.createModule(.{
                    .root_source_file = b.path("src/internal.zig"),
                    .target = target,
                    .optimize = runtime_optimize,
                    .imports = &.{
                        .{
                            .name = "build_options",
                            .module = build_options_module,
                        },
                        .{
                            .name = "ztracy",
                            .module = ztracy_stub_module,
                        },
                    },
                }),
            },
        },
    });
    const labos_kernel_bench_exe = b.addExecutable(.{
        .name = "labos-kernel-bench",
        .root_module = labos_kernel_bench_module,
    });
    const run_labos_kernel_bench = b.addRunArtifact(labos_kernel_bench_exe);
    const bench_step = b.step("bench", "Run bounded LABOS kernel performance probes");
    bench_step.dependOn(&run_labos_kernel_bench.step);

    const trace_internal_module = b.createModule(.{
        .root_source_file = b.path("src/internal.zig"),
        .target = target,
        .optimize = trace_optimize,
        .imports = &.{
            .{
                .name = "build_options",
                .module = trace_build_options_module,
            },
            .{
                .name = "ztracy",
                .module = trace_ztracy_module,
            },
        },
    });
    const labos_bottleneck_trace_module = b.createModule(.{
        .root_source_file = b.path("src/validation/performance/labos_bottleneck_trace_cli.zig"),
        .target = target,
        .optimize = trace_optimize,
        .imports = &.{
            .{
                .name = "internal",
                .module = trace_internal_module,
            },
        },
    });
    const labos_bottleneck_trace_exe = b.addExecutable(.{
        .name = "labos-bottleneck-trace",
        .root_module = labos_bottleneck_trace_module,
    });
    if (enable_ztracy) {
        labos_bottleneck_trace_exe.root_module.linkLibrary(trace_ztracy_dependency.artifact("tracy"));
    }
    const run_labos_bottleneck_trace = b.addRunArtifact(labos_bottleneck_trace_exe);
    if (b.args) |args| run_labos_bottleneck_trace.addArgs(args);
    const labos_bottleneck_trace_step = b.step(
        "labos-bottleneck-trace",
        "Run the trace-enabled O2A LABOS bottleneck research harness",
    );
    labos_bottleneck_trace_step.dependOn(&run_labos_bottleneck_trace.step);
    const run_o2a_jacobian_trace = b.addRunArtifact(labos_bottleneck_trace_exe);
    run_o2a_jacobian_trace.addArg("--derivative-sweep");
    if (b.args) |args| run_o2a_jacobian_trace.addArgs(args);
    const o2a_jacobian_trace_step = b.step(
        "o2a-jacobian-trace",
        "Run the trace-enabled O2A forward/Jacobian derivative sweep",
    );
    o2a_jacobian_trace_step.dependOn(&run_o2a_jacobian_trace.step);
    const labos_bottleneck_trace_install = b.addInstallArtifact(labos_bottleneck_trace_exe, .{});
    const labos_bottleneck_trace_bin_step = b.step(
        "labos-bottleneck-trace-bin",
        "Build the trace-enabled LABOS bottleneck executable for disassembly",
    );
    labos_bottleneck_trace_bin_step.dependOn(&labos_bottleneck_trace_install.step);

    const fmt_check_cmd = b.addFmt(.{
        .check = true,
        .paths = &.{ "build.zig", "src", "tests", "scripts" },
    });
    const fmt_check_step = b.step("fmt-check", "Verify Zig formatting without rewriting files");
    fmt_check_step.dependOn(&fmt_check_cmd.step);

    const o2a_plot_bundle_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/spectra/plot_validation.py",
    });
    o2a_plot_bundle_cmd.step.dependOn(&c_api_install.step);
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
        "validation/spectra/plot_validation_test.py",
    });
    o2a_plot_bundle_test_cmd.step.dependOn(&c_api_install.step);
    const o2a_plot_bundle_test_step = b.step(
        "test-validation-o2a-plot-bundle",
        "Run the O2A plot bundle harness smoke test",
    );
    o2a_plot_bundle_test_step.dependOn(&o2a_plot_bundle_test_cmd.step);

    const o2a_optimal_estimation_validation_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/optimal_estimation/validate_optimal_estimation.py",
    });
    o2a_optimal_estimation_validation_cmd.step.dependOn(&c_api_install.step);
    const o2a_optimal_estimation_validation_step = b.step(
        "test-validation-o2a-optimal-estimation",
        "Run the DISAMAR reference two-state O2A optimal-estimation validation fixture",
    );
    o2a_optimal_estimation_validation_step.dependOn(&o2a_optimal_estimation_validation_cmd.step);

    const o2a_optimal_estimation_sweep_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/optimal_estimation/sweep_optimal_estimation.py",
    });
    o2a_optimal_estimation_sweep_cmd.step.dependOn(&c_api_install.step);
    const o2a_optimal_estimation_sweep_step = b.step(
        "validation-o2a-optimal-estimation-sweep",
        "Run the aerosol-only O2A optimal-estimation scene sweep",
    );
    o2a_optimal_estimation_sweep_step.dependOn(&o2a_optimal_estimation_sweep_cmd.step);

    const o2a_slow_forward_jacobian_benchmark_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "validation/optimal_estimation/benchmark_slow_forward_jacobian.py",
    });
    o2a_slow_forward_jacobian_benchmark_cmd.step.dependOn(&c_api_install.step);
    const o2a_slow_forward_jacobian_benchmark_step = b.step(
        "validation-o2a-slow-forward-jacobian-benchmark",
        "Run the retained slow O2A optimal-estimation forward+jacobian latency benchmark",
    );
    o2a_slow_forward_jacobian_benchmark_step.dependOn(
        &o2a_slow_forward_jacobian_benchmark_cmd.step,
    );

    const python_o2a_setup_roundtrip_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "python",
        "tests/python/o2a_setup_roundtrip_test.py",
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
    check_step.dependOn(&unit_tests.step);
    check_step.dependOn(&internal_tests.step);
    check_step.dependOn(validation_o2a.compile_step);
    check_step.dependOn(validation_o2a_vendor.compile_step);
    check_step.dependOn(validation_o2a_vendor_line_list.compile_step);
    check_step.dependOn(&run_unit_tests.step);
    check_step.dependOn(&run_internal_tests.step);

    const test_fast_step = b.step("test-fast", "Run the fast O2A verification suites");
    test_fast_step.dependOn(&run_unit_tests.step);
    test_fast_step.dependOn(&run_internal_tests.step);
    test_fast_step.dependOn(validation_o2a.compile_step);
    test_fast_step.dependOn(validation_o2a_vendor_line_list.run_step);
    test_fast_step.dependOn(o2a_optimal_estimation_validation_step);

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
    test_step.dependOn(o2a_plot_bundle_test_step);
    test_step.dependOn(o2a_optimal_estimation_validation_step);
}
