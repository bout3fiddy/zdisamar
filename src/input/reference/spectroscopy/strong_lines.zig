// Strong-line spectroscopy helpers and isotopologue-specific scaling logic.

const std = @import("std");
const hitran_partition_tables = @import("../../hitran_partition_tables.zig");
const Core = @import("physics_core.zig");
const Types = @import("types.zig");

// layout(64-bit):
//   size: 5136 B, align: 8 B
//   field storage: 5136 B across 7 fields; largest: population_t=1024 B, dipole_t=1024 B, mod_sig_cm1=1024 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: 5 fields reserve 5120 B inside each instance
//   cache span: 81 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 5136 B (5.016 KiB); total = per instance * live instance count
pub const StrongLineConvTPState = struct {
    line_count: usize = 0,
    sig_moy_cm1: f64 = 0.0,
    population_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    dipole_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    mod_sig_cm1: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    half_width_cm1_at_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    line_mixing_coefficients: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
};

pub fn strongLineContribution(
    wavelength_nm: f64,
    strong_lines: []const Types.SpectroscopyStrongLine,
    strong_index: usize,
    convtp_state: *const StrongLineConvTPState,
    temperature_k: f64,
    pressure_scale: f64,
) Types.SpectroscopyEvaluation {
    _ = strong_lines;
    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_scale, Types.min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = Core.wavelengthToWavenumberCm1(wavelength_nm);
    const sig_moy_cm1 = @max(convtp_state.sig_moy_cm1, 1.0e-6);
    const gam_d = @max(
        Core.dopplerWidthCm1(safe_temperature, sig_moy_cm1, o2StrongLineMolecularWeight()),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(Types.hitran_pi);
    const cpf = Core.complexProbabilityFunction(
        (convtp_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        convtp_state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        convtp_state.population_t[strong_index] *
        convtp_state.dipole_t[strong_index] *
        convtp_state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / Types.hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        convtp_state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

// hot path:
//   when: each strong-line sidecar contributes to sigma at a wavelength
//   work: evaluates prepared line-mixing contribution using CPF terms
//   data: strong-line sidecar, prepared ConvTP state, wavelength, temperature scale
//   follow: complexProbabilityFunction and relaxation-state layout
pub fn strongLineContributionPrepared(
    wavelength_nm: f64,
    strong_lines: []const Types.SpectroscopyStrongLine,
    strong_index: usize,
    prepared_state: *const Types.StrongLinePreparedState,
    temperature_k: f64,
    pressure_scale: f64,
) Types.SpectroscopyEvaluation {
    _ = strong_lines;
    const safe_temperature = @max(temperature_k, 150.0);
    const safe_pressure = @max(pressure_scale, Types.min_spectroscopy_pressure_atm);
    const evaluation_wavenumber_cm1 = Core.wavelengthToWavenumberCm1(wavelength_nm);
    const sig_moy_cm1 = @max(prepared_state.sig_moy_cm1, 1.0e-6);
    const gam_d = @max(
        Core.dopplerWidthCm1(safe_temperature, sig_moy_cm1, o2StrongLineMolecularWeight()),
        1.0e-6,
    );
    const cte = @sqrt(@log(2.0)) / gam_d;
    const cte1 = cte / @sqrt(Types.hitran_pi);
    const cpf = Core.complexProbabilityFunction(
        (prepared_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        prepared_state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    const cte2 = evaluation_wavenumber_cm1 *
        @max(1.0 - @exp(-Types.hitran_hc_over_kb_cm_k * evaluation_wavenumber_cm1 / safe_temperature), 0.0);
    const base_absorption = cte1 *
        safe_pressure *
        prepared_state.population_t[strong_index] *
        prepared_state.dipole_t[strong_index] *
        prepared_state.dipole_t[strong_index] *
        cte2;
    const number_density = 1013.25 * safe_pressure / safe_temperature / Types.hitran_boltzmann_constant_cm3_hpa_per_k;
    const line_sigma = @max(base_absorption * cpf.wr / number_density, 0.0);
    const line_mixing_sigma = (-base_absorption *
        prepared_state.line_mixing_coefficients[strong_index] *
        cpf.wi) / number_density;
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = line_sigma,
        .line_sigma_cm2_per_molecule = line_sigma,
        .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
        .total_sigma_cm2_per_molecule = @max(line_sigma + line_mixing_sigma, 0.0),
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}

fn o2StrongLineMolecularWeight() f64 {
    return 31.989830;
}

// hot path:
//   when: strong-line sidecars are prepared for a thermodynamic state
//   work: computes ConvTP relaxation terms for all active strong lines
//   data: strong-line sidecar array, relaxation matrix, pressure scale, temperature
//   follow: strongLineContributionPrepared and state.line_count ordering
pub fn prepareStrongLineConvTPState(
    strong_lines: []const Types.SpectroscopyStrongLine,
    relaxation_matrix: Types.RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
) StrongLineConvTPState {
    var relaxation_weights: [Types.max_strong_line_sidecars * Types.max_strong_line_sidecars]f64 = undefined;
    return prepareStrongLineConvTPStateWithScratch(
        strong_lines,
        relaxation_matrix,
        temperature_k,
        pressure_atm,
        relaxation_weights[0..],
    );
}

pub fn prepareStrongLineConvTPStateWithScratch(
    strong_lines: []const Types.SpectroscopyStrongLine,
    relaxation_matrix: Types.RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
    relaxation_weights: []f64,
) StrongLineConvTPState {
    const safe_temperature = @max(temperature_k, 150.0);
    const temperature_ratio = Types.hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(66, safe_temperature, Types.hitran_reference_temperature_k) orelse temperature_ratio;
    const line_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), Types.max_strong_line_sidecars);
    std.debug.assert(line_count == 0 or relaxation_weights.len / line_count >= line_count);

    var state = StrongLineConvTPState{ .line_count = line_count };
    if (line_count == 0) return state;

    fillStrongLineState(
        &state,
        relaxation_weights,
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

// hot path:
//   when: preparing persistent strong-line state for profile nodes or support rows
//   work: fills exactly-sized prepared slices and avoids the 136 KiB max-capacity temporary
//   data: strong-line sidecars, relaxation-matrix scratch, pressure/temperature inputs, prepared output
//   follow: prepareStrongLineStateInto and strongLineContributionPrepared
pub fn prepareStrongLinePreparedStateInto(
    strong_lines: []const Types.SpectroscopyStrongLine,
    relaxation_matrix: Types.RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
    relaxation_weights: []f64,
    prepared: *Types.StrongLinePreparedState,
) void {
    const safe_temperature = @max(temperature_k, 150.0);
    const temperature_ratio = Types.hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(66, safe_temperature, Types.hitran_reference_temperature_k) orelse temperature_ratio;
    const line_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), Types.max_strong_line_sidecars);
    std.debug.assert(prepared.population_t.len >= line_count);
    std.debug.assert(prepared.dipole_t.len >= line_count);
    std.debug.assert(prepared.mod_sig_cm1.len >= line_count);
    std.debug.assert(prepared.half_width_cm1_at_t.len >= line_count);
    std.debug.assert(prepared.line_mixing_coefficients.len >= line_count);
    std.debug.assert(line_count <= Types.max_strong_line_sidecars);
    std.debug.assert(line_count == 0 or relaxation_weights.len / line_count >= line_count);

    prepared.line_count = line_count;
    prepared.sig_moy_cm1 = 0.0;
    if (line_count == 0) return;

    fillStrongLineState(
        prepared,
        relaxation_weights,
        strong_lines,
        relaxation_matrix,
        line_count,
        safe_temperature,
        temperature_ratio,
        partition_ratio,
        pressure_atm,
    );
}

fn fillStrongLineState(
    state: anytype,
    relaxation_weights: []f64,
    strong_lines: []const Types.SpectroscopyStrongLine,
    relaxation_matrix: Types.RelaxationMatrix,
    line_count: usize,
    safe_temperature: f64,
    temperature_ratio: f64,
    partition_ratio: f64,
    pressure_atm: f64,
) void {
    for (0..line_count) |row_index| {
        const strong_line = strong_lines[row_index];
        state.population_t[row_index] = strong_line.population_t0 *
            partition_ratio *
            @exp(Types.hitran_o2_line_mixing_hc_over_kb_cm_k * strong_line.lower_state_energy_cm1 * ((1.0 / Types.hitran_reference_temperature_k) - (1.0 / safe_temperature)));
        state.dipole_t[row_index] = strong_line.dipole_t0 * std.math.sqrt(temperature_ratio);
        state.mod_sig_cm1[row_index] = strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1;
        state.half_width_cm1_at_t[row_index] = strong_line.air_half_width_cm1 *
            std.math.pow(f64, temperature_ratio, strong_line.temperature_exponent);

        for (0..line_count) |column_index| {
            setRelaxationWeight(
                relaxation_weights,
                line_count,
                row_index,
                column_index,
                relaxation_matrix.weightAt(row_index, column_index) *
                    std.math.pow(f64, temperature_ratio, relaxation_matrix.temperatureExponentAt(row_index, column_index)),
            );
        }
    }

    for (0..line_count) |row_index| {
        for (0..line_count) |column_index| {
            if (strong_lines[column_index].lower_state_energy_cm1 < strong_lines[row_index].lower_state_energy_cm1) continue;
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
    else if (line_count != 0)
        state.mod_sig_cm1[0]
    else
        0.0;

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

fn relaxationWeightAt(relaxation_weights: []const f64, line_count: usize, row: usize, col: usize) f64 {
    return relaxation_weights[row * line_count + col];
}

fn setRelaxationWeight(relaxation_weights: []f64, line_count: usize, row: usize, col: usize, value: f64) void {
    relaxation_weights[row * line_count + col] = value;
}

pub fn shiftedLineCenterWavenumberCm1(line: Types.SpectroscopyLine, pressure_atm: f64) f64 {
    const center_wavenumber_cm1 = if (std.math.isFinite(line.center_wavenumber_cm1))
        line.center_wavenumber_cm1
    else
        Core.wavelengthToWavenumberCm1(line.center_wavelength_nm);
    const pressure_shift_cm1 = if (std.math.isFinite(line.pressure_shift_cm1))
        line.pressure_shift_cm1
    else
        -Core.spectralWidthNmToCm1(line.pressure_shift_nm, center_wavenumber_cm1);
    // PARITY:
    //   `HITRANModule::CalculatAbsXsec` applies pressure shift as
    //   `Sig + delt * P` in wavenumber space. The Zig line payload stores the
    //   equivalent wavelength-width magnitude, so convert once and keep the
    //   vendor's linear wavenumber update.
    return @max(center_wavenumber_cm1 + pressure_shift_cm1 * pressure_atm, 1.0);
}

pub fn partitionRatioT0OverT(
    line: Types.SpectroscopyLine,
    temperature_k: f64,
    reference_temperature_k: f64,
) f64 {
    const isotopologue_code = deriveIsotopologueCode(line.gas_index, line.isotope_number);
    if (hitran_partition_tables.ratioT0OverT(isotopologue_code, temperature_k, reference_temperature_k)) |ratio| {
        return ratio;
    }

    const safe_temperature = @max(temperature_k, 150.0);
    const exponent: f64 = switch (isotopologue_code) {
        66, 68, 67, 101, 102 => 1.0,
        626, 636, 628, 627, 638, 637 => 1.35,
        161, 181, 171, 162, 182, 172 => 1.10,
        else => 1.0 + 0.04 * @as(f64, @floatFromInt(@max(line.isotope_number, 1) - 1)),
    };
    return std.math.pow(f64, reference_temperature_k / safe_temperature, exponent);
}

pub fn deriveIsotopologueCode(gas_index: u16, isotope_number: u8) i32 {
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

pub fn molecularWeightForLine(line: Types.SpectroscopyLine) f64 {
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

fn zeroContribution() Types.SpectroscopyEvaluation {
    return .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };
}
