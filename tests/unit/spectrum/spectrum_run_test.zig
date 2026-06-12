const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

const controls = internal.transport.controls;
const jacobian_states = internal.transport.jacobian_states;
const radiance_results = internal.spectrum.radiance_results;
const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const readers = internal.assets.readers;
const sampling_table = internal.spectrum.sampling_table;
const solar_table = internal.setup.solar_table;
const spectrum_run = internal.spectrum.spectrum_run;

const ExpectedWorkerPrimitiveLayout = struct {
    chunk_queue_size: usize,
    error_state_size: usize,
};

const expected_worker_primitive_layout: ExpectedWorkerPrimitiveLayout = if (builtin.mode == .Debug)
    .{ .chunk_queue_size = 40, .error_state_size = 24 }
else
    .{ .chunk_queue_size = 32, .error_state_size = 8 };

test "ChunkQueue returns contiguous chunks and drains once" {
    var queue = spectrum_run.ChunkQueue.init(10, 4);

    try std.testing.expectEqual(spectrum_run.Range{ .start = 0, .end = 4 }, queue.next().?);
    try std.testing.expectEqual(spectrum_run.Range{ .start = 4, .end = 8 }, queue.next().?);
    try std.testing.expectEqual(spectrum_run.Range{ .start = 8, .end = 10 }, queue.next().?);
    try std.testing.expectEqual(@as(?spectrum_run.Range, null), queue.next());
}

test "static worker ranges cover evidence radiance work without overlap" {
    const item_count: usize = 3874;
    const worker_count: usize = 10;
    var expected_start: usize = 0;
    var min_count: usize = std.math.maxInt(usize);
    var max_count: usize = 0;

    for (0..worker_count) |worker_index| {
        const range = spectrum_run.staticRange(item_count, worker_count, worker_index);
        try std.testing.expectEqual(expected_start, range.start);
        try std.testing.expect(range.end >= range.start);
        const count = range.len();
        min_count = @min(min_count, count);
        max_count = @max(max_count, count);
        expected_start = range.end;
    }

    try std.testing.expectEqual(item_count, expected_start);
    try std.testing.expect(max_count - min_count <= 1);
}

test "nextStaticChunk drains a static worker range in old radiance-prefetch chunks" {
    var start: usize = 3;
    const end: usize = 22;

    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 3, .end = 11 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 11, .end = 19 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(
        spectrum_run.Range{ .start = 19, .end = 22 },
        spectrum_run.nextStaticChunk(&start, end).?,
    );
    try std.testing.expectEqual(@as(?spectrum_run.Range, null), spectrum_run.nextStaticChunk(&start, end));
}

test "preferred radiance worker count keeps small batches single-threaded" {
    try std.testing.expectEqual(
        @as(usize, 1),
        spectrum_run.preferredRadianceWorkerCount(spectrum_run.min_parallel_radiance_count - 1),
    );
}

test "preferred worker count honors explicit worker limits and available work" {
    try std.testing.expectEqual(
        @as(usize, 2),
        spectrum_run.preferredWorkerCountForCpuCount(1024, 32, 12, 2),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        spectrum_run.preferredWorkerCountForCpuCount(128, 32, 12, null),
    );
    try std.testing.expectEqual(
        @as(usize, spectrum_run.max_workers),
        spectrum_run.preferredWorkerCountForCpuCount(
            spectrum_run.max_workers * 128,
            1,
            spectrum_run.max_workers * 2,
            null,
        ),
    );
}

test "FirstWorkerErrorState stores only the first worker failure" {
    const ErrorState = spectrum_run.FirstWorkerErrorState(error{
        FirstFailure,
        LaterFailure,
    });
    var state = ErrorState{};

    state.store(error.FirstFailure);
    state.store(error.LaterFailure);

    try std.testing.expectEqual(error.FirstFailure, state.err.?);
}

test "prefetchRadianceRowsSingleWorker fills dense rows in exact wavelength order" {
    var wavelengths = [_]radiance_wavelengths.RadianceWavelength{
        .{ .key = radiance_wavelengths.keyFor(758.0), .wavelength_nm = 758.0 },
        .{ .key = radiance_wavelengths.keyFor(760.0), .wavelength_nm = 760.0 },
        .{ .key = radiance_wavelengths.keyFor(765.0), .wavelength_nm = 765.0 },
    };
    var results: [3]radiance_results.RadianceResult = undefined;
    var memory = internal.cache.transport_worker_memory.TransportWorkerMemory{};
    var context = TestRadianceComputeContext{};

    try spectrum_run.prefetchRadianceRowsSingleWorker(
        TestRadianceComputeContext,
        TestRadianceComputeError,
        .{ .wavelengths = &wavelengths },
        &results,
        &memory,
        &context,
        testRadianceCompute,
    );

    try std.testing.expectEqual(@as(usize, 3), context.call_count);
    try std.testing.expectEqual(@as(usize, 0), context.worker_index_sum);
    try std.testing.expect(context.memory_seen == &memory);
    try std.testing.expectApproxEqAbs(758.0, context.seen_wavelengths[0], 0.0);
    try std.testing.expectApproxEqAbs(760.0, context.seen_wavelengths[1], 0.0);
    try std.testing.expectApproxEqAbs(765.0, context.seen_wavelengths[2], 0.0);
    try std.testing.expectApproxEqAbs(7.58, results[0].radiance, 1.0e-15);
    try std.testing.expectApproxEqAbs(7.60, results[1].radiance, 1.0e-15);
    try std.testing.expectApproxEqAbs(7.65, results[2].radiance, 1.0e-15);
    try std.testing.expectEqual([3]f64{ 760.0, 0.0, 1.0 }, results[1].jacobian);
}

test "prefetchRadianceRowsSingleWorker checks result shape and propagates compute errors" {
    var wavelengths = [_]radiance_wavelengths.RadianceWavelength{
        .{ .key = radiance_wavelengths.keyFor(758.0), .wavelength_nm = 758.0 },
        .{ .key = radiance_wavelengths.keyFor(760.0), .wavelength_nm = 760.0 },
    };
    var short_results: [1]radiance_results.RadianceResult = undefined;
    var results: [2]radiance_results.RadianceResult = undefined;
    var memory = internal.cache.transport_worker_memory.TransportWorkerMemory{};
    var context = TestRadianceComputeContext{ .fail_at_call = 1 };

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.prefetchRadianceRowsSingleWorker(
            TestRadianceComputeContext,
            TestRadianceComputeError,
            .{ .wavelengths = &wavelengths },
            &short_results,
            &memory,
            &context,
            testRadianceCompute,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), context.call_count);

    try std.testing.expectError(
        error.InjectedFailure,
        spectrum_run.prefetchRadianceRowsSingleWorker(
            TestRadianceComputeContext,
            TestRadianceComputeError,
            .{ .wavelengths = &wavelengths },
            &results,
            &memory,
            &context,
            testRadianceCompute,
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), context.call_count);
}

test "gatherProductRows gathers radiance irradiance and active Jacobian lanes" {
    var rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
        .{
            .nominal_wavelength_nm = 761.0,
            .radiance_wavelength_nm = 761.0,
            .irradiance_wavelength_nm = 761.0,
            .radiance_integration = .{
                .side_start = 0,
                .sample_count = 2,
                .encoding = .side_samples,
            },
            .irradiance_integration = .{
                .side_start = 0,
                .sample_count = 2,
                .encoding = .side_samples,
            },
        },
    };
    const offsets = [_]f64{ -1.0, 1.0 };
    const weights = [_]f64{ 0.25, 0.75 };
    const table = sampling_table.SpectrumSamplingTable{
        .rows = &rows,
        .kernel_storage = .{
            .offsets_nm = offsets[0..],
            .weights = weights[0..],
        },
    };
    const sample_indices = [_]u32{ 1, 0, 2 };
    var row_refs = [_]radiance_wavelengths.RadianceSampleIndexRef{
        .{ .start = 0 },
        .{ .start = 1 },
    };
    var dense = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 10.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 20.0, 200.0 } },
        .{ .radiance = 30.0, .jacobian = .{ 3.0, 30.0, 300.0 } },
    };
    var solar_rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = 759.0, .irradiance = 100.0 },
        .{ .wavelength_nm = 760.0, .irradiance = 200.0 },
        .{ .wavelength_nm = 761.0, .irradiance = 300.0 },
        .{ .wavelength_nm = 762.0, .irradiance = 500.0 },
    };
    const solar = solar_table.SolarTable{
        .rows = solar_rows[0..],
        .spline_second_derivatives = &.{},
    };
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer solar_memory.deinit();

    var out_wavelengths: [2]f64 = undefined;
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    try spectrum_run.gatherProductRows(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = jacobian_states.stateMask(.surface_albedo) |
                jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        },
        table,
        .{
            .rows = row_refs[0..],
            .sample_indices = sample_indices[0..],
            .wavelengths = &.{},
        },
        dense[0..],
        solar,
        &solar_memory,
        out_wavelengths[0..],
        out_radiance[0..],
        out_irradiance[0..],
    );

    try std.testing.expectApproxEqAbs(760.0, out_wavelengths[0], 0.0);
    try std.testing.expectApproxEqAbs(761.0, out_wavelengths[1], 0.0);
    try std.testing.expectApproxEqAbs(20.0, out_radiance[0].radiance, 0.0);
    try std.testing.expectEqual([3]f64{ 2.0, 20.0, 200.0 }, out_radiance[0].jacobian);
    try std.testing.expectApproxEqAbs(25.0, out_radiance[1].radiance, 0.0);
    try std.testing.expectApproxEqAbs(2.5, out_radiance[1].jacobian[0], 0.0);
    try std.testing.expectApproxEqAbs(0.0, out_radiance[1].jacobian[1], 0.0);
    try std.testing.expectApproxEqAbs(250.0, out_radiance[1].jacobian[2], 0.0);
    try std.testing.expectApproxEqAbs(200.0, out_irradiance[0], 0.0);
    try std.testing.expectApproxEqAbs(425.0, out_irradiance[1], 0.0);
    try std.testing.expectEqual(@as(u32, 2), solar_memory.values.count());
}

test "gatherProductRows resets stale solar memory and rejects malformed shapes" {
    var rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
    };
    const table = sampling_table.SpectrumSamplingTable{ .rows = &rows };
    const sample_indices = [_]u32{0};
    var row_refs = [_]radiance_wavelengths.RadianceSampleIndexRef{.{ .start = 0 }};
    var dense = [_]radiance_results.RadianceResult{.{ .radiance = 3.0 }};
    var solar_rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = 760.0, .irradiance = 22.0 },
    };
    const solar = solar_table.SolarTable{
        .rows = solar_rows[0..],
        .spline_second_derivatives = &.{},
    };
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer solar_memory.deinit();
    try solar_memory.put(760.0, 999.0);

    var out_wavelengths: [1]f64 = undefined;
    var out_radiance: [1]radiance_results.RadianceResult = undefined;
    var out_irradiance: [1]f64 = undefined;
    try spectrum_run.gatherProductRows(
        .{},
        table,
        .{
            .rows = row_refs[0..],
            .sample_indices = sample_indices[0..],
            .wavelengths = &.{},
        },
        dense[0..],
        solar,
        &solar_memory,
        out_wavelengths[0..],
        out_radiance[0..],
        out_irradiance[0..],
    );

    try std.testing.expectApproxEqAbs(22.0, out_irradiance[0], 0.0);
    try std.testing.expectEqual(@as(u32, 1), solar_memory.values.count());

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.gatherProductRows(
            .{},
            table,
            .{
                .rows = &.{},
                .sample_indices = sample_indices[0..],
                .wavelengths = &.{},
            },
            dense[0..],
            solar,
            &solar_memory,
            out_wavelengths[0..],
            out_radiance[0..],
            out_irradiance[0..],
        ),
    );
}

test "postprocessAndAssembleProductRows carries integrated radiance irradiance and Jacobians" {
    const solve_config: controls.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.surface_albedo) |
            jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
    };
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 10.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 20.0, 200.0 } },
    };
    const raw_irradiance = [_]f64{ 100.0, 200.0 };
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    var out_reflectance: [2]f64 = undefined;
    var out_jacobian: [2]jacobian_states.Vector = undefined;

    const summary = try spectrum_run.postprocessAndAssembleProductRows(
        solve_config,
        true,
        true,
        .{ .gain = 2.0, .offset = 1.0 },
        .{ .gain = 0.5, .offset = 2.0 },
        &.{},
        &.{},
        0.25,
        raw_radiance[0..],
        raw_irradiance[0..],
        out_radiance[0..],
        out_irradiance[0..],
        out_reflectance[0..],
        out_jacobian[0..],
    );

    const row0_scale = std.math.pi / (52.0 * 0.25);
    const row1_scale = std.math.pi / (102.0 * 0.25);
    try std.testing.expectApproxEqAbs(21.0, out_radiance[0].radiance, 0.0);
    try std.testing.expectEqual([3]f64{ 2.0, 0.0, 200.0 }, out_radiance[0].jacobian);
    try std.testing.expectApproxEqAbs(41.0, out_radiance[1].radiance, 0.0);
    try std.testing.expectEqual([3]f64{ 4.0, 0.0, 400.0 }, out_radiance[1].jacobian);
    try std.testing.expectEqual([2]f64{ 52.0, 102.0 }, out_irradiance);
    try std.testing.expectApproxEqAbs(21.0 * row0_scale, out_reflectance[0], 1.0e-14);
    try std.testing.expectApproxEqAbs(41.0 * row1_scale, out_reflectance[1], 1.0e-14);
    try std.testing.expectApproxEqAbs(2.0 * row0_scale, out_jacobian[0][0], 1.0e-14);
    try std.testing.expectApproxEqAbs(0.0, out_jacobian[0][1], 0.0);
    try std.testing.expectApproxEqAbs(200.0 * row0_scale, out_jacobian[0][2], 1.0e-14);
    try std.testing.expectApproxEqAbs(4.0 * row1_scale, out_jacobian[1][0], 1.0e-14);
    try std.testing.expectApproxEqAbs(0.0, out_jacobian[1][1], 0.0);
    try std.testing.expectApproxEqAbs(400.0 * row1_scale, out_jacobian[1][2], 1.0e-14);
    try std.testing.expectEqual(@as(usize, 2), summary.sample_count);
    try std.testing.expectApproxEqAbs(out_reflectance[0] + out_reflectance[1], summary.reflectance_sum, 1.0e-14);
}

test "postprocessAndAssembleProductRows convolves non-integrated product rows" {
    const solve_config: controls.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
    };
    const kernel = [_]f64{ 1.0, 1.0, 1.0 };
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 10.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 20.0, 200.0 } },
        .{ .radiance = 40.0, .jacobian = .{ 4.0, 40.0, 400.0 } },
    };
    const raw_irradiance = [_]f64{ 100.0, 200.0, 300.0 };
    var out_radiance: [3]radiance_results.RadianceResult = undefined;
    var out_irradiance: [3]f64 = undefined;
    var out_reflectance: [3]f64 = undefined;
    var out_jacobian: [3]jacobian_states.Vector = undefined;

    const summary = try spectrum_run.postprocessAndAssembleProductRows(
        solve_config,
        false,
        false,
        .{},
        .{},
        kernel[0..],
        kernel[0..],
        0.5,
        raw_radiance[0..],
        raw_irradiance[0..],
        out_radiance[0..],
        out_irradiance[0..],
        out_reflectance[0..],
        out_jacobian[0..],
    );

    const expected_radiance = [_]f64{ 15.0, 70.0 / 3.0, 30.0 };
    const expected_irradiance = [_]f64{ 150.0, 200.0, 250.0 };
    const expected_jacobian = [_]f64{ 1.5, 7.0 / 3.0, 3.0 };
    for (expected_radiance, expected_irradiance, expected_jacobian, 0..) |radiance, irradiance, jacobian, index| {
        const scale = std.math.pi / (irradiance * 0.5);
        try std.testing.expectApproxEqAbs(radiance, out_radiance[index].radiance, 1.0e-14);
        try std.testing.expectApproxEqAbs(jacobian, out_radiance[index].jacobian[0], 1.0e-14);
        try std.testing.expectApproxEqAbs(0.0, out_radiance[index].jacobian[1], 0.0);
        try std.testing.expectApproxEqAbs(0.0, out_radiance[index].jacobian[2], 0.0);
        try std.testing.expectApproxEqAbs(irradiance, out_irradiance[index], 1.0e-14);
        try std.testing.expectApproxEqAbs(radiance * scale, out_reflectance[index], 1.0e-14);
        try std.testing.expectApproxEqAbs(jacobian * scale, out_jacobian[index][0], 1.0e-14);
        try std.testing.expectApproxEqAbs(0.0, out_jacobian[index][1], 0.0);
        try std.testing.expectApproxEqAbs(0.0, out_jacobian[index][2], 0.0);
    }
    try std.testing.expectEqual(@as(usize, 3), summary.sample_count);
    try std.testing.expectApproxEqAbs(15.0 + 70.0 / 3.0 + 30.0, summary.radiance_sum, 1.0e-14);
}

test "postprocessAndAssembleProductRows rejects inconsistent product shapes" {
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0 },
        .{ .radiance = 20.0 },
    };
    const raw_irradiance = [_]f64{100.0};
    const full_raw_irradiance = [_]f64{ 100.0, 200.0 };
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    var out_reflectance: [2]f64 = undefined;
    var out_jacobian: [2]jacobian_states.Vector = undefined;

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.postprocessAndAssembleProductRows(
            .{},
            true,
            true,
            .{},
            .{},
            &.{},
            &.{},
            1.0,
            raw_radiance[0..],
            raw_irradiance[0..],
            out_radiance[0..],
            out_irradiance[0..],
            out_reflectance[0..],
            out_jacobian[0..],
        ),
    );

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.postprocessAndAssembleProductRows(
            .{
                .derivative_mode = .semi_analytical,
                .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
            },
            true,
            true,
            .{},
            .{},
            &.{},
            &.{},
            1.0,
            raw_radiance[0..],
            full_raw_irradiance[0..],
            out_radiance[0..],
            out_irradiance[0..],
            out_reflectance[0..],
            &.{},
        ),
    );
}

test "spectrum run worker primitives keep explicit layout" {
    const ErrorState = spectrum_run.FirstWorkerErrorState(error{WorkerFailed});

    try std.testing.expectEqual(@as(usize, 16), @sizeOf(spectrum_run.Range));
    try std.testing.expectEqual(expected_worker_primitive_layout.chunk_queue_size, @sizeOf(spectrum_run.ChunkQueue));
    try std.testing.expectEqual(expected_worker_primitive_layout.error_state_size, @sizeOf(ErrorState));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(spectrum_run.Range, "start"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(spectrum_run.Range, "end"));
}

const TestRadianceComputeError = error{
    InjectedFailure,
};

const TestRadianceComputeContext = struct {
    call_count: usize = 0,
    fail_at_call: ?usize = null,
    worker_index_sum: usize = 0,
    memory_seen: ?*internal.cache.transport_worker_memory.TransportWorkerMemory = null,
    seen_wavelengths: [8]f64 = [_]f64{0.0} ** 8,
};

fn testRadianceCompute(
    context: *TestRadianceComputeContext,
    wavelength_nm: f64,
    worker_index: usize,
    memory: *internal.cache.transport_worker_memory.TransportWorkerMemory,
) TestRadianceComputeError!radiance_results.RadianceResult {
    // testRadianceCompute ---------------------------------------------------------------------------------- |
    // Test-local deterministic dense-row calculator for spectrum-run prefetch coverage.                      |
    // -------------------------------------------------------------------------------------------------------|
    const call_index = context.call_count;
    context.call_count += 1;
    context.worker_index_sum += worker_index;
    context.memory_seen = memory;
    context.seen_wavelengths[call_index] = wavelength_nm;
    if (context.fail_at_call) |fail_at_call| {
        if (call_index == fail_at_call) return error.InjectedFailure;
    }

    return .{
        .radiance = wavelength_nm * 0.01,
        .jacobian = .{ wavelength_nm, @floatFromInt(worker_index), @floatFromInt(call_index) },
    };
}
