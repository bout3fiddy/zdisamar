//! Purpose:
//!   Hold wavelength-dependent optical-depth and layer-evaluation helpers for
//!   prepared optical state reuse.

const PhaseFunctions = @import("../prepare/phase_functions.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const ReferenceData = @import("../../../model/ReferenceData.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const PreparedState = @import("prepared_state.zig");
const Scalar = @import("state_scalar.zig");
const Spectroscopy = @import("state_spectroscopy.zig");
const Types = @import("state_types.zig");

const phase_coefficient_count = Types.phase_coefficient_count;
const PreparedOpticalState = PreparedState.PreparedOpticalState;
const PreparedSublayer = Types.PreparedSublayer;
const OpticalDepthBreakdown = Types.OpticalDepthBreakdown;
const EvaluatedLayer = Types.EvaluatedLayer;

pub fn opticalDepthBreakdownAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
) OpticalDepthBreakdown {
    var profile_cache = Spectroscopy.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    if (self.sublayers) |sublayers| {
        var totals: OpticalDepthBreakdown = .{};
        for (self.layers) |layer| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const evaluated = evaluateLayerAtWavelengthWithSpectroscopyCache(
                self,
                null,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                if (self.strong_line_states) |states| states[start_index..end_index] else null,
                &profile_cache,
            );
            totals.gas_absorption_optical_depth += evaluated.breakdown.gas_absorption_optical_depth;
            totals.gas_scattering_optical_depth += evaluated.breakdown.gas_scattering_optical_depth;
            totals.cia_optical_depth += evaluated.breakdown.cia_optical_depth;
            totals.aerosol_optical_depth += evaluated.breakdown.aerosol_optical_depth;
            totals.aerosol_scattering_optical_depth += evaluated.breakdown.aerosol_scattering_optical_depth;
            totals.cloud_optical_depth += evaluated.breakdown.cloud_optical_depth;
            totals.cloud_scattering_optical_depth += evaluated.breakdown.cloud_scattering_optical_depth;
        }
        return totals;
    }

    const gas_absorption_optical_depth =
        Spectroscopy.totalCrossSectionAtWavelength(self, wavelength_nm) * self.column_density_factor;
    const gas_scattering_optical_depth = Rayleigh.crossSectionCm2(wavelength_nm) *
        self.air_column_density_factor;
    const cia_optical_depth = if (self.operational_o2o2_lut.enabled())
        self.operational_o2o2_lut.sigmaAt(
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        ) * self.cia_pair_path_factor_cm5
    else if (self.collision_induced_absorption) |cia_table|
        cia_table.sigmaAt(wavelength_nm, self.effective_temperature_k) * self.cia_pair_path_factor_cm5
    else
        0.0;
    const aerosol_optical_depth = Scalar.particleOpticalDepthAtWavelength(
        self.aerosol_optical_depth,
        self.aerosol_base_optical_depth,
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        self.aerosol_fraction_control,
        wavelength_nm,
    );
    const cloud_optical_depth = Scalar.particleOpticalDepthAtWavelength(
        self.cloud_optical_depth,
        self.cloud_base_optical_depth,
        self.cloud_reference_wavelength_nm,
        self.cloud_angstrom_exponent,
        self.cloud_fraction_control,
        wavelength_nm,
    );
    const particle_single_scatter_albedos = self.resolvedParticleSingleScatterAlbedos();
    return .{
        .gas_absorption_optical_depth = gas_absorption_optical_depth,
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .cia_optical_depth = cia_optical_depth,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_scattering_optical_depth = aerosol_optical_depth * particle_single_scatter_albedos.aerosol,
        .cloud_optical_depth = cloud_optical_depth,
        .cloud_scattering_optical_depth = cloud_optical_depth * particle_single_scatter_albedos.cloud,
    };
}

pub fn evaluateLayerAtWavelength(
    self: *const PreparedOpticalState,
    scene: ?*const Scene,
    altitude_km: f64,
    wavelength_nm: f64,
    sublayer_start_index: usize,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
) EvaluatedLayer {
    return evaluateLayerAtWavelengthWithSpectroscopyCache(
        self,
        scene,
        altitude_km,
        wavelength_nm,
        sublayer_start_index,
        sublayers,
        strong_line_states,
        null,
    );
}

pub fn evaluateLayerAtWavelengthWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: ?*const Scene,
    altitude_km: f64,
    wavelength_nm: f64,
    sublayer_start_index: usize,
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    profile_cache: ?*const Spectroscopy.ProfileNodeSpectroscopyCache,
) EvaluatedLayer {
    var breakdown: OpticalDepthBreakdown = .{};
    var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
    const gas_phase_coefficients = PhaseFunctions.gasPhaseCoefficientsAtWavelength(wavelength_nm);
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };

    for (sublayers, 0..) |sublayer, sublayer_index| {
        const global_sublayer_index = sublayer_start_index + sublayer_index;
        const continuum_sigma = if (self.cross_section_absorbers.len == 0)
            continuum_table.interpolateSigma(wavelength_nm)
        else
            0.0;
        const gas_absorption_optical_depth = blk: {
            const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
                Scalar.continuumCarrierDensityAtSublayer(self, sublayer, global_sublayer_index)
            else
                0.0;
            const continuum_optical_depth =
                continuum_sigma *
                continuum_density_cm3 *
                sublayer.path_length_cm;
            var cross_section_optical_depth: f64 = 0.0;
            for (self.cross_section_absorbers) |cross_section_absorber| {
                if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;
                const absorber_density_cm3 = cross_section_absorber.number_densities_cm3[global_sublayer_index];
                if (absorber_density_cm3 <= 0.0) continue;
                cross_section_optical_depth += cross_section_absorber.sigmaAt(
                    wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                ) * absorber_density_cm3 * sublayer.path_length_cm;
            }
            if (self.line_absorbers.len != 0) {
                var line_optical_depth: f64 = 0.0;
                for (self.line_absorbers) |line_absorber| {
                    if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
                    const absorber_density_cm3 = line_absorber.number_densities_cm3[global_sublayer_index];
                    if (absorber_density_cm3 <= 0.0) continue;
                    const sigma = line_absorber.line_list.sigmaAtPrepared(
                        wavelength_nm,
                        sublayer.temperature_k,
                        sublayer.pressure_hpa,
                        if (line_absorber.strong_line_states) |states|
                            &states[global_sublayer_index]
                        else
                            null,
                    );
                    line_optical_depth += sigma * absorber_density_cm3 * sublayer.path_length_cm;
                }
                if (self.operational_o2_lut.enabled() and sublayer.oxygen_number_density_cm3 > 0.0) {
                    line_optical_depth +=
                        self.operational_o2_lut.sigmaAt(
                            wavelength_nm,
                            sublayer.temperature_k,
                            sublayer.pressure_hpa,
                        ) *
                        sublayer.oxygen_number_density_cm3 *
                        sublayer.path_length_cm;
                }
                break :blk continuum_optical_depth + cross_section_optical_depth + line_optical_depth;
            }

            const spectroscopy_sigma = Spectroscopy.spectroscopySigmaAtAltitudeWithCache(
                self,
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                sublayer.altitude_km,
                if (strong_line_states) |states| &states[sublayer_index] else null,
                profile_cache,
            );
            const spectroscopy_carrier_density_cm3 = Scalar.lineSpectroscopyCarrierDensityAtSublayer(
                self,
                sublayer,
                global_sublayer_index,
            );
            const gas_column_density_cm2 = spectroscopy_carrier_density_cm3 * sublayer.path_length_cm;
            break :blk continuum_optical_depth + cross_section_optical_depth + spectroscopy_sigma * gas_column_density_cm2;
        };
        const gas_scattering_optical_depth =
            Rayleigh.crossSectionCm2(wavelength_nm) *
            sublayer.number_density_cm3 *
            sublayer.path_length_cm;
        const cia_sigma_cm5_per_molecule2 = Spectroscopy.ciaSigmaAtWavelength(
            self,
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
        const cia_optical_depth =
            cia_sigma_cm5_per_molecule2 *
            sublayer.ciaPairDensityCm6() *
            sublayer.path_length_cm;
        const aerosol_optical_depth = Scalar.particleOpticalDepthAtWavelength(
            sublayer.aerosol_optical_depth,
            sublayer.aerosol_base_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const cloud_optical_depth = Scalar.particleOpticalDepthAtWavelength(
            sublayer.cloud_optical_depth,
            sublayer.cloud_base_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            self.cloud_fraction_control,
            wavelength_nm,
        );
        const aerosol_scattering_optical_depth = aerosol_optical_depth * sublayer.aerosol_single_scatter_albedo;
        const cloud_scattering_optical_depth = cloud_optical_depth * sublayer.cloud_single_scatter_albedo;

        breakdown.gas_absorption_optical_depth += gas_absorption_optical_depth;
        breakdown.gas_scattering_optical_depth += gas_scattering_optical_depth;
        breakdown.cia_optical_depth += cia_optical_depth;
        breakdown.aerosol_optical_depth += aerosol_optical_depth;
        breakdown.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
        breakdown.cloud_optical_depth += cloud_optical_depth;
        breakdown.cloud_scattering_optical_depth += cloud_scattering_optical_depth;

        for (0..phase_coefficient_count) |index| {
            phase_numerator[index] +=
                gas_scattering_optical_depth * gas_phase_coefficients[index] +
                aerosol_scattering_optical_depth * sublayer.aerosol_phase_coefficients[index] +
                cloud_scattering_optical_depth * sublayer.cloud_phase_coefficients[index];
        }
    }

    const total_scattering = breakdown.totalScatteringOpticalDepth();
    var phase_coefficients = PhaseFunctions.gasPhaseCoefficientsAtWavelength(wavelength_nm);
    if (total_scattering > 0.0) {
        for (0..phase_coefficient_count) |index| {
            phase_coefficients[index] = phase_numerator[index] / total_scattering;
        }
        phase_coefficients[0] = 1.0;
    }

    return .{
        .breakdown = breakdown,
        .phase_coefficients = phase_coefficients,
        .solar_mu = if (scene) |owned_scene| owned_scene.geometry.solarCosineAtAltitude(altitude_km) else 1.0,
        .view_mu = if (scene) |owned_scene| owned_scene.geometry.viewingCosineAtAltitude(altitude_km) else 1.0,
    };
}
