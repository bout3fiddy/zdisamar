const std = @import("std");

const readers = @import("../assets/readers.zig");
const hashing = @import("../common/hashing.zig");
const spline = @import("../common/math/spline.zig");
const worker_partition = @import("../common/worker_partition.zig");
const hitran_partition_tables = @import("../input/hitran_partition_tables.zig");
const o2_case = @import("../input/o2_case.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const line_tables = @import("../setup/line_tables.zig");
const Trace = @import("../instrumentation/trace.zig");

const Allocator = std.mem.Allocator;
const hitran_reference_temperature_k = 296.0;
const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
const hitran_hc_over_kb_cm_k = 1.4387770;
const hitran_gas_constant_j_per_mol_k = 8.3144621;
const hitran_speed_of_light_m_per_s = 2.99792458e8;
const hitran_pi = 3.1415926536;
const min_spectroscopy_pressure_atm = 1.0e-12;
const max_strong_line_sidecars: usize = 128;
const max_spectroscopy_profile_nodes: usize = 64;
const cutoff_grid_merge_tolerance_nm = 1.0e-9;
const min_parallel_profile_line_state_count: usize = 4;
const profile_line_state_chunk_size: usize = 2;
const min_parallel_profile_cache_build_count: usize = 32;
const profile_cache_build_chunk_size: usize = 8;

// min_hitran_temperature_k -----------------------------------------------------------------------------------|
// Old provenance: main:`src/input/reference/spectroscopy/physics_core.zig` clamps weak-line temperatures to   |
// 150 K before HITRAN strength scaling. This protects the partition ratio, Boltzmann factor, Doppler width,   |
// and finite-difference derivative from nonphysical low-temperature inputs.                                   |
// ------------------------------------------------------------------------------------------------------------|
const min_hitran_temperature_k = 150.0;

// vendor_cutoff_boundary_margin_cm1 --------------------------------------------------------------------------|
// Old provenance: main:`src/input/reference/spectroscopy/types.zig`. When no DISAMAR high-resolution cutoff   |
// grid is attached, the scalar fallback includes lines whose shifted center is within cutoff_cm1 + 0.115 cm^-1|
// of the evaluation wavenumber.                                                                               |
// ------------------------------------------------------------------------------------------------------------|
const vendor_cutoff_boundary_margin_cm1 = 0.115;

// vendor_cutoff_prewindow_margin_cm1 -------------------------------------------------------------------------|
// Old provenance: main:`src/input/reference/spectroscopy/types.zig`. The sorted line-window prefilter is      |
// wider than the final scalar cutoff by 0.25 cm^-1 so the later pressure-shifted cutoff test cannot lose      |
// endpoint candidates.                                                                                        |
// ------------------------------------------------------------------------------------------------------------|
const vendor_cutoff_prewindow_margin_cm1 = 0.25;

// profile_line_memory.zig ------------------------------------------------------------------------------------|
// Retained weak-line cross-section values for exact setup wavelengths and layer profile nodes.                |
//                                                                                                             |
// setup boundary                                                                                              |
//   WP2 builds a preparation-time line-value grid from the parsed HITRAN rows and the computed layer grid.    |
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

// ProfileSupportLineValue ------------------------------------------------------------------------------------|
// One total-spectroscopy value at a vendor spectroscopy-profile altitude for support-row interpolation.       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                    : f64                                                             |
// [ 8..15] altitude_km                      : f64                                                             |
// [16..23] pressure_hpa                     : f64                                                             |
// [24..31] temperature_k                    : f64                                                             |
// [32..39] line_sigma_cm2_per_molecule      : f64                                                             |
// [40..47] line_mixing_sigma_cm2_per_molecule: f64                                                            |
// [48..55] total_sigma_cm2_per_molecule     : f64                                                             |
// [56..59] profile_node_index               : u32                                                             |
// [60..63] trailing padding                 : 4 B                                                             |
pub const ProfileSupportLineValue = struct {
    wavelength_nm: f64,
    profile_node_index: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValues ------------------------------------------------------------------------------------------|
// Owner for wavelength-major layer-node and spectroscopy-profile line-value grids.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] values                    : []ProfileLineValue                                                     |
// [16..31] support_profile_values    : []ProfileSupportLineValue                                              |
// [32..39] wavelength_count          : usize                                                                  |
// [40..47] profile_node_count        : usize                                                                  |
// [48..55] support_profile_node_count: usize                                                                  |
// [56..63] reuse_stamp               : ReuseStamp                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   values owns wavelength_count * profile_node_count rows. support_profile_values owns                       |
//   wavelength_count * support_profile_node_count rows used to interpolate support-row sigma.                 |
pub const ProfileLineValues = struct {
    values: []ProfileLineValue = &.{},
    support_profile_values: []ProfileSupportLineValue = &.{},
    wavelength_count: usize = 0,
    profile_node_count: usize = 0,
    support_profile_node_count: usize = 0,
    reuse_stamp: hashing.ReuseStamp = .{},

    pub fn deinit(self: *ProfileLineValues, allocator: Allocator) void {
        // ProfileLineValues.deinit ---------------------------------------------------------------------------|
        // Release exact-route profile-line rows owned by this memory object.                                  |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.support_profile_values);
        allocator.free(self.values);
        self.* = .{};
    }

    pub fn row(self: ProfileLineValues, wavelength_index: usize, profile_node_index: usize) ?ProfileLineValue {
        // ProfileLineValues.row ------------------------------------------------------------------------------|
        // Return one wavelength-major row when both indexes are in range.                                     |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count or profile_node_index >= self.profile_node_count) {
            return null;
        }
        return self.values[wavelength_index * self.profile_node_count + profile_node_index];
    }

    pub fn supportProfileRow(
        self: ProfileLineValues,
        wavelength_index: usize,
        profile_node_index: usize,
    ) ?ProfileSupportLineValue {
        // ProfileLineValues.supportProfileRow ----------------------------------------------------------------|
        // Return one spectroscopy-profile row used by support-row interpolation.                              |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_index >= self.wavelength_count or
            profile_node_index >= self.support_profile_node_count)
        {
            return null;
        }
        return self.support_profile_values[
            wavelength_index * self.support_profile_node_count + profile_node_index
        ];
    }

    pub fn fillSupportLineSigmaAtWavelengthIndex(
        self: ProfileLineValues,
        layer_grid: atmosphere_layers.LayerGrid,
        wavelength_index: usize,
        out_sigma_cm2_per_molecule: []f64,
    ) !void {
        // ProfileLineValues.fillSupportLineSigmaAtWavelengthIndex --------------------------------------------|
        // Sample retained old-route sigma_total profile rows onto the setup support grid.                     |
        //                                                                                                     |
        // provenance                                                                                          |
        //   Ports main:`state_build/layer_spectroscopy.zig` profile-cache sampling for the O2 A route.        |
        //   The line list has already been evaluated into support_profile_values; this helper only prepares   |
        //   endpoint-secant spline curvature and samples total_sigma_cm2_per_molecule by support altitude.    |
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

        const rows = self.support_profile_values[wavelength_index * node_count .. (wavelength_index + 1) * node_count];
        var altitudes_km: [max_spectroscopy_profile_nodes]f64 = undefined;
        var line_values: [max_spectroscopy_profile_nodes]f64 = undefined;
        var line_mixing_values: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_values: [max_spectroscopy_profile_nodes]f64 = undefined;
        var line_second: [max_spectroscopy_profile_nodes]f64 = undefined;
        var line_mixing_second: [max_spectroscopy_profile_nodes]f64 = undefined;
        var total_second: [max_spectroscopy_profile_nodes]f64 = undefined;

        for (rows, 0..) |row_value, profile_node_index| {
            altitudes_km[profile_node_index] = row_value.altitude_km;
            line_values[profile_node_index] = row_value.line_sigma_cm2_per_molecule;
            line_mixing_values[profile_node_index] = row_value.line_mixing_sigma_cm2_per_molecule;
            total_values[profile_node_index] = row_value.total_sigma_cm2_per_molecule;
        }

        const altitudes = altitudes_km[0..node_count];
        spline.endpointSecantSecondDerivatives3(
            altitudes,
            line_values[0..node_count],
            line_mixing_values[0..node_count],
            total_values[0..node_count],
            line_second[0..node_count],
            line_mixing_second[0..node_count],
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

pub fn buildO2ProfileLineValues(
    allocator: Allocator,
    case: o2_case.O2Case,
) !ProfileLineValues {
    // buildO2ProfileLineValues -------------------------------------------------------------------------------|
    // Build line values over the case's evenly spaced setup wavelengths.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_count = case.spectral_grid.sample_count;
    const wavelengths_nm = try allocator.alloc(f64, wavelength_count);
    defer allocator.free(wavelengths_nm);

    const step_nm = if (wavelength_count > 1)
        (case.spectral_grid.end_nm - case.spectral_grid.start_nm) / @as(f64, @floatFromInt(wavelength_count - 1))
    else
        0.0;

    for (wavelengths_nm, 0..) |*wavelength_nm, wavelength_index| {
        wavelength_nm.* = case.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(wavelength_index));
    }

    return buildO2ProfileLineValuesForWavelengths(allocator, case, wavelengths_nm);
}

pub fn buildO2ProfileLineValuesForWavelengths(
    allocator: Allocator,
    case: o2_case.O2Case,
    wavelengths_nm: []const f64,
) !ProfileLineValues {
    // buildO2ProfileLineValuesForWavelengths -----------------------------------------------------------------|
    // Build retained line values with the scalar weak-line cutoff fallback used by setup/profile parity tests.|
    // --------------------------------------------------------------------------------------------------------|
    return buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
        allocator,
        case,
        wavelengths_nm,
        &.{},
        true,
        null,
        preferredProfileLineWorkerCount(wavelengths_nm.len),
    );
}

pub fn buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
    allocator: Allocator,
    case: o2_case.O2Case,
    wavelengths_nm: []const f64,
    cutoff_grid_wavelengths_nm: []const f64,
    include_temperature_derivatives: bool,
    pool: ?*std.Thread.Pool,
    worker_count: usize,
) !ProfileLineValues {
    // buildO2ProfileLineValuesForWavelengthsWithCutoffGrid ---------------------------------------------------|
    // Build retained line values over a caller-provided exact wavelength list.                                |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports the old profile-line cache fill from main:`state_build/state_spectroscopy.zig`, but accepts     |
    //   the exact radiance wavelengths selected by `spectrum/radiance_wavelengths.zig` instead of assuming    |
    //   a uniform public product grid.                                                                        |
    //                                                                                                         |
    // row contract                                                                                            |
    //   Output rows stay wavelength-major and preserve the input wavelength order exactly. Dense spectrum     |
    //   prefetch can therefore use its `RadianceWavelengthList` index as the ProfileLineValues index.         |
    // --------------------------------------------------------------------------------------------------------|
    var layers = try atmosphere_layers.build(allocator, case);
    defer layers.deinit(allocator);
    var lines = try line_tables.build(allocator, case);
    defer lines.deinit(allocator);

    const wavelength_count = wavelengths_nm.len;
    const profile_node_count = layers.layer_pressures_hpa.len;
    const support_profile_node_count = layers.spectroscopy_profile.rows.len;
    const values = try allocator.alloc(ProfileLineValue, wavelength_count * profile_node_count);
    errdefer allocator.free(values);
    const support_profile_values = try allocator.alloc(
        ProfileSupportLineValue,
        wavelength_count * support_profile_node_count,
    );
    errdefer allocator.free(support_profile_values);

    const cutoff_grid = try prepareCutoffGrid(allocator, cutoff_grid_wavelengths_nm);
    defer cutoff_grid.deinit(allocator);
    const runtime = RuntimeControls{
        .cutoff_cm1 = lines.cutoff_sim_cm1,
        .line_mixing_factor = lines.line_mixing_factor,
        .cutoff_grid_wavelengths_nm = cutoff_grid.wavelengths_nm,
        .cutoff_grid_wavenumbers_cm1 = cutoff_grid.wavenumbers_cm1,
    };
    const line_strength_threshold = thresholdStrength(lines.rows, lines.threshold_line_sim);
    const active_lines = try collectActiveLines(
        allocator,
        lines.rows,
        lines.isotopes_sim,
        line_strength_threshold,
    );
    defer allocator.free(active_lines);
    const total_lines = try collectRuntimeLines(allocator, lines.rows, lines.isotopes_sim);
    defer allocator.free(total_lines);
    const weak_states = try prepareLayerWeakLineStates(
        allocator,
        active_lines,
        layers.layer_temperatures_k,
        layers.layer_pressures_hpa,
        0.0,
    );
    defer deinitWeakLineStates(allocator, weak_states);

    // The old-route temperature derivative is a centered finite difference at T +/- 0.5 K. The public WP4
    // Jacobian states are surface/aerosol controls, so root spectrum runs do not read d_sigma/dT and skip
    // these two full weak-line state families. Explicit profile-line parity builders still request the rows
    // directly, and the reuse stamp records the choice so incompatible session caches cannot mix.
    var upper_weak_states: []WeakLinePreparedState = &.{};
    var lower_weak_states: []WeakLinePreparedState = &.{};
    if (include_temperature_derivatives) {
        upper_weak_states = try prepareLayerWeakLineStates(
            allocator,
            active_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            0.5,
        );
        errdefer deinitWeakLineStates(allocator, upper_weak_states);
        lower_weak_states = try prepareLayerWeakLineStates(
            allocator,
            active_lines,
            layers.layer_temperatures_k,
            layers.layer_pressures_hpa,
            -0.5,
        );
    }
    defer if (include_temperature_derivatives) {
        deinitWeakLineStates(allocator, lower_weak_states);
        deinitWeakLineStates(allocator, upper_weak_states);
    };
    const total_weak_states = try prepareLayerWeakLineStates(
        allocator,
        total_lines,
        layers.layer_temperatures_k,
        layers.layer_pressures_hpa,
        0.0,
    );
    defer deinitWeakLineStates(allocator, total_weak_states);
    const support_total_weak_states = try prepareProfileWeakLineStates(
        allocator,
        total_lines,
        layers.spectroscopy_profile.rows,
    );
    defer deinitWeakLineStates(allocator, support_total_weak_states);
    const strong_states = try prepareLayerStrongLineStates(
        allocator,
        lines.strong_lines,
        lines.relaxation_matrix,
        layers.layer_temperatures_k,
        layers.layer_pressures_hpa,
    );
    defer allocator.free(strong_states);
    const support_strong_states = try prepareProfileStrongLineStates(
        allocator,
        lines.strong_lines,
        lines.relaxation_matrix,
        layers.spectroscopy_profile.rows,
    );
    defer allocator.free(support_strong_states);

    try buildProfileLineValuesByWavelength(
        pool,
        worker_count,
        wavelengths_nm,
        layers,
        lines,
        runtime,
        include_temperature_derivatives,
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
        support_profile_values,
    );

    return .{
        .values = values,
        .support_profile_values = support_profile_values,
        .wavelength_count = wavelength_count,
        .profile_node_count = profile_node_count,
        .support_profile_node_count = support_profile_node_count,
        .reuse_stamp = profileLineReuseStamp(case.id, wavelengths_nm, include_temperature_derivatives),
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
    active_lines: []const readers.O2LineAssetRow,
    total_lines: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    weak_states: []const WeakLinePreparedState,
    upper_weak_states: []const WeakLinePreparedState,
    lower_weak_states: []const WeakLinePreparedState,
    total_weak_states: []const WeakLinePreparedState,
    support_total_weak_states: []const WeakLinePreparedState,
    strong_states: []const StrongLinePreparedState,
    support_strong_states: []const StrongLinePreparedState,
    values: []ProfileLineValue,
    support_profile_values: []ProfileSupportLineValue,
    start_index: usize,
    end_index: usize,
    worker_index: usize = 0,
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
    lines: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64 = 0.0,
    weak_states: ?[]WeakLinePreparedState = null,
    strong_states: ?[]StrongLinePreparedState = null,
    queue: *worker_partition.ChunkQueue,
    worker_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

fn buildProfileLineValuesByWavelength(
    pool: ?*std.Thread.Pool,
    worker_count: usize,
    wavelengths_nm: []const f64,
    layers: atmosphere_layers.LayerGrid,
    lines: line_tables.O2LineTable,
    runtime: RuntimeControls,
    include_temperature_derivatives: bool,
    active_lines: []const readers.O2LineAssetRow,
    total_lines: []const readers.O2LineAssetRow,
    weak_states: []const WeakLinePreparedState,
    upper_weak_states: []const WeakLinePreparedState,
    lower_weak_states: []const WeakLinePreparedState,
    total_weak_states: []const WeakLinePreparedState,
    support_total_weak_states: []const WeakLinePreparedState,
    strong_states: []const StrongLinePreparedState,
    support_strong_states: []const StrongLinePreparedState,
    values: []ProfileLineValue,
    support_profile_values: []ProfileSupportLineValue,
) !void {
    // buildProfileLineValuesByWavelength ---------------------------------------------------------------------|
    // Fill retained profile-line values over exact wavelengths, partitioned exactly like the old profile      |
    // spectroscopy cache build: threshold 32, static worker ranges, chunk size 8, and optional session pool.  |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   `profile_spectroscopy_cache.build` measures this whole setup phase. Worker and chunk zones live in    |
    //   `profileLineBuildWorkerMain` and retain the old trace names for profile-cache construction.           |
    // --------------------------------------------------------------------------------------------------------|
    if (worker_count == 0 or worker_count > worker_partition.max_workers) return error.InvalidShape;
    if (wavelengths_nm.len == 0) return;

    const profile_node_count = layers.layer_pressures_hpa.len;
    const support_profile_node_count = layers.spectroscopy_profile.rows.len;
    if (values.len != wavelengths_nm.len * profile_node_count) return error.InvalidShape;
    if (support_profile_values.len != wavelengths_nm.len * support_profile_node_count) return error.InvalidShape;

    // instrumentation: trace zone: profile spectroscopy cache build ----------------------------------------- |
    // captures: profile-line cache build wall time and exact-wavelength count                                 |
    // why: shows setup cost that WP4 compares before forward prefetch starts.                                 |
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
            .strong_lines = lines.strong_lines,
            .relaxation_matrix = lines.relaxation_matrix,
            .weak_states = weak_states,
            .upper_weak_states = upper_weak_states,
            .lower_weak_states = lower_weak_states,
            .total_weak_states = total_weak_states,
            .support_total_weak_states = support_total_weak_states,
            .strong_states = strong_states,
            .support_strong_states = support_strong_states,
            .values = values,
            .support_profile_values = support_profile_values,
            .start_index = range.start,
            .end_index = range.end,
            .worker_index = worker_index,
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
        // why: preserves the old chunk boundary while showing uneven wavelength-window costs.                 |
        const chunk_zone = Trace.deepStaticZone(@src(), "profile_spectroscopy_cache.build");
        chunk_zone.value(@intCast(chunk.len()));
        defer chunk_zone.end();
        // end instrumentation: trace zone: profile spectroscopy cache build chunk ----------------------------|

        for (chunk.start..chunk.end) |wavelength_index| {
            fillProfileLineValueRowsAtWavelength(worker, wavelength_index);
            fillSupportProfileLineValueRowsAtWavelength(worker, wavelength_index);
        }
    }
}

fn fillProfileLineValueRowsAtWavelength(worker: *ProfileLineBuildWorker, wavelength_index: usize) void {
    // fillProfileLineValueRowsAtWavelength -------------------------------------------------------------------|
    // Fill all layer-node line-value rows for one exact wavelength.                                           |
    // --------------------------------------------------------------------------------------------------------|
    const wavelength_nm = worker.wavelengths_nm[wavelength_index];
    for (worker.layer_pressures_hpa, worker.layer_temperatures_k, 0..) |pressure_hpa, temperature_k, node_index| {
        const sigma = weakLineSigmaAtPrepared(
            worker.active_lines,
            &worker.weak_states[node_index],
            wavelength_nm,
            worker.runtime,
        );

        var d_sigma_d_temperature: f64 = 0.0;
        if (worker.include_temperature_derivatives) {
            const upper_sigma = weakLineSigmaAtPreparedFiniteDifference(
                worker.active_lines,
                &worker.upper_weak_states[node_index],
                wavelength_nm,
                worker.runtime,
            );
            const lower_sigma = weakLineSigmaAtPreparedFiniteDifference(
                worker.active_lines,
                &worker.lower_weak_states[node_index],
                wavelength_nm,
                worker.runtime,
            );
            d_sigma_d_temperature = (upper_sigma - lower_sigma) / 1.0;
        }

        const total = totalSpectroscopyAt(
            worker.total_lines,
            worker.strong_lines,
            worker.relaxation_matrix,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            worker.runtime,
            &worker.strong_states[node_index],
            &worker.total_weak_states[node_index],
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
    for (worker.support_profile_rows, 0..) |profile_row, node_index| {
        const total = totalSpectroscopyAt(
            worker.total_lines,
            worker.strong_lines,
            worker.relaxation_matrix,
            wavelength_nm,
            profile_row.temperature_k,
            profile_row.pressure_hpa,
            worker.runtime,
            &worker.support_strong_states[node_index],
            &worker.support_total_weak_states[node_index],
        );
        const row_index = wavelength_index * worker.support_profile_rows.len + node_index;
        worker.support_profile_values[row_index] = .{
            .wavelength_nm = wavelength_nm,
            .profile_node_index = @intCast(node_index),
            .altitude_km = profile_row.altitude_km,
            .pressure_hpa = profile_row.pressure_hpa,
            .temperature_k = profile_row.temperature_k,
            .line_sigma_cm2_per_molecule = total.line_sigma_cm2_per_molecule,
            .line_mixing_sigma_cm2_per_molecule = total.line_mixing_sigma_cm2_per_molecule,
            .total_sigma_cm2_per_molecule = total.total_sigma_cm2_per_molecule,
        };
    }
}

fn preferredProfileLineWorkerCount(wavelength_count: usize) usize {
    // preferredProfileLineWorkerCount ------------------------------------------------------------------------|
    // Resolve the old profile-cache build worker-count policy for retained exact-wavelength spectroscopy.     |
    // --------------------------------------------------------------------------------------------------------|
    return worker_partition.preferredWorkerCount(
        wavelength_count,
        min_parallel_profile_cache_build_count,
    );
}

fn preferredProfileLineStateWorkerCount(profile_count: usize) usize {
    // preferredProfileLineStateWorkerCount -------------------------------------------------------------------|
    // Resolve the old thermodynamic profile-line state worker-count policy.                                   |
    // --------------------------------------------------------------------------------------------------------|
    return worker_partition.preferredWorkerCount(
        profile_count,
        min_parallel_profile_line_state_count,
    );
}

fn profileLineReuseStamp(
    case_id: []const u8,
    wavelengths_nm: []const f64,
    include_temperature_derivatives: bool,
) hashing.ReuseStamp {
    // profileLineReuseStamp ----------------------------------------------------------------------------------|
    // Include exact wavelength bits and derivative-row presence in the retained line-value stamp.             |
    // --------------------------------------------------------------------------------------------------------|
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(case_id);
    hasher.update(std.mem.sliceAsBytes(wavelengths_nm));
    const derivative_byte = [_]u8{if (include_temperature_derivatives) 1 else 0};
    hasher.update(&derivative_byte);
    return .{ .value = hasher.final() };
}

fn prepareCutoffGrid(allocator: Allocator, support_wavelengths_nm: []const f64) !CutoffGrid {
    // prepareCutoffGrid --------------------------------------------------------------------------------------|
    // Sort and merge the realized weak-line support grid before computing matching wavenumbers.               |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/o2a_reference/run.zig` installVendorWeakCutoffGrid and old                      |
    //   main:`instrument/adaptive_plan.zig` buildAdaptiveSupportWavelengths merge tolerance.                  |
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
        wavenumber_cm1.* = wavelengthToWavenumberCm1(wavelength_nm);
    }
    return .{ .wavelengths_nm = merged_wavelengths, .wavenumbers_cm1 = wavenumbers };
}

fn lessThanF64(_: void, lhs: f64, rhs: f64) bool {
    // lessThanF64 --------------------------------------------------------------------------------------------|
    // Sort finite support wavelengths in ascending wavelength order for old cutoff-grid index searches.       |
    // --------------------------------------------------------------------------------------------------------|
    return lhs < rhs;
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

    fn deinit(self: *const CutoffGrid, allocator: Allocator) void {
        // CutoffGrid.deinit --------------------------------------------------------------------------------- |
        // Release the paired weak-line cutoff grid arrays.                                                    |
        //                                                                                                     |
        // ownership                                                                                           |
        //   Both slices are owned by CutoffGrid and are never borrowed after the parent setup object exits.   |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavenumbers_cm1);
        allocator.free(self.wavelengths_nm);
    }
};
// ------------------------------------------------------------------------------------------------------------|

// SpectroscopyComponents -------------------------------------------------------------------------------------|
// Split line-spectroscopy result for one thermodynamic point and wavelength.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] weak_line_sigma_cm2_per_molecule   : f64                                                           |
// [ 8..15] strong_line_sigma_cm2_per_molecule : f64                                                           |
// [16..23] line_sigma_cm2_per_molecule        : f64                                                           |
// [24..31] line_mixing_sigma_cm2_per_molecule : f64                                                           |
// [32..39] total_sigma_cm2_per_molecule       : f64                                                           |
const SpectroscopyComponents = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
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
const StrongLinePreparedState = struct {
    line_count: usize = 0,
    sig_moy_cm1: f64 = 0.0,
    population_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    dipole_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    mod_sig_cm1: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    half_width_cm1_at_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    line_mixing_coefficients: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
};
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedLineState ----------------------------------------------------------------------------------|
// Per-line weak-lane constants prepared for one temperature and pressure.                                     |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/input/reference/spectroscopy/types.zig` WeakLinePreparedLineState.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] shifted_center_wavenumber_cm1 : f64                                                                |
// [ 8..15] cte                            : f64                                                               |
// [16..23] line_shape_y                   : f64                                                               |
// [24..31] prefactor_base                 : f64                                                               |
const WeakLinePreparedLineState = struct {
    shifted_center_wavenumber_cm1: f64,
    cte: f64,
    line_shape_y: f64,
    prefactor_base: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedState --------------------------------------------------------------------------------------|
// Header over weak-line constants prepared for one temperature and pressure.                                  |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/input/reference/spectroscopy/types.zig` WeakLinePreparedState.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count       : usize                                                                           |
// [ 8..15] safe_temperature : f64                                                                             |
// [16..23] safe_pressure    : f64                                                                             |
// [24..39] lines            : []WeakLinePreparedLineState                                                     |
const WeakLinePreparedState = struct {
    line_count: usize,
    safe_temperature: f64,
    safe_pressure: f64,
    lines: []WeakLinePreparedLineState,

    fn deinit(self: *WeakLinePreparedState, allocator: Allocator) void {
        // WeakLinePreparedState.deinit ---------------------------------------------------------------------- |
        // Release per-line weak-lane constants prepared for one temperature/pressure profile node.            |
        //                                                                                                     |
        // ownership                                                                                           |
        //   `lines` owns heap storage; scalar thermodynamic fields are copied values and need no teardown.    |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.lines);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ComplexProbability -----------------------------------------------------------------------------------------|
// Complex probability function result used by the weak-line Voigt formula.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wr : f64                                                                                           |
// [ 8..15] wi : f64                                                                                           |
const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// LineWindow -------------------------------------------------------------------------------------------------|
// Borrowed wavelength-local line slice plus its start index in the sorted source list.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] lines      : []const O2LineAssetRow                                                                |
// [16..23] start_index: usize                                                                                 |
const LineWindow = struct {
    lines: []const readers.O2LineAssetRow,
    start_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

fn thresholdStrength(lines: []const readers.O2LineAssetRow, scale: f64) f64 {
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
    lines: []const readers.O2LineAssetRow,
    active_isotopes: []const u8,
    line_strength_threshold: f64,
) ![]readers.O2LineAssetRow {
    // collectActiveLines -------------------------------------------------------------------------------------|
    // Copy weak-line rows that participate in setup evaluation, sorted for local window scans.                |
    // --------------------------------------------------------------------------------------------------------|
    var active_count: usize = 0;
    for (lines) |line| {
        if (activeLine(line, active_isotopes, line_strength_threshold)) active_count += 1;
    }

    const active_lines = try allocator.alloc(readers.O2LineAssetRow, active_count);
    errdefer allocator.free(active_lines);

    var active_index: usize = 0;
    for (lines) |line| {
        if (!activeLine(line, active_isotopes, line_strength_threshold)) continue;
        active_lines[active_index] = line;
        active_index += 1;
    }

    std.mem.sort(readers.O2LineAssetRow, active_lines, {}, lessByCenterWavelength);
    return active_lines;
}

fn collectRuntimeLines(
    allocator: Allocator,
    lines: []const readers.O2LineAssetRow,
    active_isotopes: []const u8,
) ![]readers.O2LineAssetRow {
    // collectRuntimeLines ------------------------------------------------------------------------------------|
    // Copy O2 rows that participate in old total-sigma evaluation, without applying the weak-line threshold.  |
    // --------------------------------------------------------------------------------------------------------|
    var active_count: usize = 0;
    for (lines) |line| {
        if (runtimeLine(line, active_isotopes)) active_count += 1;
    }

    const active_lines = try allocator.alloc(readers.O2LineAssetRow, active_count);
    errdefer allocator.free(active_lines);

    var active_index: usize = 0;
    for (lines) |line| {
        if (!runtimeLine(line, active_isotopes)) continue;
        active_lines[active_index] = line;
        active_index += 1;
    }

    std.mem.sort(readers.O2LineAssetRow, active_lines, {}, lessByCenterWavelength);
    return active_lines;
}

fn lessByCenterWavelength(_: void, lhs: readers.O2LineAssetRow, rhs: readers.O2LineAssetRow) bool {
    // lessByCenterWavelength ---------------------------------------------------------------------------------|
    // Order line rows by center wavelength so binary searches can isolate a local HITRAN cutoff window.       |
    // --------------------------------------------------------------------------------------------------------|
    return lhs.center_wavelength_nm < rhs.center_wavelength_nm;
}

fn prepareLayerWeakLineStates(
    allocator: Allocator,
    lines: []const readers.O2LineAssetRow,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
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
    );
}

fn prepareProfileWeakLineStates(
    allocator: Allocator,
    lines: []const readers.O2LineAssetRow,
    profile_rows: []const readers.AtmosphereProfileRow,
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
    );
}

fn prepareWeakLineStatesForRows(
    allocator: Allocator,
    lines: []const readers.O2LineAssetRow,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
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
    );
    return states;
}

fn prepareLayerStrongLineStates(
    allocator: Allocator,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
) ![]StrongLinePreparedState {
    // prepareLayerStrongLineStates ---------------------------------------------------------------------------|
    // Prepare one strong-line ConvTP state per layer profile node through the old raw worker policy.          |
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
    );
    return states;
}

fn prepareProfileStrongLineStates(
    allocator: Allocator,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    profile_rows: []const readers.AtmosphereProfileRow,
) ![]StrongLinePreparedState {
    // prepareProfileStrongLineStates -------------------------------------------------------------------------|
    // Prepare one strong-line ConvTP state per spectroscopy-profile row through the old raw worker policy.    |
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
    );
}

fn fillProfileLineStates(
    lines: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    temperatures_k: []const f64,
    pressures_hpa: []const f64,
    temperature_offset_k: f64,
    weak_states: ?[]WeakLinePreparedState,
    strong_states: ?[]StrongLinePreparedState,
) void {
    // fillProfileLineStates ----------------------------------------------------------------------------------|
    // Fill weak and/or strong line states with the old profile-line-state worker policy.                      |
    //                                                                                                         |
    // scheduling                                                                                              |
    //   Threshold 4 and chunk size 2 match main:`state_build/absorbers.zig` for thermodynamic profile nodes.  |
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
        // why: preserves the old chunk boundary for P/T spectroscopy preparation.                             |
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
    for (start..end) |index| {
        const pressure_atm = @max(worker.pressures_hpa[index] / 1013.25, min_spectroscopy_pressure_atm);
        if (worker.weak_states) |states| {
            fillWeakLineStateInto(
                &states[index],
                worker.lines,
                @max(worker.temperatures_k[index] + worker.temperature_offset_k, min_hitran_temperature_k),
                pressure_atm,
            );
        }
        if (worker.strong_states) |states| {
            states[index] = prepareStrongLineState(
                worker.strong_lines,
                worker.relaxation_matrix,
                worker.temperatures_k[index],
                pressure_atm,
            );
        }
    }
}

fn fillWeakLineStateInto(
    state: *WeakLinePreparedState,
    lines: []const readers.O2LineAssetRow,
    temperature_k: f64,
    pressure_atm: f64,
) void {
    // fillWeakLineStateInto ----------------------------------------------------------------------------------|
    // Fill old-route weak-line constants for one already-allocated thermodynamic state row.                   |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/physics_core.zig` prepareWeakLinePreparedLineState.      |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const safe_pressure = @max(pressure_atm, min_spectroscopy_pressure_atm);
    std.debug.assert(state.lines.len == lines.len);
    state.line_count = lines.len;
    state.safe_temperature = safe_temperature;
    state.safe_pressure = safe_pressure;
    for (lines, state.lines) |line, *prepared_line| {
        prepared_line.* = prepareWeakLinePreparedLineState(line, safe_temperature, safe_pressure);
    }
}

fn deinitWeakLineStates(allocator: Allocator, states: []WeakLinePreparedState) void {
    // deinitWeakLineStates -----------------------------------------------------------------------------------|
    // Release a prepared weak-line state row set after setup evaluation completes.                            |
    // --------------------------------------------------------------------------------------------------------|
    for (states) |*state| state.deinit(allocator);
    allocator.free(states);
}

fn emptyRelaxationMatrix() readers.O2RelaxationMatrixAsset {
    // emptyRelaxationMatrix ----------------------------------------------------------------------------------|
    // Provide an unused, well-formed relaxation-matrix view for weak-only profile-line state workers.         |
    // --------------------------------------------------------------------------------------------------------|
    return .{ .line_count = 0, .wt0 = &.{}, .bw = &.{} };
}

fn prepareWeakLinePreparedLineState(
    line: readers.O2LineAssetRow,
    safe_temperature: f64,
    safe_pressure: f64,
) WeakLinePreparedLineState {
    // prepareWeakLinePreparedLineState -----------------------------------------------------------------------|
    // Precompute the temperature/pressure terms shared by all wavelength evaluations for one HITRAN line.     |
    // --------------------------------------------------------------------------------------------------------|
    const center_wavenumber_cm1 = line.center_wavenumber_cm1;
    const temperature_ratio = hitran_reference_temperature_k / safe_temperature;
    const shifted_center_wavenumber_cm1 = @max(
        center_wavenumber_cm1 + line.pressure_shift_cm1 * safe_pressure,
        1.0,
    );
    const half_width_cm1_at_t = @max(
        line.air_half_width_cm1 * std.math.pow(f64, temperature_ratio, line.temperature_exponent),
        1.0e-6,
    );
    const doppler_width_cm1 = @max(
        dopplerWidthCm1(safe_temperature, shifted_center_wavenumber_cm1, molecularWeightForLine(line)),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / doppler_width_cm1;

    var converted_strength = line.line_strength_cm2_per_molecule *
        partitionRatioT0OverT(line, safe_temperature) *
        @exp(
            hitran_hc_over_kb_cm_k * line.lower_state_energy_cm1 *
                ((1.0 / hitran_reference_temperature_k) - (1.0 / safe_temperature)),
        ) /
        shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013 /
        hitran_boltzmann_constant_j_per_k /
        safe_temperature /
        @max(
            1.0 - @exp(-hitran_hc_over_kb_cm_k * shifted_center_wavenumber_cm1 / hitran_reference_temperature_k),
            1.0e-12,
        );

    return .{
        .shifted_center_wavenumber_cm1 = shifted_center_wavenumber_cm1,
        .cte = cte,
        .line_shape_y = half_width_cm1_at_t * safe_pressure * cte,
        .prefactor_base = @sqrt(@log(2.0)) /
            doppler_width_cm1 /
            @sqrt(hitran_pi) *
            safe_pressure *
            converted_strength,
    };
}

fn totalSpectroscopyAt(
    runtime_lines: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    runtime: RuntimeControls,
    strong_state: *const StrongLinePreparedState,
    prepared_weak_state: ?*const WeakLinePreparedState,
) SpectroscopyComponents {
    // totalSpectroscopyAt ------------------------------------------------------------------------------------|
    // Sum old-route weak, strong-line, and line-mixing sigma for one profile-node row.                        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/line_list.zig` totalSigmaWithPreparedStrongLineState*    |
    //   and main:`src/input/reference/spectroscopy/strong_lines.zig` strongLineContributionPrepared.          |
    // --------------------------------------------------------------------------------------------------------|
    if (runtime_lines.len == 0) return .{};

    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const pressure_atm = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
    const window = relevantLineWindow(runtime_lines, wavelength_nm, runtime.cutoff_cm1);
    const vendor_partition = usesVendorStrongLinePartition(runtime_lines, strong_lines);
    const prepared_state = prepared_weak_state;
    const prepared_matches = if (prepared_state) |state|
        state.line_count == runtime_lines.len and state.lines.len == runtime_lines.len
    else
        false;

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const stimulated_emission_scale: f64 = stimulated_scale: {
        if (!prepared_matches) break :stimulated_scale 0.0;

        break :stimulated_scale weakLinePreparedStimulatedEmissionScale(
            evaluation_wavenumber_cm1,
            prepared_state.?.safe_temperature,
        );
    };
    const thermodynamic_scale: f64 = thermodynamic_scale: {
        if (!prepared_matches) break :thermodynamic_scale 0.0;

        break :thermodynamic_scale weakLinePreparedThermodynamicScale(
            prepared_state.?.safe_temperature,
            prepared_state.?.safe_pressure,
        );
    };
    var weak_line_sigma: f64 = 0.0;
    for (window.lines, 0..) |line, line_index| {
        if (shouldExcludeWeakLine(line, line_index, window.lines, strong_lines, vendor_partition)) continue;

        if (prepared_matches) {
            weak_line_sigma += weakLinePreparedContribution(
                evaluation_wavenumber_cm1,
                prepared_state.?.lines[window.start_index + line_index],
                runtime,
                stimulated_emission_scale,
                thermodynamic_scale,
            );
            continue;
        }

        weak_line_sigma += weakLineContribution(
            wavelength_nm,
            line,
            safe_temperature,
            pressure_atm,
            runtime,
        );
    }

    var strong_line_sigma: f64 = 0.0;
    var line_mixing_sigma: f64 = 0.0;
    const strong_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), strong_state.line_count);
    for (0..strong_count) |strong_index| {
        const contribution = strongLineContribution(
            wavelength_nm,
            strong_index,
            strong_state,
            safe_temperature,
            pressure_atm,
        );
        strong_line_sigma += contribution.strong_line_sigma_cm2_per_molecule;
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule * runtime.line_mixing_factor;
    }

    const line_sigma = weak_line_sigma + strong_line_sigma;
    return .{
        .weak_line_sigma_cm2_per_molecule = weak_line_sigma,
        .strong_line_sigma_cm2_per_molecule = strong_line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
    };
}

fn weakLineSigmaAtPrepared(
    active_lines: []const readers.O2LineAssetRow,
    state: *const WeakLinePreparedState,
    wavelength_nm: f64,
    runtime: RuntimeControls,
) f64 {
    // weakLineSigmaAtPrepared --------------------------------------------------------------------------------|
    // Sum weak-line Voigt contributions using one thermodynamic state's prepared line constants.              |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/physics_core.zig`                                        |
    //   weakLineSigmaPreparedWithStimulatedEmissionScale over the WP2 setup row names.                        |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(state.line_count == active_lines.len);
    std.debug.assert(state.lines.len == active_lines.len);

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const stimulated_emission_scale = weakLinePreparedStimulatedEmissionScale(
        evaluation_wavenumber_cm1,
        state.safe_temperature,
    );
    const thermodynamic_scale = weakLinePreparedThermodynamicScale(state.safe_temperature, state.safe_pressure);
    const window = relevantLineWindow(active_lines, wavelength_nm, runtime.cutoff_cm1);
    var sigma: f64 = 0.0;
    for (window.lines, 0..) |_, line_index| {
        sigma += weakLinePreparedContribution(
            evaluation_wavenumber_cm1,
            state.lines[window.start_index + line_index],
            runtime,
            stimulated_emission_scale,
            thermodynamic_scale,
        );
    }
    return sigma;
}

fn weakLineSigmaAtPreparedFiniteDifference(
    active_lines: []const readers.O2LineAssetRow,
    state: *const WeakLinePreparedState,
    wavelength_nm: f64,
    runtime: RuntimeControls,
) f64 {
    // weakLineSigmaAtPreparedFiniteDifference ----------------------------------------------------------------|
    // Evaluate T +/- 0.5 K rows with the scalar old-route multiplication order for d_sigma/dT evidence.       |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(state.line_count == active_lines.len);
    std.debug.assert(state.lines.len == active_lines.len);

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const stimulated_emission_scale = weakLinePreparedStimulatedEmissionScale(
        evaluation_wavenumber_cm1,
        state.safe_temperature,
    );
    const window = relevantLineWindow(active_lines, wavelength_nm, runtime.cutoff_cm1);
    var sigma: f64 = 0.0;
    for (window.lines, 0..) |_, line_index| {
        sigma += weakLinePreparedContributionFiniteDifference(
            evaluation_wavenumber_cm1,
            state.lines[window.start_index + line_index],
            runtime,
            stimulated_emission_scale,
            state.safe_temperature,
            state.safe_pressure,
        );
    }
    return sigma;
}

fn relevantLineWindow(
    active_lines: []const readers.O2LineAssetRow,
    wavelength_nm: f64,
    cutoff_cm1: f64,
) LineWindow {
    // relevantLineWindow -------------------------------------------------------------------------------------|
    // Return the center-wavelength slice that can fall inside the old-route cutoff prewindow.                 |
    // --------------------------------------------------------------------------------------------------------|
    if (active_lines.len == 0) return .{ .lines = active_lines, .start_index = 0 };

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const prewindow_cm1 = cutoff_cm1 + vendor_cutoff_prewindow_margin_cm1;
    const lower_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - prewindow_cm1, 1.0);
    const upper_wavenumber_cm1 = evaluation_wavenumber_cm1 + prewindow_cm1;
    const lower_wavelength_nm = wavenumberToWavelengthNm(upper_wavenumber_cm1);
    const upper_wavelength_nm = wavenumberToWavelengthNm(lower_wavenumber_cm1);
    const begin = lowerBoundByCenterWavelength(active_lines, lower_wavelength_nm);
    const end = lowerBoundByCenterWavelength(active_lines, upper_wavelength_nm);

    return .{ .lines = active_lines[begin..end], .start_index = begin };
}

fn lowerBoundByCenterWavelength(lines: []const readers.O2LineAssetRow, wavelength_nm: f64) usize {
    // lowerBoundByCenterWavelength ---------------------------------------------------------------------------|
    // Find the first sorted line row with center wavelength at or above the requested wavelength.             |
    // --------------------------------------------------------------------------------------------------------|
    var begin: usize = 0;
    var end = lines.len;
    while (begin < end) {
        const middle = begin + (end - begin) / 2;
        if (lines[middle].center_wavelength_nm < wavelength_nm) {
            begin = middle + 1;
        } else {
            end = middle;
        }
    }
    return begin;
}

fn activeLine(
    line: readers.O2LineAssetRow,
    active_isotopes: []const u8,
    line_strength_threshold: f64,
) bool {
    // activeLine ---------------------------------------------------------------------------------------------|
    // Apply the WP2 line-gas isotope and weak-line threshold controls to one parsed HITRAN row.               |
    // --------------------------------------------------------------------------------------------------------|
    if (line.gas_index != 7) return false;

    if (line.line_strength_cm2_per_molecule < line_strength_threshold) return false;

    if (active_isotopes.len == 0) return true;

    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }

    return false;
}

fn runtimeLine(line: readers.O2LineAssetRow, active_isotopes: []const u8) bool {
    // runtimeLine --------------------------------------------------------------------------------------------|
    // Apply the old total-sigma gas/isotope controls without the weak-line threshold filter.                  |
    // --------------------------------------------------------------------------------------------------------|
    if (line.gas_index != 7) return false;

    if (active_isotopes.len == 0) return true;

    for (active_isotopes) |isotope_number| {
        if (line.isotope_number == isotope_number) return true;
    }

    return false;
}

fn usesVendorStrongLinePartition(
    lines: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
) bool {
    // usesVendorStrongLinePartition --------------------------------------------------------------------------|
    // Detect the old O2 A sidecar partition from retained HITRAN branch metadata.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (strong_lines.len == 0) return false;

    for (lines) |line| {
        const has_old_branch_metadata =
            line.branch_ic1 != null and
            line.branch_ic2 != null and
            line.rotational_nf != null;

        if (line.gas_index == 7 and has_old_branch_metadata) {
            return true;
        }
    }

    return false;
}

fn shouldExcludeWeakLine(
    line: readers.O2LineAssetRow,
    line_index: usize,
    window: []const readers.O2LineAssetRow,
    strong_lines: []const readers.O2StrongLineAssetRow,
    vendor_partition: bool,
) bool {
    // shouldExcludeWeakLine ----------------------------------------------------------------------------------|
    // Keep lines covered by old O2 strong-line sidecars out of the total weak-line contribution.              |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition) {
        if (!isVendorO2AStrongCandidateFromSource(line)) return false;
        return findStrongLineMatch(strong_lines, line.center_wavelength_nm) != null;
    }

    const strong_index = findStrongLineMatch(strong_lines, line.center_wavelength_nm) orelse return false;
    return strongestWindowAnchorForSidecar(window, strong_lines[strong_index]) == line_index;
}

fn strongestWindowAnchorForSidecar(
    window: []const readers.O2LineAssetRow,
    strong_line: readers.O2StrongLineAssetRow,
) usize {
    // strongestWindowAnchorForSidecar ------------------------------------------------------------------------|
    // Select the old generic sidecar anchor: closest line center, then strongest line on an equal delta.      |
    // --------------------------------------------------------------------------------------------------------|
    var best_index: usize = 0;
    var best_delta = std.math.inf(f64);
    var best_strength: f64 = -std.math.inf(f64);
    for (window, 0..) |line, line_index| {
        const delta = @abs(strong_line.center_wavelength_nm - line.center_wavelength_nm);
        const tolerance_nm = @max(0.01, strong_line.air_half_width_nm * 4.0);
        if (delta > tolerance_nm) continue;

        if (delta > best_delta) continue;

        if (delta == best_delta and line.line_strength_cm2_per_molecule < best_strength) continue;

        best_index = line_index;
        best_delta = delta;
        best_strength = line.line_strength_cm2_per_molecule;
    }
    return best_index;
}

fn findStrongLineMatch(strong_lines: []const readers.O2StrongLineAssetRow, wavelength_nm: f64) ?usize {
    // findStrongLineMatch ------------------------------------------------------------------------------------|
    // Return the closest LISA sidecar center within the old tolerance rule.                                   |
    // --------------------------------------------------------------------------------------------------------|
    var best_index: ?usize = null;
    var best_delta = std.math.inf(f64);
    for (strong_lines, 0..) |strong_line, strong_index| {
        const delta = @abs(strong_line.center_wavelength_nm - wavelength_nm);
        const tolerance_nm = @max(0.01, strong_line.air_half_width_nm * 4.0);
        if (delta > tolerance_nm or delta >= best_delta) continue;
        best_index = strong_index;
        best_delta = delta;
    }
    return best_index;
}

fn isVendorO2AStrongCandidateFromSource(line: readers.O2LineAssetRow) bool {
    // isVendorO2AStrongCandidateFromSource -------------------------------------------------------------------|
    // Match old support.zig: only source-marked O2 isotope-1 P-branch rows participate in vendor partition.   |
    // --------------------------------------------------------------------------------------------------------|
    return line.vendor_filter_metadata_from_source and
        line.gas_index == 7 and
        line.isotope_number == 1 and
        line.branch_ic1 != null and
        line.branch_ic2 != null and
        line.rotational_nf != null and
        line.branch_ic1.? == 5 and
        line.branch_ic2.? == 1 and
        line.rotational_nf.? <= 35;
}

fn weakLineContribution(
    wavelength_nm: f64,
    line: readers.O2LineAssetRow,
    temperature_k: f64,
    pressure_atm: f64,
    runtime: RuntimeControls,
) f64 {
    // weakLineContribution -----------------------------------------------------------------------------------|
    // Evaluate one HITRAN weak-line contribution with the old scalar fallback cutoff and CPF route.           |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and constants follow main:`src/input/reference/spectroscopy/physics_core.zig` after the       |
    //   WP2 row-type reduction from SpectroscopyLine to O2LineAssetRow.                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   nu0       = center_wavenumber_cm1 + pressure_shift_cm1 * pressure_atm                                 |
    //   gammaD    = Doppler half-width in cm^-1                                                               |
    //   cte       = sqrt(log(2)) / gammaD                                                                     |
    //   y         = gamma_air(T) * pressure_atm * cte                                                         |
    //                                                                                                         |
    //   S(T) = S(T0) * Q(T0)/Q(T)                                                                             |
    //        * exp((hc/k) * E_lower * (1/T0 - 1/T)) / nu0                                                     |
    //        * 0.1013 / (k_B * T * max(1 - exp(-(hc/k) * nu0 / T0), 1e-12))                                   |
    //                                                                                                         |
    //   cpf = complexProbability((nu0 - nu) * cte, y)                                                         |
    //   sigma = max(sqrt(log(2)) / gammaD / sqrt(pi) * pressure_atm * S(T)                                    |
    //               * nu * (1 - exp(-(hc/k) * nu / T)) * T * k_B_cm3_hPa / pressure_atm / 1013.25             |
    //               * cpf.wr, 0)                                                                              |
    // --------------------------------------------------------------------------------------------------------|
    if (!insideCutoff(line, wavelength_nm, pressure_atm, runtime)) return 0.0;

    const center_wavenumber_cm1 = line.center_wavenumber_cm1;
    const shifted_center_wavenumber_cm1 = @max(center_wavenumber_cm1 + line.pressure_shift_cm1 * pressure_atm, 1.0);
    const temperature_ratio = hitran_reference_temperature_k / temperature_k;
    const half_width_cm1_at_t = @max(
        line.air_half_width_cm1 * std.math.pow(f64, temperature_ratio, line.temperature_exponent),
        1.0e-6,
    );
    const doppler_width_cm1 = @max(
        dopplerWidthCm1(temperature_k, shifted_center_wavenumber_cm1, molecularWeightForLine(line)),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / doppler_width_cm1;
    const line_shape_y = half_width_cm1_at_t * pressure_atm * cte;

    var converted_strength = line.line_strength_cm2_per_molecule *
        partitionRatioT0OverT(line, temperature_k) *
        @exp(
            hitran_hc_over_kb_cm_k * line.lower_state_energy_cm1 *
                ((1.0 / hitran_reference_temperature_k) - (1.0 / temperature_k)),
        ) /
        shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013 /
        hitran_boltzmann_constant_j_per_k /
        temperature_k /
        @max(
            1.0 - @exp(-hitran_hc_over_kb_cm_k * shifted_center_wavenumber_cm1 / hitran_reference_temperature_k),
            1.0e-12,
        );

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const cpf = complexProbabilityFunction(
        (shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * cte,
        line_shape_y,
    );
    const stimulated_emission_scale = evaluation_wavenumber_cm1 *
        (1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / temperature_k));
    const prefactor = @sqrt(@log(2.0)) /
        doppler_width_cm1 /
        @sqrt(hitran_pi) *
        pressure_atm *
        converted_strength *
        stimulated_emission_scale *
        temperature_k *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        pressure_atm /
        1013.25;

    return @max(prefactor * cpf.wr, 0.0);
}

fn weakLinePreparedStimulatedEmissionScale(evaluation_wavenumber_cm1: f64, safe_temperature: f64) f64 {
    // weakLinePreparedStimulatedEmissionScale ----------------------------------------------------------------|
    // Compute the wavelength term shared by all prepared weak lines at one thermodynamic point.               |
    // --------------------------------------------------------------------------------------------------------|
    return evaluation_wavenumber_cm1 *
        (1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature));
}

fn weakLinePreparedThermodynamicScale(safe_temperature: f64, safe_pressure: f64) f64 {
    // weakLinePreparedThermodynamicScale ---------------------------------------------------------------------|
    // Compute the number-density conversion shared by all prepared weak lines at one thermodynamic point.     |
    // --------------------------------------------------------------------------------------------------------|
    return safe_temperature *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;
}

fn weakLinePreparedContribution(
    evaluation_wavenumber_cm1: f64,
    prepared_line: WeakLinePreparedLineState,
    runtime: RuntimeControls,
    stimulated_emission_scale: f64,
    thermodynamic_scale: f64,
) f64 {
    // weakLinePreparedContribution ---------------------------------------------------------------------------|
    // Evaluate one prepared weak-line contribution with the old scalar fallback cutoff and CPF route.         |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/physics_core.zig`                                        |
    //   weakLineSigmaPreparedWithStimulatedEmissionScale.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    if (!preparedInsideCutoff(prepared_line, evaluation_wavenumber_cm1, runtime)) return 0.0;

    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * prepared_line.cte,
        prepared_line.line_shape_y,
    );
    const prefactor = prepared_line.prefactor_base *
        stimulated_emission_scale *
        thermodynamic_scale;
    return @max(prefactor * cpf.wr, 0.0);
}

fn weakLinePreparedContributionFiniteDifference(
    evaluation_wavenumber_cm1: f64,
    prepared_line: WeakLinePreparedLineState,
    runtime: RuntimeControls,
    stimulated_emission_scale: f64,
    safe_temperature: f64,
    safe_pressure: f64,
) f64 {
    // weakLinePreparedContributionFiniteDifference -----------------------------------------------------------|
    // Match weakLineContribution's multiply/divide order for pinned d_sigma/dT finite-difference rows.        |
    // --------------------------------------------------------------------------------------------------------|
    if (!preparedInsideCutoff(prepared_line, evaluation_wavenumber_cm1, runtime)) return 0.0;

    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * prepared_line.cte,
        prepared_line.line_shape_y,
    );
    const prefactor = prepared_line.prefactor_base *
        stimulated_emission_scale *
        safe_temperature *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;
    return @max(prefactor * cpf.wr, 0.0);
}

fn preparedInsideCutoff(
    prepared_line: WeakLinePreparedLineState,
    evaluation_wavenumber_cm1: f64,
    runtime: RuntimeControls,
) bool {
    // preparedInsideCutoff -----------------------------------------------------------------------------------|
    // Apply the HITRAN cutoff around a pre-shifted line center.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return shiftedCenterInsideCutoff(
        prepared_line.shifted_center_wavenumber_cm1,
        evaluation_wavenumber_cm1,
        runtime,
    );
}

fn prepareStrongLineState(
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    temperature_k: f64,
    pressure_atm: f64,
) StrongLinePreparedState {
    // prepareStrongLineState ---------------------------------------------------------------------------------|
    // Prepare old O2 ConvTP line-mixing state for one profile-node temperature and pressure.                  |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/strong_lines.zig` prepareStrongLineConvTPStateWithScratch|
    //   and fillStrongLineState over the new setup row names.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const temperature_ratio = hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(
        66,
        safe_temperature,
        hitran_reference_temperature_k,
    ) orelse temperature_ratio;
    const line_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), max_strong_line_sidecars);
    var state = StrongLinePreparedState{ .line_count = line_count };
    if (line_count == 0) return state;

    var relaxation_weights: [max_strong_line_sidecars * max_strong_line_sidecars]f64 = undefined;
    const relaxation_weight_count: usize = @as(usize, line_count) * @as(usize, line_count);
    fillStrongLineState(
        &state,
        relaxation_weights[0..relaxation_weight_count],
        strong_lines,
        relaxation_matrix,
        line_count,
        safe_temperature,
        temperature_ratio,
        partition_ratio,
        pressure_atm,
    );
    return state;
}

fn fillStrongLineState(
    state: *StrongLinePreparedState,
    relaxation_weights: []f64,
    strong_lines: []const readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    line_count: usize,
    safe_temperature: f64,
    temperature_ratio: f64,
    partition_ratio: f64,
    pressure_atm: f64,
) void {
    // fillStrongLineState ------------------------------------------------------------------------------------|
    // Fill old DISAMAR O2 line-mixing relaxation state for all retained strong-line sidecars.                 |
    // --------------------------------------------------------------------------------------------------------|
    for (0..line_count) |row_index| {
        const strong_line = strong_lines[row_index];
        const inverse_temperature_delta =
            (1.0 / hitran_reference_temperature_k) - (1.0 / safe_temperature);
        const population_energy_scale = 1.43877696 *
            strong_line.lower_state_energy_cm1 *
            inverse_temperature_delta;
        state.population_t[row_index] = strong_line.population_t0 *
            partition_ratio *
            @exp(population_energy_scale);
        state.dipole_t[row_index] = strong_line.dipole_t0 * @sqrt(temperature_ratio);
        state.mod_sig_cm1[row_index] =
            strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1;
        state.half_width_cm1_at_t[row_index] = strong_line.air_half_width_cm1 *
            std.math.pow(f64, temperature_ratio, strong_line.temperature_exponent);

        for (0..line_count) |column_index| {
            setRelaxationWeight(
                relaxation_weights,
                line_count,
                row_index,
                column_index,
                relaxation_matrix.weightAt(row_index, column_index) *
                    std.math.pow(
                        f64,
                        temperature_ratio,
                        relaxation_matrix.temperatureExponentAt(row_index, column_index),
                    ),
            );
        }
    }

    for (0..line_count) |row_index| {
        for (0..line_count) |column_index| {
            const column_energy_cm1 = strong_lines[column_index].lower_state_energy_cm1;
            const row_energy_cm1 = strong_lines[row_index].lower_state_energy_cm1;
            if (column_energy_cm1 < row_energy_cm1) continue;

            setRelaxationWeight(
                relaxation_weights,
                line_count,
                column_index,
                row_index,
                relaxationWeightAt(relaxation_weights, line_count, row_index, column_index) *
                    state.population_t[column_index] /
                    @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |index| {
        setRelaxationWeight(relaxation_weights, line_count, index, index, state.half_width_cm1_at_t[index]);
    }

    var weighted_center_sum: f64 = 0.0;
    var weighted_center_norm: f64 = 0.0;
    for (0..line_count) |line_index| {
        const weight = state.population_t[line_index] * state.dipole_t[line_index] * state.dipole_t[line_index];
        weighted_center_sum += state.mod_sig_cm1[line_index] * weight;
        weighted_center_norm += weight;
    }

    state.sig_moy_cm1 = if (weighted_center_norm > 0.0)
        weighted_center_sum / weighted_center_norm
    else
        state.mod_sig_cm1[0];

    for (0..line_count) |column_index| {
        var upper_sum: f64 = 0.0;
        var lower_sum: f64 = 0.0;
        for (0..line_count) |row_index| {
            if (row_index <= column_index) {
                upper_sum += strong_lines[row_index].dipole_ratio *
                    relaxationWeightAt(relaxation_weights, line_count, row_index, column_index);
            } else {
                lower_sum += strong_lines[row_index].dipole_ratio *
                    relaxationWeightAt(relaxation_weights, line_count, row_index, column_index);
            }
        }
        const rotational_gate = 1.0 -
            @abs(@as(f64, @floatFromInt(strong_lines[column_index].rotational_index_m1))) / 36.0;
        const renormalization_anchor = strong_lines[column_index].dipole_ratio *
            rotational_gate *
            rotational_gate *
            0.04;

        for (0..line_count) |row_index| {
            if (row_index <= column_index) continue;
            const renormalized = -relaxationWeightAt(relaxation_weights, line_count, row_index, column_index) *
                (upper_sum - renormalization_anchor) /
                lower_sum;
            setRelaxationWeight(relaxation_weights, line_count, row_index, column_index, renormalized);
            setRelaxationWeight(
                relaxation_weights,
                line_count,
                column_index,
                row_index,
                renormalized * state.population_t[column_index] / state.population_t[row_index],
            );
        }
    }

    for (0..line_count) |line_index| {
        var mixing_sum: f64 = 0.0;
        for (0..line_count) |other_index| {
            if (other_index == line_index) continue;

            const delta_sig = state.mod_sig_cm1[line_index] - state.mod_sig_cm1[other_index];
            if (delta_sig == 0.0) continue;

            mixing_sum += 2.0 * state.dipole_t[other_index] / state.dipole_t[line_index] *
                relaxationWeightAt(relaxation_weights, line_count, other_index, line_index) /
                delta_sig;
        }
        state.line_mixing_coefficients[line_index] = pressure_atm * mixing_sum;
    }
}

fn strongLineContribution(
    wavelength_nm: f64,
    strong_index: usize,
    state: *const StrongLinePreparedState,
    temperature_k: f64,
    pressure_atm: f64,
) SpectroscopyComponents {
    // strongLineContribution ---------------------------------------------------------------------------------|
    // Evaluate one prepared O2 strong-line sidecar with the old CPF line-mixing formula.                      |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const safe_pressure = @max(pressure_atm, min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const sig_moy_cm1 = @max(state.sig_moy_cm1, 1.0e-6);
    const gam_d = @max(
        dopplerWidthCm1(safe_temperature, sig_moy_cm1, 31.989830),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(hitran_pi);
    const cpf = complexProbabilityFunction(
        (state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        state.population_t[strong_index] *
        state.dipole_t[strong_index] *
        state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
    };
}

fn relaxationWeightAt(relaxation_weights: []const f64, line_count: usize, row: usize, column: usize) f64 {
    // relaxationWeightAt -------------------------------------------------------------------------------------|
    // Read one row-major relaxation-matrix scratch value.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    return relaxation_weights[row * line_count + column];
}

fn setRelaxationWeight(
    relaxation_weights: []f64,
    line_count: usize,
    row: usize,
    column: usize,
    value: f64,
) void {
    // setRelaxationWeight ------------------------------------------------------------------------------------|
    // Write one row-major relaxation-matrix scratch value.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    relaxation_weights[row * line_count + column] = value;
}

fn insideCutoff(
    line: readers.O2LineAssetRow,
    wavelength_nm: f64,
    pressure_atm: f64,
    runtime: RuntimeControls,
) bool {
    // insideCutoff -------------------------------------------------------------------------------------------|
    // Apply the scalar HITRAN cutoff window around the pressure-shifted line center.                          |
    // --------------------------------------------------------------------------------------------------------|
    const shifted_center_wavenumber_cm1 = @max(
        line.center_wavenumber_cm1 + line.pressure_shift_cm1 * pressure_atm,
        1.0,
    );
    return shiftedCenterInsideCutoff(
        shifted_center_wavenumber_cm1,
        wavelengthToWavenumberCm1(wavelength_nm),
        runtime,
    );
}

fn shiftedCenterInsideCutoff(
    shifted_center_wavenumber_cm1: f64,
    evaluation_wavenumber_cm1: f64,
    runtime: RuntimeControls,
) bool {
    // shiftedCenterInsideCutoff ------------------------------------------------------------------------------|
    // Apply old weak-line cutoff behavior, preferring the realized support-grid index route when present.     |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/input/reference/spectroscopy/physics_core.zig` shiftedCenterInsideVendorCutoff.       |
    // --------------------------------------------------------------------------------------------------------|
    if (runtime.cutoff_grid_wavenumbers_cm1.len >= 2 and
        runtime.cutoff_grid_wavenumbers_cm1.len == runtime.cutoff_grid_wavelengths_nm.len)
    {
        const lower_endpoint_index = nearestWavenumberGridIndexFromWavenumbers(
            runtime.cutoff_grid_wavenumbers_cm1,
            shifted_center_wavenumber_cm1 + runtime.cutoff_cm1,
        );
        const upper_endpoint_index = nearestWavenumberGridIndexFromWavenumbers(
            runtime.cutoff_grid_wavenumbers_cm1,
            shifted_center_wavenumber_cm1 - runtime.cutoff_cm1,
        );
        const evaluation_index = nearestWavenumberGridIndexFromWavenumbers(
            runtime.cutoff_grid_wavenumbers_cm1,
            evaluation_wavenumber_cm1,
        );
        return evaluation_index >= @min(lower_endpoint_index, upper_endpoint_index) and
            evaluation_index <= @max(lower_endpoint_index, upper_endpoint_index);
    }

    const center_distance_cm1 = @abs(shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1);
    return center_distance_cm1 <= runtime.cutoff_cm1 + vendor_cutoff_boundary_margin_cm1;
}

fn nearestWavenumberGridIndexFromWavenumbers(wavenumbers_cm1: []const f64, target_wavenumber_cm1: f64) usize {
    // nearestWavenumberGridIndexFromWavenumbers --------------------------------------------------------------|
    // Return the nearest support-grid index in wavenumber space with old minloc tie handling.                 |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(wavenumbers_cm1.len != 0);
    if (wavenumbers_cm1.len == 1) return 0;

    const first_wavenumber_cm1 = wavenumbers_cm1[0];
    const last_index = wavenumbers_cm1.len - 1;
    const last_wavenumber_cm1 = wavenumbers_cm1[last_index];
    const descending = first_wavenumber_cm1 >= last_wavenumber_cm1;
    if (descending) {
        if (target_wavenumber_cm1 >= first_wavenumber_cm1) return 0;
        if (target_wavenumber_cm1 <= last_wavenumber_cm1) return last_index;

        var lower_index: usize = 0;
        var upper_index: usize = last_index;
        while (upper_index - lower_index > 1) {
            const midpoint = lower_index + (upper_index - lower_index) / 2;
            if (wavenumbers_cm1[midpoint] >= target_wavenumber_cm1) {
                lower_index = midpoint;
            } else {
                upper_index = midpoint;
            }
        }
        return nearestOfTwoPrecomputedWavenumberGridIndices(
            wavenumbers_cm1,
            target_wavenumber_cm1,
            lower_index,
            upper_index,
        );
    }

    if (target_wavenumber_cm1 <= first_wavenumber_cm1) return 0;
    if (target_wavenumber_cm1 >= last_wavenumber_cm1) return last_index;

    var lower_index: usize = 0;
    var upper_index: usize = last_index;
    while (upper_index - lower_index > 1) {
        const midpoint = lower_index + (upper_index - lower_index) / 2;
        if (wavenumbers_cm1[midpoint] <= target_wavenumber_cm1) {
            lower_index = midpoint;
        } else {
            upper_index = midpoint;
        }
    }
    return nearestOfTwoPrecomputedWavenumberGridIndices(
        wavenumbers_cm1,
        target_wavenumber_cm1,
        lower_index,
        upper_index,
    );
}

fn nearestOfTwoPrecomputedWavenumberGridIndices(
    wavenumbers_cm1: []const f64,
    target_wavenumber_cm1: f64,
    lower_index: usize,
    upper_index: usize,
) usize {
    // nearestOfTwoPrecomputedWavenumberGridIndices -----------------------------------------------------------|
    // Pick the closest of two support-grid candidates, keeping the lower index on exact ties.                 |
    // --------------------------------------------------------------------------------------------------------|
    const lower_delta = @abs(wavenumbers_cm1[lower_index] - target_wavenumber_cm1);
    const upper_delta = @abs(wavenumbers_cm1[upper_index] - target_wavenumber_cm1);
    return if (upper_delta < lower_delta) upper_index else lower_index;
}

fn complexProbabilityFunction(x: f64, y: f64) ComplexProbability {
    // complexProbabilityFunction -----------------------------------------------------------------------------|
    // Compute the CPF approximation used by the retained weak-line Voigt formula.                             |
    // --------------------------------------------------------------------------------------------------------|
    const t = [_]f64{ 0.314240376, 0.947788391, 1.59768264, 2.27950708, 3.02063703, 3.8897249 };
    const u = [_]f64{ 1.01172805, -0.75197147, 1.2557727e-2, 1.00220082e-2, -2.42068135e-4, 5.00848061e-7 };
    const s = [_]f64{ 1.393237, 0.231152406, -0.155351466, 6.21836624e-3, 9.19082986e-5, -6.27525958e-7 };

    var wr: f64 = 0.0;
    var wi: f64 = 0.0;
    const y1 = y + 1.5;
    const y2 = y1 * y1;

    if (y > 0.85 or @abs(x) < (18.1 * y + 1.65)) {
        for (0..t.len) |index| {
            var r = x - t[index];
            var d = 1.0 / (r * r + y2);
            const d1 = y1 * d;
            const d2 = r * d;
            r = x + t[index];
            d = 1.0 / (r * r + y2);
            const d3 = y1 * d;
            const d4 = r * d;
            wr += u[index] * (d1 + d3) - s[index] * (d2 - d4);
            wi += u[index] * (d2 + d4) + s[index] * (d1 - d3);
        }
    } else {
        if (@abs(x) < 12.0) wr = @exp(-x * x);
        const y3 = y + 3.0;
        for (0..t.len) |index| {
            var r = x - t[index];
            var r2 = r * r;
            var d = 1.0 / (r2 + y2);
            const d1 = y1 * d;
            const d2 = r * d;
            wr += y * (u[index] * (r * d2 - 1.5 * d1) + s[index] * y3 * d2) / (r2 + 2.25);

            r = x + t[index];
            r2 = r * r;
            d = 1.0 / (r2 + y2);
            const d3 = y1 * d;
            const d4 = r * d;
            wr += y * (u[index] * (r * d4 - 1.5 * d3) - s[index] * y3 * d4) / (r2 + 2.25);
            wi += u[index] * (d2 + d4) + s[index] * (d1 - d3);
        }
    }

    return .{ .wr = wr, .wi = wi };
}

fn wavelengthToWavenumberCm1(wavelength_nm: f64) f64 {
    // wavelengthToWavenumberCm1 ------------------------------------------------------------------------------|
    // Convert nanometer wavelength to inverse-centimeter wavenumber with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
    // wavenumberToWavelengthNm -------------------------------------------------------------------------------|
    // Convert inverse-centimeter wavenumber to nanometer wavelength with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavenumber_cm1, 1.0e-9);
}

fn dopplerWidthCm1(temperature_k: f64, wavenumber_cm1: f64, molecular_weight_g_per_mol: f64) f64 {
    // dopplerWidthCm1 ----------------------------------------------------------------------------------------|
    // Compute HITRAN Doppler half-width in inverse centimeters from temperature and molecular mass.           |
    // --------------------------------------------------------------------------------------------------------|
    const prefactor = @sqrt(
        2.0 * @log(2.0) * hitran_gas_constant_j_per_mol_k /
            (hitran_speed_of_light_m_per_s * hitran_speed_of_light_m_per_s),
    );
    return prefactor *
        std.math.sqrt(@max(temperature_k, 1.0)) /
        std.math.sqrt(@max(molecular_weight_g_per_mol / 1.0e3, 1.0e-12)) *
        wavenumber_cm1;
}

fn partitionRatioT0OverT(line: readers.O2LineAssetRow, temperature_k: f64) f64 {
    // partitionRatioT0OverT ----------------------------------------------------------------------------------|
    // Return HITRAN partition Q(T0) / Q(T) from the retained TIPS tables, with old-route fallback exponents.  |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Fallback exponents match main:`src/input/reference/spectroscopy/strong_lines.zig`: O2/O3 use 1.0,     |
    //   CO2 uses 1.35, H2O uses 1.10, and unlisted isotopologues use 1.0 + 0.04 * (isotope_number - 1).       |
    // --------------------------------------------------------------------------------------------------------|
    const isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number);
    if (hitran_partition_tables.ratioT0OverT(
        isotopologue_code,
        temperature_k,
        hitran_reference_temperature_k,
    )) |ratio| {
        return ratio;
    }

    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const exponent: f64 = switch (isotopologue_code) {
        66, 68, 67, 101, 102 => 1.0,
        626, 636, 628, 627, 638, 637 => 1.35,
        161, 181, 171, 162, 182, 172 => 1.10,
        else => 1.0 + 0.04 * @as(f64, @floatFromInt(@max(line.isotope_number, 1) - 1)),
    };
    return std.math.pow(f64, hitran_reference_temperature_k / safe_temperature, exponent);
}

fn molecularWeightForLine(line: readers.O2LineAssetRow) f64 {
    // molecularWeightForLine ---------------------------------------------------------------------------------|
    // Return isotopologue molecular mass, falling back to the parent gas mass for unsupported codes.          |
    // --------------------------------------------------------------------------------------------------------|
    return switch (deriveIsotopologueCode(line.gas_index, line.isotope_number)) {
        161 => 18.010565,
        181 => 20.014811,
        171 => 19.014780,
        162 => 19.016740,
        182 => 21.020985,
        172 => 20.020956,
        626 => 43.989830,
        636 => 44.993185,
        628 => 45.994076,
        627 => 44.994045,
        638 => 46.997431,
        637 => 45.997400,
        26 => 27.994915,
        36 => 28.998270,
        28 => 29.999161,
        27 => 28.999130,
        38 => 31.002516,
        37 => 30.002485,
        211 => 16.031300,
        311 => 17.034655,
        212 => 17.037475,
        66 => 31.989830,
        68 => 33.994076,
        67 => 32.994045,
        4111 => 17.026549,
        5111 => 18.023583,
        else => switch (line.gas_index) {
            1 => 18.01528,
            2 => 44.0095,
            5 => 28.0101,
            6 => 16.0425,
            7 => 31.9988,
            10 => 46.0055,
            11 => 17.0305,
            else => 28.97,
        },
    };
}

fn deriveIsotopologueCode(gas_index: u16, isotope_number: u8) i32 {
    // deriveIsotopologueCode ---------------------------------------------------------------------------------|
    // Map HITRAN gas/isotope indexes to the retained DISAMAR isotopologue partition-table code.               |
    // --------------------------------------------------------------------------------------------------------|
    return switch (gas_index) {
        1 => switch (isotope_number) {
            1 => 161,
            2 => 181,
            3 => 171,
            4 => 162,
            5 => 182,
            6 => 172,
            else => 160 + @as(i32, @intCast(isotope_number)),
        },

        7 => switch (isotope_number) {
            1 => 66,
            2 => 68,
            3 => 67,
            4 => 69,
            else => 70 + @as(i32, @intCast(isotope_number)),
        },

        2 => switch (isotope_number) {
            1 => 626,
            2 => 636,
            3 => 628,
            4 => 627,
            5 => 638,
            6 => 637,
            else => 620 + @as(i32, @intCast(isotope_number)),
        },

        5 => switch (isotope_number) {
            1 => 26,
            2 => 36,
            3 => 28,
            4 => 27,
            5 => 38,
            6 => 37,
            else => 20 + @as(i32, @intCast(isotope_number)),
        },

        6 => switch (isotope_number) {
            1 => 211,
            2 => 311,
            3 => 212,
            else => 210 + @as(i32, @intCast(isotope_number)),
        },

        11 => switch (isotope_number) {
            1 => 4111,
            2 => 5111,
            else => 4100 + @as(i32, @intCast(isotope_number)),
        },

        else => @as(i32, gas_index) * 100 + @as(i32, isotope_number),
    };
}
