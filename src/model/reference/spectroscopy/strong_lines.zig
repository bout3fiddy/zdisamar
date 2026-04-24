//! Strong-line spectroscopy helpers and isotopologue-specific scaling logic.

const std = @import("std");
const hitran_partition_tables = @import("../../hitran_partition_tables.zig");
const Core = @import("physics_core.zig");
const Types = @import("types.zig");

pub const StrongLineConvTPState = struct {
    line_count: usize = 0,
    sig_moy_cm1: f64 = 0.0,
    population_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    dipole_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    mod_sig_cm1: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    half_width_cm1_at_t: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    line_mixing_coefficients: [Types.max_strong_line_sidecars]f64 = [_]f64{0.0} ** Types.max_strong_line_sidecars,
    relaxation_weights: [Types.max_strong_line_sidecars * Types.max_strong_line_sidecars]f64 =
        [_]f64{0.0} ** (Types.max_strong_line_sidecars * Types.max_strong_line_sidecars),

    pub fn weightAt(self: StrongLineConvTPState, row: usize, col: usize) f64 {
        return self.relaxation_weights[row * self.line_count + col];
    }

    pub fn setWeight(self: *StrongLineConvTPState, row: usize, col: usize, value: f64) void {
        self.relaxation_weights[row * self.line_count + col] = value;
    }
};

pub fn strongLineContribution(
    wavelength_nm: f64,
    strong_lines: []const Types.SpectroscopyStrongLine,
    strong_index: usize,
    convtp_state: StrongLineConvTPState,
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
    const cte1 = cte / @sqrt(std.math.pi);
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
    const cte1 = cte / @sqrt(std.math.pi);
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

pub fn prepareStrongLineConvTPState(
    strong_lines: []const Types.SpectroscopyStrongLine,
    relaxation_matrix: Types.RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
) StrongLineConvTPState {
    const safe_temperature = @max(temperature_k, 150.0);
    const temperature_ratio = Types.hitran_reference_temperature_k / safe_temperature;
    const partition_ratio = hitran_partition_tables.ratioT0OverT(66, safe_temperature, Types.hitran_reference_temperature_k) orelse temperature_ratio;
    const line_count = @min(@min(strong_lines.len, relaxation_matrix.line_count), Types.max_strong_line_sidecars);

    var state = StrongLineConvTPState{ .line_count = line_count };
    if (line_count == 0) return state;

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
            state.setWeight(
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
            state.setWeight(
                column_index,
                row_index,
                state.weightAt(row_index, column_index) *
                    state.population_t[column_index] /
                    @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |index| {
        state.setWeight(index, index, state.half_width_cm1_at_t[index]);
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
                upper_sum += strong_lines[row_index].dipole_ratio * state.weightAt(row_index, column_index);
            } else {
                lower_sum += strong_lines[row_index].dipole_ratio * state.weightAt(row_index, column_index);
            }
        }
        if (@abs(lower_sum) <= 1.0e-24) continue;

        const rotational_gate = 1.0 - std.math.clamp(
            @abs(@as(f64, @floatFromInt(strong_lines[column_index].rotational_index_m1))) / 36.0,
            0.0,
            1.0,
        );
        const renormalization_anchor = strong_lines[column_index].dipole_ratio *
            rotational_gate *
            rotational_gate *
            0.04;

        for (0..line_count) |row_index| {
            if (row_index <= column_index) continue;
            const renormalized = -state.weightAt(row_index, column_index) *
                (upper_sum - renormalization_anchor) /
                lower_sum;
            state.setWeight(row_index, column_index, renormalized);
            state.setWeight(
                column_index,
                row_index,
                renormalized * state.population_t[column_index] / @max(state.population_t[row_index], 1.0e-24),
            );
        }
    }

    for (0..line_count) |line_index| {
        var mixing_sum: f64 = 0.0;
        const self_dipole = if (@abs(state.dipole_t[line_index]) > 1.0e-24)
            state.dipole_t[line_index]
        else
            1.0e-24;
        for (0..line_count) |other_index| {
            if (other_index == line_index) continue;
            const delta_sig = state.mod_sig_cm1[line_index] - state.mod_sig_cm1[other_index];
            if (@abs(delta_sig) <= 1.0e-12) continue;
            mixing_sum += 2.0 * state.dipole_t[other_index] / self_dipole *
                state.weightAt(other_index, line_index) /
                delta_sig;
        }
        state.line_mixing_coefficients[line_index] = pressure_atm * mixing_sum;
    }

    return state;
}

pub fn shiftedLineCenterWavenumberCm1(line: Types.SpectroscopyLine, pressure_atm: f64) f64 {
    const center_wavenumber_cm1 = Core.wavelengthToWavenumberCm1(line.center_wavelength_nm);
    const pressure_shift_cm1 = -Core.spectralWidthNmToCm1(line.pressure_shift_nm, center_wavenumber_cm1);
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
