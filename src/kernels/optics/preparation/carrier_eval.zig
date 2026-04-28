const std = @import("std");
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const State = @import("state.zig");
const Scalar = @import("state_scalar.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedSublayer = State.PreparedSublayer;
const SharedRtmLevelGeometry = State.SharedRtmLevelGeometry;

const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const centimeters_per_kilometer = 1.0e5;

pub const SharedOpticalCarrier = struct {
    gas_absorption_optical_depth_per_km: f64 = 0.0,
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    cia_optical_depth_per_km: f64 = 0.0,
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,
    phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),

    pub fn totalScatteringOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.gas_scattering_optical_depth_per_km +
            self.aerosol_scattering_optical_depth_per_km +
            self.cloud_scattering_optical_depth_per_km;
    }

    pub fn totalOpticalDepthPerKm(self: SharedOpticalCarrier) f64 {
        return self.gas_absorption_optical_depth_per_km +
            self.gas_scattering_optical_depth_per_km +
            self.cia_optical_depth_per_km +
            self.aerosol_optical_depth_per_km +
            self.cloud_optical_depth_per_km;
    }
};

pub const PreparedQuadratureCarrier = struct {
    ksca: f64,
    phase_coefficients: [phase_coefficient_count]f64,
};

pub const SharedBoundaryCarrier = struct {
    gas_scattering_optical_depth_per_km: f64 = 0.0,
    particle_scattering_optical_depth_above_per_km: f64 = 0.0,
    particle_scattering_optical_depth_below_per_km: f64 = 0.0,
    ksca_above: f64 = 0.0,
    ksca_below: f64 = 0.0,
    gas_phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.gasPhaseCoefficients(),
    phase_coefficients_above: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    phase_coefficients_below: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
};

const ParticleBoundaryCarrier = struct {
    aerosol_optical_depth_per_km: f64 = 0.0,
    aerosol_scattering_optical_depth_per_km: f64 = 0.0,
    cloud_optical_depth_per_km: f64 = 0.0,
    cloud_scattering_optical_depth_per_km: f64 = 0.0,
    aerosol_phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    cloud_phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),

    fn totalScatteringOpticalDepthPerKm(self: ParticleBoundaryCarrier) f64 {
        return self.aerosol_scattering_optical_depth_per_km + self.cloud_scattering_optical_depth_per_km;
    }
};

pub const InterpolatedQuadratureState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    cia_pair_density_cm6: f64 = 0.0,
    absorber_number_density_cm3: f64,
    aerosol_optical_depth_per_km: f64,
    cloud_optical_depth_per_km: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,

    fn ciaPairDensityCm6(self: InterpolatedQuadratureState) f64 {
        return if (self.cia_pair_density_cm6 > 0.0)
            self.cia_pair_density_cm6
        else
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3;
    }
};

fn opticalDepthPerKilometer(optical_depth: f64, path_length_cm: f64) f64 {
    const span_km = @max(path_length_cm / centimeters_per_kilometer, 0.0);
    return if (span_km > 0.0) optical_depth / span_km else 0.0;
}

fn particleBoundaryCarrierAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
) ParticleBoundaryCarrier {
    const aerosol_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    const cloud_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        wavelength_nm,
    );
    return .{
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_optical_depth_per_km * sublayer.cloud_single_scatter_albedo,
        .aerosol_phase_coefficients = sublayer.aerosol_phase_coefficients,
        .cloud_phase_coefficients = sublayer.cloud_phase_coefficients,
    };
}

fn particleBoundaryCarrierFromIndex(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    support_row_index: u32,
) ParticleBoundaryCarrier {
    if (support_row_index == @import("shared_geometry.zig").invalid_support_row_index) return .{};
    const row_index: usize = @intCast(support_row_index);
    if (row_index >= sublayers.len) return .{};
    return particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[row_index]);
}

pub fn sharedBoundaryCarrierAtLevel(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
) SharedBoundaryCarrier {
    return sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        level_geometry,
        null,
    );
}

pub fn sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedBoundaryCarrier {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};
    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );
    const particle_above = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_above_support_row_index,
    );
    const particle_below = particleBoundaryCarrierFromIndex(
        self,
        wavelength_nm,
        sublayers,
        level_geometry.particle_below_support_row_index,
    );
    const gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km;
    return .{
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .particle_scattering_optical_depth_above_per_km = particle_above.totalScatteringOpticalDepthPerKm(),
        .particle_scattering_optical_depth_below_per_km = particle_below.totalScatteringOpticalDepthPerKm(),
        .ksca_above = gas_scattering_optical_depth_per_km + particle_above.totalScatteringOpticalDepthPerKm(),
        .ksca_below = gas_scattering_optical_depth_per_km + particle_below.totalScatteringOpticalDepthPerKm(),
        .gas_phase_coefficients = PhaseFunctions.gasPhaseCoefficientsAtWavelength(wavelength_nm),
        .phase_coefficients_above = PhaseFunctions.combinePhaseCoefficients(
            wavelength_nm,
            gas_scattering_optical_depth_per_km,
            particle_above.aerosol_scattering_optical_depth_per_km,
            particle_above.cloud_scattering_optical_depth_per_km,
            particle_above.aerosol_phase_coefficients,
            particle_above.cloud_phase_coefficients,
        ),
        .phase_coefficients_below = PhaseFunctions.combinePhaseCoefficients(
            wavelength_nm,
            gas_scattering_optical_depth_per_km,
            particle_below.aerosol_scattering_optical_depth_per_km,
            particle_below.cloud_scattering_optical_depth_per_km,
            particle_below.aerosol_phase_coefficients,
            particle_below.cloud_phase_coefficients,
        ),
    };
}

pub fn sharedActiveCarrierAtLevel(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
) SharedOpticalCarrier {
    return sharedActiveCarrierAtLevelWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        level_geometry,
        null,
    );
}

pub fn sharedActiveCarrierAtLevelWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    level_geometry: SharedRtmLevelGeometry,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const boundary_row_index: usize = @intCast(level_geometry.support_row_index);
    if (boundary_row_index >= sublayers.len) return .{};

    const strong_line_state = if (strong_line_states) |states|
        if (boundary_row_index < states.len) &states[boundary_row_index] else null
    else
        null;
    const gas_carrier = sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers[boundary_row_index],
        boundary_row_index,
        strong_line_state,
        profile_cache,
    );

    const below_index_u32 = level_geometry.particle_below_support_row_index;
    const above_index_u32 = level_geometry.particle_above_support_row_index;
    const invalid_index = @import("shared_geometry.zig").invalid_support_row_index;
    if (below_index_u32 == invalid_index and above_index_u32 == invalid_index) return gas_carrier;

    if (below_index_u32 == invalid_index) {
        const above_index: usize = @intCast(above_index_u32);
        if (above_index >= sublayers.len) return gas_carrier;
        const particle = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[above_index]);
        return composeSharedActiveCarrier(wavelength_nm, gas_carrier, particle, particle, 0.0);
    }
    if (above_index_u32 == invalid_index) {
        const below_index: usize = @intCast(below_index_u32);
        if (below_index >= sublayers.len) return gas_carrier;
        const particle = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, sublayers[below_index]);
        return composeSharedActiveCarrier(wavelength_nm, gas_carrier, particle, particle, 0.0);
    }

    const below_index: usize = @intCast(below_index_u32);
    const above_index: usize = @intCast(above_index_u32);
    if (below_index >= sublayers.len or above_index >= sublayers.len) return gas_carrier;

    const below_row = sublayers[below_index];
    const above_row = sublayers[above_index];
    const altitude_span_km = above_row.altitude_km - below_row.altitude_km;
    const fraction = if (altitude_span_km > 0.0)
        std.math.clamp((level_geometry.altitude_km - below_row.altitude_km) / altitude_span_km, 0.0, 1.0)
    else
        0.5;
    const particle_below = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, below_row);
    const particle_above = particleBoundaryCarrierAtSupportRow(self, wavelength_nm, above_row);
    return composeSharedActiveCarrier(wavelength_nm, gas_carrier, particle_below, particle_above, fraction);
}

fn composeSharedActiveCarrier(
    wavelength_nm: f64,
    gas_carrier: SharedOpticalCarrier,
    particle_below: ParticleBoundaryCarrier,
    particle_above: ParticleBoundaryCarrier,
    fraction: f64,
) SharedOpticalCarrier {
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;
    const aerosol_optical_depth_per_km =
        left_weight * particle_below.aerosol_optical_depth_per_km +
        right_weight * particle_above.aerosol_optical_depth_per_km;
    const aerosol_scattering_optical_depth_per_km =
        left_weight * particle_below.aerosol_scattering_optical_depth_per_km +
        right_weight * particle_above.aerosol_scattering_optical_depth_per_km;
    const cloud_optical_depth_per_km =
        left_weight * particle_below.cloud_optical_depth_per_km +
        right_weight * particle_above.cloud_optical_depth_per_km;
    const cloud_scattering_optical_depth_per_km =
        left_weight * particle_below.cloud_scattering_optical_depth_per_km +
        right_weight * particle_above.cloud_scattering_optical_depth_per_km;
    const aerosol_phase_coefficients = interpolatePhaseCoefficientsByScattering(
        particle_below.aerosol_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        particle_below.aerosol_phase_coefficients,
        particle_above.aerosol_phase_coefficients,
        clamped_fraction,
    );
    const cloud_phase_coefficients = interpolatePhaseCoefficientsByScattering(
        particle_below.cloud_scattering_optical_depth_per_km,
        particle_above.cloud_scattering_optical_depth_per_km,
        particle_below.cloud_phase_coefficients,
        particle_above.cloud_phase_coefficients,
        clamped_fraction,
    );
    return .{
        .gas_absorption_optical_depth_per_km = gas_carrier.gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_carrier.gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = gas_carrier.cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
        .phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
            wavelength_nm,
            gas_carrier.gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            aerosol_phase_coefficients,
            cloud_phase_coefficients,
        ),
    };
}

fn interpolatePhaseCoefficientsByScattering(
    left_scattering_per_km: f64,
    right_scattering_per_km: f64,
    left_phase_coefficients: [phase_coefficient_count]f64,
    right_phase_coefficients: [phase_coefficient_count]f64,
    fraction: f64,
) [phase_coefficient_count]f64 {
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;
    const interpolated_scattering_per_km =
        left_weight * left_scattering_per_km +
        right_weight * right_scattering_per_km;

    var coefficients = [_]f64{0.0} ** phase_coefficient_count;
    coefficients[0] = 1.0;
    for (1..phase_coefficient_count) |index| {
        if (interpolated_scattering_per_km > 0.0) {
            coefficients[index] =
                (left_weight * left_scattering_per_km * left_phase_coefficients[index] +
                    right_weight * right_scattering_per_km * right_phase_coefficients[index]) /
                interpolated_scattering_per_km;
        } else {
            coefficients[index] =
                left_weight * left_phase_coefficients[index] +
                right_weight * right_phase_coefficients[index];
        }
    }
    return coefficients;
}

fn interpolateQuadratureStateBetweenSublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    altitude_km: f64,
) InterpolatedQuadratureState {
    const interpolation_span_km = right.altitude_km - left.altitude_km;
    const fraction = if (interpolation_span_km > 0.0)
        (altitude_km - left.altitude_km) / interpolation_span_km
    else
        0.0;
    const clamped_fraction = std.math.clamp(fraction, 0.0, 1.0);
    const left_weight = 1.0 - clamped_fraction;
    const right_weight = clamped_fraction;

    const left_aerosol_per_km = opticalDepthPerKilometer(left.aerosol_optical_depth, left.path_length_cm);
    const right_aerosol_per_km = opticalDepthPerKilometer(right.aerosol_optical_depth, right.path_length_cm);
    const left_cloud_per_km = opticalDepthPerKilometer(left.cloud_optical_depth, left.path_length_cm);
    const right_cloud_per_km = opticalDepthPerKilometer(right.cloud_optical_depth, right.path_length_cm);
    const left_aerosol_scattering_per_km = left_aerosol_per_km * left.aerosol_single_scatter_albedo;
    const right_aerosol_scattering_per_km = right_aerosol_per_km * right.aerosol_single_scatter_albedo;
    const left_cloud_scattering_per_km = left_cloud_per_km * left.cloud_single_scatter_albedo;
    const right_cloud_scattering_per_km = right_cloud_per_km * right.cloud_single_scatter_albedo;

    return .{
        .pressure_hpa = @max(left_weight * left.pressure_hpa + right_weight * right.pressure_hpa, 0.0),
        .temperature_k = @max(left_weight * left.temperature_k + right_weight * right.temperature_k, 0.0),
        .number_density_cm3 = @max(left_weight * left.number_density_cm3 + right_weight * right.number_density_cm3, 0.0),
        .oxygen_number_density_cm3 = @max(left_weight * left.oxygen_number_density_cm3 + right_weight * right.oxygen_number_density_cm3, 0.0),
        .cia_pair_density_cm6 = @max(left_weight * left.ciaPairDensityCm6() + right_weight * right.ciaPairDensityCm6(), 0.0),
        .absorber_number_density_cm3 = @max(left_weight * left.absorber_number_density_cm3 + right_weight * right.absorber_number_density_cm3, 0.0),
        .aerosol_optical_depth_per_km = @max(left_weight * left_aerosol_per_km + right_weight * right_aerosol_per_km, 0.0),
        .cloud_optical_depth_per_km = @max(left_weight * left_cloud_per_km + right_weight * right_cloud_per_km, 0.0),
        .aerosol_single_scatter_albedo = std.math.clamp(
            left_weight * left.aerosol_single_scatter_albedo + right_weight * right.aerosol_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .cloud_single_scatter_albedo = std.math.clamp(
            left_weight * left.cloud_single_scatter_albedo + right_weight * right.cloud_single_scatter_albedo,
            0.0,
            1.0,
        ),
        .aerosol_phase_coefficients = interpolatePhaseCoefficientsByScattering(
            left_aerosol_scattering_per_km,
            right_aerosol_scattering_per_km,
            left.aerosol_phase_coefficients,
            right.aerosol_phase_coefficients,
            clamped_fraction,
        ),
        .cloud_phase_coefficients = interpolatePhaseCoefficientsByScattering(
            left_cloud_scattering_per_km,
            right_cloud_scattering_per_km,
            left.cloud_phase_coefficients,
            right.cloud_phase_coefficients,
            clamped_fraction,
        ),
    };
}

// PUB FOR TEST: kept `pub` so `internal.zig` can re-export this helper for
// tests. Extracting the body would also require lifting
// `interpolateQuadratureStateBetweenSublayers` and `opticalDepthPerKilometer`
// — both consumed elsewhere in this file.
pub fn interpolateQuadratureStateAtAltitude(
    sublayers: []const PreparedSublayer,
    altitude_km: f64,
) ?InterpolatedQuadratureState {
    if (sublayers.len == 0) return null;

    if (sublayers.len == 1) {
        const sublayer = sublayers[0];
        return .{
            .pressure_hpa = sublayer.pressure_hpa,
            .temperature_k = sublayer.temperature_k,
            .number_density_cm3 = sublayer.number_density_cm3,
            .oxygen_number_density_cm3 = sublayer.oxygen_number_density_cm3,
            .cia_pair_density_cm6 = sublayer.ciaPairDensityCm6(),
            .absorber_number_density_cm3 = sublayer.absorber_number_density_cm3,
            .aerosol_optical_depth_per_km = opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
            .cloud_optical_depth_per_km = opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
            .aerosol_single_scatter_albedo = sublayer.aerosol_single_scatter_albedo,
            .cloud_single_scatter_albedo = sublayer.cloud_single_scatter_albedo,
            .aerosol_phase_coefficients = sublayer.aerosol_phase_coefficients,
            .cloud_phase_coefficients = sublayer.cloud_phase_coefficients,
        };
    }

    const first = sublayers[0];
    const last = sublayers[sublayers.len - 1];
    if (altitude_km <= first.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(first, sublayers[1], altitude_km);
    }
    if (altitude_km >= last.altitude_km) {
        return interpolateQuadratureStateBetweenSublayers(sublayers[sublayers.len - 2], last, altitude_km);
    }
    for (sublayers[0 .. sublayers.len - 1], sublayers[1..]) |left, right| {
        if (altitude_km > right.altitude_km) continue;
        return interpolateQuadratureStateBetweenSublayers(left, right, altitude_km);
    }

    return null;
}

pub fn quadratureCarrierAtAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) PreparedQuadratureCarrier {
    return quadratureCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        null,
    );
}

pub fn quadratureCarrierAtAltitudeWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) PreparedQuadratureCarrier {
    const carrier = sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        profile_cache,
    );
    return .{
        .ksca = carrier.totalScatteringOpticalDepthPerKm(),
        .phase_coefficients = carrier.phase_coefficients,
    };
}

fn weightedSpectroscopyEvaluationAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) ReferenceData.SpectroscopyEvaluation {
    var total_weight: f64 = 0.0;
    var weighted: ReferenceData.SpectroscopyEvaluation = .{
        .weak_line_sigma_cm2_per_molecule = 0.0,
        .strong_line_sigma_cm2_per_molecule = 0.0,
        .line_sigma_cm2_per_molecule = 0.0,
        .line_mixing_sigma_cm2_per_molecule = 0.0,
        .total_sigma_cm2_per_molecule = 0.0,
        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
    };

    if (self.operational_o2_lut.enabled() and sublayer.oxygen_number_density_cm3 > 0.0) {
        const o2_evaluation = self.weightedSpectroscopyEvaluationAtWavelength(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
        total_weight += sublayer.oxygen_number_density_cm3;
        weighted.weak_line_sigma_cm2_per_molecule +=
            o2_evaluation.weak_line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.strong_line_sigma_cm2_per_molecule +=
            o2_evaluation.strong_line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.line_sigma_cm2_per_molecule +=
            o2_evaluation.line_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.line_mixing_sigma_cm2_per_molecule +=
            o2_evaluation.line_mixing_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.total_sigma_cm2_per_molecule +=
            o2_evaluation.total_sigma_cm2_per_molecule * sublayer.oxygen_number_density_cm3;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * sublayer.oxygen_number_density_cm3;
    }

    for (self.line_absorbers) |line_absorber| {
        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
        if (global_sublayer_index >= line_absorber.number_densities_cm3.len) continue;
        const weight = line_absorber.number_densities_cm3[global_sublayer_index];
        if (weight <= 0.0) continue;
        const prepared_state = if (line_absorber.strong_line_states) |states|
            if (global_sublayer_index < states.len) &states[global_sublayer_index] else null
        else
            null;
        const evaluation = line_absorber.line_list.evaluateAtPrepared(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
            prepared_state,
        );
        total_weight += weight;
        weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
        weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
        weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
        weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
        weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
            evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
    }

    if (total_weight <= 0.0) return weighted;
    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
    return weighted;
}

pub fn sharedOpticalCarrierAtSupportRow(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
) SharedOpticalCarrier {
    return sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayer,
        global_sublayer_index,
        strong_line_state,
        null,
    );
}

pub fn sharedOpticalCarrierAtSupportRowWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    strong_line_state: ?*const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
    const spectroscopy_eval = if (self.line_absorbers.len != 0)
        weightedSpectroscopyEvaluationAtSupportRow(
            self,
            wavelength_nm,
            sublayer,
            global_sublayer_index,
        )
    else
        self.spectroscopyEvaluationAtAltitudeWithCache(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
            sublayer.altitude_km,
            strong_line_state,
            profile_cache,
        );
    var cross_section_density_cm3: f64 = 0.0;
    var cross_section_absorption_optical_depth_per_km: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;
        const absorber_density_cm3 = cross_section_absorber.number_densities_cm3[global_sublayer_index];
        if (absorber_density_cm3 <= 0.0) continue;
        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            cross_section_absorber.sigmaAt(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
            ) *
            absorber_density_cm3 *
            centimeters_per_kilometer;
    }

    const line_absorber_density_cm3 = Scalar.lineSpectroscopyCarrierDensityAtSublayer(
        self,
        sublayer,
        global_sublayer_index,
    );
    const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
        Scalar.continuumCarrierDensityAtSublayer(
            self,
            sublayer,
            global_sublayer_index,
        )
    else
        0.0;
    const gas_absorption_optical_depth_per_km =
        continuum_sigma * continuum_density_cm3 * centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_eval.total_sigma_cm2_per_molecule * line_absorber_density_cm3 * centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        Rayleigh.crossSectionCm2(wavelength_nm) *
        sublayer.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_optical_depth_per_km =
        self.ciaSigmaAtWavelength(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        ) *
        sublayer.ciaPairDensityCm6() *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        opticalDepthPerKilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    const cloud_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        opticalDepthPerKilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        wavelength_nm,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * sublayer.cloud_single_scatter_albedo;
    return .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
        .phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
            wavelength_nm,
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            sublayer.aerosol_phase_coefficients,
            sublayer.cloud_phase_coefficients,
        ),
    };
}

pub fn sharedOpticalCarrierAtAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
) SharedOpticalCarrier {
    return sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
        null,
    );
}

pub fn sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) SharedOpticalCarrier {
    const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return .{};
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const continuum_sigma = if (self.cross_section_absorbers.len == 0)
        continuum_table.interpolateSigma(wavelength_nm)
    else
        0.0;
    const prepared_state = State.PreparedOpticalState.preparedStrongLineStateAtAltitude(
        sublayers,
        strong_line_states,
        altitude_km,
    );
    const spectroscopy_sigma = if (self.line_absorbers.len != 0)
        self.weightedSpectroscopyEvaluationAtAltitude(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            sublayers,
            altitude_km,
            state.oxygen_number_density_cm3,
        ).total_sigma_cm2_per_molecule
    else
        self.spectroscopySigmaAtAltitudeWithCache(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            altitude_km,
            prepared_state,
            profile_cache,
        );
    var cross_section_density_cm3: f64 = 0.0;
    var cross_section_absorption_optical_depth_per_km: f64 = 0.0;
    for (self.cross_section_absorbers) |cross_section_absorber| {
        const absorber_density_cm3 = State.PreparedOpticalState.interpolatePreparedScalarAtAltitude(
            sublayers,
            cross_section_absorber.number_densities_cm3,
            altitude_km,
        );
        if (absorber_density_cm3 <= 0.0) continue;
        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            cross_section_absorber.sigmaAt(
                wavelength_nm,
                state.temperature_k,
                state.pressure_hpa,
            ) *
            absorber_density_cm3 *
            centimeters_per_kilometer;
    }
    const line_absorber_density_cm3 = self.lineSpectroscopyCarrierDensity(
        state.absorber_number_density_cm3,
        state.oxygen_number_density_cm3,
        cross_section_density_cm3,
    );
    const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
        self.continuumCarrierDensityAtAltitude(
            sublayers,
            altitude_km,
            state.absorber_number_density_cm3,
            state.oxygen_number_density_cm3,
        )
    else
        0.0;
    const gas_absorption_optical_depth_per_km =
        continuum_sigma *
        continuum_density_cm3 *
        centimeters_per_kilometer +
        cross_section_absorption_optical_depth_per_km +
        spectroscopy_sigma *
            line_absorber_density_cm3 *
            centimeters_per_kilometer;
    const gas_scattering_optical_depth_per_km =
        Rayleigh.crossSectionCm2(wavelength_nm) *
        state.number_density_cm3 *
        centimeters_per_kilometer;
    const cia_optical_depth_per_km =
        self.ciaSigmaAtWavelength(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
        ) *
        state.ciaPairDensityCm6() *
        centimeters_per_kilometer;
    const aerosol_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.aerosol_optical_depth_per_km,
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    const cloud_optical_depth_per_km = ParticleProfiles.scaleOpticalDepth(
        state.cloud_optical_depth_per_km,
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        wavelength_nm,
    );
    const aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * state.aerosol_single_scatter_albedo;
    const cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * state.cloud_single_scatter_albedo;

    return .{
        .gas_absorption_optical_depth_per_km = gas_absorption_optical_depth_per_km,
        .gas_scattering_optical_depth_per_km = gas_scattering_optical_depth_per_km,
        .cia_optical_depth_per_km = cia_optical_depth_per_km,
        .aerosol_optical_depth_per_km = aerosol_optical_depth_per_km,
        .aerosol_scattering_optical_depth_per_km = aerosol_scattering_optical_depth_per_km,
        .cloud_optical_depth_per_km = cloud_optical_depth_per_km,
        .cloud_scattering_optical_depth_per_km = cloud_scattering_optical_depth_per_km,
        .phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
            wavelength_nm,
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            state.aerosol_phase_coefficients,
            state.cloud_phase_coefficients,
        ),
    };
}
