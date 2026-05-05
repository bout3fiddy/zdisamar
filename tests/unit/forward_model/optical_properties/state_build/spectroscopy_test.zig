const std = @import("std");
const internal = @import("internal");

const Spectroscopy = internal.forward_model.optical_properties.spectroscopy;
const ReferenceData = internal.reference_data;

test "line species inference rejects unsupported HITRAN gas indices" {
    var lines = [_]ReferenceData.SpectroscopyLine{.{
        .gas_index = 5,
        .center_wavelength_nm = 760.0,
        .line_strength_cm2_per_molecule = 1.0e-25,
        .air_half_width_nm = 0.01,
        .temperature_exponent = 0.7,
        .lower_state_energy_cm1 = 0.0,
        .pressure_shift_nm = 0.0,
        .line_mixing_coefficient = 0.0,
    }};
    const line_list = ReferenceData.SpectroscopyLineList{ .lines = lines[0..] };

    try std.testing.expectError(
        error.UnsupportedSpectroscopyConfiguration,
        Spectroscopy.resolveActiveLineSpecies(null, line_list, .{}),
    );
}
