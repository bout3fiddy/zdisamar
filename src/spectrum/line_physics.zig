const std = @import("std");

const readers = @import("../assets/readers.zig");
const CostTiming = @import("../instrumentation/cost_timing.zig");
const hitran_partition_tables = @import("../input/hitran_partition_tables.zig");

const Allocator = std.mem.Allocator;

const hitran_reference_temperature_k = 296.0;
const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
const hitran_hc_over_kb_cm_k = 1.4387770;
const hitran_gas_constant_j_per_mol_k = 8.3144621;
const hitran_speed_of_light_m_per_s = 2.99792458e8;
const hitran_pi = 3.1415926536;

pub const min_hitran_temperature_k = 150.0;
pub const min_spectroscopy_pressure_atm = 1.0e-12;
pub const max_strong_line_sidecars: usize = 128;
pub const vendor_cutoff_boundary_margin_cm1 = 0.115;
pub const vendor_cutoff_prewindow_margin_cm1 = 0.25;

// line_physics.zig ------------------------------------------------------------------------------------------ |
// Shared O2 HITRAN weak-line and ConvTP sidecar spectroscopy kernels.                                         |
//                                                                                                             |
// boundary                                                                                                    |
//   This file owns scalar line physics only. Callers pass parsed line rows, thermodynamic scalars, wavelength |
//   scalars, and optional cutoff-grid slices; cache and diagnostic owners attach storage, row metadata, and   |
//   public ABI details outside this module.                                                                   |
//                                                                                                             |
// ------------------------------------------------------------------------------------------------------------|

// SpectroscopyComponents ------------------------------------------------------------------------------------ |
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
pub const SpectroscopyComponents = struct {
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// StrongLinePreparedState ----------------------------------------------------------------------------------- |
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
pub const StrongLinePreparedState = struct {
    line_count: usize = 0,
    sig_moy_cm1: f64 = 0.0,
    population_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    dipole_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    mod_sig_cm1: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    half_width_cm1_at_t: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
    line_mixing_coefficients: [max_strong_line_sidecars]f64 = [_]f64{0.0} ** max_strong_line_sidecars,
};
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedLineState --------------------------------------------------------------------------------- |
// Per-line weak-lane constants prepared for one temperature and pressure.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] shifted_center_wavenumber_cm1 : f64                                                                |
// [ 8..15] cte                           : f64                                                                |
// [16..23] line_shape_y                  : f64                                                                |
// [24..31] prefactor_base                : f64                                                                |
pub const WeakLinePreparedLineState = struct {
    shifted_center_wavenumber_cm1: f64,
    cte: f64,
    line_shape_y: f64,
    prefactor_base: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// WeakLinePreparedState ------------------------------------------------------------------------------------- |
// Header over weak-line constants prepared for one temperature and pressure.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count       : usize                                                                           |
// [ 8..15] safe_temperature : f64                                                                             |
// [16..23] safe_pressure    : f64                                                                             |
// [24..39] lines            : []WeakLinePreparedLineState                                                     |
pub const WeakLinePreparedState = struct {
    line_count: usize,
    safe_temperature: f64,
    safe_pressure: f64,
    lines: []WeakLinePreparedLineState,

    pub fn deinit(self: *WeakLinePreparedState, allocator: Allocator) void {
        // WeakLinePreparedState.deinit ---------------------------------------------------------------------- |
        // Release per-line weak-lane constants prepared for one temperature/pressure profile node.            |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.lines);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// LineWindow ------------------------------------------------------------------------------------------------ |
// Borrowed wavelength-local line slice plus its start index in the sorted source list.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] lines       : []const LineAssetRow                                                                 |
// [16..23] start_index : usize                                                                                |
pub const LineWindow = struct {
    lines: []const readers.LineAssetRow,
    start_index: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// WeakLineWavelengthState ----------------------------------------------------------------------------------- |
// Wavelength-local weak-line state shared by every prepared line evaluated at that wavelength.                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] evaluation_wavenumber_cm1 : f64                                                                    |
// [ 8..23] cutoff_grid_index        : ?usize                                                                  |
pub const WeakLineWavelengthState = struct {
    evaluation_wavenumber_cm1: f64,
    cutoff_grid_index: ?usize,
};
// ------------------------------------------------------------------------------------------------------------|

const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};

pub fn fillWeakLineStateInto(
    state: *WeakLinePreparedState,
    lines: []const readers.LineAssetRow,
    temperature_k: f64,
    pressure_atm: f64,
    stage_cost: ?CostTiming.Active,
) void {
    // fillWeakLineStateInto --------------------------------------------------------------------------------- |
    // Fill canonical weak-line constants for one already-allocated thermodynamic state row.                   |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const safe_pressure = @max(pressure_atm, min_spectroscopy_pressure_atm);
    std.debug.assert(state.lines.len == lines.len);
    state.line_count = lines.len;
    state.safe_temperature = safe_temperature;
    state.safe_pressure = safe_pressure;
    for (lines, state.lines) |line, *prepared_line| {
        prepared_line.* = prepareWeakLinePreparedLineState(line, safe_temperature, safe_pressure, stage_cost);
    }
}

fn prepareWeakLinePreparedLineState(
    line: readers.LineAssetRow,
    safe_temperature: f64,
    safe_pressure: f64,
    stage_cost: ?CostTiming.Active,
) WeakLinePreparedLineState {
    // prepareWeakLinePreparedLineState ---------------------------------------------------------------------- |
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
        partitionRatioT0OverT(line, safe_temperature, stage_cost) *
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

pub fn totalSpectroscopyAt(
    runtime_lines: []const readers.LineAssetRow,
    window: LineWindow,
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    wavelength_nm: f64,
    wavelength_state: WeakLineWavelengthState,
    temperature_k: f64,
    pressure_hpa: f64,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
    line_mixing_factor: f64,
    strong_state: *const StrongLinePreparedState,
    prepared_weak_state: ?*const WeakLinePreparedState,
    stage_cost: ?CostTiming.Active,
) SpectroscopyComponents {
    // totalSpectroscopyAt ----------------------------------------------------------------------------------- |
    // Sum canonical weak, strong-line, and line-mixing sigma for one profile-node row.                        |
    // --------------------------------------------------------------------------------------------------------|
    if (runtime_lines.len == 0) return .{};

    const timing_start = CostTiming.start(stage_cost);
    defer CostTiming.finish(stage_cost, timing_start, "spectroscopy_sigma");

    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const pressure_atm = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
    const vendor_partition = usesVendorStrongLinePartition(runtime_lines, strong_lines);
    const prepared_state = prepared_weak_state;
    const prepared_matches = if (prepared_state) |state|
        state.line_count == runtime_lines.len and state.lines.len == runtime_lines.len
    else
        false;

    const stimulated_emission_scale: f64 = choose_stimulated_scale: {
        if (!prepared_matches) break :choose_stimulated_scale 0.0;

        break :choose_stimulated_scale weakLinePreparedStimulatedEmissionScale(
            wavelength_state.evaluation_wavenumber_cm1,
            prepared_state.?.safe_temperature,
        );
    };
    const thermodynamic_scale: f64 = choose_thermodynamic_scale: {
        if (!prepared_matches) break :choose_thermodynamic_scale 0.0;

        break :choose_thermodynamic_scale weakLinePreparedThermodynamicScale(
            prepared_state.?.safe_temperature,
            prepared_state.?.safe_pressure,
        );
    };
    var weak_line_sigma: f64 = 0.0;
    for (window.lines, 0..) |line, line_index| {
        if (shouldExcludeWeakLine(line, line_index, window.lines, strong_lines, vendor_partition)) continue;

        if (prepared_matches) {
            weak_line_sigma += weakLinePreparedContribution(
                wavelength_state,
                prepared_state.?.lines[window.start_index + line_index],
                cutoff_cm1,
                cutoff_grid_wavelengths_nm,
                cutoff_grid_wavenumbers_cm1,
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
            cutoff_cm1,
            cutoff_grid_wavelengths_nm,
            cutoff_grid_wavenumbers_cm1,
            stage_cost,
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
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule * line_mixing_factor;
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

pub fn weakLineSigmaAtPrepared(
    active_lines: []const readers.LineAssetRow,
    window: LineWindow,
    state: *const WeakLinePreparedState,
    wavelength_state: WeakLineWavelengthState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) f64 {
    // weakLineSigmaAtPrepared ------------------------------------------------------------------------------- |
    // Sum weak-line Voigt contributions using one thermodynamic state's prepared line constants.              |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(state.line_count == active_lines.len);
    std.debug.assert(state.lines.len == active_lines.len);

    const stimulated_emission_scale = weakLinePreparedStimulatedEmissionScale(
        wavelength_state.evaluation_wavenumber_cm1,
        state.safe_temperature,
    );
    const thermodynamic_scale = weakLinePreparedThermodynamicScale(state.safe_temperature, state.safe_pressure);
    var sigma: f64 = 0.0;
    for (window.lines, 0..) |_, line_index| {
        sigma += weakLinePreparedContribution(
            wavelength_state,
            state.lines[window.start_index + line_index],
            cutoff_cm1,
            cutoff_grid_wavelengths_nm,
            cutoff_grid_wavenumbers_cm1,
            stimulated_emission_scale,
            thermodynamic_scale,
        );
    }
    return sigma;
}

pub fn weakLineSigmaAtPreparedFiniteDifference(
    active_lines: []const readers.LineAssetRow,
    window: LineWindow,
    state: *const WeakLinePreparedState,
    wavelength_state: WeakLineWavelengthState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) f64 {
    // weakLineSigmaAtPreparedFiniteDifference --------------------------------------------------------------- |
    // Evaluate T +/- 0.5 K rows with the scalar canonical multiplication order for d_sigma/dT evidence.       |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(state.line_count == active_lines.len);
    std.debug.assert(state.lines.len == active_lines.len);

    const stimulated_emission_scale = weakLinePreparedStimulatedEmissionScale(
        wavelength_state.evaluation_wavenumber_cm1,
        state.safe_temperature,
    );
    var sigma: f64 = 0.0;
    for (window.lines, 0..) |_, line_index| {
        sigma += weakLinePreparedContributionFiniteDifference(
            wavelength_state,
            state.lines[window.start_index + line_index],
            cutoff_cm1,
            cutoff_grid_wavelengths_nm,
            cutoff_grid_wavenumbers_cm1,
            stimulated_emission_scale,
            state.safe_temperature,
            state.safe_pressure,
        );
    }
    return sigma;
}

pub fn relevantLineWindow(
    active_lines: []const readers.LineAssetRow,
    wavelength_nm: f64,
    cutoff_cm1: f64,
) LineWindow {
    // relevantLineWindow ------------------------------------------------------------------------------------ |
    // Return the center-wavelength slice that can fall inside the canonical cutoff prewindow.                 |
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

fn usesVendorStrongLinePartition(
    lines: []const readers.LineAssetRow,
    strong_lines: []const readers.StrongLineAssetRow,
) bool {
    // usesVendorStrongLinePartition ------------------------------------------------------------------------- |
    // Detect the sidecar partition from retained HITRAN branch metadata.                                 |
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
    line: readers.LineAssetRow,
    line_index: usize,
    window: []const readers.LineAssetRow,
    strong_lines: []const readers.StrongLineAssetRow,
    vendor_partition: bool,
) bool {
    // shouldExcludeWeakLine --------------------------------------------------------------------------------- |
    // Keep lines covered by O2 strong-line sidecars out of the total weak-line contribution.                  |
    // --------------------------------------------------------------------------------------------------------|
    if (vendor_partition) {
        if (!isVendorStrongCandidateFromSource(line)) return false;
        return findStrongLineMatch(strong_lines, line.center_wavelength_nm) != null;
    }

    const strong_index = findStrongLineMatch(strong_lines, line.center_wavelength_nm) orelse return false;
    return strongestWindowAnchorForSidecar(window, strong_lines[strong_index]) == line_index;
}

fn strongestWindowAnchorForSidecar(
    window: []const readers.LineAssetRow,
    strong_line: readers.StrongLineAssetRow,
) usize {
    // strongestWindowAnchorForSidecar ----------------------------------------------------------------------- |
    // Select the generic sidecar anchor: closest line center, then strongest line on an equal delta.          |
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

pub fn findStrongLineMatch(strong_lines: []const readers.StrongLineAssetRow, wavelength_nm: f64) ?usize {
    // findStrongLineMatch ----------------------------------------------------------------------------------- |
    // Return the closest LISA sidecar center within the tolerance rule.                                       |
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

pub fn isVendorStrongCandidateFromSource(line: readers.LineAssetRow) bool {
    // isVendorStrongCandidateFromSource ------------------------------------------------------------------    |
    // Match support.zig: only source-marked O2 isotope-1 P-branch rows participate in vendor partition.       |
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

pub fn weakLineContribution(
    wavelength_nm: f64,
    line: readers.LineAssetRow,
    temperature_k: f64,
    pressure_atm: f64,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
    stage_cost: ?CostTiming.Active,
) f64 {
    // weakLineContribution ---------------------------------------------------------------------------------- |
    // Evaluate one HITRAN weak-line contribution with the scalar fallback cutoff and CPF route.               |
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
    // --------------------------------------------------------------------------------------------------------|
    if (!insideCutoff(
        line,
        wavelength_nm,
        pressure_atm,
        cutoff_cm1,
        cutoff_grid_wavelengths_nm,
        cutoff_grid_wavenumbers_cm1,
    )) return 0.0;

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
        partitionRatioT0OverT(line, temperature_k, stage_cost) *
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
    // weakLinePreparedStimulatedEmissionScale --------------------------------------------------------------- |
    // Compute the wavelength term shared by all prepared weak lines at one thermodynamic point.               |
    // --------------------------------------------------------------------------------------------------------|
    return evaluation_wavenumber_cm1 *
        (1.0 - @exp(-hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature));
}

fn weakLinePreparedThermodynamicScale(safe_temperature: f64, safe_pressure: f64) f64 {
    // weakLinePreparedThermodynamicScale -------------------------------------------------------------------- |
    // Compute the number-density conversion shared by all prepared weak lines at one thermodynamic point.     |
    // --------------------------------------------------------------------------------------------------------|
    return safe_temperature *
        hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;
}

fn weakLinePreparedContribution(
    wavelength_state: WeakLineWavelengthState,
    prepared_line: WeakLinePreparedLineState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
    stimulated_emission_scale: f64,
    thermodynamic_scale: f64,
) f64 {
    // weakLinePreparedContribution -------------------------------------------------------------------------- |
    // Evaluate one prepared weak-line contribution with the scalar fallback cutoff and CPF route.             |
    // --------------------------------------------------------------------------------------------------------|
    if (!preparedInsideCutoff(
        prepared_line,
        wavelength_state,
        cutoff_cm1,
        cutoff_grid_wavelengths_nm,
        cutoff_grid_wavenumbers_cm1,
    )) return 0.0;

    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1) *
            prepared_line.cte,
        prepared_line.line_shape_y,
    );
    const prefactor = prepared_line.prefactor_base *
        stimulated_emission_scale *
        thermodynamic_scale;
    return @max(prefactor * cpf.wr, 0.0);
}

fn weakLinePreparedContributionFiniteDifference(
    wavelength_state: WeakLineWavelengthState,
    prepared_line: WeakLinePreparedLineState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
    stimulated_emission_scale: f64,
    safe_temperature: f64,
    safe_pressure: f64,
) f64 {
    // weakLinePreparedContributionFiniteDifference ---------------------------------------------------------- |
    // Match weakLineContribution's multiply/divide order for pinned d_sigma/dT finite-difference rows.        |
    // --------------------------------------------------------------------------------------------------------|
    if (!preparedInsideCutoff(
        prepared_line,
        wavelength_state,
        cutoff_cm1,
        cutoff_grid_wavelengths_nm,
        cutoff_grid_wavenumbers_cm1,
    )) return 0.0;

    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1) *
            prepared_line.cte,
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
    wavelength_state: WeakLineWavelengthState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) bool {
    // preparedInsideCutoff ---------------------------------------------------------------------------------- |
    // Apply the HITRAN cutoff around a pre-shifted line center.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return shiftedCenterInsideCutoff(
        prepared_line.shifted_center_wavenumber_cm1,
        wavelength_state,
        cutoff_cm1,
        cutoff_grid_wavelengths_nm,
        cutoff_grid_wavenumbers_cm1,
    );
}

pub fn prepareStrongLineState(
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    temperature_k: f64,
    pressure_atm: f64,
    stage_cost: ?CostTiming.Active,
) StrongLinePreparedState {
    // prepareStrongLineState -------------------------------------------------------------------------------- |
    // Prepare O2 ConvTP line-mixing state for one profile-node temperature and pressure.                      |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const temperature_ratio = hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(
        66,
        safe_temperature,
        hitran_reference_temperature_k,
        stage_cost,
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
    strong_lines: []const readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    line_count: usize,
    safe_temperature: f64,
    temperature_ratio: f64,
    partition_ratio: f64,
    pressure_atm: f64,
) void {
    // fillStrongLineState ----------------------------------------------------------------------------------- |
    // Fill DISAMAR O2 line-mixing relaxation state for all retained strong-line sidecars.                     |
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

pub fn strongLineContribution(
    wavelength_nm: f64,
    strong_index: usize,
    state: *const StrongLinePreparedState,
    temperature_k: f64,
    pressure_atm: f64,
) SpectroscopyComponents {
    // strongLineContribution -------------------------------------------------------------------------------- |
    // Evaluate one prepared O2 strong-line sidecar with the CPF line-mixing formula.                          |
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
    // relaxationWeightAt ------------------------------------------------------------------------------------ |
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
    // setRelaxationWeight ----------------------------------------------------------------------------------- |
    // Write one row-major relaxation-matrix scratch value.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    relaxation_weights[row * line_count + column] = value;
}

fn insideCutoff(
    line: readers.LineAssetRow,
    wavelength_nm: f64,
    pressure_atm: f64,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) bool {
    // insideCutoff ------------------------------------------------------------------------------------------ |
    // Apply the scalar HITRAN cutoff window around the pressure-shifted line center.                          |
    // --------------------------------------------------------------------------------------------------------|
    return shiftedCenterInsideCutoff(
        shiftedCenterWavenumberCm1(line, pressure_atm),
        prepareWeakLineWavelengthState(wavelength_nm, cutoff_grid_wavelengths_nm, cutoff_grid_wavenumbers_cm1),
        cutoff_cm1,
        cutoff_grid_wavelengths_nm,
        cutoff_grid_wavenumbers_cm1,
    );
}

pub fn shiftedCenterWavenumberCm1(line: readers.LineAssetRow, pressure_atm: f64) f64 {
    // shiftedCenterWavenumberCm1 ---------------------------------------------------------------------------- |
    // Apply the pressure-shifted line-center floor before cutoff checks and public row projection.            |
    // --------------------------------------------------------------------------------------------------------|
    return @max(line.center_wavenumber_cm1 + line.pressure_shift_cm1 * pressure_atm, 1.0);
}

pub fn prepareWeakLineWavelengthState(
    wavelength_nm: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) WeakLineWavelengthState {
    // prepareWeakLineWavelengthState ------------------------------------------------------------------------ |
    // Prepare the wavelength-local weak-line cutoff state shared across one exact wavelength.                 |
    // --------------------------------------------------------------------------------------------------------|
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const cutoff_grid_index = choose_cutoff_grid_index: {
        if (cutoff_grid_wavenumbers_cm1.len >= 2 and
            cutoff_grid_wavenumbers_cm1.len == cutoff_grid_wavelengths_nm.len)
        {
            break :choose_cutoff_grid_index nearestWavenumberGridIndexFromWavenumbers(
                cutoff_grid_wavenumbers_cm1,
                evaluation_wavenumber_cm1,
            );
        }

        break :choose_cutoff_grid_index null;
    };
    return .{
        .evaluation_wavenumber_cm1 = evaluation_wavenumber_cm1,
        .cutoff_grid_index = cutoff_grid_index,
    };
}

fn shiftedCenterInsideCutoff(
    shifted_center_wavenumber_cm1: f64,
    wavelength_state: WeakLineWavelengthState,
    cutoff_cm1: f64,
    cutoff_grid_wavelengths_nm: []const f64,
    cutoff_grid_wavenumbers_cm1: []const f64,
) bool {
    // shiftedCenterInsideCutoff ----------------------------------------------------------------------------- |
    // Apply weak-line cutoff behavior, preferring the realized support-grid index route when present.         |
    // --------------------------------------------------------------------------------------------------------|
    if (cutoff_grid_wavenumbers_cm1.len >= 2 and
        cutoff_grid_wavenumbers_cm1.len == cutoff_grid_wavelengths_nm.len)
    {
        const lower_endpoint_index = nearestWavenumberGridIndexFromWavenumbers(
            cutoff_grid_wavenumbers_cm1,
            shifted_center_wavenumber_cm1 + cutoff_cm1,
        );
        const upper_endpoint_index = nearestWavenumberGridIndexFromWavenumbers(
            cutoff_grid_wavenumbers_cm1,
            shifted_center_wavenumber_cm1 - cutoff_cm1,
        );
        const evaluation_index = wavelength_state.cutoff_grid_index.?;
        return evaluation_index >= @min(lower_endpoint_index, upper_endpoint_index) and
            evaluation_index <= @max(lower_endpoint_index, upper_endpoint_index);
    }

    const center_distance_cm1 = @abs(shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1);
    return center_distance_cm1 <= cutoff_cm1 + vendor_cutoff_boundary_margin_cm1;
}

fn lowerBoundByCenterWavelength(lines: []const readers.LineAssetRow, wavelength_nm: f64) usize {
    // lowerBoundByCenterWavelength -------------------------------------------------------------------------- |
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

fn nearestWavenumberGridIndexFromWavenumbers(wavenumbers_cm1: []const f64, target_wavenumber_cm1: f64) usize {
    // nearestWavenumberGridIndexFromWavenumbers ------------------------------------------------------------- |
    // Return the nearest support-grid index in wavenumber space with minloc tie handling.                     |
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
    // nearestOfTwoPrecomputedWavenumberGridIndices ---------------------------------------------------------- |
    // Pick the closest of two support-grid candidates, keeping the lower index on exact ties.                 |
    // --------------------------------------------------------------------------------------------------------|
    const lower_delta = @abs(wavenumbers_cm1[lower_index] - target_wavenumber_cm1);
    const upper_delta = @abs(wavenumbers_cm1[upper_index] - target_wavenumber_cm1);
    return if (upper_delta < lower_delta) upper_index else lower_index;
}

fn complexProbabilityFunction(x: f64, y: f64) ComplexProbability {
    // complexProbabilityFunction ---------------------------------------------------------------------------- |
    // Compute the CPF approximation used by the retained weak-line and strong-line Voigt formulas.            |
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

pub fn wavelengthToWavenumberCm1(wavelength_nm: f64) f64 {
    // wavelengthToWavenumberCm1 ----------------------------------------------------------------------------- |
    // Convert nanometer wavelength to inverse-centimeter wavenumber with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

pub fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
    // wavenumberToWavelengthNm ------------------------------------------------------------------------------ |
    // Convert inverse-centimeter wavenumber to nanometer wavelength with a positive divisor floor.            |
    // --------------------------------------------------------------------------------------------------------|
    return 1.0e7 / @max(wavenumber_cm1, 1.0e-9);
}

fn dopplerWidthCm1(temperature_k: f64, wavenumber_cm1: f64, molecular_weight_g_per_mol: f64) f64 {
    // dopplerWidthCm1 --------------------------------------------------------------------------------------- |
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

fn partitionRatioT0OverT(
    line: readers.LineAssetRow,
    temperature_k: f64,
    stage_cost: ?CostTiming.Active,
) f64 {
    // partitionRatioT0OverT --------------------------------------------------------------------------------- |
    // Return HITRAN partition Q(T0) / Q(T) from the retained TIPS tables, with canonical fallback exponents.  |
    // --------------------------------------------------------------------------------------------------------|
    const isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number);
    if (hitran_partition_tables.ratioT0OverT(
        isotopologue_code,
        temperature_k,
        hitran_reference_temperature_k,
        stage_cost,
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

fn molecularWeightForLine(line: readers.LineAssetRow) f64 {
    // molecularWeightForLine -------------------------------------------------------------------------------- |
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

pub fn deriveIsotopologueCode(gas_index: u16, isotope_number: u8) i32 {
    // deriveIsotopologueCode -------------------------------------------------------------------------------- |
    // Map HITRAN gas/isotope indexes to the retained DISAMAR isotopologue partition-table code.               |
    // --------------------------------------------------------------------------------------------------------|
    return switch (gas_index) {
        1 => waterIsotopologueCode(isotope_number),
        2 => co2IsotopologueCode(isotope_number),
        5 => coIsotopologueCode(isotope_number),
        6 => ch4IsotopologueCode(isotope_number),
        7 => o2IsotopologueCode(isotope_number),
        11 => no2IsotopologueCode(isotope_number),
        else => @as(i32, gas_index) * 100 + @as(i32, isotope_number),
    };
}

fn waterIsotopologueCode(isotope_number: u8) i32 {
    // waterIsotopologueCode --------------------------------------------------------------------------------- |
    // Map HITRAN water isotope numbers to retained partition-table codes.                                     |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 161,
        2 => 181,
        3 => 171,
        4 => 162,
        5 => 182,
        6 => 172,
        else => 160 + @as(i32, @intCast(isotope_number)),
    };
}

fn co2IsotopologueCode(isotope_number: u8) i32 {
    // co2IsotopologueCode ----------------------------------------------------------------------------------- |
    // Map HITRAN CO2 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 626,
        2 => 636,
        3 => 628,
        4 => 627,
        5 => 638,
        6 => 637,
        else => 620 + @as(i32, @intCast(isotope_number)),
    };
}

fn coIsotopologueCode(isotope_number: u8) i32 {
    // coIsotopologueCode ------------------------------------------------------------------------------------ |
    // Map HITRAN CO isotope numbers to retained partition-table codes.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 26,
        2 => 36,
        3 => 28,
        4 => 27,
        5 => 38,
        6 => 37,
        else => 20 + @as(i32, @intCast(isotope_number)),
    };
}

fn ch4IsotopologueCode(isotope_number: u8) i32 {
    // ch4IsotopologueCode ----------------------------------------------------------------------------------- |
    // Map HITRAN CH4 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 211,
        2 => 311,
        3 => 212,
        else => 210 + @as(i32, @intCast(isotope_number)),
    };
}

fn o2IsotopologueCode(isotope_number: u8) i32 {
    // o2IsotopologueCode ------------------------------------------------------------------------------------ |
    // Map HITRAN O2 isotope numbers to retained partition-table codes.                                        |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 66,
        2 => 68,
        3 => 67,
        else => 70 + @as(i32, @intCast(isotope_number)),
    };
}

fn no2IsotopologueCode(isotope_number: u8) i32 {
    // no2IsotopologueCode ----------------------------------------------------------------------------------- |
    // Map HITRAN NO2 isotope numbers to retained partition-table codes.                                       |
    // --------------------------------------------------------------------------------------------------------|
    return switch (isotope_number) {
        1 => 4111,
        2 => 5111,
        else => 4100 + @as(i32, @intCast(isotope_number)),
    };
}
