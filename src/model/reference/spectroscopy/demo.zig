const Types = @import("types.zig");
const LineList = @import("line_list.zig");

const demo_spectroscopy_lines = [_]Types.SpectroscopyLine{
    .{ .center_wavelength_nm = 429.8, .line_strength_cm2_per_molecule = 8.2e-21, .air_half_width_nm = 0.035, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 112.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.04 },
    .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    .{ .center_wavelength_nm = 441.2, .line_strength_cm2_per_molecule = 9.7e-21, .air_half_width_nm = 0.038, .temperature_exponent = 0.74, .lower_state_energy_cm1 = 165.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.05 },
    .{ .center_wavelength_nm = 448.1, .line_strength_cm2_per_molecule = 7.6e-21, .air_half_width_nm = 0.034, .temperature_exponent = 0.77, .lower_state_energy_cm1 = 188.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.03 },
    .{ .center_wavelength_nm = 456.0, .line_strength_cm2_per_molecule = 5.4e-21, .air_half_width_nm = 0.030, .temperature_exponent = 0.81, .lower_state_energy_cm1 = 205.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.02 },
};

pub fn buildDemoSpectroscopyLines(allocator: Types.Allocator) !LineList.SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(Types.SpectroscopyLine, demo_spectroscopy_lines[0..]),
        .lines_sorted_ascending = true,
    };
}
