//! Weak-line spectroscopy helpers and shared line-shape math.

const std = @import("std");
const Types = @import("types.zig");

pub const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};

pub const VoigtProfile = struct {
    real: f64,
    imag: f64,
};

pub const WeakLineVoigtState = struct {
    prefactor: f64,
    cpf: ComplexProbability,
};

pub fn clonePreparedStrongLineState(
    allocator: Types.Allocator,
    state: anytype,
) !Types.StrongLinePreparedState {
    const population_t = try allocator.dupe(f64, state.population_t[0..state.line_count]);
    errdefer allocator.free(population_t);
    const dipole_t = try allocator.dupe(f64, state.dipole_t[0..state.line_count]);
    errdefer allocator.free(dipole_t);
    const mod_sig_cm1 = try allocator.dupe(f64, state.mod_sig_cm1[0..state.line_count]);
    errdefer allocator.free(mod_sig_cm1);
    const half_width_cm1_at_t = try allocator.dupe(f64, state.half_width_cm1_at_t[0..state.line_count]);
    errdefer allocator.free(half_width_cm1_at_t);
    const line_mixing_coefficients = try allocator.dupe(f64, state.line_mixing_coefficients[0..state.line_count]);
    errdefer allocator.free(line_mixing_coefficients);
    const relaxation_weights = try allocator.alloc(f64, state.line_count * state.line_count);
    errdefer allocator.free(relaxation_weights);

    for (0..state.line_count) |row_index| {
        for (0..state.line_count) |column_index| {
            relaxation_weights[row_index * state.line_count + column_index] =
                state.weightAt(row_index, column_index);
        }
    }

    return .{
        .line_count = state.line_count,
        .sig_moy_cm1 = state.sig_moy_cm1,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
        .relaxation_weights = relaxation_weights,
    };
}

pub fn voigtProfile(wavelength_nm: f64, center_nm: f64, doppler_hwhm_nm: f64, lorentz_hwhm_nm: f64) VoigtProfile {
    const safe_doppler_hwhm_nm = @max(doppler_hwhm_nm, 1.0e-6);
    const cte = @sqrt(@log(2.0)) / safe_doppler_hwhm_nm;
    const cte1 = cte / @sqrt(std.math.pi);
    const cpf = complexProbabilityFunction(
        (center_nm - wavelength_nm) * cte,
        @max(lorentz_hwhm_nm, 1.0e-6) * cte,
    );
    return .{
        .real = cte1 * cpf.wr,
        .imag = cte1 * cpf.wi,
    };
}

pub fn linesSortedAscending(lines: []const Types.SpectroscopyLine) bool {
    if (lines.len < 2) return true;
    for (lines[0 .. lines.len - 1], lines[1..]) |left, right| {
        if (left.center_wavelength_nm > right.center_wavelength_nm) return false;
    }
    return true;
}

pub fn lowerBoundLineIndex(lines: []const Types.SpectroscopyLine, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = lines.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (lines[middle].center_wavelength_nm < wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

pub fn upperBoundLineIndex(lines: []const Types.SpectroscopyLine, wavelength_nm: f64) usize {
    var low: usize = 0;
    var high: usize = lines.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (lines[middle].center_wavelength_nm <= wavelength_nm) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

pub fn complexProbabilityFunction(x: f64, y: f64) ComplexProbability {
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
    return 1.0e7 / @max(wavelength_nm, 1.0e-9);
}

pub fn spectralWidthNmToCm1(width_nm: f64, center_wavenumber_cm1: f64) f64 {
    const safe_center = @max(center_wavenumber_cm1, 1.0);
    return width_nm * safe_center * safe_center / 1.0e7;
}

pub fn dopplerWidthCm1(temperature_k: f64, wavenumber_cm1: f64, molecular_weight_g_per_mol: f64) f64 {
    const prefactor = @sqrt(
        2.0 * @log(2.0) * Types.hitran_gas_constant_j_per_mol_k /
            (Types.hitran_speed_of_light_m_per_s * Types.hitran_speed_of_light_m_per_s),
    );
    return prefactor *
        std.math.sqrt(@max(temperature_k, 1.0)) /
        std.math.sqrt(@max(molecular_weight_g_per_mol / 1.0e3, 1.0e-12)) *
        wavenumber_cm1;
}

pub fn prepareWeakLineVoigtState(
    wavelength_nm: f64,
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
) WeakLineVoigtState {
    const Strong = @import("strong_lines.zig");

    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_atm, Types.min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const center_wavenumber_cm1 = wavelengthToWavenumberCm1(line.center_wavelength_nm);
    const temperature_ratio = reference_temperature_k / safe_temperature;
    const pressure_shift_cm1 = -spectralWidthNmToCm1(line.pressure_shift_nm, center_wavenumber_cm1);
    const shifted_center_wavenumber_cm1 = @max(
        center_wavenumber_cm1 + pressure_shift_cm1 * safe_pressure,
        1.0,
    );
    const half_width_cm1_at_t = @max(
        spectralWidthNmToCm1(line.air_half_width_nm, center_wavenumber_cm1) *
            std.math.pow(f64, temperature_ratio, line.temperature_exponent),
        1.0e-6,
    );
    const doppler_width_cm1 = @max(
        dopplerWidthCm1(
            safe_temperature,
            shifted_center_wavenumber_cm1,
            Strong.molecularWeightForLine(line),
        ),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / doppler_width_cm1;
    const cpf = complexProbabilityFunction(
        (shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * cte,
        half_width_cm1_at_t * safe_pressure * cte,
    );

    var converted_strength = line.line_strength_cm2_per_molecule *
        Strong.partitionRatioT0OverT(line, safe_temperature, reference_temperature_k) *
        @exp(
            Types.hitran_hc_over_kb_cm_k * line.lower_state_energy_cm1 *
                ((1.0 / reference_temperature_k) - (1.0 / safe_temperature)),
        ) /
        shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013 /
        Types.hitran_boltzmann_constant_j_per_k /
        safe_temperature /
        @max(
            1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * shifted_center_wavenumber_cm1 / reference_temperature_k),
            1.0e-12,
        );

    const stimulated_emission_scale = evaluation_wavenumber_cm1 *
        (1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature));
    const prefactor = @sqrt(@log(2.0)) /
        doppler_width_cm1 /
        @sqrt(std.math.pi) *
        safe_pressure *
        converted_strength *
        stimulated_emission_scale *
        safe_temperature *
        Types.hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;

    return .{
        .prefactor = prefactor,
        .cpf = cpf,
    };
}

pub fn weakLineContribution(
    wavelength_nm: f64,
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    cutoff_cm1: ?f64,
) Types.SpectroscopyEvaluation {
    const Strong = @import("strong_lines.zig");

    if (cutoff_cm1) |window_cm1| {
        const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
        if (@abs(Strong.shiftedLineCenterWavenumberCm1(line, pressure_atm) - evaluation_wavenumber_cm1) > window_cm1) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }
    }
    const state = prepareWeakLineVoigtState(
        wavelength_nm,
        line,
        temperature_k,
        pressure_atm,
        reference_temperature_k,
    );
    const line_sigma = @max(state.prefactor * state.cpf.wr, 0.0);
    return .{
        .weak_line_sigma_cm2_per_molecule = line_sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = line_sigma,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
