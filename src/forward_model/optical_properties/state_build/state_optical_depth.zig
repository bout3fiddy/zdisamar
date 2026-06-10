const PhaseFunctions = @import("../shared/phase_functions.zig");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const PreparedState = @import("prepared_state.zig");
const Scalar = @import("state_scalar.zig");
const Spectroscopy = @import("state_spectroscopy.zig");
const Types = @import("state.zig");

const PreparedOpticalState = PreparedState.PreparedOpticalState;
const PreparedSublayer = Types.PreparedSublayer;
const OpticalDepthBreakdown = Types.OpticalDepthBreakdown;
const EvaluatedLayer = Types.EvaluatedLayer;

// state_optical_depth.zig -----------------------------------------------------------------------------------|
// Evaluates scalar and layer optical-depth breakdowns from a prepared optical state at one wavelength.       |
//                                                                                                            |
// called by                                                                                                  |
//   PreparedOpticalState helpers, forward_layers, diagnostics, atmospheric budgets, and output reports.      |
//                                                                                                            |
// main paths                                                                                                 |
//   total route   : sum every prepared layer or prepared scene mean into OpticalDepthBreakdown.              |
//   layer route   : evaluate one layer/support span into EvaluatedLayer.                                     |
//   cache route   : reuse ProfileNodeSpectroscopyCache while several layers share a wavelength.              |
//                                                                                                            |
// row handoff                                                                                                |
//   PreparedLayer supplies the support span and representative altitude for sublayer evaluation.             |
//   PreparedSublayer rows carry temperature, pressure, density, path length, aerosol, and support metadata.  |
//   Totals are scalar summaries; layer builders use EvaluatedLayer when they must also fill transport rows.  |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs per high-resolution wavelength. Profile caches prevent repeating spectroscopy over pressure nodes.  |
//   The PreparedLayer loop reads a few index/altitude fields by pointer; it does not copy the 208 B row.     |
//                                                                                                            |
// math                                                                                                       |
//   tau_total(lambda) = gas absorption + Rayleigh scattering + CIA + aerosol extinction.                     |
//   aerosol scattering = aerosol extinction * resolved single-scatter albedo.                                |
// -----------------------------------------------------------------------------------------------------------|

pub fn opticalDepthBreakdownAtWavelength(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
) OpticalDepthBreakdown {
    // opticalDepthBreakdownAtWavelength -------------------------------------------------------------------- |
    // Accumulate gas, CIA, aerosol, and scattering optical depths at one wavelength.                         |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Used by diagnostics and layer-free routes that need a scalar optical-depth breakdown.                |
    //   A profile cache is built once for the wavelength, then reused while the layer loop walks the state.  |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   PreparedLayer supplies sublayer_start_index, sublayer_count, and representative altitude.            |
    //   The loop slices PreparedSublayer and strong-line state rows, then calls the layer evaluator.         |
    //   The result is only a scalar total; callers that need transport rows use forward_layers instead.      |
    //                                                                                                        |
    // memory                                                                                                 |
    //   The PreparedLayer loop uses pointer capture; no 208 B row is copied while reading the support span.  |
    //   A standalone span column would duplicate the slicing contract already carried by PreparedLayer.      |
    //                                                                                                        |
    // math                                                                                                   |
    //   tau_total(lambda) = tau_abs_gas + tau_rayleigh + tau_cia + tau_aerosol(lambda)                       |
    //   tau_aerosol_sca  = tau_aerosol * omega0_aerosol                                                      |
    // -------------------------------------------------------------------------------------------------------|

    var profile_cache = Spectroscopy.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);

    if (self.sublayers) |sublayers| {
        var totals: OpticalDepthBreakdown = .{};
        const layers: []const Types.PreparedLayer = self.layers;
        for (layers) |*layer| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const strong_line_state = if (self.strong_line_states) |states|
                states[start_index..end_index]
            else
                null;

            const evaluated = evaluateLayerAtWavelengthWithSpectroscopyCache(
                self,
                null,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                strong_line_state,
                &profile_cache,
            );

            totals.gas_absorption_optical_depth += evaluated.breakdown.gas_absorption_optical_depth;
            totals.gas_scattering_optical_depth += evaluated.breakdown.gas_scattering_optical_depth;
            totals.cia_optical_depth += evaluated.breakdown.cia_optical_depth;
            totals.aerosol_optical_depth += evaluated.breakdown.aerosol_optical_depth;
            totals.aerosol_scattering_optical_depth += evaluated.breakdown.aerosol_scattering_optical_depth;
        }
        return totals;
    }

    const gas_absorption_optical_depth =
        Spectroscopy.totalCrossSectionAtWavelength(self, wavelength_nm) * self.column_density_factor;
    const gas_scattering_optical_depth = Rayleigh.crossSectionCm2(wavelength_nm) *
        self.air_column_density_factor;

    const cia_optical_depth = choose_cia_optical_depth: {
        if (self.operational_o2o2_lut.enabled()) {
            break :choose_cia_optical_depth self.operational_o2o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ) * self.cia_pair_path_factor_cm5;
        }

        if (self.collision_induced_absorption) |cia_table| {
            break :choose_cia_optical_depth cia_table.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
            ) * self.cia_pair_path_factor_cm5;
        }

        break :choose_cia_optical_depth 0.0;
    };

    const aerosol_optical_depth = Scalar.particleOpticalDepthAtWavelength(
        self.aerosol_optical_depth,
        self.aerosol_base_optical_depth,
        self.aerosol_reference_wavelength_nm,
        self.aerosol_angstrom_exponent,
        self.aerosol_fraction_control,
        wavelength_nm,
    );
    const aerosol_single_scatter_albedo = self.resolvedAerosolSingleScatterAlbedo();

    return .{
        .gas_absorption_optical_depth = gas_absorption_optical_depth,
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .cia_optical_depth = cia_optical_depth,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo,
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
    // evaluateLayerAtWavelength ---------------------------------------------------------------------------- |
    // Evaluate one layer/support span without a caller-owned profile cache. This is the simple public helper;|
    // repeated wavelength routes should pass the cache to the implementation below.                          |
    // -------------------------------------------------------------------------------------------------------|

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
    // evaluateLayerAtWavelengthWithSpectroscopyCache ------------------------------------------------------- |
    // Evaluate one physical layer or support-row span at one wavelength.                                     |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Used by atmospheric budgets and non-shared layer routes. The loop walks PreparedSublayer rows and    |
    //   accumulates absorption, scattering, CIA, particle, and phase numerator fields into one result row.   |
    //                                                                                                        |
    // math                                                                                                   |
    // per sublayer tau_abs = sigma_cont*N_cont + sigma_xs*N_xs + sigma_line*N_line                           |
    // tau_rayleigh = sigma_R*N_air; tau_cia = sigma_cia*n_pair*path                                          |
    // -------------------------------------------------------------------------------------------------------|

    const AerosolProfile = struct {
        reference_wavelength_nm: f64,
        angstrom_exponent: f64,
    };
    const DirectionCosines = struct {
        solar_mu: f64,
        view_mu: f64,
    };

    var breakdown: OpticalDepthBreakdown = .{};
    const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
    const use_table_continuum = self.cross_section_absorbers.len == 0;

    for (sublayers, 0..) |sublayer, sublayer_index| {
        const global_sublayer_index = sublayer_start_index + sublayer_index;

        const continuum_optical_depth = choose_continuum_optical_depth: {
            if (!use_table_continuum) break :choose_continuum_optical_depth 0.0;

            const continuum_sigma = continuum_table.interpolateSigma(wavelength_nm);
            const continuum_density_cm3 =
                Scalar.continuumCarrierDensityAtSublayer(self, sublayer, global_sublayer_index);
            break :choose_continuum_optical_depth continuum_sigma *
                continuum_density_cm3 *
                sublayer.path_length_cm;
        };

        const gas_absorption_optical_depth = compute_gas_absorption: {
            var cross_section_optical_depth: f64 = 0.0;
            for (self.cross_section_absorbers) |cross_section_absorber| {
                if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;

                const absorber_density_cm3 =
                    cross_section_absorber.number_densities_cm3[global_sublayer_index];
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

                    const strong_line_state = if (line_absorber.strong_line_states) |states|
                        &states[global_sublayer_index]
                    else
                        null;
                    const sigma = line_absorber.line_list.sigmaAtPrepared(
                        wavelength_nm,
                        sublayer.temperature_k,
                        sublayer.pressure_hpa,
                        strong_line_state,
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

                break :compute_gas_absorption continuum_optical_depth +
                    cross_section_optical_depth +
                    line_optical_depth;
            }

            const strong_line_state = if (strong_line_states) |states| &states[sublayer_index] else null;
            const spectroscopy_sigma = Spectroscopy.spectroscopySigmaAtAltitudeWithCache(
                self,
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                sublayer.altitude_km,
                strong_line_state,
                profile_cache,
            );
            const spectroscopy_carrier_density_cm3 = Scalar.lineSpectroscopyCarrierDensityAtSublayer(
                self,
                sublayer,
                global_sublayer_index,
            );
            const gas_column_density_cm2 = spectroscopy_carrier_density_cm3 * sublayer.path_length_cm;

            break :compute_gas_absorption continuum_optical_depth +
                cross_section_optical_depth +
                spectroscopy_sigma * gas_column_density_cm2;
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

        const aerosol_profile: AerosolProfile = choose_aerosol_profile: {
            if (self.has_aerosol_profile_properties) {
                break :choose_aerosol_profile .{
                    .reference_wavelength_nm = sublayer.aerosol_reference_wavelength_nm,
                    .angstrom_exponent = sublayer.aerosol_angstrom_exponent,
                };
            }

            break :choose_aerosol_profile .{
                .reference_wavelength_nm = self.aerosol_reference_wavelength_nm,
                .angstrom_exponent = self.aerosol_angstrom_exponent,
            };
        };
        const aerosol_optical_depth = Scalar.particleOpticalDepthAtWavelength(
            sublayer.aerosol_optical_depth,
            sublayer.aerosol_base_optical_depth,
            aerosol_profile.reference_wavelength_nm,
            aerosol_profile.angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const aerosol_scattering_optical_depth =
            aerosol_optical_depth * sublayer.aerosol_single_scatter_albedo;

        breakdown.gas_absorption_optical_depth += gas_absorption_optical_depth;
        breakdown.gas_scattering_optical_depth += gas_scattering_optical_depth;
        breakdown.cia_optical_depth += cia_optical_depth;
        breakdown.aerosol_optical_depth += aerosol_optical_depth;
        breakdown.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
    }

    const phase = PhaseFunctions.PhaseMixture.fromScatteringMix(
        PhaseFunctions.rayleighPhaseCoefficient2AtWavelength(wavelength_nm),
        breakdown.gas_scattering_optical_depth,
        breakdown.aerosol_scattering_optical_depth,
        &self.aerosol_phase_coefficients,
    );
    const direction_cosines: DirectionCosines = choose_direction_cosines: {
        if (scene) |owned_scene| {
            break :choose_direction_cosines .{
                .solar_mu = owned_scene.geometry.solarCosineAtAltitude(altitude_km),
                .view_mu = owned_scene.geometry.viewingCosineAtAltitude(altitude_km),
            };
        }

        break :choose_direction_cosines .{
            .solar_mu = 1.0,
            .view_mu = 1.0,
        };
    };

    return .{
        .breakdown = breakdown,
        .phase = phase,
        .solar_mu = direction_cosines.solar_mu,
        .view_mu = direction_cosines.view_mu,
    };
}
