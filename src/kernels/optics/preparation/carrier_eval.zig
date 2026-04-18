const std = @import("std");
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const State = @import("state.zig");

const PreparedSublayer = State.PreparedSublayer;

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

pub const InterpolatedQuadratureState = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64,
    aerosol_optical_depth_per_km: f64,
    cloud_optical_depth_per_km: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
};

fn opticalDepthPerKilometer(optical_depth: f64, path_length_cm: f64) f64 {
    const span_km = @max(path_length_cm / centimeters_per_kilometer, 0.0);
    return if (span_km > 0.0) optical_depth / span_km else 0.0;
}

fn interpolatePhaseCoefficientsByScattering(
    left_scattering_per_km: f64,
    right_scattering_per_km: f64,
    left_phase_coefficients: [phase_coefficient_count]f64,
    right_phase_coefficients: [phase_coefficient_count]f64,
    fraction: f64,
) [phase_coefficient_count]f64 {
    const left_weight = 1.0 - fraction;
    const right_weight = fraction;
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
    const left_weight = 1.0 - fraction;
    const right_weight = fraction;

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

fn interpolateQuadratureStateAtAltitude(
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
    const carrier = sharedOpticalCarrierAtAltitude(
        self,
        wavelength_nm,
        sublayers,
        strong_line_states,
        altitude_km,
    );
    return .{
        .ksca = carrier.totalScatteringOpticalDepthPerKm(),
        .phase_coefficients = carrier.phase_coefficients,
    };
}

pub fn sharedOpticalCarrierAtAltitude(
    self: *const State.PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    altitude_km: f64,
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
        self.spectroscopySigmaAtWavelength(
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            prepared_state,
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
        state.oxygen_number_density_cm3 *
        state.oxygen_number_density_cm3 *
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
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            state.aerosol_phase_coefficients,
            state.cloud_phase_coefficients,
        ),
    };
}
