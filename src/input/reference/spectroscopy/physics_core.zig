// Weak-line spectroscopy helpers and shared line-shape math.

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
    const center_wavenumber_cm1 = lineCenterWavenumberCm1(line);
    const temperature_ratio = reference_temperature_k / safe_temperature;
    const pressure_shift_cm1 = linePressureShiftCm1(line);
    const shifted_center_wavenumber_cm1 = @max(
        center_wavenumber_cm1 + pressure_shift_cm1 * safe_pressure,
        1.0,
    );
    const half_width_cm1_at_t = @max(
        lineAirHalfWidthCm1(line) *
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
        @sqrt(Types.hitran_pi) *
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

fn lineCenterWavenumberCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.center_wavenumber_cm1))
        line.center_wavenumber_cm1
    else
        wavelengthToWavenumberCm1(line.center_wavelength_nm);
}

fn lineAirHalfWidthCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.air_half_width_cm1))
        line.air_half_width_cm1
    else
        spectralWidthNmToCm1(line.air_half_width_nm, lineCenterWavenumberCm1(line));
}

fn linePressureShiftCm1(line: Types.SpectroscopyLine) f64 {
    return if (std.math.isFinite(line.pressure_shift_cm1))
        line.pressure_shift_cm1
    else
        -spectralWidthNmToCm1(line.pressure_shift_nm, lineCenterWavenumberCm1(line));
}

pub fn weakLineContribution(
    wavelength_nm: f64,
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
) Types.SpectroscopyEvaluation {
    if (!weakLineInsideVendorCutoff(wavelength_nm, line, pressure_atm, runtime_controls)) {
        return .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
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

fn weakLineInsideVendorCutoff(
    wavelength_nm: f64,
    line: Types.SpectroscopyLine,
    pressure_atm: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
) bool {
    const window_cm1 = runtime_controls.cutoff_cm1 orelse return true;
    const Strong = @import("strong_lines.zig");
    const shifted_center_wavenumber_cm1 = Strong.shiftedLineCenterWavenumberCm1(line, pressure_atm);
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);

    if (runtime_controls.cutoff_grid_wavelengths_nm.len >= 2) {
        // PARITY:
        //   `HITRANModule::CalculatAbsXsec` computes nearest HR-grid indices
        //   for `Lsig +/- cutoff` with `minloc`, then loops inclusively from
        //   the high-wavenumber endpoint to the low-wavenumber endpoint. The
        //   retained O2 A grid is stored as increasing wavelength, so index
        //   order is the opposite of wavenumber order but still monotonic.
        const lower_wavelength_endpoint_index = nearestWavenumberGridIndex(
            runtime_controls.cutoff_grid_wavelengths_nm,
            shifted_center_wavenumber_cm1 + window_cm1,
        );
        const upper_wavelength_endpoint_index = nearestWavenumberGridIndex(
            runtime_controls.cutoff_grid_wavelengths_nm,
            shifted_center_wavenumber_cm1 - window_cm1,
        );
        const evaluation_index = nearestWavenumberGridIndex(
            runtime_controls.cutoff_grid_wavelengths_nm,
            evaluation_wavenumber_cm1,
        );
        const start_index = @min(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);
        const end_index = @max(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);
        return evaluation_index >= start_index and evaluation_index <= end_index;
    }

    const fallback_cutoff_cm1 = window_cm1 + Types.vendor_cutoff_boundary_margin_cm1;
    return @abs(shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) <= fallback_cutoff_cm1;
}

fn nearestWavenumberGridIndex(wavelengths_nm: []const f64, target_wavenumber_cm1: f64) usize {
    std.debug.assert(wavelengths_nm.len != 0);
    if (wavelengths_nm.len == 1) return 0;

    const first_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelengths_nm[0]);
    const last_index = wavelengths_nm.len - 1;
    const last_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelengths_nm[last_index]);

    const descending = first_wavenumber_cm1 >= last_wavenumber_cm1;
    if (descending) {
        if (target_wavenumber_cm1 >= first_wavenumber_cm1) return 0;
        if (target_wavenumber_cm1 <= last_wavenumber_cm1) return last_index;

        var lower_index: usize = 0;
        var upper_index: usize = last_index;
        while (upper_index - lower_index > 1) {
            const midpoint = lower_index + (upper_index - lower_index) / 2;
            const midpoint_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelengths_nm[midpoint]);
            if (midpoint_wavenumber_cm1 >= target_wavenumber_cm1) {
                lower_index = midpoint;
            } else {
                upper_index = midpoint;
            }
        }
        return nearestOfTwoWavenumberGridIndices(
            wavelengths_nm,
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
        const midpoint_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelengths_nm[midpoint]);
        if (midpoint_wavenumber_cm1 <= target_wavenumber_cm1) {
            lower_index = midpoint;
        } else {
            upper_index = midpoint;
        }
    }
    return nearestOfTwoWavenumberGridIndices(
        wavelengths_nm,
        target_wavenumber_cm1,
        lower_index,
        upper_index,
    );
}

fn nearestOfTwoWavenumberGridIndices(
    wavelengths_nm: []const f64,
    target_wavenumber_cm1: f64,
    lower_index: usize,
    upper_index: usize,
) usize {
    const lower_delta = @abs(wavelengthToWavenumberCm1(wavelengths_nm[lower_index]) - target_wavenumber_cm1);
    const upper_delta = @abs(wavelengthToWavenumberCm1(wavelengths_nm[upper_index]) - target_wavenumber_cm1);
    // PARITY:
    //   Fortran `minloc` returns the first matching array element on ties.
    return if (upper_delta < lower_delta) upper_index else lower_index;
}
