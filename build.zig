const std = @import("std");

const InstrumentationModules = struct {
    build_options: *std.Build.Module,
    ztracy: *std.Build.Module,
    calculation_telemetry_sink: *std.Build.Module,
    perturbation_sensitivity_sink: *std.Build.Module,
};

fn addBuildOptions(
    b: *std.Build,
    enable_trace_phase_timing: bool,
    enable_calculation_telemetry: bool,
    enable_perturbation_sensitivity: bool,
) *std.Build.Module {
    // addBuildOptions -------------------------------------------------------------------------------------- |
    // Build the compile-time instrumentation option module shared by product and test roots.                 |
    // -------------------------------------------------------------------------------------------------------|
    const options = b.addOptions();
    options.addOption(bool, "enable_test_support", false);
    options.addOption(bool, "enable_ztracy", false);
    options.addOption(bool, "enable_trace_phase_timing", enable_trace_phase_timing);
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

fn addReferenceDataSync(b: *std.Build, sync_files: *std.Build.Step.UpdateSourceFiles) void {
    // addReferenceDataSync --------------------------------------------------------------------------------- |
    // Copy package reference-data assets into the ignored source-checkout resource tree used by Python.      |
    // -------------------------------------------------------------------------------------------------------|
    var data_dir = std.fs.cwd().openDir("data/reference_data", .{ .iterate = true }) catch |err| {
        std.debug.panic("open data/reference_data: {s}", .{@errorName(err)});
    };
    defer data_dir.close();

    var walker = data_dir.walk(b.allocator) catch |err| {
        std.debug.panic("walk data/reference_data: {s}", .{@errorName(err)});
    };
    defer walker.deinit();

    while (walker.next() catch |err| {
        std.debug.panic("walk next data/reference_data: {s}", .{@errorName(err)});
    }) |entry| {
        if (entry.kind != .file) continue;

        sync_files.addCopyFileToSource(
            b.path(b.fmt("data/reference_data/{s}", .{entry.path})),
            b.fmt("python/zdisamar/reference_data/assets/{s}", .{entry.path}),
        );
    }
}

pub fn build(b: *std.Build) void {
    // build ------------------------------------------------------------------------------------------------ |
    // Define the explicit-dataflow library, unit-test roots, focused WP3 gates, and fast local checks.       |
    // -------------------------------------------------------------------------------------------------------|
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const disabled_instrumentation = InstrumentationModules{
        .build_options = addBuildOptions(b, false, false, false),
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
        .build_options = addBuildOptions(b, true, true, true),
        .ztracy = disabled_instrumentation.ztracy,
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
    const c_api_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zdisamar_c",
        .root_module = c_api_module,
    });
    b.installArtifact(c_api_lib);

    const internal_module = addSourceModule(b, target, optimize, disabled_instrumentation, "src/internal.zig");
    const enabled_internal_module = addSourceModule(
        b,
        target,
        optimize,
        enabled_instrumentation,
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
        "Run focused WP3 RTM tests",
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
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_api", .module = c_api_module },
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
    b.step("test-api-c", "Run focused C ABI tests").dependOn(&run_c_api_tests.step);

    const no_inline_src_tests_cmd = b.addSystemCommand(&.{"scripts/check-no-inline-src-tests.sh"});
    const fmt_check_cmd = b.addFmt(.{
        .check = true,
        .paths = &.{ "build.zig", "src", "tests" },
    });

    const sync_python_package_files = b.addUpdateSourceFiles();
    sync_python_package_files.addCopyFileToSource(
        c_api_lib.getEmittedBin(),
        b.fmt("python/zdisamar/bindings/{s}", .{c_api_lib.out_filename}),
    );
    addReferenceDataSync(b, sync_python_package_files);
    const sync_python_package_step = b.step(
        "sync-python-package",
        "Build and sync native C API and reference data into the Python package",
    );
    sync_python_package_step.dependOn(&sync_python_package_files.step);

    const check_step = b.step("check", "Run fast local verification");
    check_step.dependOn(&fmt_check_cmd.step);
    check_step.dependOn(&no_inline_src_tests_cmd.step);
    check_step.dependOn(&lib.step);
    check_step.dependOn(&c_api_lib.step);
    check_step.dependOn(&run_unit_tests.step);
    check_step.dependOn(&run_c_api_tests.step);
    check_step.dependOn(&run_enabled_instrumentation_tests.step);

    const test_fast_step = b.step("test-fast", "Run fast explicit-dataflow test suite");
    test_fast_step.dependOn(&run_unit_tests.step);
    test_fast_step.dependOn(&run_c_api_tests.step);
    test_fast_step.dependOn(&run_rtm_tests.step);
    test_fast_step.dependOn(&run_enabled_instrumentation_tests.step);

    const test_step = b.step("test", "Run retained explicit-dataflow test suite");
    test_step.dependOn(test_fast_step);
}
