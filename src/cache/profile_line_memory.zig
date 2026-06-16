const std = @import("std");

const readers = @import("../assets/readers.zig");
const hashing = @import("../common/hashing.zig");
const spline = @import("../common/math/spline.zig");
const worker_partition = @import("../common/worker_partition.zig");
const scene_input = @import("../input/scene.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const line_tables = @import("../setup/line_tables.zig");
const line_physics = @import("../spectrum/line_physics.zig");
const CostTiming = @import("../instrumentation/cost_timing.zig");
const Trace = @import("../instrumentation/trace.zig");

const Allocator = std.mem.Allocator;
const min_spectroscopy_pressure_atm = line_physics.min_spectroscopy_pressure_atm;
const max_spectroscopy_profile_nodes: usize = 64;
const cutoff_grid_merge_tolerance_nm = 1.0e-9;
const min_parallel_profile_line_state_count: usize = 4;
const profile_line_state_chunk_size: usize = 2;
const min_parallel_profile_cache_build_count: usize = 32;
const profile_cache_build_chunk_size: usize = 8;

// min_hitran_temperature_k -----------------------------------------------------------------------------------|
// 150 K before HITRAN strength scaling. This protects the partition ratio, Boltzmann factor, Doppler width,   |
// and finite-difference derivative from nonphysical low-temperature inputs.                                   |
// ------------------------------------------------------------------------------------------------------------|
const min_hitran_temperature_k = line_physics.min_hitran_temperature_k;

// profile_line_memory.zig ------------------------------------------------------------------------------------|
// Retained weak-line cross-section values for exact setup wavelengths and layer profile nodes.                |
//                                                                                                             |
// setup boundary                                                                                              |
//   O2 A builds a preparation-time line-value grid from the parsed HITRAN rows and the computed layer grid.   |
//   Rows are indexed as wavelength-major, then layer-node minor, so later optics code can read a contiguous   |
//   profile column for each exact wavelength without rebuilding weak-line Voigt terms.                        |
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValue -------------------------------------------------------------------------------------------|
// One line-spectroscopy value at a single exact wavelength and layer profile node.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                     : f64                                                            |
// [ 8..11] layer_index                       : u32                                                            |
// [12..15] interval_index_1based             : u32                                                            |
// [16..23] pressure_hpa                      : f64                                                            |
// [24..31] temperature_k                     : f64                                                            |
// [32..39] weak_line_sigma_cm2_per_molecule  : f64                                                            |
// [40..47] strong_line_sigma_cm2_per_molecule: f64                                                            |
// [48..55] line_sigma_cm2_per_molecule       : f64                                                            |
// [56..63] line_mixing_sigma_cm2_per_molecule: f64                                                            |
// [64..71] total_sigma_cm2_per_molecule      : f64                                                            |
// [72..79] d_sigma_d_temperature_cm2_per_molecule_per_k : f64                                                 |
pub const ProfileLineValue = struct {
    wavelength_nm: f64,
    layer_index: u32,
    interval_index_1based: u32,
    pressure_hpa: f64,
    temperature_k: f64,
    weak_line_sigma_cm2_per_molecule: f64,
    strong_line_sigma_cm2_per_molecule: f64,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValues ------------------------------------------------------------------------------------------|
// Owner for wavelength-major layer-node rows and support-profile total-sigma columns.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] values                    : []ProfileLineValue                                                     |
// [16..31] support_profile_total_sigma_cm2_per_molecule: []f64                                                |
// [32..39] wavelength_count          : usize                                                                  |
// [40..47] profile_node_count        : usize                                                                  |
// [48..55] support_profile_node_count: usize                                                                  |
// [56..63] reuse_stamp               : ReuseStamp                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   values owns wavelength_count * profile_node_count diagnostic rows. support_profile_total_sigma owns one   |
//   f64 column indexed as wavelength-major, then support-profile node. Root spectrum runs may set             |
//   profile_node_count to zero when diagnostics are not requested; support sigma rows still exist.            |
pub const ProfileLineValues = struct {
    values: []ProfileLineValue = &.{},
    support_profile_total_sigma_cm2_per_molecule: []f64 = &.{},
    wavelength_count: usize = 0,
    profile_node_count: usize = 0,
    support_profile_node_count: usize = 0,
    reuse_stamp: hashing.ReuseStamp = .{},

    pub fn deinit(self: *ProfileLineValues, allocator: Allocator) void {
        // ProfileLineValues.deinit ---------------------------------------------------------------------------|
        // Release exact-route profile-line rows owned by this memory object.                                  |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.support_profile_total_sigma_cm2_per_molecule);
        allocator.free(self.values);
        self.* = .{};
    }

    pub fn supportProfileTotalSigmaAt(
        self: ProfileLineValues,
        wavelength_index: usize,
        profile_node_index: usize,
    ) ?f64 {
        // ProfileLineValues.supportProfileTotalSigmaAt -------------------------------------------------------|
        // Return one retained support-profile sigma from the dense f64 column.                                |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count or
            profile_node_index >= self.support_profile_node_count)
        {
            return null;
        }
        return self.support_profile_total_sigma_cm2_per_molecule[
            wavelength_index * self.support_profile_node_count + profile_node_index
        ];
    }

    pub fn fillSupportLineSigmaAtWavelengthIndex(
        self: ProfileLineValues,
        layer_grid: atmosphere_layers.LayerGrid,
        wavelength_index: usize,
        out_sigma_cm2_per_molecule: []f64,
        stage_cost: ?CostTiming.Active,
    ) !void {
        // ProfileLineValues.fillSupportLineSigmaAtWavelengthIndex --------------------------------------------|
        // Sample retained canonical sigma_total profile rows onto the setup support grid.                     |
        //                                                                                                     |
        //   The line list has already been evaluated into the support-profile total-sigma column; this helper |
        //   only prepares endpoint-secant spline curvature and samples it by support altitude.                |
        //                                                                                                     |
        // memory                                                                                              |
        //   Uses fixed stack rows capped at max_spectroscopy_profile_nodes and writes caller-owned support    |
        //   sigma storage. It allocates nothing inside the per-wavelength solve.                              |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count) return error.InvalidShape;
        if (out_sigma_cm2_per_molecule.len != layer_grid.support_mid_altitudes_km.len) return error.InvalidShape;

        const node_count = self.support_profile_node_count;
        if (node_count < 3 or node_count > max_spectroscopy_profile_nodes) return error.InvalidShape;
        if (layer_grid.spectroscopy_profile.rows.len != node_count) return error.InvalidShape;

        const timing_start = CostTiming.start(stage_cost);
        defer CostTiming.finish(stage_cost, timing_start, "profile_interp");

        const start = wavelength_index * node_count;
        const total_column = self.support_profile_total_sigma_cm2_per_molecule[start .. start + node_count];
        var altitudes_km: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_values: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_second: [max_spectroscopy_profile_nodes]f64 = undefined;

        for (layer_grid.spectroscopy_profile.rows, total_column, 0..) |profile_row, total_sigma, profile_node_index| {
            altitudes_km[profile_node_index] = profile_row.altitude_km;
            total_values[profile_node_index] = total_sigma;
        }

        const altitudes = altitudes_km[0..node_count];
        spline.endpointSecantSecondDerivatives(
            altitudes,
            total_values[0..node_count],
            total_second[0..node_count],
        ) catch return error.InvalidShape;

        for (out_sigma_cm2_per_molecule, layer_grid.support_mid_altitudes_km) |*sigma, altitude_km| {
            sigma.* = @max(
                spline.sampleWithSecondDerivatives(
                    altitudes,
                    total_values[0..node_count],
                    total_second[0..node_count],
                    altitude_km,
                ) catch return error.InvalidShape,
                0.0,
            );
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildProfileLineValues(
    allocator: Allocator,
    scene: scene_input.Scene,
) !ProfileLineValues {
    // buildProfileLineValues ---------------------------------------------------------------------------------|
    // Build line values over the case's evenly spaced setup wavelengths.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_count = scene.spectral_grid.sample_count;
    const wavelengths_nm = try allocator.alloc(f64, wavelength_count);
    defer allocator.free(wavelengths_nm);

    const step_nm = if (wavelength_count > 1)
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / @as(f64, @floatFromInt(wavelength_count - 1))
    else
        0.0;

    for (wavelengths_nm, 0..) |*wavelength_nm, wavelength_index| {
        wavelength_nm.* = scene.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(wavelength_index));
    }

    return buildProfileLineValuesForWavelengths(allocator, scene, wavelengths_nm);
}

pub fn buildProfileLineValuesForWavelengths(
    allocator: Allocator,
    scene: scene_input.Scene,
    wavelengths_nm: []const f64,
) !ProfileLineValues {
    // buildProfileLineValuesForWavelengths -------------------------------------------------------------------|
    // Build retained line values with the scalar weak-line cutoff fallback used by canonical setup tests.     |
    // --------------------------------------------------------------------------------------------------------|
    return buildProfileLineValuesForWavelengthsWithCutoffGrid(
        allocator,
        scene,
        wavelengths_nm,
        &.{},
        true,
        true,
        null,
        preferredProfileLineWorkerCount(wavelengths_nm.len),
        &.{},
    );
}

pub fn buildProfileLineValuesForWavelengthsWithCutoffGrid(
    allocator: Allocator,
    scene: scene_input.Scene,
    wavelengths_nm: []const f64,
    cutoff_grid_wavelengths_nm: []const f64,
    build_layer_values: bool,
    include_temperature_derivatives: bool,
    pool: ?*std.Thread.Pool,
    worker_count: usize,
    cost_timing_active: []const ?CostTiming.Active,
) !ProfileLineValues {
    // buildProfileLineValuesForWavelengthsWithCutoffGrid -----------------------------------------------------|
    // Build retained line values over a caller-provided exact wavelength list.                                |
    //                                                                                                         |
    //   the exact radiance wavelengths selected by `spectrum/radiance_wavelengths.zig` instead of assuming    |
    //   a uniform public product grid.                                                                        |
    //                                                                                                         |
    // row contract                                                                                            |
    //   Output rows stay wavelength-major and preserve the input wavelength order exactly. Dense spectrum     |
    //   prefetch can therefore use its `RadianceWavelengthList` index as the ProfileLineValues index.         |
    //   `build_layer_values` keeps the O2 A diagnostic layer rows for evidence paths. The public spectrum     |
    //   route uses only support-profile total sigma, so root skips preparing unused layer rows.               |
    // --------------------------------------------------------------------------------------------------------|
    var build_arena = std.heap.ArenaAllocator.init(allocator);
    defer build_arena.deinit();
    const scratch_allocator = build_arena.allocator();

    const layers = try atmosphere_layers.build(scratch_allocator, scene);
    const lines = try line_tables.build(scratch_allocator, scene);

    const wavelength_count = wavelengths_nm.len;
    const profile_node_count = if (build_layer_values) layers.layer_pressures_hpa.len else 0;
    const support_profile_node_count = layers.spectroscopy_profile.rows.len;
    const values = try allocator.alloc(ProfileLineValue, wavelength_count * profile_node_count);
    errdefer allocator.free(values);
    const support_profile_total_sigma = try allocator.alloc(f64, wavelength_count * support_profile_node_count);
    errdefer allocator.free(support_profile_total_sigma);

    const cutoff_grid = try prepareCutoffGrid(scratch_allocator, cutoff_grid_wavelengths_nm);
    const runtime = RuntimeControls{
        .cutoff_cm1 = lines.cutoff_sim_cm1,
        .line_mixing_factor = lines.line_mixing_factor,
        .cutoff_grid_wavelengths_nm = cutoff_grid.wavelengths_nm,
        .cutoff_grid_wavenumbers_cm1 = cutoff_grid.wavenumbers_cm1,
    };
    const total_lines = try collectRuntimeLines(scratch_allocator, lines.rows, lines.isotopes_sim);

    const strong_sidecars = chooseStrongLineSidecars(lines);

    var active_lines: []readers.LineAssetRow = &.{};
    var weak_states: []WeakLinePreparedState = &.{};
    var total_weak_states: []WeakLinePreparedState = &.{};
    var strong_states: []StrongLinePreparedState = &.{};

    if (build_layer_values) {
        const line_strength_threshold = thresholdStrength(lines.rows, lines.threshold_line_sim);
        active_lines = try collectActiveLines(
            scratch_allocator,
            lines.rows,
            lines.isotopes_sim,
            line_strength_threshold,
        );
        weak_states = try prepareLayerWeakLineStates(
            scratch_allocator,
            active_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            0.0,
            cost_timing_active,
        );
        total_weak_states = try prepareLayerWeakLineStates(
            scratch_allocator,
            total_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            0.0,
            cost_timing_active,
        );
        strong_states = try prepareLayerStrongLineStates(
            scratch_allocator,
            strong_sidecars.lines,
            strong_sidecars.relaxation_matrix,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            cost_timing_active,
        );
    }

    // The canonical temperature derivative is a centered finite difference at T +/- 0.5 K. The public O2 A
    // Jacobian states are surface/aerosol controls, so root spectrum runs do not read d_sigma/dT and skip
    // these two full weak-line state families. Explicit profile-line canonical builders still request the rows
    // directly, and the reuse stamp records the choice so mismatched session caches cannot mix.
    var upper_weak_states: []WeakLinePreparedState = &.{};
    var lower_weak_states: []WeakLinePreparedState = &.{};
    if (build_layer_values and include_temperature_derivatives) {
        upper_weak_states = try prepareLayerWeakLineStates(
            scratch_allocator,
            active_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            0.5,
            cost_timing_active,
        );
        lower_weak_states = try prepareLayerWeakLineStates(
            scratch_allocator,
            active_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            -0.5,
            cost_timing_active,
        );
    }
    const support_total_weak_states = try prepareProfileWeakLineStates(
        scratch_allocator,
        total_lines,
        layers.spectroscopy_profile.rows,
        cost_timing_active,
    );
    const support_strong_states = try prepareProfileStrongLineStates(
        scratch_allocator,
        strong_sidecars.lines,
        strong_sidecars.relaxation_matrix,
        layers.spectroscopy_profile.rows,
        cost_timing_active,
    );

    try buildProfileLineValuesByWavelength(
        pool,
        worker_count,
        wavelengths_nm,
        layers,
        strong_sidecars.lines,
        strong_sidecars.relaxation_matrix,
        runtime,
        build_layer_values and include_temperature_derivatives,
        active_lines,
        total_lines,
        weak_states,
        upper_weak_states,
        lower_weak_states,
        total_weak_states,
        support_total_weak_states,
        strong_states,
        support_strong_states,
        values,
        support_profile_total_sigma,
        cost_timing_active,
    );

    return .{
        .values = values,
        .support_profile_total_sigma_cm2_per_molecule = support_profile_total_sigma,
        .wavelength_count = wavelength_count,
        .profile_node_count = profile_node_count,
        .support_profile_node_count = support_profile_node_count,
        .reuse_stamp = profileLineReuseStamp(
            scene.id,
            lines,
            layers.spectroscopy_profile.rows,
            wavelengths_nm,
            build_layer_values,
            include_temperature_derivatives,
        ),
    };
}

// ProfileLineBuildWorker -------------------------------------------------------------------------------------|
// Site-local worker row for wavelength-major profile-line value construction.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// This row is not size-pinned because it carries many borrowed slice descriptors and only lives on the build  |
// stack. No field owns heap storage; every output write is to a disjoint wavelength-major row range.          |
//                                                                                                             |
// memory groups                                                                                               |
//   inputs     : exact wavelengths, layer/support thermodynamic rows, HITRAN/strong-line tables, runtime      |
//   prepared   : weak-line and strong-line states prepared before workers start                               |
//   outputs    : wavelength-major layer rows and spectroscopy-profile support rows                            |
//   scheduling : static range, worker index                                                                   |
const ProfileLineBuildWorker = struct {
    wavelengths_nm: []const f64,
    layer_pressures_hpa: []const f64,
    layer_temperatures_k: []const f64,
    layer_interval_indices_1based: []const u32,
    support_profile_rows: []const readers.AtmosphereProfileRow,
    runtime: RuntimeControls,
    include_temperature_derivatives: bool,
    active_lines: []const readers.LineAssetRow,
    total_lines: []const readers.LineAssetRow,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    weak_states: []const WeakLinePreparedState,
    upper_weak_states: []const WeakLinePreparedState,
    lower_weak_states: []const WeakLinePreparedState,
    total_weak_states: []const WeakLinePreparedState,
    support_total_weak_states: []const WeakLinePreparedState,
    strong_states: []const StrongLinePreparedState,
    support_strong_states: []const StrongLinePreparedState,
    values: []ProfileLineValue,
    support_profile_total_sigma_cm2_per_molecule: []f64,
    start_index: usize,
    end_index: usize,
    worker_index: usize = 0,
    cost_timing_active: []const ?CostTiming.Active,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineStateWorker -------------------------------------------------------------------------------------|
// Site-local raw worker row for profile-node weak/strong line-state preparation.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// This worker row is not size-pinned because it carries borrowed slices plus a relaxation-matrix view.        |
// Workers perform no allocation; the caller allocates output row storage before launch and deinitializes it   |
// after the later spectroscopy-value phase.                                                                   |
//                                                                                                             |
// memory groups                                                                                               |
//   inputs     : thermodynamic node rows and parsed weak/strong-line tables                                   |
//   outputs    : optional weak-line and strong-line prepared states, indexed by profile node                  |
//   scheduling : shared chunk queue, worker index                                                             |
const ProfileLineStateWorker = struct {
    lines: []const readers.LineAssetRow,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64 = 0.0,
    weak_states: ?[]WeakLinePreparedState = null,
    strong_states: ?[]StrongLinePreparedState = null,
    queue: *worker_partition.ChunkQueue,
    worker_index: usize,
    cost_timing_active: []const ?CostTiming.Active,
};
// ------------------------------------------------------------------------------------------------------------|

fn costTimingForWorker(
    cost_timing_active: []const ?CostTiming.Active,
    worker_index: usize,
) ?CostTiming.Active {
    // costTimingForWorker ------------------------------------------------------------------------------------|
    // Borrow the caller-supplied per-worker cost row when this worker group maps to one.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (worker_index >= cost_timing_active.len) return null;
    return cost_timing_active[worker_index];
}

fn buildProfileLineValuesByWavelength(
    pool: ?*std.Thread.Pool,
    worker_count: usize,
    wavelengths_nm: []const f64,
    layers: atmosphere_layers.LayerGrid,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    runtime: RuntimeControls,
    include_temperature_derivatives: bool,
    active_lines: []const readers.LineAssetRow,
    total_lines: []const readers.LineAssetRow,
    weak_states: []const WeakLinePreparedState,
    upper_weak_states: []const WeakLinePreparedState,
    lower_weak_states: []const WeakLinePreparedState,
    total_weak_states: []const WeakLinePreparedState,
    support_total_weak_states: []const WeakLinePreparedState,
    strong_states: []const StrongLinePreparedState,
    support_strong_states: []const StrongLinePreparedState,
    values: []ProfileLineValue,
    support_profile_total_sigma_cm2_per_molecule: []f64,
    cost_timing_active: []const ?CostTiming.Active,
) !void {
    // buildProfileLineValuesByWavelength ---------------------------------------------------------------------|
    // Fill retained profile-line values over exact wavelengths, partitioned exactly like the profile          |
    // spectroscopy cache build: threshold 32, static worker ranges, chunk size 8, and optional session pool.  |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   `profile_spectroscopy_cache.build` measures this whole setup phase. Worker and chunk zones live in    |
    //   `profileLineBuildWorkerMain` and retain the trace names for profile-cache construction.               |
    // --------------------------------------------------------------------------------------------------------|
    if (worker_count == 0 or worker_count > worker_partition.max_workers) return error.InvalidShape;
    if (wavelengths_nm.len == 0) return;

    const profile_node_count = if (values.len != 0) layers.layer_pressures_hpa.len else 0;
    const support_profile_node_count = layers.spectroscopy_profile.rows.len;
    if (values.len != wavelengths_nm.len * profile_node_count) return error.InvalidShape;
    if (support_profile_total_sigma_cm2_per_molecule.len != wavelengths_nm.len * support_profile_node_count) {
        return error.InvalidShape;
    }

    // instrumentation: trace zone: profile spectroscopy cache build ----------------------------------------- |
    // captures: profile-line cache build wall time and exact-wavelength count                                 |
    // why: shows setup cost that O2 A compares before forward prefetch starts.                                |
    const zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.build");
    zone.value(@intCast(wavelengths_nm.len));
    defer zone.end();
    // end instrumentation: trace zone: profile spectroscopy cache build ------------------------------------- |

    var worker_storage: [worker_partition.max_workers]ProfileLineBuildWorker = undefined;
    for (0..worker_count) |worker_index| {
        const range = worker_partition.staticRange(wavelengths_nm.len, worker_count, worker_index);
        worker_storage[worker_index] = .{
            .wavelengths_nm = wavelengths_nm,
            .layer_pressures_hpa = layers.layer_pressures_hpa,
            .layer_temperatures_k = layers.layer_temperatures_k,
            .layer_interval_indices_1based = layers.layer_interval_indices_1based,
            .support_profile_rows = layers.spectroscopy_profile.rows,
            .runtime = runtime,
            .include_temperature_derivatives = include_temperature_derivatives,
            .active_lines = active_lines,
            .total_lines = total_lines,
            .strong_lines = strong_lines,
            .relaxation_matrix = relaxation_matrix,
            .weak_states = weak_states,
            .upper_weak_states = upper_weak_states,
            .lower_weak_states = lower_weak_states,
            .total_weak_states = total_weak_states,
            .support_total_weak_states = support_total_weak_states,
            .strong_states = strong_states,
            .support_strong_states = support_strong_states,
            .values = values,
            .support_profile_total_sigma_cm2_per_molecule = support_profile_total_sigma_cm2_per_molecule,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
            .cost_timing_active = cost_timing_active,
        };
    }

    worker_partition.runWorkers(pool, worker_storage[0..worker_count], profileLineBuildWorkerMain);
}

fn profileLineBuildWorkerMain(worker: *ProfileLineBuildWorker) void {
    // profileLineBuildWorkerMain -----------------------------------------------------------------------------|
    // Fill one worker-owned range of wavelength-major profile-line rows.                                      |
    // --------------------------------------------------------------------------------------------------------|
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-profile-cache-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-profile-cache";

    // instrumentation: trace thread label: profile spectroscopy cache worker -------------------------------- |
    // captures: profile-line build worker identity                                                            |
    // why: makes parallel profile-cache lanes separable in timeline traces.                                   |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: profile spectroscopy cache worker ---------------------------- |

    // instrumentation: trace zone: profile spectroscopy cache worker ---------------------------------------- |
    // captures: worker wall time for retained profile-line value construction                                 |
    // why: exposes load balance across exact-wavelength profile-cache ranges.                                 |
    const worker_zone = Trace.staticZone(@src(), "profile_spectroscopy_cache.worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();
    // end instrumentation: trace zone: profile spectroscopy cache worker ------------------------------------ |

    var chunk_start = worker.start_index;
    while (worker_partition.nextStaticChunk(
        &chunk_start,
        worker.end_index,
        profile_cache_build_chunk_size,
    )) |chunk| {

        // instrumentation: trace zone: profile spectroscopy cache build chunk --------------------------------|
        // captures: chunk wall time and exact-wavelength row count                                            |
        // why: preserves the chunk boundary while showing uneven wavelength-window costs.                     |
        const chunk_zone = Trace.deepStaticZone(@src(), "profile_spectroscopy_cache.build");
        chunk_zone.value(@intCast(chunk.len()));
        defer chunk_zone.end();
        // end instrumentation: trace zone: profile spectroscopy cache build chunk ----------------------------|

        for (chunk.start..chunk.end) |wavelength_index| {
            if (worker.values.len != 0) fillProfileLineValueRowsAtWavelength(worker, wavelength_index);
            fillSupportProfileLineValueRowsAtWavelength(worker, wavelength_index);
        }
    }
}

fn fillProfileLineValueRowsAtWavelength(worker: *ProfileLineBuildWorker, wavelength_index: usize) void {
    // fillProfileLineValueRowsAtWavelength -------------------------------------------------------------------|
    // Fill all layer-node line-value rows for one exact wavelength.                                           |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_nm = worker.wavelengths_nm[wavelength_index];
    const active_window = line_physics.relevantLineWindow(
        worker.active_lines,
        wavelength_nm,
        worker.runtime.cutoff_cm1,
    );
    const total_window = line_physics.relevantLineWindow(worker.total_lines, wavelength_nm, worker.runtime.cutoff_cm1);
    const wavelength_state = line_physics.prepareWeakLineWavelengthState(
        wavelength_nm,
        worker.runtime.cutoff_grid_wavelengths_nm,
        worker.runtime.cutoff_grid_wavenumbers_cm1,
    );
    const stage_cost = costTimingForWorker(worker.cost_timing_active, worker.worker_index);
    for (worker.layer_pressures_hpa, worker.layer_temperatures_k, 0..) |pressure_hpa, temperature_k, node_index| {
        const sigma = line_physics.weakLineSigmaAtPrepared(
            worker.active_lines,
            active_window,
            &worker.weak_states[node_index],
            wavelength_state,
            worker.runtime.cutoff_cm1,
            worker.runtime.cutoff_grid_wavelengths_nm,
            worker.runtime.cutoff_grid_wavenumbers_cm1,
        );

        var d_sigma_d_temperature: f64 = 0.0;
        if (worker.include_temperature_derivatives) {
            const upper_sigma = line_physics.weakLineSigmaAtPreparedFiniteDifference(
                worker.active_lines,
                active_window,
                &worker.upper_weak_states[node_index],
                wavelength_state,
                worker.runtime.cutoff_cm1,
                worker.runtime.cutoff_grid_wavelengths_nm,
                worker.runtime.cutoff_grid_wavenumbers_cm1,
            );
            const lower_sigma = line_physics.weakLineSigmaAtPreparedFiniteDifference(
                worker.active_lines,
                active_window,
                &worker.lower_weak_states[node_index],
                wavelength_state,
                worker.runtime.cutoff_cm1,
                worker.runtime.cutoff_grid_wavelengths_nm,
                worker.runtime.cutoff_grid_wavenumbers_cm1,
            );
            d_sigma_d_temperature = (upper_sigma - lower_sigma) / 1.0;
        }

        const total = line_physics.totalSpectroscopyAt(
            worker.total_lines,
            total_window,
            worker.strong_lines,
            worker.relaxation_matrix,
            wavelength_nm,
            wavelength_state,
            temperature_k,
            pressure_hpa,
            worker.runtime.cutoff_cm1,
            worker.runtime.cutoff_grid_wavelengths_nm,
            worker.runtime.cutoff_grid_wavenumbers_cm1,
            worker.runtime.line_mixing_factor,
            &worker.strong_states[node_index],
            &worker.total_weak_states[node_index],
            stage_cost,
        );
        const row_index = wavelength_index * worker.layer_pressures_hpa.len + node_index;
        worker.values[row_index] = .{
            .wavelength_nm = wavelength_nm,
            .layer_index = @intCast(node_index),
            .interval_index_1based = worker.layer_interval_indices_1based[node_index],
            .pressure_hpa = pressure_hpa,
            .temperature_k = temperature_k,
            .weak_line_sigma_cm2_per_molecule = sigma,
            .strong_line_sigma_cm2_per_molecule = total.strong_line_sigma_cm2_per_molecule,
            .line_sigma_cm2_per_molecule = total.line_sigma_cm2_per_molecule,
            .line_mixing_sigma_cm2_per_molecule = total.line_mixing_sigma_cm2_per_molecule,
            .total_sigma_cm2_per_molecule = total.total_sigma_cm2_per_molecule,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = d_sigma_d_temperature,
        };
    }
}

fn fillSupportProfileLineValueRowsAtWavelength(worker: *ProfileLineBuildWorker, wavelength_index: usize) void {
    // fillSupportProfileLineValueRowsAtWavelength ------------------------------------------------------------|
    // Fill all spectroscopy-profile support rows for one exact wavelength.                                    |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_nm = worker.wavelengths_nm[wavelength_index];
    const total_window = line_physics.relevantLineWindow(worker.total_lines, wavelength_nm, worker.runtime.cutoff_cm1);
    const wavelength_state = line_physics.prepareWeakLineWavelengthState(
        wavelength_nm,
        worker.runtime.cutoff_grid_wavelengths_nm,
        worker.runtime.cutoff_grid_wavenumbers_cm1,
    );
    const stage_cost = costTimingForWorker(worker.cost_timing_active, worker.worker_index);
    for (worker.support_profile_rows, 0..) |profile_row, node_index| {
        const total = line_physics.totalSpectroscopyAt(
            worker.total_lines,
            total_window,
            worker.strong_lines,
            worker.relaxation_matrix,
            wavelength_nm,
            wavelength_state,
            profile_row.temperature_k,
            profile_row.pressure_hpa,
            worker.runtime.cutoff_cm1,
            worker.runtime.cutoff_grid_wavelengths_nm,
            worker.runtime.cutoff_grid_wavenumbers_cm1,
            worker.runtime.line_mixing_factor,
            &worker.support_strong_states[node_index],
            &worker.support_total_weak_states[node_index],
            stage_cost,
        );
        const row_index = wavelength_index * worker.support_profile_rows.len + node_index;
        worker.support_profile_total_sigma_cm2_per_molecule[row_index] = total.total_sigma_cm2_per_molecule;
    }
}

fn preferredProfileLineWorkerCount(wavelength_count: usize) usize {
    // preferredProfileLineWorkerCount ------------------------------------------------------------------------|
    // Resolve the profile-cache build worker-count policy for retained exact-wavelength spectroscopy.         |
    // --------------------------------------------------------------------------------------------------------|
    return worker_partition.preferredWorkerCount(
        wavelength_count,
        min_parallel_profile_cache_build_count,
    );
}

fn preferredProfileLineStateWorkerCount(profile_count: usize) usize {
    // preferredProfileLineStateWorkerCount -------------------------------------------------------------------|
    // Resolve the thermodynamic profile-line state worker-count policy.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return worker_partition.preferredWorkerCount(
        profile_count,
        min_parallel_profile_line_state_count,
    );
}

pub fn profileLineReuseStamp(
    scene_id: []const u8,
    lines: line_tables.LineTable,
    spectroscopy_profile_rows: []const readers.AtmosphereProfileRow,
    wavelengths_nm: []const f64,
    build_layer_values: bool,
    include_temperature_derivatives: bool,
) hashing.ReuseStamp {
    // profileLineReuseStamp ----------------------------------------------------------------------------------|
    // Hash only session-fixed inputs: scene identity, exact wavelengths, the parsed line assets, and the      |
    // spectroscopy-profile thermodynamics. Do not hash LayerGrid support rows: profile-line values sit at     |
    // fixed spectroscopy nodes and are resampled per pressure state downstream, so hashing support placement  |
    // would defeat reuse across the pressure changes optimal estimation makes each iteration.                 |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(scene_id);
    hashF64Slice(&hasher, wavelengths_nm);
    hashLineInputs(&hasher, lines);
    hashAtmosphereRows(&hasher, spectroscopy_profile_rows);
    hashing.updateBool(&hasher, build_layer_values);
    hashing.updateBool(&hasher, include_temperature_derivatives);
    return .{ .value = hasher.final() };
}

fn hashLineInputs(hasher: *std.hash.Wyhash, lines: line_tables.LineTable) void {
    // hashLineInputs -----------------------------------------------------------------------------------------|
    // Hash parsed line assets and runtime line-filter controls without reading struct padding bytes.          |
    // --------------------------------------------------------------------------------------------------------|
    hashLineRows(hasher, lines.rows);
    hashStrongLineRows(hasher, lines.strong_lines);
    hashRelaxationMatrix(hasher, lines.relaxation_matrix);
    hashing.updateValue(hasher, lines.isotopes_sim.len);
    hasher.update(lines.isotopes_sim);
    hashing.updateValue(hasher, lines.threshold_line_sim);
    hashing.updateValue(hasher, lines.cutoff_sim_cm1);
    hashing.updateValue(hasher, lines.line_mixing_factor);
}

fn hashLineRows(hasher: *std.hash.Wyhash, rows: []const readers.LineAssetRow) void {
    // hashLineRows -------------------------------------------------------------------------------------------|
    // Hash one HITRAN row family field-by-field so optional metadata participates in cache identity.          |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, rows.len);
    for (rows) |row| {
        hashing.updateValue(hasher, row.gas_index);
        hashing.updateValue(hasher, row.isotope_number);
        hashing.updateBool(hasher, row.vendor_filter_metadata_from_source);
        for ([_]f64{
            row.center_wavelength_nm,
            row.center_wavenumber_cm1,
            row.line_strength_cm2_per_molecule,
            row.air_half_width_cm1,
            row.lower_state_energy_cm1,
            row.temperature_exponent,
            row.pressure_shift_cm1,
        }) |value| hashing.updateValue(hasher, value);
        hashOptionalU8(hasher, row.branch_ic1);
        hashOptionalU8(hasher, row.branch_ic2);
        hashOptionalU8(hasher, row.rotational_nf);
    }
}

fn hashStrongLineRows(hasher: *std.hash.Wyhash, rows: []const readers.StrongLineAssetRow) void {
    // hashStrongLineRows -------------------------------------------------------------------------------------|
    // Hash LISA SDF sidecar rows that can contribute to strong-line and line-mixing sigma.                    |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, rows.len);
    for (rows) |row| {
        for ([_]f64{
            row.center_wavenumber_cm1,
            row.center_wavelength_nm,
            row.population_t0,
            row.dipole_ratio,
            row.dipole_t0,
            row.lower_state_energy_cm1,
            row.air_half_width_cm1,
            row.air_half_width_nm,
            row.temperature_exponent,
            row.pressure_shift_cm1,
            row.pressure_shift_nm,
        }) |value| hashing.updateValue(hasher, value);
        hashing.updateValue(hasher, row.rotational_index_m1);
    }
}

fn hashRelaxationMatrix(hasher: *std.hash.Wyhash, matrix: readers.RelaxationMatrixAsset) void {
    // hashRelaxationMatrix -----------------------------------------------------------------------------------|
    // Hash the dense LISA RMF matrices and their square dimension.                                            |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, matrix.line_count);
    hashF64Slice(hasher, matrix.wt0);
    hashF64Slice(hasher, matrix.bw);
}

fn hashAtmosphereRows(hasher: *std.hash.Wyhash, rows: []const readers.AtmosphereProfileRow) void {
    // hashAtmosphereRows -------------------------------------------------------------------------------------|
    // Hash spectroscopy-profile thermodynamics used by support-profile sigma rows.                            |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, rows.len);
    for (rows) |row| {
        for ([_]f64{
            row.altitude_km,
            row.pressure_hpa,
            row.temperature_k,
            row.air_number_density_cm3,
        }) |value| hashing.updateValue(hasher, value);
    }
}

fn hashF64Slice(hasher: *std.hash.Wyhash, values: []const f64) void {
    // hashF64Slice -------------------------------------------------------------------------------------------|
    // Hash an f64 slice with its length so empty and repeated-prefix rows stay distinct.                      |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, values.len);
    hasher.update(std.mem.sliceAsBytes(values));
}

fn hashOptionalU8(hasher: *std.hash.Wyhash, value: ?u8) void {
    // hashOptionalU8 -----------------------------------------------------------------------------------------|
    // Hash optional compact metadata with explicit presence.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateBool(hasher, value != null);
    if (value) |resolved| hashing.updateValue(hasher, resolved);
}

fn prepareCutoffGrid(allocator: Allocator, support_wavelengths_nm: []const f64) !CutoffGrid {
    // prepareCutoffGrid --------------------------------------------------------------------------------------|
    // Sort and merge the realized weak-line support grid before computing matching wavenumbers.               |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    if (support_wavelengths_nm.len < 2) return .{};

    const wavelengths = try allocator.dupe(f64, support_wavelengths_nm);
    errdefer allocator.free(wavelengths);
    std.mem.sort(f64, wavelengths, {}, lessThanF64);

    var merged_count: usize = 0;
    for (wavelengths) |wavelength_nm| {
        if (merged_count != 0 and
            @abs(wavelengths[merged_count - 1] - wavelength_nm) <= cutoff_grid_merge_tolerance_nm)
        {
            continue;
        }
        wavelengths[merged_count] = wavelength_nm;
        merged_count += 1;
    }

    const merged_wavelengths = try allocator.realloc(wavelengths, merged_count);
    errdefer allocator.free(merged_wavelengths);
    const wavenumbers = try allocator.alloc(f64, merged_count);
    errdefer allocator.free(wavenumbers);
    for (merged_wavelengths, wavenumbers) |wavelength_nm, *wavenumber_cm1| {
        wavenumber_cm1.* = line_physics.wavelengthToWavenumberCm1(wavelength_nm);
    }
    return .{ .wavelengths_nm = merged_wavelengths, .wavenumbers_cm1 = wavenumbers };
}

fn lessThanF64(_: void, lhs: f64, rhs: f64) bool {
    // lessThanF64 --------------------------------------------------------------------------------------------|
    // Sort finite support wavelengths in ascending wavelength order for cutoff-grid index searches.           |
    // --------------------------------------------------------------------------------------------------------|
    return lhs < rhs;
}

fn chooseStrongLineSidecars(lines: line_tables.LineTable) StrongLineSidecars {
    // chooseStrongLineSidecars -------------------------------------------------------------------------------|
    // Use LISA strong-line sidecars only for isotope-1 O2 rows.                                               |
    // --------------------------------------------------------------------------------------------------------|
    if (isotopeOneActive(lines.isotopes_sim)) {
        return .{
            .lines = lines.strong_lines,
            .relaxation_matrix = lines.relaxation_matrix,
        };
    }

    return .{
        .lines = &.{},
        .relaxation_matrix = emptyRelaxationMatrix(),
    };
}

// RuntimeControls --------------------------------------------------------------------------------------------|
// Borrowed line-list controls needed by weak-line setup evaluation.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] cutoff_cm1               : f64                                                                     |
// [ 8..15] line_mixing_factor       : f64                                                                     |
// [16..31] cutoff_grid_wavelengths_nm : []const f64                                                           |
// [32..47] cutoff_grid_wavenumbers_cm1: []const f64                                                           |
const RuntimeControls = struct {
    cutoff_cm1: f64,
    line_mixing_factor: f64,
    cutoff_grid_wavelengths_nm: []const f64 = &.{},
    cutoff_grid_wavenumbers_cm1: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

const StrongLineSidecars = struct {
    lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
};
// ------------------------------------------------------------------------------------------------------------|

// CutoffGrid -------------------------------------------------------------------------------------------------|
// Owned weak-line cutoff support grid used during setup-time line evaluation.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelengths_nm : []f64                                                                             |
// [16..31] wavenumbers_cm1: []f64                                                                             |
const CutoffGrid = struct {
    wavelengths_nm: []f64 = &.{},
    wavenumbers_cm1: []f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// StrongLinePreparedState ------------------------------------------------------------------------------------|
// Fixed-capacity O2 strong-line ConvTP state prepared for one profile-node thermodynamic point.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 5136 B (5.016 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..   7] line_count               : usize                                                               |
// [   8..  15] sig_moy_cm1              : f64                                                                 |
// [  16..1039] population_t             : [128]f64                                                            |
// [1040..2063] dipole_t                 : [128]f64                                                            |
// [2064..3087] mod_sig_cm1              : [128]f64                                                            |
// [3088..4111] half_width_cm1_at_t      : [128]f64                                                            |
// [4112..5135] line_mixing_coefficients : [128]f64                                                            |
const StrongLinePreparedState = line_physics.StrongLinePreparedState;
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedLineState ----------------------------------------------------------------------------------|
// Per-line weak-lane constants prepared for one temperature and pressure.                                     |
//                                                                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] shifted_center_wavenumber_cm1 : f64                                                                |
// [ 8..15] cte                            : f64                                                               |
// [16..23] line_shape_y                   : f64                                                               |
// [24..31] prefactor_base                 : f64                                                               |
const WeakLinePreparedLineState = line_physics.WeakLinePreparedLineState;
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedState --------------------------------------------------------------------------------------|
// Header over weak-line constants prepared for one temperature and pressure.                                  |
//                                                                                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count       : usize                                                                           |
// [ 8..15] safe_temperature : f64                                                                             |
// [16..23] safe_pressure    : f64                                                                             |
// [24..39] lines            : []WeakLinePreparedLineState                                                     |
const WeakLinePreparedState = line_physics.WeakLinePreparedState;
// ------------------------------------------------------------------------------------------------------------|

fn thresholdStrength(lines: []const readers.LineAssetRow, scale: f64) f64 {
    // thresholdStrength --------------------------------------------------------------------------------------|
    // Convert the relative weak-line threshold control into an absolute line-strength floor.                  |
    // --------------------------------------------------------------------------------------------------------|
    var max_strength: f64 = 0.0;
    for (lines) |line| {
        max_strength = @max(max_strength, line.line_strength_cm2_per_molecule);
    }
    return max_strength * scale;
}

fn collectActiveLines(
    allocator: Allocator,
    lines: []const readers.LineAssetRow,
    active_isotopes: []const u8,
    line_strength_threshold: f64,
) ![]readers.LineAssetRow {
    // collectActiveLines -------------------------------------------------------------------------------------|
    // Copy weak-line rows that participate in setup evaluation, sorted for local window scans.                |
    // --------------------------------------------------------------------------------------------------------|
    var active_count: usize = 0;
    for (lines) |line| {
        if (activeLine(line, active_isotopes, line_strength_threshold)) active_count += 1;
    }

    const active_lines = try allocator.alloc(readers.LineAssetRow, active_count);
    errdefer allocator.free(active_lines);

    var active_index: usize = 0;
    for (lines) |line| {
        if (!activeLine(line, active_isotopes, line_strength_threshold)) continue;
        active_lines[active_index] = line;
        active_index += 1;
    }

    std.mem.sort(readers.LineAssetRow, active_lines, {}, lessByCenterWavelength);
    return active_lines;
}

fn collectRuntimeLines(
    allocator: Allocator,
    lines: []const readers.LineAssetRow,
    active_isotopes: []const u8,
) ![]readers.LineAssetRow {
    // collectRuntimeLines ------------------------------------------------------------------------------------|
    // Copy O2 rows that participate in total-sigma evaluation, without applying the weak-line threshold.      |
    // --------------------------------------------------------------------------------------------------------|
    var active_count: usize = 0;
    for (lines) |line| {
        if (runtimeLine(line, active_isotopes)) active_count += 1;
    }

    const active_lines = try allocator.alloc(readers.LineAssetRow, active_count);
    errdefer allocator.free(active_lines);

    var active_index: usize = 0;
    for (lines) |line| {
        if (!runtimeLine(line, active_isotopes)) continue;
        active_lines[active_index] = line;
        active_index += 1;
    }

    std.mem.sort(readers.LineAssetRow, active_lines, {}, lessByCenterWavelength);
    return active_lines;
}

fn lessByCenterWavelength(_: void, lhs: readers.LineAssetRow, rhs: readers.LineAssetRow) bool {
    // lessByCenterWavelength ---------------------------------------------------------------------------------|
    // Order line rows by center wavelength so binary searches can isolate a local HITRAN cutoff window.       |
    // --------------------------------------------------------------------------------------------------------|
    return lhs.center_wavelength_nm < rhs.center_wavelength_nm;
}

fn prepareLayerWeakLineStates(
    allocator: Allocator,
    lines: []const readers.LineAssetRow,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
    cost_timing_active: []const ?CostTiming.Active,
) ![]WeakLinePreparedState {
    // prepareLayerWeakLineStates -----------------------------------------------------------------------------|
    // Prepare one weak-line state per layer profile node for the exact-route setup grid.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (temperatures_k.len != pressures_hpa.len) return error.InvalidShape;
    return prepareWeakLineStatesForRows(
        allocator,
        lines,
        temperatures_k,
        pressures_hpa,
        temperature_offset_k,
        cost_timing_active,
    );
}

fn prepareProfileWeakLineStates(
    allocator: Allocator,
    lines: []const readers.LineAssetRow,
    profile_rows: []const readers.AtmosphereProfileRow,
    cost_timing_active: []const ?CostTiming.Active,
) ![]WeakLinePreparedState {
    // prepareProfileWeakLineStates ---------------------------------------------------------------------------|
    // Prepare one weak-line state per vendor spectroscopy-profile row for support-row interpolation.          |
    // --------------------------------------------------------------------------------------------------------|
    if (profile_rows.len > max_spectroscopy_profile_nodes) return error.InvalidShape;

    var temperatures_k: [max_spectroscopy_profile_nodes]f64 = undefined;
    var pressures_hpa: [max_spectroscopy_profile_nodes]f64 = undefined;
    for (profile_rows, 0..) |profile_row, index| {
        temperatures_k[index] = profile_row.temperature_k;
        pressures_hpa[index] = profile_row.pressure_hpa;
    }

    return prepareWeakLineStatesForRows(
        allocator,
        lines,
        temperatures_k[0..profile_rows.len],
        pressures_hpa[0..profile_rows.len],
        0.0,
        cost_timing_active,
    );
}

fn prepareWeakLineStatesForRows(
    allocator: Allocator,
    lines: []const readers.LineAssetRow,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
    cost_timing_active: []const ?CostTiming.Active,
) ![]WeakLinePreparedState {
    // prepareWeakLineStatesForRows ---------------------------------------------------------------------------|
    // Allocate weak-line row storage serially, then fill thermodynamic state rows through raw worker chunks.  |
    //                                                                                                         |
    // allocation                                                                                              |
    //   Each state owns one per-line slice. Allocation stays on the caller thread because the active          |
    //   allocator may not be thread-safe; workers only write already-owned row storage.                       |
    // --------------------------------------------------------------------------------------------------------|
    if (temperatures_k.len != pressures_hpa.len) return error.InvalidShape;
    const states = try allocator.alloc(WeakLinePreparedState, temperatures_k.len);
    var initialized_count: usize = 0;
    errdefer {
        for (states[0..initialized_count]) |*state| state.deinit(allocator);
        allocator.free(states);
    }

    for (states) |*state| {
        state.* = .{
            .line_count = lines.len,
            .safe_temperature = 0.0,
            .safe_pressure = 0.0,
            .lines = try allocator.alloc(WeakLinePreparedLineState, lines.len),
        };
        initialized_count += 1;
    }

    fillProfileLineStates(
        lines,
        &.{},
        emptyRelaxationMatrix(),
        temperatures_k,
        pressures_hpa,
        temperature_offset_k,
        states,
        null,
        cost_timing_active,
    );
    return states;
}

fn prepareLayerStrongLineStates(
    allocator: Allocator,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    cost_timing_active: []const ?CostTiming.Active,
) ![]StrongLinePreparedState {
    // prepareLayerStrongLineStates ---------------------------------------------------------------------------|
    // Prepare one strong-line ConvTP state per layer profile node through the raw worker policy.              |
    // --------------------------------------------------------------------------------------------------------|
    if (temperatures_k.len != pressures_hpa.len) return error.InvalidShape;

    const states = try allocator.alloc(StrongLinePreparedState, temperatures_k.len);
    errdefer allocator.free(states);
    fillProfileLineStates(
        &.{},
        strong_lines,
        relaxation_matrix,
        temperatures_k,
        pressures_hpa,
        0.0,
        null,
        states,
        cost_timing_active,
    );
    return states;
}

fn prepareProfileStrongLineStates(
    allocator: Allocator,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    profile_rows: []const readers.AtmosphereProfileRow,
    cost_timing_active: []const ?CostTiming.Active,
) ![]StrongLinePreparedState {
    // prepareProfileStrongLineStates -------------------------------------------------------------------------|
    // Prepare one strong-line ConvTP state per spectroscopy-profile row through the raw worker policy.        |
    // --------------------------------------------------------------------------------------------------------|
    if (profile_rows.len > max_spectroscopy_profile_nodes) return error.InvalidShape;

    var temperatures_k: [max_spectroscopy_profile_nodes]f64 = undefined;
    var pressures_hpa: [max_spectroscopy_profile_nodes]f64 = undefined;
    for (profile_rows, 0..) |profile_row, index| {
        temperatures_k[index] = profile_row.temperature_k;
        pressures_hpa[index] = profile_row.pressure_hpa;
    }

    return prepareLayerStrongLineStates(
        allocator,
        strong_lines,
        relaxation_matrix,
        temperatures_k[0..profile_rows.len],
        pressures_hpa[0..profile_rows.len],
        cost_timing_active,
    );
}

fn fillProfileLineStates(
    lines: []const readers.LineAssetRow,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
    weak_states: ?[]WeakLinePreparedState,
    strong_states: ?[]StrongLinePreparedState,
    cost_timing_active: []const ?CostTiming.Active,
) void {
    // fillProfileLineStates ----------------------------------------------------------------------------------|
    // Fill weak and/or strong line states with the profile-line-state worker policy.                          |
    //                                                                                                         |
    // scheduling                                                                                              |
    //   This phase always uses raw spawn mode; the session pool is reserved for forward-miss cache builds.    |
    // --------------------------------------------------------------------------------------------------------|
    const row_count = temperatures_k.len;
    if (row_count == 0) return;
    std.debug.assert(pressures_hpa.len == row_count);
    if (weak_states) |states| std.debug.assert(states.len == row_count);
    if (strong_states) |states| std.debug.assert(states.len == row_count);

    const worker_count = preferredProfileLineStateWorkerCount(row_count);
    var queue = worker_partition.ChunkQueue.init(row_count, profile_line_state_chunk_size);
    var worker_storage: [worker_partition.max_workers]ProfileLineStateWorker = undefined;
    for (0..worker_count) |worker_index| {
        worker_storage[worker_index] = .{
            .lines = lines,
            .strong_lines = strong_lines,
            .relaxation_matrix = relaxation_matrix,
            .temperatures_k = temperatures_k,
            .pressures_hpa = pressures_hpa,
            .temperature_offset_k = temperature_offset_k,
            .weak_states = weak_states,
            .strong_states = strong_states,
            .queue = &queue,
            .worker_index = worker_index,
            .cost_timing_active = cost_timing_active,
        };
    }

    worker_partition.runWorkers(null, worker_storage[0..worker_count], profileLineStateWorkerMain);
}

fn profileLineStateWorkerMain(worker: *ProfileLineStateWorker) void {
    // profileLineStateWorkerMain -----------------------------------------------------------------------------|
    // Fill weak/strong line states for raw-spawn profile-node chunks.                                         |
    // --------------------------------------------------------------------------------------------------------|
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-optics-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-optics";

    // instrumentation: trace thread label: profile line-state worker ---------------------------------------- |
    // captures: profile-line state worker identity                                                            |
    // why: makes parallel thermodynamic-state preparation lanes separable in timeline traces.                 |
    Trace.setThreadName(thread_name);
    // end instrumentation: trace thread label: profile line-state worker ------------------------------------ |

    // instrumentation: trace zone: profile line-state worker ------------------------------------------------ |
    // captures: profile-line state worker wall time                                                           |
    // why: exposes work distribution across thermodynamic profile nodes.                                      |
    const worker_zone = Trace.staticZone(@src(), "optical_prepare.profile_line_state_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();
    // end instrumentation: trace zone: profile line-state worker -------------------------------------------- |

    while (worker.queue.next()) |chunk| {

        // instrumentation: trace zone: profile line-state chunk ----------------------------------------------|
        // captures: profile-line state chunk wall time and row count                                          |
        // why: preserves the chunk boundary for P/T spectroscopy preparation.                                 |
        const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.profile_line_state_chunk");
        chunk_zone.value(@intCast(chunk.len()));
        defer chunk_zone.end();
        // end instrumentation: trace zone: profile line-state chunk ------------------------------------------|

        fillProfileLineStateRows(worker, chunk.start, chunk.end);
    }
}

fn fillProfileLineStateRows(worker: *ProfileLineStateWorker, start: usize, end: usize) void {
    // fillProfileLineStateRows -------------------------------------------------------------------------------|
    // Fill one contiguous thermodynamic profile-node range claimed by the raw worker queue.                   |
    // --------------------------------------------------------------------------------------------------------|
    const stage_cost = costTimingForWorker(worker.cost_timing_active, worker.worker_index);
    for (start..end) |index| {
        const pressure_atm = @max(worker.pressures_hpa[index] / 1013.25, min_spectroscopy_pressure_atm);
        if (worker.weak_states) |states| {
            line_physics.fillWeakLineStateInto(
                &states[index],
                worker.lines,
                @max(worker.temperatures_k[index] + worker.temperature_offset_k, min_hitran_temperature_k),
                pressure_atm,
                stage_cost,
            );
        }
        if (worker.strong_states) |states| {
            states[index] = line_physics.prepareStrongLineState(
                worker.strong_lines,
                worker.relaxation_matrix,
                worker.temperatures_k[index],
                pressure_atm,
                stage_cost,
            );
        }
    }
}

fn emptyRelaxationMatrix() readers.RelaxationMatrixAsset {
    // emptyRelaxationMatrix ----------------------------------------------------------------------------------|
    // Provide an unused, well-formed relaxation-matrix view for weak-only profile-line state workers.         |
    // --------------------------------------------------------------------------------------------------------|
    return .{ .line_count = 0, .wt0 = &.{}, .bw = &.{} };
}

fn activeLine(
    line: readers.LineAssetRow,
    active_isotopes: []const u8,
    line_strength_threshold: f64,
) bool {
    // activeLine ---------------------------------------------------------------------------------------------|
    // Apply the O2 A line-gas isotope and weak-line threshold controls to one parsed HITRAN row.              |
    // --------------------------------------------------------------------------------------------------------|
    if (line.gas_index != 7) return false;

    if (line.line_strength_cm2_per_molecule < line_strength_threshold) return false;

    if (active_isotopes.len == 0) return true;

    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }

    return false;
}

fn runtimeLine(line: readers.LineAssetRow, active_isotopes: []const u8) bool {
    // runtimeLine --------------------------------------------------------------------------------------------|
    // Apply the total-sigma gas/isotope controls without the weak-line threshold filter.                      |
    // --------------------------------------------------------------------------------------------------------|
    if (line.gas_index != 7) return false;

    if (active_isotopes.len == 0) return true;

    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }

    return false;
}

fn isotopeOneActive(active_isotopes: []const u8) bool {
    // isotopeOneActive ---------------------------------------------------------------------------------------|
    // LISA strong-line sidecars are isotope-1 O2 data; disable them when that isotope is not requested.       |
    // --------------------------------------------------------------------------------------------------------|
    for (active_isotopes) |isotope_number| {
        if (isotope_number == 1) return true;
    }
    return false;
}
