const std = @import("std");
const builtin = @import("builtin");

const instrument_average = @import("instrument_average.zig");
const jacobian_states = @import("../transport/jacobian_states.zig");
const aerosol_tables = @import("../setup/aerosol_tables.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const cia_table = @import("../setup/cia_table.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const phase_table = @import("../setup/phase_table.zig");
const profile_line_memory = @import("../cache/profile_line_memory.zig");
const rayleigh = @import("../optics/rayleigh.zig");
const radiance_results = @import("radiance_results.zig");
const radiance_wavelengths = @import("radiance_wavelengths.zig");
const sampling_table = @import("sampling_table.zig");
const solve = @import("../transport/solve.zig");
const solar_lookup = @import("solar_lookup.zig");
const solar_irradiance_memory = @import("../cache/solar_irradiance_memory.zig");
const solar_table = @import("../setup/solar_table.zig");
const source_levels = @import("../optics/source_levels.zig");
const transport_worker_memory = @import("../cache/transport_worker_memory.zig");
const controls = @import("../transport/controls.zig");
const Trace = @import("../instrumentation/trace.zig");

pub const Error = error{
    ShapeMismatch,
};

// spectrum_run.zig -----------------------------------------------------------------------------------------   |
// Spectrum-level worker policy for high-resolution radiance prefetch.                                          |
//                                                                                                              |
// provenance                                                                                                   |
//   Ports the scheduling and first-error contracts from main:                                                  |
//   `src/forward_model/work_partition.zig`,                                                                    |
//   `src/forward_model/first_worker_error_state.zig`, and                                                      |
//   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`.                                 |
//                                                                                                              |
// boundary                                                                                                     |
//   This file owns only spectrum orchestration policy: worker ranges, chunk draining, worker-count limits,     |
//   and first worker error capture. It stores no scene, transport controls, optical properties, solar data,    |
//   or profile-line values. Later radiance prefetch code passes those physics inputs explicitly.               |
//                                                                                                              |
// route                                                                                                        |
//   SpectrumSamplingTable -> RadianceWavelengthList -> static radiance ranges or pooled chunks -> dense        |
//   RadianceResult rows -> nominal gather and instrument averaging.                                            |
//                                                                                                              |
// allocation                                                                                                   |
//   The helpers here allocate nothing. Thread owners and worker-local transport memory live at the call site.  |
// ------------------------------------------------------------------------------------------------------------ |

pub const max_workers: usize = 64;
pub const worker_limit_env = "ZDISAMAR_WORKER_LIMIT";
pub const min_parallel_radiance_count: usize = 32;
pub const radiance_prefetch_chunk_size: usize = 8;
pub const radiance_prefetch_pooled_chunk_size: usize = 8;

pub fn radianceAtWavelength(
    wavelength_nm: f64,
    wavelength_index: usize,
    angles: solve.ViewAngles,
    surface_albedo: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    profile_lines: profile_line_memory.ProfileLineValues,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    solar_irradiance: f64,
    solve_config: controls.SolveConfig,
    out_line_sigma_cm2_per_molecule: []f64,
    out_support: []layer_depths.SupportOptics,
    out_layers: []layer_depths.LayerOptics,
    out_source_levels: []source_levels.SourceLevel,
    out_curved_samples: []curved_sun_path.CurvedSunPathSample,
    out_curved_level_starts: []usize,
    out_curved_level_altitudes_km: []f64,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
) !radiance_results.RadianceResult {
    // radianceAtWavelength ---------------------------------------------------------------------------------   |
    // Execute one explicit high-resolution wavelength from setup rows through optics, transport, and           |
    // radiance scaling.                                                                                        |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the call shape of main:                                                                          |
    //   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`                              |
    //   `computeForwardSampleAtWavelengthWithScratch`, where one exact wavelength fills configured optical     |
    //   rows, runs LABOS transport, and scales reflectance into the prefetched radiance row.                   |
    //   Support line-sigma sampling follows main:`state_build/layer_spectroscopy.zig`.                         |
    //                                                                                                          |
    // memory                                                                                                   |
    //   All row and transport storage is caller-owned. Scattering callers must reserve worker memory before    |
    //   entering this per-wavelength helper through `TransportWorkerMemory.ensureCapacity`.                    |
    //                                                                                                          |
    // unsupported old routes                                                                                   |
    //   Source-level and curved-sun rows are only filled for controls that request those old routes. The       |
    //   current transport solver still rejects integrated-source and spherical-correction controls after       |
    //   their explicit rows are present.                                                                       |
    // -------------------------------------------------------------------------------------------------------- |
    const support_count = layer_grid.support_mid_altitudes_km.len;
    const layer_count = layer_grid.layer_pressures_hpa.len;
    if (out_support.len != support_count or
        out_line_sigma_cm2_per_molecule.len != support_count or
        out_layers.len != layer_count or
        out_source_levels.len != layer_count + 1 or
        out_curved_level_starts.len != layer_count + 1 or
        out_curved_level_altitudes_km.len != layer_count + 1)
    {
        return error.ShapeMismatch;
    }

    // instrumentation: trace zone: one exact-wavelength forward sample --------------------------------------  |
    // captures: setup-optics, optional source/curved rows, transport, and radiance scaling for one wavelength  |
    // why: separates solve-count effects from per-solve cost when WP4 compares same-sitting reruns.            |
    var sample_zone = Trace.staticZone(@src(), "spectrum.radiance_at_wavelength");
    defer sample_zone.end();
    Trace.plotU("forward_samples", 1);
    // end instrumentation: trace zone: one exact-wavelength forward sample ----------------------------------  |

    {

        // instrumentation: trace zone: configured optical rows ----------------------------------------------  |
        // captures: support optical-depth fill, layer reduction, and aerosol Jacobian row fill                 |
        // why: profiles spectroscopy-independent optical setup within each exact-wavelength solve.             |
        var optics_zone = Trace.staticZone(@src(), "spectrum.radiance_at_wavelength.optics");
        defer optics_zone.end();
        // end instrumentation: trace zone: configured optical rows ------------------------------------------  |

        try profile_lines.fillSupportLineSigmaAtWavelengthIndex(
            layer_grid,
            wavelength_index,
            out_line_sigma_cm2_per_molecule,
        );
        try layer_depths.fillSupportOpticsAtWavelength(
            wavelength_nm,
            layer_grid,
            out_line_sigma_cm2_per_molecule,
            cia,
            aerosol,
            out_support,
        );
        try layer_depths.reduceLayerOpticsFromSupportRows(layer_grid, out_support, out_layers);
        layer_depths.fillLayerAerosolJacobians(aerosol, solve_config.derivative_state_mask, out_layers);
    }

    const prepared_config = try controls.prepareSolveConfig(solve_config);
    const source_rows = source_rows: {
        if (prepared_config.controls.integrate_source_function) {
            try source_levels.fillSourceLevelsAtWavelength(
                wavelength_nm,
                layer_grid,
                out_support,
                out_layers,
                out_source_levels,
            );
            break :source_rows out_source_levels;
        }

        break :source_rows out_source_levels[0..0];
    };

    const curved_rows = curved_rows: {
        if (prepared_config.controls.use_spherical_correction) {
            const curved_count = try curved_sun_path.fillCurvedSunPathSamples(
                layer_grid,
                out_support,
                out_curved_samples,
                out_curved_level_starts,
                out_curved_level_altitudes_km,
            );
            break :curved_rows out_curved_samples[0..curved_count];
        }

        break :curved_rows out_curved_samples[0..0];
    };

    const reflectance = reflectance: {
        if (prepared_config.controls.scattering == .none) {
            break :reflectance solve.directSurfaceOnly(
                angles,
                surface_albedo,
                totalOpticalDepth(out_layers),
                prepared_config.derivative_mode,
                prepared_config.derivative_state_mask,
            );
        }

        const needs_order_local_sum =
            prepared_config.controls.integrate_source_function and
            prepared_config.derivative_mode != .none;
        var work = try worker_memory.solveWorkArrays(
            layer_count,
            prepared_config.controls.n_streams,
            needs_order_local_sum,
        );
        work.curved_level_starts = out_curved_level_starts;
        work.curved_level_altitudes_km = out_curved_level_altitudes_km;
        break :reflectance try solve.solveReflectance(
            angles,
            surface_albedo,
            out_layers,
            source_rows,
            curved_rows,
            phase,
            rayleigh.phaseCoefficient2(wavelength_nm),
            prepared_config,
            &work,
        );
    };

    return radiance_results.scaleReflectanceToRadiance(
        prepared_config,
        reflectance,
        angles.solar_mu,
        solar_irradiance,
    );
}

pub fn prefetchO2ARadianceRowsSingleWorker(
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    angles: solve.ViewAngles,
    surface_albedo: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    profile_lines: profile_line_memory.ProfileLineValues,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    solar: solar_table.SolarTable,
    solve_config: controls.SolveConfig,
    out_dense_radiance: []radiance_results.RadianceResult,
    out_line_sigma_cm2_per_molecule: []f64,
    out_support: []layer_depths.SupportOptics,
    out_layers: []layer_depths.LayerOptics,
    out_source_levels: []source_levels.SourceLevel,
    out_curved_samples: []curved_sun_path.CurvedSunPathSample,
    out_curved_level_starts: []usize,
    out_curved_level_altitudes_km: []f64,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
) !void {
    // prefetchO2ARadianceRowsSingleWorker -------------------------------------------------------------------- |
    // Fill dense high-resolution radiance rows from the explicit O2 A optics and transport route.              |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the old single-worker dense prefetch order from main:                                            |
    //   `grid_calculation/spectral_forward.zig` `prefetchForwardSamples` and                                   |
    //   `computeForwardSampleAtWavelengthWithScratch`. The per-wavelength physics remains in                   |
    //   `radianceAtWavelength`; this wrapper owns only exact-list iteration, solar lookup, and row writes.     |
    //                                                                                                          |
    // row contract                                                                                             |
    //   out_dense_radiance[index] corresponds to wavelengths.wavelengths[index]. ProfileLineValues must be     |
    //   built over the same exact list so the dense index is also the spectroscopy wavelength index.           |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Every support/layer/source/curved row is caller-owned scratch reused for each wavelength. Scattering   |
    //   callers reserve TransportWorkerMemory before entry; direct-route callers do not need worker buffers.   |
    // ---------------------------------------------------------------------------------------------------------|
    const support_count = layer_grid.support_mid_altitudes_km.len;
    const layer_count = layer_grid.layer_pressures_hpa.len;
    const shape_matches = out_dense_radiance.len == wavelengths.wavelengths.len and
        out_support.len == support_count and
        out_line_sigma_cm2_per_molecule.len == support_count and
        out_layers.len == layer_count and
        out_source_levels.len == layer_count + 1 and
        out_curved_samples.len >= support_count and
        out_curved_level_starts.len == layer_count + 1 and
        out_curved_level_altitudes_km.len == layer_count + 1;
    if (!shape_matches) return error.ShapeMismatch;

    if (wavelengths.wavelengths.len == 0) return;

    // instrumentation: trace counter: high-resolution radiance rows ------------------------------------------ |
    // captures: unique exact radiance wavelengths evaluated by this O2 A prefetch pass                         |
    // why: distinguishes fewer transport solves from cheaper work per solve.                                   |
    Trace.plotU("high_resolution_misses", @intCast(wavelengths.wavelengths.len));
    // end instrumentation: trace counter: high-resolution radiance rows -------------------------------------- |

    var start_index: usize = 0;
    while (nextStaticChunk(&start_index, wavelengths.wavelengths.len)) |chunk| {

        // instrumentation: trace zone: O2 A radiance prefetch chunk ------------------------------------------ |
        // captures: one single-worker O2 A prefetch chunk size and wall time                                   |
        // why: preserves the old chunk boundary while keeping per-wavelength optics visible separately.        |
        const chunk_zone = Trace.deepStaticZone(@src(), "radiance_prefetch.o2a_chunk");
        chunk_zone.value(@intCast(chunk.len()));
        defer chunk_zone.end();
        // end instrumentation: trace zone: O2 A radiance prefetch chunk -------------------------------------- |

        for (chunk.start..chunk.end) |index| {
            const wavelength = wavelengths.wavelengths[index];
            const solar_irradiance = try solar_lookup.irradianceAtWavelength(solar, wavelength.wavelength_nm);
            out_dense_radiance[index] = try radianceAtWavelength(
                wavelength.wavelength_nm,
                index,
                angles,
                surface_albedo,
                layer_grid,
                profile_lines,
                cia,
                aerosol,
                phase,
                solar_irradiance,
                solve_config,
                out_line_sigma_cm2_per_molecule,
                out_support,
                out_layers,
                out_source_levels,
                out_curved_samples,
                out_curved_level_starts,
                out_curved_level_altitudes_km,
                worker_memory,
            );
        }
    }
}

pub fn runO2ASpectrumSingleWorker(
    table: sampling_table.SpectrumSamplingTable,
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    angles: solve.ViewAngles,
    surface_albedo: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    profile_lines: profile_line_memory.ProfileLineValues,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    solar: solar_table.SolarTable,
    solve_config: controls.SolveConfig,
    uses_integrated_radiance_sampling: bool,
    uses_integrated_irradiance_sampling: bool,
    radiance_calibration: instrument_average.Calibration,
    irradiance_calibration: instrument_average.Calibration,
    radiance_slit_kernel: []const f64,
    irradiance_slit_kernel: []const f64,
    out_dense_radiance: []radiance_results.RadianceResult,
    out_wavelengths_nm: []f64,
    out_raw_radiance: []radiance_results.RadianceResult,
    out_raw_irradiance: []f64,
    out_radiance: []radiance_results.RadianceResult,
    out_irradiance: []f64,
    out_reflectance: []f64,
    out_jacobian: []jacobian_states.Vector,
    out_line_sigma_cm2_per_molecule: []f64,
    out_support: []layer_depths.SupportOptics,
    out_layers: []layer_depths.LayerOptics,
    out_source_levels: []source_levels.SourceLevel,
    out_curved_samples: []curved_sun_path.CurvedSunPathSample,
    out_curved_level_starts: []usize,
    out_curved_level_altitudes_km: []f64,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
    solar_memory: *solar_irradiance_memory.SolarIrradianceMemory,
) !instrument_average.ReflectanceAssemblySummary {
    // runO2ASpectrumSingleWorker ----------------------------------------------------------------------------- |
    // Run the explicit single-worker spectrum path from exact radiance wavelengths to product reflectance.     |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the old orchestration order from main:                                                           |
    //   `grid_calculation/spectral_forward.zig` dense prefetch and `grid_calculation/simulate.zig` nominal     |
    //   gather, channel postprocess, and reflectance assembly. The individual formulas stay in the stage       |
    //   helpers called below.                                                                                  |
    //                                                                                                          |
    // data flow                                                                                                |
    //   exact radiance wavelengths -> dense radiance rows -> raw product radiance and irradiance rows          |
    //   -> calibrated product rows -> reflectance and fixed-state Jacobian rows                                |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Every dense/product/optics row is caller-owned. The wrapper allocates nothing and stores no scene,     |
    //   request, product, output, or cache owner.                                                              |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = table.rows.len;
    const product_shapes_match = wavelengths.rows.len == row_count and
        out_wavelengths_nm.len == row_count and
        out_raw_radiance.len == row_count and
        out_raw_irradiance.len == row_count and
        out_radiance.len == row_count and
        out_irradiance.len == row_count and
        out_reflectance.len == row_count;
    if (!product_shapes_match) return error.ShapeMismatch;

    // instrumentation: trace zone: single-worker spectrum run ------------------------------------------------ |
    // captures: dense prefetch, product gather, channel postprocess, and reflectance assembly wall time        |
    // why: gives WP4 a same-boundary phase around the full explicit spectrum path.                             |
    const run_zone = Trace.staticZone(@src(), "spectrum.o2a_single_worker");
    run_zone.value(@intCast(row_count));
    defer run_zone.end();
    // end instrumentation: trace zone: single-worker spectrum run -------------------------------------------- |

    try prefetchO2ARadianceRowsSingleWorker(
        wavelengths,
        angles,
        surface_albedo,
        layer_grid,
        profile_lines,
        cia,
        aerosol,
        phase,
        solar,
        solve_config,
        out_dense_radiance,
        out_line_sigma_cm2_per_molecule,
        out_support,
        out_layers,
        out_source_levels,
        out_curved_samples,
        out_curved_level_starts,
        out_curved_level_altitudes_km,
        worker_memory,
    );

    try gatherProductRows(
        solve_config,
        table,
        wavelengths,
        out_dense_radiance,
        solar,
        solar_memory,
        out_wavelengths_nm,
        out_raw_radiance,
        out_raw_irradiance,
    );

    return postprocessAndAssembleProductRows(
        solve_config,
        uses_integrated_radiance_sampling,
        uses_integrated_irradiance_sampling,
        radiance_calibration,
        irradiance_calibration,
        radiance_slit_kernel,
        irradiance_slit_kernel,
        angles.solar_mu,
        out_raw_radiance,
        out_raw_irradiance,
        out_radiance,
        out_irradiance,
        out_reflectance,
        out_jacobian,
    );
}

fn totalOpticalDepth(layers: []const layer_depths.LayerOptics) f64 {
    // totalOpticalDepth ------------------------------------------------------------------------------------   |
    // Reduce explicit layer rows into the scalar optical depth used by the old direct-surface route.           |
    // -------------------------------------------------------------------------------------------------------- |
    var total: f64 = 0.0;
    for (layers) |layer| total += layer.total_optical_depth;
    return total;
}

// Range -----------------------------------------------------------------------------------------------------  |
// Half-open item range owned by one spectrum worker or one queue claim.                                        |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 16 B (0.016 KiB), align: 8 B                                                                           |
//                                                                                                              |
// memory                                                                                                       |
// [ 0.. 7] start : usize                                                                                       |
// [ 8..15] end   : usize                                                                                       |
//                                                                                                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                       |
// footprint: per instance = 16 B; stack return value                                                           |
pub const Range = struct {
    start: usize,
    end: usize,

    pub fn len(self: Range) usize {
        // Range.len ----------------------------------------------------------------------------------------   |
        // Return the number of items in this half-open worker range.                                           |
        // ---------------------------------------------------------------------------------------------------- |
        return self.end - self.start;
    }
};
// ------------------------------------------------------------------------------------------------------------ |

// ChunkQueue ------------------------------------------------------------------------------------------------  |
// Mutex-protected dynamic chunk dispenser for reusable pooled workers.                                         |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 40 B (0.039 KiB), align: 8 B in Debug; 32 B (0.031 KiB), align: 8 B in optimized builds                |
//                                                                                                              |
// memory, Debug                                                                                                |
// [ 0..15] mutex      : Thread.Mutex                                                                           |
// [16..23] next_index : usize                                                                                  |
// [24..31] item_count : usize                                                                                  |
// [32..39] chunk_size : usize                                                                                  |
//                                                                                                              |
// memory, optimized                                                                                            |
// [ 0.. 7] next_index : usize                                                                                  |
// [ 8..15] item_count : usize                                                                                  |
// [16..23] chunk_size : usize                                                                                  |
// [24..27] mutex      : Thread.Mutex                                                                           |
// [28..31] padding    : 4 B                                                                                    |
//                                                                                                              |
// footprint: per instance = 40 B Debug or 32 B optimized; one queue per pooled radiance-prefetch batch         |
pub const ChunkQueue = struct {
    mutex: std.Thread.Mutex = .{},
    next_index: usize = 0,
    item_count: usize,
    chunk_size: usize,

    pub fn init(item_count: usize, chunk_size: usize) ChunkQueue {
        // ChunkQueue.init ----------------------------------------------------------------------------------   |
        // Build a queue over `item_count` items. A zero chunk would stall all workers, so it is rejected by    |
        // assertion exactly like the old worker policy.                                                        |
        // ---------------------------------------------------------------------------------------------------- |
        std.debug.assert(chunk_size != 0);
        return .{
            .item_count = item_count,
            .chunk_size = chunk_size,
        };
    }

    pub fn next(self: *ChunkQueue) ?Range {
        // ChunkQueue.next ----------------------------------------------------------------------------------   |
        // Hand out the next contiguous item range under a short mutex.                                         |
        //                                                                                                      |
        // math                                                                                                 |
        //   start = next_index                                                                                 |
        //   end   = min(start + chunk_size, item_count)                                                        |
        // ---------------------------------------------------------------------------------------------------- |
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.next_index >= self.item_count) return null;

        const start = self.next_index;
        const end = @min(start + self.chunk_size, self.item_count);
        self.next_index = end;
        return .{ .start = start, .end = end };
    }
};
// ------------------------------------------------------------------------------------------------------------ |

pub fn FirstWorkerErrorState(comptime ErrorSet: type) type {
    // FirstWorkerErrorState --------------------------------------------------------------------------------   |
    // Shared first-error slot for parallel radiance workers. Workers write only on failure, so the mutex       |
    // guards the cold path while the successful hot loop does no cross-worker coordination.                    |
    //                                                                                                          |
    // layout(64-bit, ErrorSet with one or more errors)                                                         |
    // size: 24 B (0.023 KiB), align: 8 B in Debug; 8 B (0.008 KiB), align: 4 B in optimized builds             |
    //                                                                                                          |
    // memory, Debug                                                                                            |
    // [ 0..15] mutex   : std.Thread.Mutex                                                                      |
    // [16..17] err     : ?ErrorSet                                                                             |
    // [18..23] padding : 6 B                                                                                   |
    //                                                                                                          |
    // memory, optimized                                                                                        |
    // [0..3] mutex : std.Thread.Mutex                                                                          |
    // [4..5] err   : ?ErrorSet                                                                                 |
    // [6..7] padding : 2 B                                                                                     |
    // -------------------------------------------------------------------------------------------------------- |
    return struct {
        mutex: std.Thread.Mutex = .{},
        err: ?ErrorSet = null,

        pub fn store(self: *@This(), err: ErrorSet) void {
            // FirstWorkerErrorState.store ------------------------------------------------------------------   |
            // Preserve the first observed worker error. Later worker failures leave the original cause in      |
            // place so joined callers return the earliest failure deterministically.                           |
            // ------------------------------------------------------------------------------------------------ |
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.err == null) self.err = err;
        }
    };
}

pub fn staticRange(item_count: usize, worker_count: usize, worker_index: usize) Range {
    // staticRange -------------------------------------------------------------------------------------------  |
    // Compute deterministic ownership for one direct-spawn radiance worker.                                    |
    //                                                                                                          |
    // math                                                                                                     |
    //   start = floor(worker_index * item_count / worker_count)                                                |
    //   end   = floor((worker_index + 1) * item_count / worker_count)                                          |
    //                                                                                                          |
    // reason                                                                                                   |
    //   The full exact-wavelength list is known before prefetch starts, so static ranges prevent worker        |
    //   startup order from deciding who drains expensive wavelengths.                                          |
    // -------------------------------------------------------------------------------------------------------- |
    std.debug.assert(worker_count != 0);
    std.debug.assert(worker_index < worker_count);
    return .{
        .start = worker_index * item_count / worker_count,
        .end = (worker_index + 1) * item_count / worker_count,
    };
}

pub fn nextStaticChunk(start_index: *usize, end_index: usize) ?Range {
    // nextStaticChunk ---------------------------------------------------------------------------------------  |
    // Drain a worker's static range in the same chunk shape as the old high-resolution prefetch loop.          |
    // -------------------------------------------------------------------------------------------------------- |
    if (start_index.* >= end_index) return null;
    const chunk = Range{
        .start = start_index.*,
        .end = @min(start_index.* + radiance_prefetch_chunk_size, end_index),
    };
    start_index.* = chunk.end;
    return chunk;
}

pub fn prefetchRadianceRowsSingleWorker(
    comptime ComputeState: type,
    comptime ComputeError: type,
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    results: []radiance_results.RadianceResult,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
    compute_state: *ComputeState,
    comptime compute: fn (
        *ComputeState,
        f64,
        usize,
        *transport_worker_memory.TransportWorkerMemory,
    ) ComputeError!radiance_results.RadianceResult,
) (Error || ComputeError)!void {
    // prefetchRadianceRowsSingleWorker -------------------------------------------------------------------     |
    // Fill dense high-resolution radiance rows for one worker-local memory owner.                              |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the single-worker loop shape from main:                                                          |
    //   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`                              |
    //   `prefetchForwardSamples` and `computeForwardSampleAtWavelengthWithScratch`.                            |
    //                                                                                                          |
    // row contract                                                                                             |
    //   results[index] corresponds to wavelengths.wavelengths[index]. Later nominal gathers read these rows    |
    //   through RadianceSampleIndexRef/sample_indices, so this function must not reorder the dense array.      |
    //                                                                                                          |
    // memory                                                                                                   |
    //   The worker memory is caller-owned and reusable. The compute callback receives explicit wavelength      |
    //   and memory inputs; no scene, request, or generic cache is stored here.                                 |
    // ---------------------------------------------------------------------------------------------------------|
    if (results.len != wavelengths.wavelengths.len) return error.ShapeMismatch;
    if (wavelengths.wavelengths.len == 0) return;

    // instrumentation: trace counter: high-resolution radiance rows ------------------------------------------ |
    // captures: unique exact radiance wavelengths evaluated by this prefetch pass                              |
    // why: distinguishes fewer transport solves from cheaper work per solve.                                   |
    Trace.plotU("high_resolution_misses", @intCast(wavelengths.wavelengths.len));
    // end instrumentation: trace counter: high-resolution radiance rows -------------------------------------- |

    var start_index: usize = 0;
    while (nextStaticChunk(&start_index, wavelengths.wavelengths.len)) |chunk| {
        try prefetchRadianceChunk(
            ComputeState,
            ComputeError,
            wavelengths.wavelengths,
            results,
            chunk,
            worker_memory,
            compute_state,
            compute,
        );
    }
}

fn prefetchRadianceChunk(
    comptime ComputeState: type,
    comptime ComputeError: type,
    wavelengths: []const radiance_wavelengths.RadianceWavelength,
    results: []radiance_results.RadianceResult,
    chunk: Range,
    worker_memory: *transport_worker_memory.TransportWorkerMemory,
    compute_state: *ComputeState,
    comptime compute: fn (
        *ComputeState,
        f64,
        usize,
        *transport_worker_memory.TransportWorkerMemory,
    ) ComputeError!radiance_results.RadianceResult,
) ComputeError!void {
    // prefetchRadianceChunk --------------------------------------------------------------------------------   |
    // Compute one contiguous chunk from the dense exact-wavelength list.                                       |
    // ---------------------------------------------------------------------------------------------------------|
    const worker_index: usize = 0;

    // instrumentation: trace zone: radiance prefetch chunk --------------------------------------------------- |
    // captures: one single-worker prefetch chunk size and wall time                                            |
    // why: keeps dense radiance prefetch work visible separately from nominal gather loops.                    |
    const chunk_zone = Trace.deepStaticZone(@src(), "radiance_prefetch.chunk");
    chunk_zone.value(@intCast(chunk.len()));
    defer chunk_zone.end();
    // end instrumentation: trace zone: radiance prefetch chunk ----------------------------------------------- |

    for (chunk.start..chunk.end) |index| {
        results[index] = try compute(
            compute_state,
            wavelengths[index].wavelength_nm,
            worker_index,
            worker_memory,
        );
    }
}

pub fn gatherProductRows(
    solve_config: controls.SolveConfig,
    table: sampling_table.SpectrumSamplingTable,
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    dense_radiance: []const radiance_results.RadianceResult,
    solar: solar_table.SolarTable,
    solar_memory: *solar_irradiance_memory.SolarIrradianceMemory,
    out_wavelengths_nm: []f64,
    out_raw_radiance: []radiance_results.RadianceResult,
    out_raw_irradiance: []f64,
) (Error || radiance_results.Error || solar_lookup.Error || std.mem.Allocator.Error)!void {
    // gatherProductRows -----------------------------------------------------------------------------------    |
    // Gather nominal product rows after dense radiance prefetch.                                               |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the cache-integration sections of old main:                                                      |
    //   `src/forward_model/instrument_grid/grid_calculation/simulate.zig` `fillRadianceSamples` and            |
    //   `fillIrradianceSamples`, delegating the scalar math to `radiance_results.zig` and `solar_lookup.zig`.  |
    //                                                                                                          |
    // data flow                                                                                                |
    //   sampling row -> exact radiance sample indexes -> dense radiance rows -> raw product radiance           |
    //   sampling row -> exact solar lookup/cache                     -> raw product irradiance                 |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Output slices are caller-owned. Solar memory is reset and reserved before the row loop so exact-key    |
    //   inserts do not allocate while nominal rows are being gathered.                                         |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = table.rows.len;
    const shape_matches = wavelengths.rows.len == row_count and
        out_wavelengths_nm.len == row_count and
        out_raw_radiance.len == row_count and
        out_raw_irradiance.len == row_count;
    if (!shape_matches) return error.ShapeMismatch;

    solar_memory.reset();
    try solar_lookup.reserveIrradianceMemory(solar_memory, table);

    // instrumentation: trace zone: product row gather -------------------------------------------------------- |
    // captures: nominal-row radiance and irradiance gather wall time                                           |
    // why: separates dense transport prefetch from product-grid sampling work.                                 |
    const zone = Trace.staticZone(@src(), "spectrum.product_row_gather");
    zone.value(@intCast(row_count));
    defer zone.end();
    // end instrumentation: trace zone: product row gather ---------------------------------------------------- |

    for (table.rows, 0..) |row, index| {
        out_wavelengths_nm[index] = row.nominal_wavelength_nm;
        out_raw_radiance[index] = try radiance_results.integratePrefetchedRadianceAtNominal(
            solve_config,
            dense_radiance,
            wavelengths.rows[index],
            wavelengths.sample_indices,
            &row.radiance_integration,
            table.kernel_storage,
        );
        out_raw_irradiance[index] = try solar_lookup.integrateIrradianceAtNominalAssumeCapacity(
            solar,
            solar_memory,
            row.irradiance_wavelength_nm,
            &row.irradiance_integration,
            table.kernel_storage,
        );
    }
}

pub fn postprocessAndAssembleProductRows(
    solve_config: controls.SolveConfig,
    uses_integrated_radiance_sampling: bool,
    uses_integrated_irradiance_sampling: bool,
    radiance_calibration: instrument_average.Calibration,
    irradiance_calibration: instrument_average.Calibration,
    radiance_slit_kernel: []const f64,
    irradiance_slit_kernel: []const f64,
    solar_cosine: f64,
    raw_radiance: []const radiance_results.RadianceResult,
    raw_irradiance: []const f64,
    out_radiance: []radiance_results.RadianceResult,
    out_irradiance: []f64,
    out_reflectance: []f64,
    out_jacobian: []jacobian_states.Vector,
) (Error || instrument_average.Error)!instrument_average.ReflectanceAssemblySummary {
    // postprocessAndAssembleProductRows ------------------------------------------------------------------     |
    // Apply the old product-grid postprocess order and final reflectance assembly to caller-owned rows.        |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports the orchestration order from main: `simulate.zig` `fillRadianceSamples`,                         |
    //   `fillIrradianceSamples`, `processJacobianSamples`, and `assembleReflectance`. The scalar               |
    //   convolution, calibration, and reflectance math stays in `instrument_average.zig`.                      |
    //                                                                                                          |
    // data flow                                                                                                |
    //   raw product radiance     -> radiance convolution/calibration plus active Jacobian lanes                |
    //   raw product irradiance   -> irradiance convolution/calibration                                         |
    //   calibrated product rows  -> reflectance and optional reflectance Jacobian rows                         |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Every slice is caller-owned. Non-integrated convolution overlap guards are enforced by                 |
    //   `instrument_average`; this wrapper only proves that all product-row slices describe the same count.    |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = raw_radiance.len;
    const shape_matches = raw_irradiance.len == row_count and
        out_radiance.len == row_count and
        out_irradiance.len == row_count and
        out_reflectance.len == row_count;
    if (!shape_matches) return error.ShapeMismatch;

    // instrumentation: trace zone: radiance postprocess ------------------------------------------------------ |
    // captures: product-row radiance convolution/calibration wall time                                         |
    // why: preserves visibility of the old simulate.radiance_postprocess stage.                                |
    {
        const radiance_zone = Trace.staticZone(@src(), "spectrum.radiance_postprocess");
        radiance_zone.value(@intCast(row_count));
        defer radiance_zone.end();
        try instrument_average.postprocessRadianceResults(
            solve_config,
            uses_integrated_radiance_sampling,
            radiance_calibration,
            radiance_slit_kernel,
            raw_radiance,
            out_radiance,
        );
    }
    // end instrumentation: trace zone: radiance postprocess -------------------------------------------------- |

    // instrumentation: trace zone: irradiance postprocess ---------------------------------------------------- |
    // captures: product-row irradiance convolution/calibration wall time                                       |
    // why: preserves visibility of the old simulate.irradiance_postprocess stage.                              |
    {
        const irradiance_zone = Trace.staticZone(@src(), "spectrum.irradiance_postprocess");
        irradiance_zone.value(@intCast(row_count));
        defer irradiance_zone.end();
        try instrument_average.postprocessSignal(
            uses_integrated_irradiance_sampling,
            irradiance_calibration,
            irradiance_slit_kernel,
            raw_irradiance,
            out_irradiance,
        );
    }
    // end instrumentation: trace zone: irradiance postprocess ------------------------------------------------ |

    // instrumentation: trace zone: reflectance assembly ------------------------------------------------------ |
    // captures: final reflectance and reflectance-Jacobian assembly wall time                                  |
    // why: keeps the final product conversion separate from sampling and channel postprocess costs.            |
    const reflectance_zone = Trace.staticZone(@src(), "spectrum.reflectance_assembly");
    reflectance_zone.value(@intCast(row_count));
    defer reflectance_zone.end();
    // end instrumentation: trace zone: reflectance assembly -------------------------------------------------- |

    return instrument_average.assembleReflectanceResults(
        solve_config,
        solar_cosine,
        out_radiance,
        out_irradiance,
        out_reflectance,
        out_jacobian,
    );
}

pub fn preferredRadianceWorkerCount(radiance_count: usize) usize {
    // preferredRadianceWorkerCount -------------------------------------------------------------------------   |
    // Keep small exact-wavelength batches single-threaded and scale larger batches through the shared          |
    // worker-count policy. This is the old `preferredForwardWorkerCount` rule under the spectrum owner.        |
    // -------------------------------------------------------------------------------------------------------- |
    return preferredWorkerCount(radiance_count, min_parallel_radiance_count);
}

pub fn preferredWorkerCount(item_count: usize, min_items_per_worker: usize) usize {
    // preferredWorkerCount ---------------------------------------------------------------------------------   |
    // Resolve CPU count and configured worker limit into a batch worker count.                                 |
    //                                                                                                          |
    // math                                                                                                     |
    //   workers = min(max_workers, available_workers, max(1, item_count / min_items_per_worker))               |
    // -------------------------------------------------------------------------------------------------------- |
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return preferredWorkerCountForCpuCount(
        item_count,
        min_items_per_worker,
        cpu_count,
        configuredWorkerLimit(),
    );
}

pub fn preferredWorkerCountForCpuCount(
    item_count: usize,
    min_items_per_worker: usize,
    cpu_count: usize,
    worker_limit: ?usize,
) usize {
    // preferredWorkerCountForCpuCount ----------------------------------------------------------------------   |
    // Pure worker-count resolver used by tests and by preferredWorkerCount after CPU/env discovery.            |
    // -------------------------------------------------------------------------------------------------------- |
    std.debug.assert(min_items_per_worker != 0);
    if (item_count < min_items_per_worker) return 1;

    const count_from_work = @max(@as(usize, 1), item_count / min_items_per_worker);
    var available_workers = @max(@as(usize, 1), cpu_count);
    if (worker_limit) |limit| {
        if (limit == 0) @panic(worker_limit_env ++ " must be a positive integer");
        available_workers = @min(available_workers, limit);
    }
    return @min(max_workers, @min(available_workers, count_from_work));
}

fn configuredWorkerLimit() ?usize {
    // configuredWorkerLimit --------------------------------------------------------------------------------   |
    // Preserve the old `ZDISAMAR_WORKER_LIMIT` behavior: absent means no extra limit; invalid or zero values   |
    // are programmer/operator errors and panic before worker launch.                                           |
    // -------------------------------------------------------------------------------------------------------- |
    const limit = std.process.parseEnvVarInt(worker_limit_env, usize, 10) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => @panic(worker_limit_env ++ " must be a positive integer"),
    };
    if (limit) |value| {
        if (value == 0) @panic(worker_limit_env ++ " must be a positive integer");
    }
    return limit;
}

comptime {
    std.debug.assert(@sizeOf(Range) == 16);
    if (builtin.mode == .Debug) {
        std.debug.assert(@sizeOf(ChunkQueue) == 40);
        std.debug.assert(@sizeOf(FirstWorkerErrorState(error{WorkerFailed})) == 24);
    } else {
        std.debug.assert(@sizeOf(ChunkQueue) == 32);
        std.debug.assert(@sizeOf(FirstWorkerErrorState(error{WorkerFailed})) == 8);
    }
}
