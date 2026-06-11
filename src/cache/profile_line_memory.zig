const std = @import("std");

const readers = @import("../assets/readers.zig");
const hashing = @import("../common/hashing.zig");
const hitran_partition_tables = @import("../input/hitran_partition_tables.zig");
const o2_case = @import("../input/o2_case.zig");
const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const line_tables = @import("../setup/line_tables.zig");

const Allocator = std.mem.Allocator;
const hitran_reference_temperature_k = 296.0;
const hitran_boltzmann_constant_j_per_k = 1.3806488e-23;
const hitran_boltzmann_constant_cm3_hpa_per_k = 1.380658e-19;
const hitran_hc_over_kb_cm_k = 1.4387770;
const hitran_gas_constant_j_per_mol_k = 8.3144621;
const hitran_speed_of_light_m_per_s = 2.99792458e8;
const hitran_pi = 3.1415926536;
const min_spectroscopy_pressure_atm = 1.0e-12;

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
// One weak-line value at a single exact wavelength and layer profile node.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                     : f64                                                            |
// [ 8..11] layer_index                       : u32                                                            |
// [12..15] interval_index_1based             : u32                                                            |
// [16..23] pressure_hpa                      : f64                                                            |
// [24..31] temperature_k                     : f64                                                            |
// [32..39] weak_line_sigma_cm2_per_molecule  : f64                                                            |
// [40..47] d_sigma_d_temperature_cm2_per_molecule_per_k : f64                                                 |
pub const ProfileLineValue = struct {
    wavelength_nm: f64,
    layer_index: u32,
    interval_index_1based: u32,
    pressure_hpa: f64,
    temperature_k: f64,
    weak_line_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ProfileLineValues ------------------------------------------------------------------------------------------|
// Owner for the wavelength-major weak-line value grid.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] values            : []ProfileLineValue                                                             |
// [16..23] wavelength_count  : usize                                                                          |
// [24..31] profile_node_count: usize                                                                          |
// [32..39] reuse_stamp       : ReuseStamp                                                                     |
//                                                                                                             |
// referenced storage                                                                                          |
//   values owns wavelength_count * profile_node_count rows and is released by deinit.                         |
pub const ProfileLineValues = struct {
    values: []ProfileLineValue = &.{},
    wavelength_count: usize = 0,
    profile_node_count: usize = 0,
    reuse_stamp: hashing.ReuseStamp = .{},

    pub fn deinit(self: *ProfileLineValues, allocator: Allocator) void {
        // ProfileLineValues.deinit ---------------------------------------------------------------------------|
        // Release exact-route profile-line rows owned by this memory object.                                  |
        // ----------------------------------------------------------------------------------------------------|
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
};
// ------------------------------------------------------------------------------------------------------------|

pub fn buildReferenceProfileLineValues(
    allocator: Allocator,
    case: o2_case.O2Case,
) !ProfileLineValues {
    // buildReferenceProfileLineValues ------------------------------------------------------------------------|
    // Build weak-line values over the exact setup wavelengths and computed layer representative nodes.        |
    // --------------------------------------------------------------------------------------------------------|
    var layers = try atmosphere_layers.build(allocator, case);
    defer layers.deinit(allocator);
    var lines = try line_tables.build(allocator, case);
    defer lines.deinit(allocator);

    const wavelength_count = case.spectral_grid.sample_count;
    const profile_node_count = layers.layer_pressures_hpa.len;
    const values = try allocator.alloc(ProfileLineValue, wavelength_count * profile_node_count);
    errdefer allocator.free(values);

    const runtime = RuntimeControls{
        .cutoff_cm1 = lines.cutoff_sim_cm1,
    };
    const line_strength_threshold = thresholdStrength(lines.rows, lines.threshold_line_sim);
    const active_lines = try collectActiveLines(
        allocator,
        lines.rows,
        lines.isotopes_sim,
        line_strength_threshold,
    );
    defer allocator.free(active_lines);

    const step_nm = if (wavelength_count > 1)
        (case.spectral_grid.end_nm - case.spectral_grid.start_nm) / @as(f64, @floatFromInt(wavelength_count - 1))
    else
        0.0;

    for (0..wavelength_count) |wavelength_index| {
        const wavelength_nm = case.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(wavelength_index));
        for (0..profile_node_count) |profile_node_index| {
            const row_index = wavelength_index * profile_node_count + profile_node_index;
            const pressure_hpa = layers.layer_pressures_hpa[profile_node_index];
            const temperature_k = layers.layer_temperatures_k[profile_node_index];
            const sigma = weakLineSigmaAt(
                active_lines,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                runtime,
            );
            const upper_sigma = weakLineSigmaAt(
                active_lines,
                wavelength_nm,
                temperature_k + 0.5,
                pressure_hpa,
                runtime,
            );
            const lower_sigma = weakLineSigmaAt(
                active_lines,
                wavelength_nm,
                @max(temperature_k - 0.5, min_hitran_temperature_k),
                pressure_hpa,
                runtime,
            );

            values[row_index] = .{
                .wavelength_nm = wavelength_nm,
                .layer_index = @intCast(profile_node_index),
                .interval_index_1based = layers.layer_interval_indices_1based[profile_node_index],
                .pressure_hpa = pressure_hpa,
                .temperature_k = temperature_k,
                .weak_line_sigma_cm2_per_molecule = sigma,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = (upper_sigma - lower_sigma) / 1.0,
            };
        }
    }

    return .{
        .values = values,
        .wavelength_count = wavelength_count,
        .profile_node_count = profile_node_count,
        .reuse_stamp = hashing.ReuseStamp.fromBytes(case.id),
    };
}

// RuntimeControls --------------------------------------------------------------------------------------------|
// Borrowed line-list controls needed by weak-line setup evaluation.                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] cutoff_cm1 : f64                                                                                     |
const RuntimeControls = struct {
    cutoff_cm1: f64,
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

fn lessByCenterWavelength(_: void, lhs: readers.O2LineAssetRow, rhs: readers.O2LineAssetRow) bool {
    // lessByCenterWavelength ---------------------------------------------------------------------------------|
    // Order line rows by center wavelength so binary searches can isolate a local HITRAN cutoff window.       |
    // --------------------------------------------------------------------------------------------------------|
    return lhs.center_wavelength_nm < rhs.center_wavelength_nm;
}

fn weakLineSigmaAt(
    active_lines: []const readers.O2LineAssetRow,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    runtime: RuntimeControls,
) f64 {
    // weakLineSigmaAt ----------------------------------------------------------------------------------------|
    // Sum filtered weak-line Voigt contributions at one wavelength and profile-node thermodynamic point.      |
    // --------------------------------------------------------------------------------------------------------|
    const safe_temperature = @max(temperature_k, min_hitran_temperature_k);
    const pressure_atm = @max(pressure_hpa / 1013.25, min_spectroscopy_pressure_atm);
    const window = relevantLineWindow(active_lines, wavelength_nm, runtime.cutoff_cm1);
    var sigma: f64 = 0.0;
    for (window) |line| {
        sigma += weakLineContribution(wavelength_nm, line, safe_temperature, pressure_atm, runtime);
    }
    return sigma;
}

fn relevantLineWindow(
    active_lines: []const readers.O2LineAssetRow,
    wavelength_nm: f64,
    cutoff_cm1: f64,
) []const readers.O2LineAssetRow {
    // relevantLineWindow -------------------------------------------------------------------------------------|
    // Return the center-wavelength slice that can fall inside the old-route cutoff prewindow.                 |
    // --------------------------------------------------------------------------------------------------------|
    if (active_lines.len == 0) return active_lines;

    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const prewindow_cm1 = cutoff_cm1 + vendor_cutoff_prewindow_margin_cm1;
    const lower_wavenumber_cm1 = @max(evaluation_wavenumber_cm1 - prewindow_cm1, 1.0);
    const upper_wavenumber_cm1 = evaluation_wavenumber_cm1 + prewindow_cm1;
    const lower_wavelength_nm = wavenumberToWavelengthNm(upper_wavenumber_cm1);
    const upper_wavelength_nm = wavenumberToWavelengthNm(lower_wavenumber_cm1);
    const begin = lowerBoundByCenterWavelength(active_lines, lower_wavelength_nm);
    const end = lowerBoundByCenterWavelength(active_lines, upper_wavelength_nm);

    return active_lines[begin..end];
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
    if (!insideCutoff(line, wavelength_nm, pressure_atm, runtime.cutoff_cm1)) return 0.0;

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

fn insideCutoff(
    line: readers.O2LineAssetRow,
    wavelength_nm: f64,
    pressure_atm: f64,
    cutoff_cm1: f64,
) bool {
    // insideCutoff -------------------------------------------------------------------------------------------|
    // Apply the scalar HITRAN cutoff window around the pressure-shifted line center.                          |
    // --------------------------------------------------------------------------------------------------------|
    const shifted_center_wavenumber_cm1 = @max(
        line.center_wavenumber_cm1 + line.pressure_shift_cm1 * pressure_atm,
        1.0,
    );
    const center_distance_cm1 = @abs(shifted_center_wavenumber_cm1 - wavelengthToWavenumberCm1(wavelength_nm));
    return center_distance_cm1 <= cutoff_cm1 + vendor_cutoff_boundary_margin_cm1;
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
