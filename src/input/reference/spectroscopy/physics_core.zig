const std = @import("std");
const Types = @import("types.zig");

// physics_core.zig ------------------------------------------------------------------------------------------ |
// Weak-line spectroscopy math and shared line-window helpers.                                                 |
//                                                                                                             |
// called by                                                                                                   |
//   line_list.zig uses sorted-window helpers, weak-line contribution paths, and prepared weak-line rows.      |
//   strong_lines.zig shares complexProbabilityFunction for O2 line-mixing contributions.                      |
//                                                                                                             |
// main paths                                                                                                  |
//   line list sorted by center wavelength -> lower/upper bounds for one wavelength window                     |
//   SpectroscopyLine + T/P -> WeakLinePreparedLineState for repeated wavelength evaluation                    |
//   wavelength + prepared line state -> Voigt/CPF contribution with vendor cutoff checks                      |
//   wavelength + raw line -> one-shot weak-line contribution when no prepared state is available              |
//                                                                                                             |
// hot path                                                                                                    |
//   Prepared weak-line evaluation calls complexProbabilityFunction for each relevant line in the current      |
//   wavelength window. Setup paths prepare temperature/pressure-dependent line constants so repeated          |
//   evaluation streams compact WeakLinePreparedLineState rows instead of recomputing line-shape constants.    |
//                                                                                                             |
// math                                                                                                        |
//   wavelength_nm -> wavenumber_cm1 uses 1.0e7 / wavelength_nm. Weak-line sigma combines HITRAN strength      |
//   scaling, Doppler/Lorentz widths, pressure shift, stimulated emission, and the CPF real term.              |
//                                                                                                             |
// memory                                                                                                      |
//   The small structs below are stack values. Prepared weak-line arrays are owned by WeakLinePreparedState in |
//   types.zig and reused by line-list and forward-model carrier loops.                                        |
// ----------------------------------------------------------------------------------------------------------- |

// ComplexProbability ---------------------------------------------------------------------------------------- |
// Complex probability function result used by Voigt and line-mixing formulas.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wr : f64                                                                                           |
// [ 8..15] wi : f64                                                                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B; usually stack returned                                                      |
pub const ComplexProbability = struct {
    wr: f64,
    wi: f64,
};

// VoigtProfile ---------------------------------------------------------------------------------------------- |
// Real and imaginary Voigt profile terms for the scalar weak-line path.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] real : f64                                                                                         |
// [ 8..15] imag : f64                                                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B; usually stack returned                                                      |
pub const VoigtProfile = struct {
    real: f64,
    imag: f64,
};

// WeakLineVoigtState ---------------------------------------------------------------------------------------- |
// Scalar weak-line Voigt state before conversion into the compact prepared-row form.                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] prefactor : f64                                                                                    |
// [ 8..23] cpf       : ComplexProbability                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B; usually stack returned                                                      |
pub const WeakLineVoigtState = struct {
    prefactor: f64,
    cpf: ComplexProbability,
};

// WeakLineWavelengthState ----------------------------------------------------------------------------------- |
// Wavelength-local state shared across prepared weak-line cutoff and sigma evaluation.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] evaluation_wavenumber_cm1 : f64                                                                    |
// [ 8..23] cutoff_grid_index        : ?usize                                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B; one per evaluated wavelength                                                |
pub const WeakLineWavelengthState = struct {
    evaluation_wavenumber_cm1: f64,
    cutoff_grid_index: ?usize,
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

    return .{
        .line_count = state.line_count,
        .sig_moy_cm1 = state.sig_moy_cm1,
        .population_t = population_t,
        .dipole_t = dipole_t,
        .mod_sig_cm1 = mod_sig_cm1,
        .half_width_cm1_at_t = half_width_cm1_at_t,
        .line_mixing_coefficients = line_mixing_coefficients,
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
    // complexProbabilityFunction ---------------------------------------------------------------------------- |
    // Computes the complex probability function approximation used by weak-line Voigt and strong-line         |
    // line-mixing terms.                                                                                      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Called for each relevant prepared weak line and each active strong line at wavelength time. Fixed     |
    //   coefficient arrays stay inline and no heap state is touched.                                          |
    // ------------------------------------------------------------------------------------------------------- |

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
    // prepareWeakLineVoigtState ----------------------------------------------------------------------------- |
    // Computes pressure/temperature-dependent Voigt state for one weak line.                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs while weak-line state is prepared for a thermodynamic profile node. The prepared-row path below  |
    //   stores the reusable pieces and avoids rebuilding them for every wavelength.                           |
    // ------------------------------------------------------------------------------------------------------- |

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

pub fn prepareWeakLinePreparedLineState(
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
) Types.WeakLinePreparedLineState {
    // prepareWeakLinePreparedLineState ---------------------------------------------------------------------- |
    // Stores compact line-shape and strength terms for repeated wavelength evaluation.                        |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Runs during absorber/profile setup. The row is streamed by prepared weak-line sigma.                  |
    // ------------------------------------------------------------------------------------------------------- |

    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_atm, Types.min_spectroscopy_pressure_atm);
    return prepareWeakLinePreparedLineStateFromSafe(
        line,
        safe_temperature,
        safe_pressure,
        reference_temperature_k,
    );
}

pub fn prepareWeakLinePreparedLineStateFromSafe(
    line: Types.SpectroscopyLine,
    safe_temperature: f64,
    safe_pressure: f64,
    reference_temperature_k: f64,
) Types.WeakLinePreparedLineState {
    const Strong = @import("strong_lines.zig");

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

    return .{
        .shifted_center_wavenumber_cm1 = shifted_center_wavenumber_cm1,
        .cte = cte,
        .line_shape_y = half_width_cm1_at_t * safe_pressure * cte,
        .prefactor_base = @sqrt(@log(2.0)) /
            doppler_width_cm1 /
            @sqrt(Types.hitran_pi) *
            safe_pressure *
            converted_strength,
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
    const wavelength_state = prepareWeakLineWavelengthState(wavelength_nm, runtime_controls);
    return weakLineContributionWithWavelengthState(
        wavelength_nm,
        line,
        temperature_k,
        pressure_atm,
        reference_temperature_k,
        runtime_controls,
        wavelength_state,
    );
}

pub fn prepareWeakLineWavelengthState(
    wavelength_nm: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
) WeakLineWavelengthState {
    const evaluation_wavenumber_cm1 = wavelengthToWavenumberCm1(wavelength_nm);
    const has_precomputed_wavenumber_grid =
        runtime_controls.cutoff_grid_wavenumbers_cm1.len == runtime_controls.cutoff_grid_wavelengths_nm.len and
        runtime_controls.cutoff_grid_wavenumbers_cm1.len >= 2;
    const has_wavelength_grid = runtime_controls.cutoff_grid_wavelengths_nm.len >= 2;
    const cutoff_grid_index = choose_cutoff_grid_index: {
        if (has_precomputed_wavenumber_grid) {
            break :choose_cutoff_grid_index nearestWavenumberGridIndexFromWavenumbers(
                runtime_controls.cutoff_grid_wavenumbers_cm1,
                evaluation_wavenumber_cm1,
            );
        }

        if (has_wavelength_grid) {
            break :choose_cutoff_grid_index nearestWavenumberGridIndex(
                runtime_controls.cutoff_grid_wavelengths_nm,
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

pub fn weakLineContributionWithWavelengthState(
    wavelength_nm: f64,
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) Types.SpectroscopyEvaluation {
    if (!weakLineInsideVendorCutoff(line, pressure_atm, runtime_controls, wavelength_state)) {
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

pub fn weakLineContributionPrepared(
    wavelength_state: WeakLineWavelengthState,
    prepared_line: Types.WeakLinePreparedLineState,
    safe_temperature: f64,
    safe_pressure: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
) Types.SpectroscopyEvaluation {
    if (!preparedWeakLineInsideVendorCutoff(prepared_line, runtime_controls, wavelength_state)) {
        return .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }
    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1) * prepared_line.cte,
        prepared_line.line_shape_y,
    );
    const stimulated_emission_scale = wavelength_state.evaluation_wavenumber_cm1 *
        (1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * wavelength_state.evaluation_wavenumber_cm1 / safe_temperature));
    const prefactor = prepared_line.prefactor_base *
        stimulated_emission_scale *
        safe_temperature *
        Types.hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;
    const line_sigma = @max(prefactor * cpf.wr, 0.0);
    return .{
        .weak_line_sigma_cm2_per_molecule = line_sigma,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = line_sigma,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

pub fn weakLinePreparedStimulatedEmissionScale(
    wavelength_state: WeakLineWavelengthState,
    safe_temperature: f64,
) f64 {
    return wavelength_state.evaluation_wavenumber_cm1 *
        (1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * wavelength_state.evaluation_wavenumber_cm1 / safe_temperature));
}

pub fn weakLinePreparedThermodynamicScale(safe_temperature: f64, safe_pressure: f64) f64 {
    return safe_temperature *
        Types.hitran_boltzmann_constant_cm3_hpa_per_k /
        safe_pressure /
        1013.25;
}

pub fn weakLineSigmaPreparedWithStimulatedEmissionScale(
    wavelength_state: WeakLineWavelengthState,
    prepared_line: Types.WeakLinePreparedLineState,
    runtime_controls: Types.SpectroscopyRuntimeControls,
    stimulated_emission_scale: f64,
    thermodynamic_scale: f64,
) f64 {
    // weakLineSigmaPreparedWithStimulatedEmissionScale ------------------------------------------------------ |
    // Evaluates cutoff, line shape, and stimulated-emission-scaled sigma for one prepared weak line.          |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Called for each prepared weak line in the relevant wavelength window. The caller precomputes the      |
    //   wavelength and thermodynamic scale shared by that window.                                             |
    // ------------------------------------------------------------------------------------------------------- |

    if (!preparedWeakLineInsideVendorCutoff(prepared_line, runtime_controls, wavelength_state)) return 0.0;
    const cpf = complexProbabilityFunction(
        (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1) * prepared_line.cte,
        prepared_line.line_shape_y,
    );
    const prefactor = prepared_line.prefactor_base *
        stimulated_emission_scale *
        thermodynamic_scale;
    return @max(prefactor * cpf.wr, 0.0);
}

fn preparedWeakLineInsideVendorCutoff(
    prepared_line: Types.WeakLinePreparedLineState,
    runtime_controls: Types.SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) bool {
    const window_cm1 = runtime_controls.cutoff_cm1 orelse return true;

    if (runtime_controls.cutoff_grid_wavelengths_nm.len >= 2) {
        const has_precomputed_wavenumber_grid =
            runtime_controls.cutoff_grid_wavenumbers_cm1.len == runtime_controls.cutoff_grid_wavelengths_nm.len and
            runtime_controls.cutoff_grid_wavenumbers_cm1.len >= 2;
        const lower_wavelength_endpoint_index, const upper_wavelength_endpoint_index = choose_endpoint_indices: {
            if (has_precomputed_wavenumber_grid) {
                break :choose_endpoint_indices .{
                    nearestWavenumberGridIndexFromWavenumbers(
                        runtime_controls.cutoff_grid_wavenumbers_cm1,
                        prepared_line.shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearestWavenumberGridIndexFromWavenumbers(
                        runtime_controls.cutoff_grid_wavenumbers_cm1,
                        prepared_line.shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                };
            }

            break :choose_endpoint_indices .{
                nearestWavenumberGridIndex(
                    runtime_controls.cutoff_grid_wavelengths_nm,
                    prepared_line.shifted_center_wavenumber_cm1 + window_cm1,
                ),
                nearestWavenumberGridIndex(
                    runtime_controls.cutoff_grid_wavelengths_nm,
                    prepared_line.shifted_center_wavenumber_cm1 - window_cm1,
                ),
            };
        };
        const evaluation_index = wavelength_state.cutoff_grid_index.?;
        const start_index = @min(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);
        const end_index = @max(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);

        return evaluation_index >= start_index and evaluation_index <= end_index;
    }

    const fallback_cutoff_cm1 = window_cm1 + Types.vendor_cutoff_boundary_margin_cm1;
    const center_distance_cm1 = @abs(
        prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1,
    );

    return center_distance_cm1 <= fallback_cutoff_cm1;
}

fn weakLineInsideVendorCutoff(
    line: Types.SpectroscopyLine,
    pressure_atm: f64,
    runtime_controls: Types.SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) bool {
    const window_cm1 = runtime_controls.cutoff_cm1 orelse return true;
    const Strong = @import("strong_lines.zig");
    const shifted_center_wavenumber_cm1 = Strong.shiftedLineCenterWavenumberCm1(line, pressure_atm);

    if (runtime_controls.cutoff_grid_wavelengths_nm.len >= 2) {

        // HITRANModule::CalculatAbsXsec computes nearest HR-grid indices for Lsig +/- cutoff with minloc,
        // then loops inclusively from the high-wavenumber endpoint to the low-wavenumber endpoint. The
        // retained O2 A grid is stored as increasing wavelength, so index order is opposite wavenumber order
        // but still monotonic.
        const has_precomputed_wavenumber_grid =
            runtime_controls.cutoff_grid_wavenumbers_cm1.len == runtime_controls.cutoff_grid_wavelengths_nm.len and
            runtime_controls.cutoff_grid_wavenumbers_cm1.len >= 2;
        const lower_wavelength_endpoint_index, const upper_wavelength_endpoint_index = choose_endpoint_indices: {
            if (has_precomputed_wavenumber_grid) {
                break :choose_endpoint_indices .{
                    nearestWavenumberGridIndexFromWavenumbers(
                        runtime_controls.cutoff_grid_wavenumbers_cm1,
                        shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearestWavenumberGridIndexFromWavenumbers(
                        runtime_controls.cutoff_grid_wavenumbers_cm1,
                        shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                };
            }

            break :choose_endpoint_indices .{
                nearestWavenumberGridIndex(
                    runtime_controls.cutoff_grid_wavelengths_nm,
                    shifted_center_wavenumber_cm1 + window_cm1,
                ),
                nearestWavenumberGridIndex(
                    runtime_controls.cutoff_grid_wavelengths_nm,
                    shifted_center_wavenumber_cm1 - window_cm1,
                ),
            };
        };
        const evaluation_index = wavelength_state.cutoff_grid_index.?;
        const start_index = @min(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);
        const end_index = @max(lower_wavelength_endpoint_index, upper_wavelength_endpoint_index);

        return evaluation_index >= start_index and evaluation_index <= end_index;
    }

    const fallback_cutoff_cm1 = window_cm1 + Types.vendor_cutoff_boundary_margin_cm1;
    const center_distance_cm1 = @abs(
        shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1,
    );

    return center_distance_cm1 <= fallback_cutoff_cm1;
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

fn nearestWavenumberGridIndexFromWavenumbers(wavenumbers_cm1: []const f64, target_wavenumber_cm1: f64) usize {
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

fn nearestOfTwoWavenumberGridIndices(
    wavelengths_nm: []const f64,
    target_wavenumber_cm1: f64,
    lower_index: usize,
    upper_index: usize,
) usize {
    const lower_delta = @abs(wavelengthToWavenumberCm1(wavelengths_nm[lower_index]) - target_wavenumber_cm1);
    const upper_delta = @abs(wavelengthToWavenumberCm1(wavelengths_nm[upper_index]) - target_wavenumber_cm1);

    // Match Fortran minloc tie handling: keep the first matching grid element when distances are equal.
    return if (upper_delta < lower_delta) upper_index else lower_index;
}

fn nearestOfTwoPrecomputedWavenumberGridIndices(
    wavenumbers_cm1: []const f64,
    target_wavenumber_cm1: f64,
    lower_index: usize,
    upper_index: usize,
) usize {
    const lower_delta = @abs(wavenumbers_cm1[lower_index] - target_wavenumber_cm1);
    const upper_delta = @abs(wavenumbers_cm1[upper_index] - target_wavenumber_cm1);

    // Match Fortran minloc tie handling: keep the first matching grid element when distances are equal.
    return if (upper_delta < lower_delta) upper_index else lower_index;
}
