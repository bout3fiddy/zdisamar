const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const PreparedState = @import("prepared_state.zig");
const Types = @import("state.zig");

const PreparedOpticalState = PreparedState.PreparedOpticalState;
const PreparedSublayer = Types.PreparedSublayer;

// state_scalar.zig ------------------------------------------------------------------------------------------|
// Scalar carrier-density and aerosol-depth helpers for PreparedOpticalState evaluation.                      |
//                                                                                                            |
// called by                                                                                                  |
//   prepared_state.zig exposes these helpers as the public PreparedOpticalState scalar methods.              |
//   state_optical_depth.zig and forward_layers.zig use them while building LayerInput optical-depth rows.    |
//   carrier_eval.zig and state_spectroscopy.zig use them for shared RTM support rows and profile nodes.      |
//                                                                                                            |
// density routes                                                                                             |
//   preparedScalarForSublayer indexes a prepared scalar column by global_sublayer_index with a zero fallback |
//   for missing rows. interpolatePreparedScalarAtAltitude brackets neighboring sublayers and interpolates    |
//   linearly by altitude for arbitrary shared-geometry levels.                                               |
//   continuum carrier density uses absorber density by default, operational O2 density for O2 LUT paths, or  |
//   the configured continuum-owner line-absorber density.                                                    |
//   line spectroscopy carrier density uses oxygen density for operational O2 LUT paths; otherwise it removes |
//   cross-section carrier density from absorber density and clamps the result to zero.                       |
//                                                                                                            |
// aerosol math                                                                                               |
//   particleOpticalDepthAtWavelength applies Angstrom scaling from reference_wavelength_nm. When only an     |
//   effective reference optical depth exists, wavelength-dependent fraction controls are normalized by the   |
//   reference-wavelength fraction before applying the active-wavelength fraction.                            |
//                                                                                                            |
// hot path and memory                                                                                        |
//   These helpers run inside per-wavelength layer, carrier, and diagnostics loops. They allocate nothing and |
//   read borrowed PreparedOpticalState density arrays; keep ownership and zero-fallback rules explicit here. |
// -----------------------------------------------------------------------------------------------------------|

pub fn preparedScalarForSublayer(values: []const f64, sublayer: PreparedSublayer) f64 {
    const index: usize = @intCast(sublayer.global_sublayer_index);
    if (index >= values.len) return 0.0;
    return values[index];
}

fn interpolatePreparedScalarBetweenSublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    values: []const f64,
    altitude_km: f64,
) f64 {
    const left_value = preparedScalarForSublayer(values, left);
    const right_value = preparedScalarForSublayer(values, right);
    const span = right.altitude_km - left.altitude_km;
    if (span <= 0.0) return right_value;

    const fraction = std.math.clamp((altitude_km - left.altitude_km) / span, 0.0, 1.0);

    // math: linear interpolation over altitude with the sample fraction clamped to [0, 1].
    return left_value + (right_value - left_value) * fraction;
}

pub fn interpolatePreparedScalarAtAltitude(
    sublayers: []const PreparedSublayer,
    values: []const f64,
    altitude_km: f64,
) f64 {
    // interpolatePreparedScalarAtAltitude -------------------------------------------------------------------|
    // Sample one prepared scalar profile at an altitude.                                                     |
    //                                                                                                        |
    // hot path                                                                                               |
    // carrier evaluation uses this when shared RTM support rows need interpolated densities.                 |
    // work: bracket neighboring sublayers and linearly interpolate the scalar field.                         |
    // -------------------------------------------------------------------------------------------------------|

    if (sublayers.len == 0) return 0.0;
    if (sublayers.len == 1) return preparedScalarForSublayer(values, sublayers[0]);

    const first = sublayers[0];
    const last = sublayers[sublayers.len - 1];
    if (altitude_km <= first.altitude_km) {
        return interpolatePreparedScalarBetweenSublayers(first, sublayers[1], values, altitude_km);
    }

    if (altitude_km >= last.altitude_km) {
        return interpolatePreparedScalarBetweenSublayers(sublayers[sublayers.len - 2], last, values, altitude_km);
    }

    for (sublayers[0 .. sublayers.len - 1], sublayers[1..]) |left, right| {
        if (altitude_km > right.altitude_km) continue;
        return interpolatePreparedScalarBetweenSublayers(left, right, values, altitude_km);
    }

    return preparedScalarForSublayer(values, last);
}

fn lineAbsorberNumberDensitiesForSpecies(
    self: *const PreparedOpticalState,
    species: AbsorberModel.AbsorberSpecies,
) ?[]const f64 {
    for (self.line_absorbers) |line_absorber| {
        if (line_absorber.species != species) continue;

        return line_absorber.number_densities_cm3;
    }

    return null;
}

pub fn continuumCarrierDensityAtSublayer(
    self: *const PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) f64 {
    if (self.line_absorbers.len == 0) return sublayer.absorber_number_density_cm3;

    const owner_species = self.continuum_owner_species orelse return sublayer.absorber_number_density_cm3;
    const use_operational_o2_density = self.operational_o2_lut.enabled() and owner_species == .o2;
    if (use_operational_o2_density) {
        return sublayer.oxygen_number_density_cm3;
    }

    const number_densities_cm3 = lineAbsorberNumberDensitiesForSpecies(self, owner_species) orelse return 0.0;
    if (global_sublayer_index >= number_densities_cm3.len) return 0.0;

    return number_densities_cm3[global_sublayer_index];
}

fn crossSectionCarrierDensityAtSublayer(
    self: *const PreparedOpticalState,
    global_sublayer_index: usize,
) f64 {
    var density_cm3: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;
        density_cm3 += cross_section_absorber.number_densities_cm3[global_sublayer_index];
    }
    return density_cm3;
}

pub fn lineSpectroscopyCarrierDensity(
    self: *const PreparedOpticalState,
    absorber_density_cm3: f64,
    oxygen_density_cm3: f64,
    cross_section_density_cm3: f64,
) f64 {
    if (self.operational_o2_lut.enabled()) return oxygen_density_cm3;
    if (cross_section_density_cm3 <= 0.0) return absorber_density_cm3;

    // math: n_line = max(n_absorber - n_cross_section, 0).
    return @max(@as(f64, 0.0), absorber_density_cm3 - cross_section_density_cm3);
}

pub fn lineSpectroscopyCarrierDensityAtSublayer(
    self: *const PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) f64 {
    // lineSpectroscopyCarrierDensityAtSublayer --------------------------------------------------------------|
    // Resolve line-spectroscopy carrier density for one prepared sublayer.                                   |
    //                                                                                                        |
    // hot path                                                                                               |
    // support-row and layer evaluation call this before spectroscopy weighting.                              |
    // data: prepared sublayer, global sublayer index, and absorber density arrays.                           |
    // -------------------------------------------------------------------------------------------------------|

    const cross_section_density_cm3 = if (self.cross_section_absorbers.len == 0)
        0.0
    else
        crossSectionCarrierDensityAtSublayer(self, global_sublayer_index);

    return lineSpectroscopyCarrierDensity(
        self,
        sublayer.absorber_number_density_cm3,
        sublayer.oxygen_number_density_cm3,
        cross_section_density_cm3,
    );
}

pub fn continuumCarrierDensityAtAltitude(
    self: *const PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
    absorber_density_cm3: f64,
    oxygen_density_cm3: f64,
) f64 {
    // continuumCarrierDensityAtAltitude ---------------------------------------------------------------------|
    // Resolve continuum carrier density at an altitude.                                                      |
    //                                                                                                        |
    // hot path                                                                                               |
    // altitude carrier evaluation calls this for shared RTM support rows.                                    |
    // route: use absorber density, operational O2 density, or owner-species interpolation.                   |
    // -------------------------------------------------------------------------------------------------------|

    if (self.line_absorbers.len == 0) return absorber_density_cm3;

    const owner_species = self.continuum_owner_species orelse return absorber_density_cm3;
    const use_operational_o2_density = self.operational_o2_lut.enabled() and owner_species == .o2;
    if (use_operational_o2_density) {
        return oxygen_density_cm3;
    }

    const number_densities_cm3 = lineAbsorberNumberDensitiesForSpecies(self, owner_species) orelse return 0.0;

    return interpolatePreparedScalarAtAltitude(
        sublayers,
        number_densities_cm3,
        altitude_km,
    );
}

fn fractionAtWavelength(control: AtmosphereModel.FractionControl, wavelength_nm: f64) f64 {
    if (!control.enabled) return 1.0;
    return control.valueAtWavelength(wavelength_nm);
}

pub fn particleOpticalDepthAtWavelength(
    effective_reference_optical_depth: f64,
    base_reference_optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    control: AtmosphereModel.FractionControl,
    wavelength_nm: f64,
) f64 {
    // particleOpticalDepthAtWavelength ----------------------------------------------------------------------|
    // Scale aerosol optical depth from its reference wavelength to the active wavelength.                    |
    //                                                                                                        |
    // hot path                                                                                               |
    // layer and diagnostic evaluation call this for particle optical-depth terms.                            |
    //                                                                                                        |
    // math                                                                                                   |
    // tau(lambda) = tau_ref * (lambda_ref / lambda)^angstrom * fraction(lambda).                             |
    // Effective-only tau is normalized by fraction(lambda_ref) before applying fraction(lambda).             |
    // -------------------------------------------------------------------------------------------------------|

    if (base_reference_optical_depth > 0.0) {
        return ParticleProfiles.scaleOpticalDepth(
            base_reference_optical_depth,
            reference_wavelength_nm,
            angstrom_exponent,
            wavelength_nm,
        ) * fractionAtWavelength(control, wavelength_nm);
    }

    const effective_optical_depth = ParticleProfiles.scaleOpticalDepth(
        effective_reference_optical_depth,
        reference_wavelength_nm,
        angstrom_exponent,
        wavelength_nm,
    );
    if (!control.enabled) return effective_optical_depth;

    const reference_fraction = control.valueAtWavelength(reference_wavelength_nm);
    if (reference_fraction <= 0.0) return 0.0;
    return effective_optical_depth * fractionAtWavelength(control, wavelength_nm) / reference_fraction;
}
