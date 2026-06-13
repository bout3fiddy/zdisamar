const std = @import("std");

const instrument_average = @import("instrument_average.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");
const aerosol_tables = @import("../setup/aerosol_tables.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const cia_table = @import("../setup/cia_table.zig");
const worker_partition = @import("../common/worker_partition.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const phase_table = @import("../setup/phase_table.zig");
const profile_line_memory = @import("../cache/profile_line_memory.zig");
const rayleigh = @import("../optics/rayleigh.zig");
const radiance_results = @import("radiance_results.zig");
const radiance_wavelengths = @import("radiance_wavelengths.zig");
const sampling_table = @import("sampling_table.zig");
const solve = @import("../rtm/solve.zig");
const solar_lookup = @import("solar_lookup.zig");
const solar_irradiance_memory = @import("../cache/solar_irradiance_memory.zig");
const solar_table = @import("../setup/solar_table.zig");
const source_levels = @import("../optics/source_levels.zig");
const transport_worker_memory = @import("../cache/transport_worker_memory.zig");
const controls = @import("../rtm/controls.zig");
const Trace = @import("../instrumentation/trace.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");

pub const Error = error{
    ShapeMismatch,
};

// spectrum_run.zig -----------------------------------------------------------------------------------------   |
// Spectrum-level orchestration for high-resolution radiance prefetch and product-row assembly.                 |
//                                                                                                              |
// provenance                                                                                                   |
//   Ports the scheduling and first-error contracts from main:                                                  |
//   `src/forward_model/work_partition.zig`,                                                                    |
//   `src/forward_model/first_worker_error_state.zig`, and                                                      |
//   `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`.                                 |
//                                                                                                              |
// boundary                                                                                                     |
//   This file owns spectrum route order and radiance-specific thresholds. Shared worker partition policy       |
//   lives in common/worker_partition.zig so cache and sampling builders can use the same old-route policy.     |
//   No scene, request, product owner, C context, or cache stamp is stored here.                                |
//                                                                                                              |
// route                                                                                                        |
//   SpectrumSamplingTable -> RadianceWavelengthList -> static radiance ranges or pooled chunks -> dense        |
//   RadianceResult rows -> nominal gather and instrument averaging.                                            |
//                                                                                                              |
// allocation                                                                                                   |
//   The helpers here allocate nothing. Thread owners and worker-local transport memory live at the call site.  |
// ------------------------------------------------------------------------------------------------------------ |

pub const min_parallel_radiance_count: usize = 32;
pub const radiance_prefetch_chunk_size: usize = 8;
pub const radiance_prefetch_pooled_chunk_size: usize = 8;

const RadiancePrefetchErrorState = worker_partition.FirstWorkerErrorState(anyerror);

// O2ASamplingPolicy -----------------------------------------------------------------------------------------  |
// Product-channel sampling and calibration policy for the exercised O2 A spectrum route.                       |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 104 B (0.102 KiB), align: 8 B                                                                          |
//                                                                                                              |
// memory                                                                                                       |
// [  0.. 31] radiance_calibration              : Calibration                                                   |
// [ 32.. 63] irradiance_calibration            : Calibration                                                   |
// [ 64.. 79] radiance_slit_kernel              : []const f64                                                   |
// [ 80.. 95] irradiance_slit_kernel            : []const f64                                                   |
// [ 96.. 96] uses_integrated_radiance_sampling : bool                                                          |
// [ 97.. 97] uses_integrated_irradiance_sampling: bool                                                         |
// [ 98..103] padding                           : 6 B                                                           |
pub const O2ASamplingPolicy = struct {
    radiance_calibration: instrument_average.Calibration = .{},
    irradiance_calibration: instrument_average.Calibration = .{},
    radiance_slit_kernel: []const f64 = &.{},
    irradiance_slit_kernel: []const f64 = &.{},
    uses_integrated_radiance_sampling: bool = true,
    uses_integrated_irradiance_sampling: bool = true,
};
// ------------------------------------------------------------------------------------------------------------ |

// ProductRows ------------------------------------------------------------------------------------------------ |
// Caller-owned spectrum output rows grouped at the orchestration boundary.                                     |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 128 B (0.125 KiB), align: 8 B                                                                          |
//                                                                                                              |
// memory                                                                                                       |
// [  0.. 15] dense_radiance : []RadianceResult                                                                 |
// [ 16.. 31] wavelengths_nm : []f64                                                                            |
// [ 32.. 47] raw_radiance   : []RadianceResult                                                                 |
// [ 48.. 63] raw_irradiance : []f64                                                                            |
// [ 64.. 79] radiance       : []RadianceResult                                                                 |
// [ 80.. 95] irradiance     : []f64                                                                            |
// [ 96..111] reflectance    : []f64                                                                            |
// [112..127] jacobian       : []Vector                                                                         |
pub const ProductRows = struct {
    dense_radiance: []radiance_results.RadianceResult,
    wavelengths_nm: []f64,
    raw_radiance: []radiance_results.RadianceResult,
    raw_irradiance: []f64,
    radiance: []radiance_results.RadianceResult,
    irradiance: []f64,
    reflectance: []f64,
    jacobian: []jacobian_states.Vector,
};
// ------------------------------------------------------------------------------------------------------------ |

// RadianceWorkRows ------------------------------------------------------------------------------------------  |
// Worker-local optics scratch rows for one exact-wavelength solve.                                             |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// size: 112 B (0.109 KiB), align: 8 B                                                                          |
//                                                                                                              |
// memory                                                                                                       |
// [  0.. 15] line_sigma_cm2_per_molecule : []f64                                                               |
// [ 16.. 31] support                     : []SupportOptics                                                     |
// [ 32.. 47] layers                      : []LayerOptics                                                       |
// [ 48.. 63] source_levels               : []SourceLevel                                                       |
// [ 64.. 79] curved_samples              : []CurvedSunPathSample                                               |
// [ 80.. 95] curved_level_starts         : []usize                                                             |
// [ 96..111] curved_level_altitudes_km   : []f64                                                               |
pub const RadianceWorkRows = struct {
    line_sigma_cm2_per_molecule: []f64,
    support: []layer_depths.SupportOptics,
    layers: []layer_depths.LayerOptics,
    source_levels: []source_levels.SourceLevel,
    curved_samples: []curved_sun_path.CurvedSunPathSample,
    curved_level_starts: []usize,
    curved_level_altitudes_km: []f64,
};
// ------------------------------------------------------------------------------------------------------------ |

// RadiancePrefetchWorker ------------------------------------------------------------------------------------  |
// Site-local worker row for dense O2 A radiance prefetch.                                                      |
//                                                                                                              |
// layout(64-bit)                                                                                               |
// The row is intentionally not size-pinned because Telemetry.Context is sink-selected: zero-size in normal     |
// builds and larger in calculation-telemetry harness builds. All stored rows are borrowed; no field owns       |
// heap storage, physics controls, or cache validity stamps.                                                    |
//                                                                                                              |
// memory groups                                                                                                |
//   inputs     : wavelengths, angles, surface albedo, layer grid, profile lines, CIA, aerosol, phase, solar    |
//   controls   : prepared_solve_config                                                                         |
//   outputs    : out_dense_radiance[index] for each claimed exact wavelength                                   |
//   scheduling : static range or pooled ChunkQueue, worker index, first-error state                            |
//   scratch    : one worker-local TransportWorkerMemory with optics and LABOS rows                             |
//   telemetry  : base context copied before per-sample sample_index/wavelength fields are overlaid             |
const RadiancePrefetchWorker = struct {
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    angles: solve.ViewAngles,
    surface_albedo: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    profile_lines: profile_line_memory.ProfileLineValues,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    solar: solar_table.SolarTable,
    prepared_solve_config: controls.SolveConfig,
    out_dense_radiance: []radiance_results.RadianceResult,
    error_state: *RadiancePrefetchErrorState,
    start_index: usize,
    end_index: usize,
    queue: ?*worker_partition.ChunkQueue = null,
    worker_index: usize = 0,
    transport_memory: *transport_worker_memory.TransportWorkerMemory,
    telemetry_context: Telemetry.Context,
};
// ------------------------------------------------------------------------------------------------------------ |

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
    prepared_solve_config: controls.SolveConfig,
    work_rows: RadianceWorkRows,
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
    // hot path                                                                                                 |
    //   The caller passes a SolveConfig already validated by `controls.prepareSolveConfig`. Keeping that       |
    //   setup-side check outside this exact-wavelength loop mirrors old main:                                  |
    //   `radiative_transfer/root.zig` `executePreparedWithLabosWorkspace`.                                     |
    //                                                                                                          |
    // unsupported old routes                                                                                   |
    //   Source-level and curved-sun rows are only filled for controls that request those old routes. The       |
    //   current transport solver still rejects integrated-source and spherical-correction controls after       |
    //   their explicit rows are present.                                                                       |
    // -------------------------------------------------------------------------------------------------------- |
    const support_count = layer_grid.support_mid_altitudes_km.len;
    const layer_count = layer_grid.layer_pressures_hpa.len;
    if (work_rows.support.len != support_count or
        work_rows.line_sigma_cm2_per_molecule.len != support_count or
        work_rows.layers.len != layer_count or
        work_rows.source_levels.len != layer_count + 1 or
        work_rows.curved_level_starts.len != layer_count + 1 or
        work_rows.curved_level_altitudes_km.len != layer_count + 1)
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
            work_rows.line_sigma_cm2_per_molecule,
        );
        try layer_depths.fillSupportOpticsAtWavelength(
            wavelength_nm,
            layer_grid,
            work_rows.line_sigma_cm2_per_molecule,
            cia,
            aerosol,
            work_rows.support,
        );
        try layer_depths.reduceLayerOpticsFromSupportRows(layer_grid, work_rows.support, work_rows.layers);
        layer_depths.fillLayerAerosolJacobians(aerosol, prepared_solve_config.derivative_state_mask, work_rows.layers);
    }

    const source_rows = source_rows: {
        if (prepared_solve_config.controls.integrate_source_function) {
            try source_levels.fillSourceLevelsAtWavelength(
                wavelength_nm,
                layer_grid,
                work_rows.support,
                work_rows.layers,
                work_rows.source_levels,
            );
            break :source_rows work_rows.source_levels;
        }

        break :source_rows work_rows.source_levels[0..0];
    };

    const curved_rows = curved_rows: {
        if (prepared_solve_config.controls.use_spherical_correction) {
            const curved_count = try curved_sun_path.fillCurvedSunPathSamples(
                layer_grid,
                work_rows.support,
                work_rows.curved_samples,
                work_rows.curved_level_starts,
                work_rows.curved_level_altitudes_km,
            );
            break :curved_rows work_rows.curved_samples[0..curved_count];
        }

        break :curved_rows work_rows.curved_samples[0..0];
    };

    const reflectance = reflectance: {
        if (prepared_solve_config.controls.scattering == .none) {
            break :reflectance solve.directSurfaceOnly(
                angles,
                surface_albedo,
                totalOpticalDepth(work_rows.layers),
                prepared_solve_config.derivative_mode,
                prepared_solve_config.derivative_state_mask,
            );
        }

        const needs_order_local_sum =
            prepared_solve_config.controls.integrate_source_function and
            prepared_solve_config.derivative_mode != .none;
        var work = try worker_memory.solveWorkArrays(
            layer_count,
            prepared_solve_config.controls.n_streams,
            needs_order_local_sum,
        );
        work.curved_level_starts = work_rows.curved_level_starts;
        work.curved_level_altitudes_km = work_rows.curved_level_altitudes_km;
        break :reflectance try solve.solveReflectance(
            angles,
            surface_albedo,
            work_rows.layers,
            source_rows,
            curved_rows,
            phase,
            rayleigh.phaseCoefficient2(wavelength_nm),
            prepared_solve_config,
            &work,
        );
    };

    return radiance_results.scaleReflectanceToRadiance(
        prepared_solve_config,
        reflectance,
        angles.solar_mu,
        solar_irradiance,
    );
}

fn prefetchO2ARadianceRows(
    wavelengths: radiance_wavelengths.RadianceWavelengthList,
    angles: solve.ViewAngles,
    surface_albedo: f64,
    layer_grid: atmosphere_layers.LayerGrid,
    profile_lines: profile_line_memory.ProfileLineValues,
    cia: cia_table.O2CiaTable,
    aerosol: aerosol_tables.AerosolLayerTable,
    phase: phase_table.PhaseTable,
    solar: solar_table.SolarTable,
    prepared_solve_config: controls.SolveConfig,
    pool: ?*std.Thread.Pool,
    worker_count: usize,
    out_dense_radiance: []radiance_results.RadianceResult,
    transport_workers: []transport_worker_memory.TransportWorkerMemory,
) !void {
    // prefetchO2ARadianceRows -------------------------------------------------------------------------------- |
    // Fill dense high-resolution radiance rows through the old worker-count and pool/raw scheduling route.     |
    //                                                                                                          |
    // provenance                                                                                               |
    //   Ports main:`src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`                   |
    //   `prefetchForwardSamples`, `ForwardPrefetchWorker`, and `prefetchForwardWorkerMain`. The                |
    //   per-wavelength physics remains in `radianceAtWavelength`; this wrapper owns only scheduling, solar     |
    //   lookup, telemetry context, and dense row writes.                                                       |
    //                                                                                                          |
    // scheduling                                                                                               |
    //   pool != null : workers share a ChunkQueue with chunk size 8, matching the old pooled forward route     |
    //   pool == null : workers keep deterministic static ranges and drain chunk size 8 within each range       |
    //                                                                                                          |
    // row contract                                                                                             |
    //   out_dense_radiance[index] corresponds to wavelengths.wavelengths[index]. ProfileLineValues must be     |
    //   built over the same exact list so the dense index is also the spectroscopy wavelength index.           |
    //   prepared_solve_config has already passed the root/spectrum validation boundary.                        |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Each worker borrows its own TransportWorkerMemory optics and LABOS arrays. No worker writes another    |
    //   worker's scratch, and dense radiance output ranges are disjoint.                                       |
    // ---------------------------------------------------------------------------------------------------------|
    if (worker_count == 0 or worker_count > transport_workers.len) return error.ShapeMismatch;

    if (out_dense_radiance.len != wavelengths.wavelengths.len) return error.ShapeMismatch;

    const support_count = layer_grid.support_mid_altitudes_km.len;
    const layer_count = layer_grid.layer_pressures_hpa.len;
    for (transport_workers[0..worker_count]) |*worker_memory| {
        if (!transportWorkerShapeMatches(worker_memory, support_count, layer_count)) {
            return error.ShapeMismatch;
        }
    }

    if (wavelengths.wavelengths.len == 0) return;

    // instrumentation: trace counter: forward worker count --------------------------------------------------- |
    // captures: selected O2 A dense-prefetch worker count                                                      |
    // why: ties dense-prefetch wall time to the concurrency shape selected by root/session code.               |
    Trace.plotU("forward_worker_count", @intCast(worker_count));
    // end instrumentation: trace counter: forward worker count ----------------------------------------------- |

    // instrumentation: trace counter: high-resolution radiance rows ------------------------------------------ |
    // captures: unique exact radiance wavelengths evaluated by this O2 A prefetch pass                         |
    // why: distinguishes fewer transport solves from cheaper work per solve.                                   |
    Trace.plotU("high_resolution_misses", @intCast(wavelengths.wavelengths.len));
    // end instrumentation: trace counter: high-resolution radiance rows -------------------------------------- |

    const telemetry_context = Telemetry.currentContext();
    var error_state = RadiancePrefetchErrorState{};
    var queue_storage: worker_partition.ChunkQueue = undefined;
    const use_pooled_queue = pool != null and worker_count > 1;
    if (use_pooled_queue) {
        queue_storage = worker_partition.ChunkQueue.init(
            wavelengths.wavelengths.len,
            radiance_prefetch_pooled_chunk_size,
        );
    }

    var worker_storage: [worker_partition.max_workers]RadiancePrefetchWorker = undefined;
    for (0..worker_count) |worker_index| {
        const range = worker_partition.staticRange(wavelengths.wavelengths.len, worker_count, worker_index);
        const queue = queue: {
            if (use_pooled_queue) break :queue &queue_storage;
            break :queue null;
        };

        worker_storage[worker_index] = .{
            .wavelengths = wavelengths,
            .angles = angles,
            .surface_albedo = surface_albedo,
            .layer_grid = layer_grid,
            .profile_lines = profile_lines,
            .cia = cia,
            .aerosol = aerosol,
            .phase = phase,
            .solar = solar,
            .prepared_solve_config = prepared_solve_config,
            .out_dense_radiance = out_dense_radiance,
            .error_state = &error_state,
            .start_index = range.start,
            .end_index = range.end,
            .queue = queue,
            .worker_index = worker_index,
            .transport_memory = &transport_workers[worker_index],
            .telemetry_context = telemetry_context,
        };
    }

    worker_partition.runWorkers(pool, worker_storage[0..worker_count], radiancePrefetchWorkerMain);
    if (error_state.err) |err| return err;
}

fn transportWorkerShapeMatches(
    worker_memory: *const transport_worker_memory.TransportWorkerMemory,
    support_count: usize,
    layer_count: usize,
) bool {
    // transportWorkerShapeMatches ---------------------------------------------------------------------------  |
    // Validate the worker-local rows that one dense radiance worker borrows for optics and LABOS transport.    |
    // -------------------------------------------------------------------------------------------------------- |
    return worker_memory.line_sigma_cm2_per_molecule.len == support_count and
        worker_memory.support_optics.len == support_count and
        worker_memory.layer_optics.len == layer_count and
        worker_memory.source_level_rows.len == layer_count + 1 and
        worker_memory.curved_samples.len >= support_count and
        worker_memory.curved_level_starts.len == layer_count + 1 and
        worker_memory.curved_level_altitudes_km.len == layer_count + 1;
}

fn radiancePrefetchWorkerMain(worker: *RadiancePrefetchWorker) void {
    // radiancePrefetchWorkerMain ----------------------------------------------------------------------------- |
    // Worker loop for dense O2 A radiance rows. Each worker drains either a static range or the pooled queue,  |
    // writes disjoint dense rows, and stores the first error for the joined caller to return.                  |
    // -------------------------------------------------------------------------------------------------------- |
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-forward-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-forward-worker";

    // instrumentation: trace thread label: forward prefetch worker ------------------------------------------  |
    // captures: dense radiance prefetch worker identity                                                        |
    // why: makes parallel exact-wavelength batches separable in timeline traces.                               |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: forward prefetch worker --------------------------------------  |

    // instrumentation: trace zone: forward prefetch worker --------------------------------------------------  |
    // captures: dense radiance prefetch worker wall time                                                       |
    // why: exposes load balance across exact-wavelength chunks.                                                |
    const worker_zone = Trace.staticZone(@src(), "forward_prefetch.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();
    // end instrumentation: trace zone: forward prefetch worker ----------------------------------------------  |

    while (nextRadiancePrefetchChunk(worker)) |chunk| {

        // instrumentation: trace zone: O2 A radiance prefetch chunk ------------------------------------------ |
        // captures: one O2 A prefetch chunk size and wall time                                                 |
        // why: preserves the old chunk boundary while keeping per-wavelength optics visible separately.        |
        const chunk_zone = Trace.deepStaticZone(@src(), "forward_prefetch.chunk");
        chunk_zone.value(@intCast(chunk.len()));
        defer chunk_zone.end();
        // end instrumentation: trace zone: O2 A radiance prefetch chunk -------------------------------------- |

        for (chunk.start..chunk.end) |index| {
            const wavelength = worker.wavelengths.wavelengths[index];
            const solar_irradiance = solar_lookup.irradianceAtWavelength(
                worker.solar,
                wavelength.wavelength_nm,
            ) catch |err| {
                worker.error_state.store(err);
                return;
            };

            const previous_context = Telemetry.currentContext();
            if (comptime Telemetry.enabled) {
                var context = worker.telemetry_context;
                context.sample_index = std.math.cast(i64, index + 1) orelse std.math.maxInt(i64);
                context.wavelength_nm = wavelength.wavelength_nm;
                Telemetry.setContext(context);
            }
            defer if (comptime Telemetry.enabled) Telemetry.setContext(previous_context);

            worker.out_dense_radiance[index] = radianceAtWavelength(
                wavelength.wavelength_nm,
                index,
                worker.angles,
                worker.surface_albedo,
                worker.layer_grid,
                worker.profile_lines,
                worker.cia,
                worker.aerosol,
                worker.phase,
                solar_irradiance,
                worker.prepared_solve_config,
                .{
                    .line_sigma_cm2_per_molecule = worker.transport_memory.line_sigma_cm2_per_molecule,
                    .support = worker.transport_memory.support_optics,
                    .layers = worker.transport_memory.layer_optics,
                    .source_levels = worker.transport_memory.source_level_rows,
                    .curved_samples = worker.transport_memory.curved_samples,
                    .curved_level_starts = worker.transport_memory.curved_level_starts,
                    .curved_level_altitudes_km = worker.transport_memory.curved_level_altitudes_km,
                },
                worker.transport_memory,
            ) catch |err| {
                worker.error_state.store(err);
                return;
            };
        }
    }
}

fn nextRadiancePrefetchChunk(worker: *RadiancePrefetchWorker) ?worker_partition.Range {
    // nextRadiancePrefetchChunk ------------------------------------------------------------------------------ |
    // Return the next exact-wavelength range. Pooled workers share a queue; raw workers drain static ranges.   |
    // -------------------------------------------------------------------------------------------------------- |
    if (worker.queue) |queue| return queue.next();
    return worker_partition.nextStaticChunk(&worker.start_index, worker.end_index, radiance_prefetch_chunk_size);
}

pub fn runO2ASpectrum(
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
    prepared_solve_config: controls.SolveConfig,
    sampling_policy: O2ASamplingPolicy,
    prefetch_dense_radiance: bool,
    pool: ?*std.Thread.Pool,
    worker_count: usize,
    product_rows: ProductRows,
    transport_workers: []transport_worker_memory.TransportWorkerMemory,
    solar_memory: *solar_irradiance_memory.SolarIrradianceMemory,
) !instrument_average.ReflectanceAssemblySummary {
    // runO2ASpectrum ----------------------------------------------------------------------------------------- |
    // Run the explicit O2 A spectrum path from exact radiance wavelengths to product reflectance.              |
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
    //   Callers with a valid session cache may enter with dense radiance rows already filled; the gather and   |
    //   product assembly order is unchanged.                                                                   |
    //                                                                                                          |
    // memory                                                                                                   |
    //   Every dense/product/optics row is caller-owned. The wrapper allocates nothing and stores no scene,     |
    //   request, product, output, or cache owner. Worker-local optics rows come from transport_workers.        |
    //                                                                                                          |
    // prepared controls                                                                                        |
    //   The root facade calls `controls.prepareSolveConfig` before building session rows. Internal tests that  |
    //   call this function directly pass the same valid prepared shape.                                        |
    // ---------------------------------------------------------------------------------------------------------|
    const row_count = table.rows.len;
    const product_shapes_match = wavelengths.rows.len == row_count and
        product_rows.wavelengths_nm.len == row_count and
        product_rows.raw_radiance.len == row_count and
        product_rows.raw_irradiance.len == row_count and
        product_rows.radiance.len == row_count and
        product_rows.irradiance.len == row_count and
        product_rows.reflectance.len == row_count;
    if (!product_shapes_match) return error.ShapeMismatch;

    // instrumentation: trace zone: O2 A spectrum run --------------------------------------------------------- |
    // captures: dense prefetch, product gather, channel postprocess, and reflectance assembly wall time        |
    // why: gives WP4 a same-boundary phase around the full explicit spectrum path.                             |
    const run_zone = Trace.staticZone(@src(), "spectrum.o2a_run");
    run_zone.value(@intCast(row_count));
    defer run_zone.end();
    // end instrumentation: trace zone: O2 A spectrum run ----------------------------------------------------- |

    if (prefetch_dense_radiance) {
        try prefetchO2ARadianceRows(
            wavelengths,
            angles,
            surface_albedo,
            layer_grid,
            profile_lines,
            cia,
            aerosol,
            phase,
            solar,
            prepared_solve_config,
            pool,
            worker_count,
            product_rows.dense_radiance,
            transport_workers,
        );
    }

    try gatherProductRows(
        prepared_solve_config,
        table,
        wavelengths,
        product_rows.dense_radiance,
        solar,
        solar_memory,
        product_rows.wavelengths_nm,
        product_rows.raw_radiance,
        product_rows.raw_irradiance,
    );

    return postprocessAndAssembleProductRows(
        prepared_solve_config,
        sampling_policy.uses_integrated_radiance_sampling,
        sampling_policy.uses_integrated_irradiance_sampling,
        sampling_policy.radiance_calibration,
        sampling_policy.irradiance_calibration,
        sampling_policy.radiance_slit_kernel,
        sampling_policy.irradiance_slit_kernel,
        angles.solar_mu,
        product_rows.raw_radiance,
        product_rows.raw_irradiance,
        product_rows.radiance,
        product_rows.irradiance,
        product_rows.reflectance,
        product_rows.jacobian,
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
    return worker_partition.preferredWorkerCount(radiance_count, min_parallel_radiance_count);
}
