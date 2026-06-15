const std = @import("std");

const InstrumentationModules = struct {
    build_options: *std.Build.Module,
    ztracy: *std.Build.Module,
    calculation_telemetry_sink: *std.Build.Module,
    perturbation_sensitivity_sink: *std.Build.Module,
};

fn addBuildOptions(
    b: *std.Build,
    enable_ztracy: bool,
    enable_cost_timing: bool,
    enable_calculation_telemetry: bool,
    enable_perturbation_sensitivity: bool,
) *std.Build.Module {
    // addBuildOptions -------------------------------------------------------------------------------------- |
    // Build the compile-time instrumentation option module shared by product and test roots.                 |
    // -------------------------------------------------------------------------------------------------------|
    const options = b.addOptions();
    options.addOption(bool, "enable_test_support", false);
    options.addOption(bool, "enable_ztracy", enable_ztracy);
    options.addOption(bool, "enable_cost_timing", enable_cost_timing);
    options.addOption(bool, "enable_calculation_telemetry", enable_calculation_telemetry);
    options.addOption(bool, "enable_perturbation_sensitivity", enable_perturbation_sensitivity);
    return options.createModule();
}

fn addSourceModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    instrumentation: InstrumentationModules,
    root_source_file: []const u8,
) *std.Build.Module {
    // addSourceModule -------------------------------------------------------------------------------------- |
    // Create a source module with the instrumentation facades wired to the requested root.                   |
    // -------------------------------------------------------------------------------------------------------|
    return b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = instrumentation.build_options },
            .{ .name = "ztracy", .module = instrumentation.ztracy },
            .{ .name = "calculation_telemetry_sink", .module = instrumentation.calculation_telemetry_sink },
            .{ .name = "perturbation_sensitivity_sink", .module = instrumentation.perturbation_sensitivity_sink },
        },
    });
}

fn addTestStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    internal_module: *std.Build.Module,
    instrumentation: InstrumentationModules,
    step_name: []const u8,
    step_description: []const u8,
    root_source_file: []const u8,
) *std.Build.Step.Run {
    // addTestStep ------------------------------------------------------------------------------------------ |
    // Register one Zig test root as a named build step using the shared internal module.                     |
    // -------------------------------------------------------------------------------------------------------|
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_source_file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "internal", .module = internal_module },
                .{ .name = "build_options", .module = instrumentation.build_options },
                .{ .name = "ztracy", .module = instrumentation.ztracy },
                .{ .name = "calculation_telemetry_sink", .module = instrumentation.calculation_telemetry_sink },
                .{ .name = "perturbation_sensitivity_sink", .module = instrumentation.perturbation_sensitivity_sink },
            },
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    b.step(step_name, step_description).dependOn(&run_tests.step);
    return run_tests;
}

fn addTraceExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    internal_module: *std.Build.Module,
    name: []const u8,
    root_source_file: []const u8,
) *std.Build.Step.Compile {
    // addTraceExecutable ----------------------------------------------------------------------------------- |
    // Register a retained instrumentation CLI against the instrumentation-enabled internal module.           |
    // -------------------------------------------------------------------------------------------------------|
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_source_file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "internal", .module = internal_module },
            },
        }),
    });
}

pub fn build(b: *std.Build) void {
    // build ------------------------------------------------------------------------------------------------ |
    // Define the explicit-dataflow library, unit-test roots, focused RTM gates, and fast local checks.       |
    // -------------------------------------------------------------------------------------------------------|
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fast_test_optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const enable_ztracy = b.option(
        bool,
        "enable-ztracy",
        "Enable ztracy zones in retained trace harnesses",
    ) orelse false;

    const disabled_instrumentation = InstrumentationModules{
        .build_options = addBuildOptions(b, false, false, false, false),
        .ztracy = b.createModule(.{
            .root_source_file = b.path("src/instrumentation/stubs/ztracy.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .calculation_telemetry_sink = b.createModule(.{
            .root_source_file = b.path("src/instrumentation/stubs/calculation_telemetry_sink.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .perturbation_sensitivity_sink = b.createModule(.{
            .root_source_file = b.path("src/instrumentation/stubs/perturbation_sensitivity_sink.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };

    const enabled_instrumentation = InstrumentationModules{
        .build_options = addBuildOptions(b, false, true, true, true),
        .ztracy = disabled_instrumentation.ztracy,
        .calculation_telemetry_sink = disabled_instrumentation.calculation_telemetry_sink,
        .perturbation_sensitivity_sink = disabled_instrumentation.perturbation_sensitivity_sink,
    };

    const ztracy_dependency = resolve_ztracy_dependency: {
        if (!enable_ztracy) break :resolve_ztracy_dependency null;

        break :resolve_ztracy_dependency b.dependency("ztracy", .{
            .target = target,
            .optimize = optimize,
            .enable_ztracy = true,
        });
    };

    const trace_ztracy_module = resolve_trace_ztracy_module: {
        if (ztracy_dependency) |dependency| {
            break :resolve_trace_ztracy_module dependency.module("root");
        }

        break :resolve_trace_ztracy_module disabled_instrumentation.ztracy;
    };

    const trace_instrumentation = InstrumentationModules{
        .build_options = addBuildOptions(b, enable_ztracy, false, false, false),
        .ztracy = trace_ztracy_module,
        .calculation_telemetry_sink = disabled_instrumentation.calculation_telemetry_sink,
        .perturbation_sensitivity_sink = disabled_instrumentation.perturbation_sensitivity_sink,
    };

    const lib_module = addSourceModule(b, target, optimize, disabled_instrumentation, "src/root.zig");
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zdisamar",
        .root_module = lib_module,
    });
    b.installArtifact(lib);

    const c_api_module = b.createModule(.{
        .root_source_file = b.path("src/api/c.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zdisamar", .module = lib_module },
            .{ .name = "build_options", .module = disabled_instrumentation.build_options },
            .{ .name = "ztracy", .module = disabled_instrumentation.ztracy },
            .{ .name = "calculation_telemetry_sink", .module = disabled_instrumentation.calculation_telemetry_sink },
            .{
                .name = "perturbation_sensitivity_sink",
                .module = disabled_instrumentation.perturbation_sensitivity_sink,
            },
        },
    });
    c_api_module.link_libc = true;
    const c_api_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zdisamar_c",
        .root_module = c_api_module,
    });
    b.installArtifact(c_api_lib);

    const fast_lib_module = addSourceModule(
        b,
        target,
        fast_test_optimize,
        disabled_instrumentation,
        "src/root.zig",
    );
    const fast_c_api_module = b.createModule(.{
        .root_source_file = b.path("src/api/c.zig"),
        .target = target,
        .optimize = fast_test_optimize,
        .imports = &.{
            .{ .name = "zdisamar", .module = fast_lib_module },
            .{ .name = "build_options", .module = disabled_instrumentation.build_options },
            .{ .name = "ztracy", .module = disabled_instrumentation.ztracy },
            .{ .name = "calculation_telemetry_sink", .module = disabled_instrumentation.calculation_telemetry_sink },
            .{
                .name = "perturbation_sensitivity_sink",
                .module = disabled_instrumentation.perturbation_sensitivity_sink,
            },
        },
    });
    fast_c_api_module.link_libc = true;

    const internal_module = addSourceModule(b, target, optimize, disabled_instrumentation, "src/internal.zig");
    const enabled_internal_module = addSourceModule(
        b,
        target,
        optimize,
        enabled_instrumentation,
        "src/internal.zig",
    );
    const trace_internal_module = addSourceModule(
        b,
        target,
        optimize,
        trace_instrumentation,
        "src/internal.zig",
    );

    const run_unit_tests = addTestStep(
        b,
        target,
        optimize,
        internal_module,
        disabled_instrumentation,
        "test-unit",
        "Run explicit-dataflow unit and parity tests",
        "tests/unit/root.zig",
    );
    const run_rtm_tests = addTestStep(
        b,
        target,
        optimize,
        internal_module,
        disabled_instrumentation,
        "test-rtm",
        "Run focused RTM tests",
        "tests/unit/rtm_root.zig",
    );
    const run_enabled_instrumentation_tests = addTestStep(
        b,
        target,
        optimize,
        enabled_internal_module,
        enabled_instrumentation,
        "test-instrumentation-enabled",
        "Compile instrumentation facades with enabled build options",
        "tests/unit/instrumentation/enabled_facades_test.zig",
    );
    const c_api_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/api/c_abi_test.zig"),
            .target = target,
            .optimize = fast_test_optimize,
            .imports = &.{
                .{ .name = "c_api", .module = fast_c_api_module },
                .{ .name = "build_options", .module = disabled_instrumentation.build_options },
                .{ .name = "ztracy", .module = disabled_instrumentation.ztracy },
                .{
                    .name = "calculation_telemetry_sink",
                    .module = disabled_instrumentation.calculation_telemetry_sink,
                },
                .{
                    .name = "perturbation_sensitivity_sink",
                    .module = disabled_instrumentation.perturbation_sensitivity_sink,
                },
            },
        }),
    });
    const run_c_api_tests = b.addRunArtifact(c_api_tests);
    b.step("test-api-c", "Run fast C ABI boundary tests").dependOn(&run_c_api_tests.step);

    const c_api_retained_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/api/c_abi_retained_test.zig"),
            .target = target,
            .optimize = fast_test_optimize,
            .imports = &.{
                .{ .name = "c_api", .module = fast_c_api_module },
                .{ .name = "build_options", .module = disabled_instrumentation.build_options },
                .{ .name = "ztracy", .module = disabled_instrumentation.ztracy },
                .{
                    .name = "calculation_telemetry_sink",
                    .module = disabled_instrumentation.calculation_telemetry_sink,
                },
                .{
                    .name = "perturbation_sensitivity_sink",
                    .module = disabled_instrumentation.perturbation_sensitivity_sink,
                },
            },
        }),
    });
    const run_c_api_retained_tests = b.addRunArtifact(c_api_retained_tests);
    b.step(
        "test-api-c-retained",
        "Run retained C ABI tests with the default O2 A product case",
    ).dependOn(&run_c_api_retained_tests.step);

    const cost_timing_o2a_scene_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/support/o2a_scene.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "internal", .module = enabled_internal_module },
        },
    });
    const cost_timing_analysis = b.addExecutable(.{
        .name = "cost-timing-forward-analysis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scaffolding/instrumentation/cost_timing/zig/cost_timing_forward_analysis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "internal", .module = enabled_internal_module },
                .{ .name = "o2a_scene", .module = cost_timing_o2a_scene_module },
            },
        }),
    });
    const run_cost_timing_analysis = b.addRunArtifact(cost_timing_analysis);
    b.step(
        "cost-timing-forward-analysis",
        "Run one enabled O2 A forward analysis and emit merged cost timing",
    ).dependOn(&run_cost_timing_analysis.step);
    const run_cost_timing_fast_analysis = b.addSystemCommand(&.{
        "uv",
        "run",
        "python",
        "scaffolding/instrumentation/cost_timing/analysis/run_cost_timing_fast_analysis.py",
    });
    run_cost_timing_fast_analysis.addArtifactArg(cost_timing_analysis);
    b.step(
        "cost-timing-fast-analysis",
        "Run fast cost-timing analysis gate for one enabled O2 A forward",
    ).dependOn(&run_cost_timing_fast_analysis.step);
    const labos_bottleneck_trace = addTraceExecutable(
        b,
        target,
        optimize,
        trace_internal_module,
        "labos-bottleneck-trace",
        "scaffolding/instrumentation/trace/zig/labos_bottleneck_trace_cli.zig",
    );
    if (ztracy_dependency) |dependency| {
        const tracy = dependency.artifact("tracy");
        labos_bottleneck_trace.root_module.linkLibrary(tracy);
    }
    const install_labos_bottleneck_trace = b.addInstallArtifact(labos_bottleneck_trace, .{});
    b.step(
        "labos-bottleneck-trace-bin",
        "Build retained LABOS bottleneck trace harness",
    ).dependOn(&install_labos_bottleneck_trace.step);
    const run_labos_bottleneck_trace = b.addRunArtifact(labos_bottleneck_trace);
    if (b.args) |args| run_labos_bottleneck_trace.addArgs(args);
    b.step(
        "labos-bottleneck-trace",
        "Run retained LABOS bottleneck trace harness",
    ).dependOn(&run_labos_bottleneck_trace.step);

    const no_inline_src_tests_cmd = b.addSystemCommand(&.{"scripts/check-no-inline-src-tests.sh"});
    const fmt_check_cmd = b.addFmt(.{
        .check = true,
        .paths = &.{ "build.zig", "src", "tests" },
    });

    const sync_python_package_cmd = b.addSystemCommand(&.{
        "uv",
        "run",
        "--no-project",
        "python",
        "scripts/sync-python-package.py",
        "--binding",
    });
    sync_python_package_cmd.addArtifactArg(c_api_lib);
    const sync_python_package_step = b.step(
        "sync-python-package",
        "Build and sync native C API and reference data into the Python package",
    );
    sync_python_package_step.dependOn(&sync_python_package_cmd.step);

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(&fmt_check_cmd.step);
    check_step.dependOn(&no_inline_src_tests_cmd.step);
    check_step.dependOn(&lib.step);
    check_step.dependOn(&run_c_api_tests.step);
    check_step.dependOn(&run_enabled_instrumentation_tests.step);

    const test_fast_step = b.step("test-fast", "Run fast explicit-dataflow test suite");
    test_fast_step.dependOn(&run_c_api_tests.step);
    test_fast_step.dependOn(&run_rtm_tests.step);
    test_fast_step.dependOn(&run_enabled_instrumentation_tests.step);

    const test_retained_step = b.step(
        "test-retained",
        "Run retained explicit-dataflow suite, including full default O2 A/OE coverage",
    );
    test_retained_step.dependOn(test_fast_step);
    test_retained_step.dependOn(&run_unit_tests.step);
    test_retained_step.dependOn(&run_c_api_retained_tests.step);

    const test_step = b.step("test", "Run retained explicit-dataflow test suite");
    test_step.dependOn(test_retained_step);
}
