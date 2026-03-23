const std = @import("std");
const AbsorberModel = @import("../../model/Absorber.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OperationalReferenceGrid = @import("../../model/Instrument.zig").OperationalReferenceGrid;
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const Rayleigh = @import("../../model/reference/rayleigh.zig");
const transport_common = @import("../transport/common.zig");
const BandMeans = @import("prepare/band_means.zig");
const ParticleProfiles = @import("prepare/particle_profiles.zig");
const PhaseFunctions = @import("prepare/phase_functions.zig");
const gauss_legendre = @import("../quadrature/gauss_legendre.zig");

const Allocator = std.mem.Allocator;
const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const oxygen_volume_mixing_ratio = 0.2095;
const centimeters_per_kilometer = 1.0e5;

const ActiveLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    controls: AbsorberModel.LineGasControls,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
};

const PreparedLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    line_list: ReferenceData.SpectroscopyLineList,
    number_densities_cm3: []f64,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    strong_line_state_initialized: ?[]bool = null,
    strong_line_state_count: usize = 0,
    column_density_factor: f64 = 0.0,

    fn deinit(self: *PreparedLineAbsorber, allocator: Allocator) void {
        self.line_list.deinit(allocator);
        allocator.free(self.number_densities_cm3);
        if (self.strong_line_states) |states| {
            if (self.strong_line_state_initialized) |initialized| {
                for (states, initialized) |*state, is_initialized| {
                    if (!is_initialized) continue;
                    state.deinit(allocator);
                }
                allocator.free(initialized);
            } else {
                for (states[0..self.strong_line_state_count]) |*state| state.deinit(allocator);
            }
            allocator.free(states);
        }
        self.* = undefined;
    }
};

pub const PreparedLayer = struct {
    layer_index: u32,
    sublayer_start_index: u32 = 0,
    sublayer_count: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_optical_depth: f64,
    gas_scattering_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    layer_single_scatter_albedo: f64,
    depolarization_factor: f64,
    optical_depth: f64,
};

pub const PreparedSublayer = struct {
    parent_layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64 = 0.0,
    path_length_cm: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_sigma_cm5_per_molecule2: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    gas_extinction_optical_depth: f64,
    d_gas_optical_depth_d_temperature: f64,
    d_cia_optical_depth_d_temperature: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
    combined_phase_coefficients: [phase_coefficient_count]f64,
};

pub const OpticalDepthBreakdown = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,

    pub fn totalScatteringOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_scattering_optical_depth +
            self.aerosol_scattering_optical_depth +
            self.cloud_scattering_optical_depth;
    }

    pub fn totalOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_absorption_optical_depth +
            self.gas_scattering_optical_depth +
            self.cia_optical_depth +
            self.aerosol_optical_depth +
            self.cloud_optical_depth;
    }

    pub fn singleScatterAlbedo(self: OpticalDepthBreakdown) f64 {
        const total_optical_depth = self.totalOpticalDepth();
        if (total_optical_depth <= 0.0) return 0.0;
        return std.math.clamp(
            self.totalScatteringOpticalDepth() / total_optical_depth,
            0.0,
            1.0,
        );
    }
};

const EvaluatedLayer = struct {
    breakdown: OpticalDepthBreakdown = .{},
    phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.gasPhaseCoefficients(),
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
};

pub const PreparedOpticalState = struct {
    layers: []PreparedLayer,
    sublayers: ?[]PreparedSublayer = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    continuum_points: []ReferenceData.CrossSectionPoint,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    line_absorbers: []PreparedLineAbsorber = &.{},
    continuum_owner_species: ?AbsorberModel.AbsorberSpecies = null,
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    mean_cross_section_cm2_per_molecule: f64,
    line_mean_cross_section_cm2_per_molecule: f64,
    line_mixing_mean_cross_section_cm2_per_molecule: f64,
    cia_mean_cross_section_cm5_per_molecule2: f64,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64,
    cia_pair_path_factor_cm5: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    cloud_reference_wavelength_nm: f64,
    cloud_angstrom_exponent: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);
        allocator.free(self.continuum_points);
        if (self.collision_induced_absorption) |cia| {
            var owned_cia = cia;
            owned_cia.deinit(allocator);
        }
        if (self.line_absorbers.len != 0) {
            for (self.line_absorbers) |*line_absorber| {
                line_absorber.deinit(allocator);
            }
            allocator.free(self.line_absorbers);
        } else {
            if (self.strong_line_states) |states| {
                for (states) |*state| state.deinit(allocator);
                allocator.free(states);
            }
            if (self.spectroscopy_lines) |line_list| {
                var owned = line_list;
                owned.deinit(allocator);
            }
        }
        self.* = undefined;
    }

    pub fn toForwardInput(self: *const PreparedOpticalState, scene: *const Scene) transport_common.ForwardInput {
        return self.toForwardInputWithLayers(scene, null);
    }

    pub fn transportLayerCount(self: *const PreparedOpticalState) usize {
        if (self.sublayers) |sublayers| return sublayers.len;
        return self.layers.len;
    }

    pub fn toForwardInputWithLayers(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        layer_inputs: ?[]transport_common.LayerInput,
    ) transport_common.ForwardInput {
        return self.toForwardInputAtWavelengthWithLayers(
            scene,
            (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
            layer_inputs,
        );
    }

    pub fn toForwardInputAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
    ) transport_common.ForwardInput {
        return self.toForwardInputAtWavelengthWithLayers(scene, wavelength_nm, null);
    }

    pub fn toForwardInputAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        layer_inputs: ?[]transport_common.LayerInput,
    ) transport_common.ForwardInput {
        const optical_depths = if (layer_inputs) |owned_layers|
            self.fillForwardLayersAtWavelength(scene, wavelength_nm, owned_layers)
        else
            self.opticalDepthBreakdownAtWavelength(wavelength_nm);
        const mu0 = scene.geometry.solarCosineAtAltitude(0.0);
        const muv = scene.geometry.viewingCosineAtAltitude(0.0);
        const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
        const spectral_weight = if (scene.spectral_grid.sample_count <= 1)
            @max(span_nm, 1.0e-6)
        else
            span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
        return .{
            .wavelength_nm = wavelength_nm,
            .spectral_weight = @max(spectral_weight, 1.0e-6),
            .air_mass_factor = self.effective_air_mass_factor,
            .mu0 = mu0,
            .muv = muv,
            .relative_azimuth_rad = std.math.degreesToRadians(scene.geometry.relative_azimuth_deg),
            .surface_albedo = std.math.clamp(scene.surface.albedo, 0.0, 1.0),
            .gas_absorption_optical_depth = optical_depths.gas_absorption_optical_depth,
            .gas_scattering_optical_depth = optical_depths.gas_scattering_optical_depth,
            .cia_optical_depth = optical_depths.cia_optical_depth,
            .aerosol_optical_depth = optical_depths.aerosol_optical_depth,
            .aerosol_scattering_optical_depth = optical_depths.aerosol_scattering_optical_depth,
            .cloud_optical_depth = optical_depths.cloud_optical_depth,
            .cloud_scattering_optical_depth = optical_depths.cloud_scattering_optical_depth,
            .optical_depth = optical_depths.totalOpticalDepth(),
            .single_scatter_albedo = if (optical_depths.totalOpticalDepth() > 0.0)
                optical_depths.singleScatterAlbedo()
            else
                self.effective_single_scatter_albedo,
            .layers = if (layer_inputs) |owned_layers| owned_layers else &.{},
        };
    }

    pub fn totalCrossSectionAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        const continuum = (ReferenceData.CrossSectionTable{
            .points = self.continuum_points,
        }).interpolateSigma(wavelength_nm);
        const line_sigma = if (self.line_absorbers.len != 0)
            self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else if (self.operational_o2_lut.enabled())
            self.operational_o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            )
        else if (self.spectroscopy_lines) |line_list|
            line_list.evaluateAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else
            0.0;
        return continuum + line_sigma;
    }

    pub fn collisionInducedOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).cia_optical_depth;
    }

    pub fn gasOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        const optical_depths = self.opticalDepthBreakdownAtWavelength(wavelength_nm);
        return optical_depths.gas_absorption_optical_depth + optical_depths.gas_scattering_optical_depth;
    }

    pub fn aerosolOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).aerosol_optical_depth;
    }

    pub fn cloudOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).cloud_optical_depth;
    }

    pub fn totalOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).totalOpticalDepth();
    }

    pub fn fillForwardLayersAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        layer_inputs: []transport_common.LayerInput,
    ) OpticalDepthBreakdown {
        if (layer_inputs.len == 0) return self.opticalDepthBreakdownAtWavelength(wavelength_nm);

        if (self.sublayers) |sublayers| {
            if (layer_inputs.len == sublayers.len) {
                var totals: OpticalDepthBreakdown = .{};
                for (sublayers, 0..) |sublayer, sublayer_index| {
                    const evaluated = self.evaluateLayerAtWavelength(
                        scene,
                        sublayer.altitude_km,
                        wavelength_nm,
                        sublayer_index,
                        sublayers[sublayer_index .. sublayer_index + 1],
                        if (self.strong_line_states) |states| states[sublayer_index .. sublayer_index + 1] else null,
                    );
                    layer_inputs[sublayer_index] = .{
                        .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
                        .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
                        .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
                        .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
                        .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
                        .cloud_optical_depth = evaluated.breakdown.cloud_optical_depth,
                        .cloud_scattering_optical_depth = evaluated.breakdown.cloud_scattering_optical_depth,
                        .optical_depth = evaluated.breakdown.totalOpticalDepth(),
                        .scattering_optical_depth = evaluated.breakdown.totalScatteringOpticalDepth(),
                        .single_scatter_albedo = evaluated.breakdown.singleScatterAlbedo(),
                        .solar_mu = evaluated.solar_mu,
                        .view_mu = evaluated.view_mu,
                        .phase_coefficients = evaluated.phase_coefficients,
                    };
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

            var totals: OpticalDepthBreakdown = .{};
            for (self.layers, layer_inputs) |layer, *layer_input| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
                const evaluated = self.evaluateLayerAtWavelength(
                    scene,
                    layer.altitude_km,
                    wavelength_nm,
                    start_index,
                    sublayers[start_index..end_index],
                    if (self.strong_line_states) |states| states[start_index..end_index] else null,
                );
                layer_input.* = .{
                    .gas_absorption_optical_depth = evaluated.breakdown.gas_absorption_optical_depth,
                    .gas_scattering_optical_depth = evaluated.breakdown.gas_scattering_optical_depth,
                    .cia_optical_depth = evaluated.breakdown.cia_optical_depth,
                    .aerosol_optical_depth = evaluated.breakdown.aerosol_optical_depth,
                    .aerosol_scattering_optical_depth = evaluated.breakdown.aerosol_scattering_optical_depth,
                    .cloud_optical_depth = evaluated.breakdown.cloud_optical_depth,
                    .cloud_scattering_optical_depth = evaluated.breakdown.cloud_scattering_optical_depth,
                    .optical_depth = evaluated.breakdown.totalOpticalDepth(),
                    .scattering_optical_depth = evaluated.breakdown.totalScatteringOpticalDepth(),
                    .single_scatter_albedo = evaluated.breakdown.singleScatterAlbedo(),
                    .solar_mu = evaluated.solar_mu,
                    .view_mu = evaluated.view_mu,
                    .phase_coefficients = evaluated.phase_coefficients,
                };
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

        var totals: OpticalDepthBreakdown = .{};
        for (self.layers, layer_inputs) |layer, *layer_input| {
            const aerosol_optical_depth = ParticleProfiles.scaleOpticalDepth(
                layer.aerosol_optical_depth,
                self.aerosol_reference_wavelength_nm,
                self.aerosol_angstrom_exponent,
                wavelength_nm,
            );
            const cloud_optical_depth = ParticleProfiles.scaleOpticalDepth(
                layer.cloud_optical_depth,
                self.cloud_reference_wavelength_nm,
                self.cloud_angstrom_exponent,
                wavelength_nm,
            );
            const gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
            const scattering_optical_depth =
                gas_scattering_optical_depth +
                aerosol_optical_depth * layer.layer_single_scatter_albedo +
                cloud_optical_depth * layer.layer_single_scatter_albedo;
            layer_input.* = .{
                .gas_absorption_optical_depth = layer.gas_optical_depth,
                .gas_scattering_optical_depth = gas_scattering_optical_depth,
                .cia_optical_depth = layer.cia_optical_depth,
                .aerosol_optical_depth = aerosol_optical_depth,
                .aerosol_scattering_optical_depth = aerosol_optical_depth * layer.layer_single_scatter_albedo,
                .cloud_optical_depth = cloud_optical_depth,
                .cloud_scattering_optical_depth = cloud_optical_depth * layer.layer_single_scatter_albedo,
                .optical_depth = layer.gas_optical_depth + gas_scattering_optical_depth + layer.cia_optical_depth + aerosol_optical_depth + cloud_optical_depth,
                .scattering_optical_depth = scattering_optical_depth,
                .single_scatter_albedo = layer.layer_single_scatter_albedo,
                .solar_mu = scene.geometry.solarCosineAtAltitude(layer.altitude_km),
                .view_mu = scene.geometry.viewingCosineAtAltitude(layer.altitude_km),
                .phase_coefficients = PhaseFunctions.hgPhaseCoefficients(scene.aerosol.asymmetry_factor),
            };
            totals.gas_absorption_optical_depth += layer.gas_optical_depth;
            totals.gas_scattering_optical_depth += gas_scattering_optical_depth;
            totals.cia_optical_depth += layer.cia_optical_depth;
            totals.aerosol_optical_depth += aerosol_optical_depth;
            totals.aerosol_scattering_optical_depth += aerosol_optical_depth * layer.layer_single_scatter_albedo;
            totals.cloud_optical_depth += cloud_optical_depth;
            totals.cloud_scattering_optical_depth += cloud_optical_depth * layer.layer_single_scatter_albedo;
        }
        return totals;
    }

    pub fn fillSourceInterfacesAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        _: f64,
        layer_inputs: []const transport_common.LayerInput,
        source_interfaces: []transport_common.SourceInterfaceInput,
    ) void {
        if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

        transport_common.fillSourceInterfacesFromLayers(layer_inputs, source_interfaces);

        if (self.sublayers) |sublayers| {
            if (layer_inputs.len == sublayers.len) {
                for (1..layer_inputs.len) |ilevel| {
                    const sublayer = sublayers[ilevel];
                    const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
                    const rtm_weight = @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
                    source_interfaces[ilevel] = .{
                        .source_weight = 0.0,
                        .rtm_weight = rtm_weight,
                        .ksca_above = if (rtm_weight > 0.0)
                            scattering_optical_depth / rtm_weight
                        else
                            0.0,
                        .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                    };
                }
                return;
            }

            if (layer_inputs.len == 1) {
                return;
            }

            if (self.layers.len != layer_inputs.len) return;
            for (1..layer_inputs.len) |ilevel| {
                const layer = self.layers[ilevel];
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const sublayer_count: usize = @intCast(layer.sublayer_count);
                if (sublayer_count == 0) {
                    source_interfaces[ilevel] = .{
                        .source_weight = 0.0,
                        .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                    };
                    continue;
                }
                const stop_index = start_index + sublayer_count;
                var rtm_weight: f64 = 0.0;
                for (sublayers[start_index..stop_index]) |sublayer| {
                    rtm_weight += @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
                }
                const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .rtm_weight = rtm_weight,
                    .ksca_above = if (rtm_weight > 0.0)
                        scattering_optical_depth / rtm_weight
                    else
                        0.0,
                    .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                };
            }
            return;
        }
    }

    fn levelAltitudeFromSublayers(
        sublayers: []const PreparedSublayer,
        level: usize,
    ) f64 {
        if (sublayers.len == 0) return 0.0;
        if (level == 0) {
            const first = sublayers[0];
            return @max(first.altitude_km - 0.5 * first.path_length_cm / centimeters_per_kilometer, 0.0);
        }
        if (level >= sublayers.len) {
            const last = sublayers[sublayers.len - 1];
            return @max(last.altitude_km + 0.5 * last.path_length_cm / centimeters_per_kilometer, 0.0);
        }
        const sample = sublayers[level];
        return @max(sample.altitude_km - 0.5 * sample.path_length_cm / centimeters_per_kilometer, 0.0);
    }

    const PreparedQuadratureCarrier = struct {
        ksca: f64,
        phase_coefficients: [phase_coefficient_count]f64,
    };

    const PseudoSphericalCarrier = struct {
        optical_depth: f64,
    };

    const PseudoSphericalInterval = struct {
        support_sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
        lower_altitude_km: f64,
        upper_altitude_km: f64,
    };

    const InterpolatedQuadratureState = struct {
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

    fn opticalDepthPerKilometer(
        optical_depth: f64,
        path_length_cm: f64,
    ) f64 {
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

    fn preparedStrongLineStateAtAltitude(
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
        altitude_km: f64,
    ) ?*const ReferenceData.StrongLinePreparedState {
        const states = strong_line_states orelse return null;
        if (states.len == 0 or states.len != sublayers.len) return null;
        if (states.len == 1) return &states[0];

        if (altitude_km <= sublayers[0].altitude_km) return &states[0];
        if (altitude_km >= sublayers[sublayers.len - 1].altitude_km) return &states[states.len - 1];

        for (sublayers[0 .. sublayers.len - 1], sublayers[1..], 0..) |left, right, index| {
            if (altitude_km > right.altitude_km) continue;
            const left_distance = @abs(altitude_km - left.altitude_km);
            const right_distance = @abs(right.altitude_km - altitude_km);
            return if (left_distance <= right_distance) &states[index] else &states[index + 1];
        }

        return &states[states.len - 1];
    }

    fn operationalO2EvaluationAtWavelength(
        operational_o2_lut: OperationalCrossSectionLut,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        const sigma = operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        return .{
            .weak_line_sigma_cm2_per_molecule = sigma,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = sigma,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = sigma,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            ),
        };
    }

    fn preparedScalarForSublayer(values: []const f64, sublayer: PreparedSublayer) f64 {
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
        return left_value + (right_value - left_value) * fraction;
    }

    fn interpolatePreparedScalarAtAltitude(
        sublayers: []const PreparedSublayer,
        values: []const f64,
        altitude_km: f64,
    ) f64 {
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

    fn lineAbsorberDensityForSpeciesAtSublayer(
        self: *const PreparedOpticalState,
        species: AbsorberModel.AbsorberSpecies,
        global_sublayer_index: usize,
    ) f64 {
        for (self.line_absorbers) |line_absorber| {
            if (line_absorber.species != species) continue;
            if (global_sublayer_index >= line_absorber.number_densities_cm3.len) return 0.0;
            return line_absorber.number_densities_cm3[global_sublayer_index];
        }
        return 0.0;
    }

    fn lineAbsorberDensityForSpeciesAtAltitude(
        self: *const PreparedOpticalState,
        species: AbsorberModel.AbsorberSpecies,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
    ) f64 {
        for (self.line_absorbers) |line_absorber| {
            if (line_absorber.species != species) continue;
            return interpolatePreparedScalarAtAltitude(
                sublayers,
                line_absorber.number_densities_cm3,
                altitude_km,
            );
        }
        return 0.0;
    }

    fn continuumCarrierDensityAtSublayer(
        self: *const PreparedOpticalState,
        sublayer: PreparedSublayer,
        global_sublayer_index: usize,
    ) f64 {
        if (self.line_absorbers.len == 0) return sublayer.absorber_number_density_cm3;

        const owner_species = self.continuum_owner_species orelse return sublayer.absorber_number_density_cm3;
        // DECISION:
        //   When preparation can identify a continuum owner, scope the continuum to that
        //   gas only. If ownership is unknown, preserve the prior summed-density behavior
        //   rather than dropping continuum absorption entirely for mixed non-O2 families.
        if (self.operational_o2_lut.enabled() and owner_species == .o2) {
            return sublayer.oxygen_number_density_cm3;
        }
        return self.lineAbsorberDensityForSpeciesAtSublayer(owner_species, global_sublayer_index);
    }

    fn continuumCarrierDensityAtAltitude(
        self: *const PreparedOpticalState,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
        absorber_density_cm3: f64,
        oxygen_density_cm3: f64,
    ) f64 {
        if (self.line_absorbers.len == 0) return absorber_density_cm3;

        const owner_species = self.continuum_owner_species orelse return absorber_density_cm3;
        if (self.operational_o2_lut.enabled() and owner_species == .o2) {
            return oxygen_density_cm3;
        }
        return self.lineAbsorberDensityForSpeciesAtAltitude(owner_species, sublayers, altitude_km);
    }

    fn quadratureCarrierAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
    ) PreparedQuadratureCarrier {
        const default: PreparedQuadratureCarrier = .{
            .ksca = 0.0,
            .phase_coefficients = [_]f64{ 1.0, 0.0, 0.0, 0.0 },
        };
        const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return default;

        const gas_scattering_optical_depth_per_km =
            Rayleigh.crossSectionCm2(wavelength_nm) *
            state.number_density_cm3 *
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
            .ksca = gas_scattering_optical_depth_per_km +
                aerosol_scattering_optical_depth_per_km +
                cloud_scattering_optical_depth_per_km,
            .phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
                gas_scattering_optical_depth_per_km,
                aerosol_scattering_optical_depth_per_km,
                cloud_scattering_optical_depth_per_km,
                state.aerosol_phase_coefficients,
                state.cloud_phase_coefficients,
            ),
        };
    }

    fn pseudoSphericalCarrierAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
        altitude_km: f64,
        weight_km: f64,
    ) PseudoSphericalCarrier {
        const state = interpolateQuadratureStateAtAltitude(sublayers, altitude_km) orelse return .{ .optical_depth = 0.0 };
        const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };
        const continuum_sigma = continuum_table.interpolateSigma(wavelength_nm);
        const prepared_state = preparedStrongLineStateAtAltitude(sublayers, strong_line_states, altitude_km);
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
        const continuum_density_cm3 = self.continuumCarrierDensityAtAltitude(
            sublayers,
            altitude_km,
            state.absorber_number_density_cm3,
            state.oxygen_number_density_cm3,
        );
        const gas_absorption_optical_depth_per_km =
            continuum_sigma *
            continuum_density_cm3 *
            centimeters_per_kilometer +
            spectroscopy_sigma *
                state.absorber_number_density_cm3 *
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

        return .{
            .optical_depth = weight_km * (gas_absorption_optical_depth_per_km +
                gas_scattering_optical_depth_per_km +
                cia_optical_depth_per_km +
                aerosol_optical_depth_per_km +
                cloud_optical_depth_per_km),
        };
    }

    pub fn fillRtmQuadratureAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        layer_inputs: []const transport_common.LayerInput,
        rtm_levels: []transport_common.RtmQuadratureLevel,
    ) bool {
        const sublayers = self.sublayers orelse return false;
        if (layer_inputs.len != sublayers.len or rtm_levels.len != layer_inputs.len + 1) return false;

        for (rtm_levels, 0..) |*rtm_level, level| {
            rtm_level.* = .{
                .altitude_km = levelAltitudeFromSublayers(sublayers, level),
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
            };
        }

        var has_active_quadrature = false;
        for (self.layers) |layer| {
            const start: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) continue;
            const stop = start + count;
            if (stop >= rtm_levels.len) return false;

            const active_count = if (count > 0) count - 1 else 0;
            if (active_count == 0) continue;
            const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
            const lower_altitude_km = rtm_levels[start].altitude_km;
            const upper_altitude_km = rtm_levels[stop].altitude_km;
            const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);

            var total_span_km: f64 = 0.0;
            var total_scattering: f64 = 0.0;
            for (sublayers[start..stop], layer_inputs[start..stop]) |sublayer, layer_input| {
                total_span_km += @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
                total_scattering += @max(layer_input.scattering_optical_depth, 0.0);
            }
            if (total_span_km <= 0.0) continue;

            var raw_scattering_sum: f64 = 0.0;
            for (0..active_count) |node_index| {
                const level = start + 1 + node_index;
                const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
                const node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
                const carrier = self.quadratureCarrierAtAltitude(
                    wavelength_nm,
                    sublayers[start..stop],
                    node_altitude_km,
                );
                rtm_levels[level].altitude_km = node_altitude_km;
                rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
                rtm_levels[level].ksca = carrier.ksca;
                rtm_levels[level].phase_coefficients = carrier.phase_coefficients;
                raw_scattering_sum += rtm_levels[level].weightedScattering();
            }

            if (total_scattering <= 0.0) {
                for (start + 1..stop) |level| {
                    rtm_levels[level].ksca = 0.0;
                }
                continue;
            }

            if (raw_scattering_sum > 0.0) {
                const scale = total_scattering / raw_scattering_sum;
                for (start + 1..stop) |level| {
                    rtm_levels[level].ksca *= scale;
                }
                has_active_quadrature = true;
            } else {
                for (start + 1..stop) |level| {
                    rtm_levels[level].weight = 0.0;
                    rtm_levels[level].ksca = 0.0;
                }
            }
        }

        return has_active_quadrature;
    }

    pub fn fillPseudoSphericalGridAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        solver_layer_count: usize,
        attenuation_layers: []transport_common.LayerInput,
        attenuation_samples: []transport_common.PseudoSphericalSample,
        level_sample_starts: []usize,
        level_altitudes_km: []f64,
    ) bool {
        const sublayers = self.sublayers orelse return false;
        const subgrid_divisions = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
        const sample_count = solver_layer_count * subgrid_divisions;
        _ = attenuation_layers;
        if (attenuation_samples.len < sample_count or
            level_sample_starts.len != solver_layer_count + 1 or
            level_altitudes_km.len != solver_layer_count + 1)
        {
            return false;
        }

        if (solver_layer_count != sublayers.len and solver_layer_count != self.layers.len) {
            return false;
        }

        var sample_index: usize = 0;
        if (solver_layer_count == sublayers.len) {
            level_altitudes_km[0] = levelAltitudeFromSublayers(sublayers, 0);
            for (1..solver_layer_count + 1) |ilevel| {
                level_altitudes_km[ilevel] = levelAltitudeFromSublayers(sublayers, ilevel);
            }
        } else {
            level_altitudes_km[0] = levelAltitudeFromSublayers(sublayers, 0);
            for (1..solver_layer_count) |ilevel| {
                const start_index: usize = @intCast(self.layers[ilevel].sublayer_start_index);
                level_altitudes_km[ilevel] = levelAltitudeFromSublayers(sublayers, start_index);
            }
            level_altitudes_km[solver_layer_count] = levelAltitudeFromSublayers(sublayers, sublayers.len);
        }

        for (0..solver_layer_count) |solver_level| {
            const interval = if (solver_layer_count == sublayers.len)
                PseudoSphericalInterval{
                    .support_sublayers = sublayers[solver_level .. solver_level + 1],
                    .strong_line_states = if (self.strong_line_states) |states|
                        states[solver_level .. solver_level + 1]
                    else
                        null,
                    .lower_altitude_km = levelAltitudeFromSublayers(sublayers, solver_level),
                    .upper_altitude_km = levelAltitudeFromSublayers(sublayers, solver_level + 1),
                }
            else blk: {
                const layer = self.layers[solver_level];
                const start: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) return false;
                const stop = start + count;
                break :blk PseudoSphericalInterval{
                    .support_sublayers = sublayers[start..stop],
                    .strong_line_states = if (self.strong_line_states) |states|
                        states[start..stop]
                    else
                        null,
                    .lower_altitude_km = levelAltitudeFromSublayers(sublayers, start),
                    .upper_altitude_km = levelAltitudeFromSublayers(sublayers, stop),
                };
            };
            const altitude_span_km = @max(interval.upper_altitude_km - interval.lower_altitude_km, 0.0);
            const active_count = subgrid_divisions - 1;

            level_sample_starts[solver_level] = sample_index;
            if (active_count == 0) {
                const sample_altitude_km = if (altitude_span_km > 0.0)
                    interval.lower_altitude_km + 0.5 * altitude_span_km
                else
                    interval.lower_altitude_km;
                attenuation_samples[sample_index] = .{
                    .altitude_km = sample_altitude_km,
                    .thickness_km = altitude_span_km,
                    .optical_depth = self.pseudoSphericalCarrierAtAltitude(
                        wavelength_nm,
                        interval.support_sublayers,
                        interval.strong_line_states,
                        sample_altitude_km,
                        altitude_span_km,
                    ).optical_depth,
                };
                sample_index += 1;
                continue;
            }

            attenuation_samples[sample_index] = .{
                .altitude_km = interval.lower_altitude_km,
                .thickness_km = 0.0,
                .optical_depth = 0.0,
            };
            sample_index += 1;

            if (altitude_span_km <= 0.0) {
                for (0..active_count) |_| {
                    attenuation_samples[sample_index] = .{
                        .altitude_km = interval.lower_altitude_km,
                        .thickness_km = 0.0,
                        .optical_depth = 0.0,
                    };
                    sample_index += 1;
                }
                continue;
            }

            const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
            for (0..active_count) |node_index| {
                const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
                const node_altitude_km = interval.lower_altitude_km + normalized_position * altitude_span_km;
                const weight_km = 0.5 * rule.weights[node_index] * altitude_span_km;
                attenuation_samples[sample_index] = .{
                    .altitude_km = node_altitude_km,
                    .thickness_km = weight_km,
                    .optical_depth = self.pseudoSphericalCarrierAtAltitude(
                        wavelength_nm,
                        interval.support_sublayers,
                        interval.strong_line_states,
                        node_altitude_km,
                        weight_km,
                    ).optical_depth,
                };
                sample_index += 1;
            }
        }

        level_sample_starts[solver_layer_count] = sample_index;
        return true;
    }

    pub fn opticalDepthBreakdownAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) OpticalDepthBreakdown {
        if (self.sublayers) |sublayers| {
            var totals: OpticalDepthBreakdown = .{};
            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
                const evaluated = self.evaluateLayerAtWavelength(
                    null,
                    layer.altitude_km,
                    wavelength_nm,
                    start_index,
                    sublayers[start_index..end_index],
                    if (self.strong_line_states) |states| states[start_index..end_index] else null,
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
            self.totalCrossSectionAtWavelength(wavelength_nm) * self.column_density_factor;
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
        const aerosol_optical_depth = ParticleProfiles.scaleOpticalDepth(
            self.aerosol_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            wavelength_nm,
        );
        const cloud_optical_depth = ParticleProfiles.scaleOpticalDepth(
            self.cloud_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            wavelength_nm,
        );
        return .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_optical_depth * self.effective_single_scatter_albedo,
            .cloud_optical_depth = cloud_optical_depth,
            .cloud_scattering_optical_depth = cloud_optical_depth * self.effective_single_scatter_albedo,
        };
    }

    fn evaluateLayerAtWavelength(
        self: *const PreparedOpticalState,
        scene: ?*const Scene,
        altitude_km: f64,
        wavelength_nm: f64,
        sublayer_start_index: usize,
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    ) EvaluatedLayer {
        var breakdown: OpticalDepthBreakdown = .{};
        var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
        const gas_phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
        const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };

        for (sublayers, 0..) |sublayer, sublayer_index| {
            const global_sublayer_index = sublayer_start_index + sublayer_index;
            const continuum_sigma = continuum_table.interpolateSigma(wavelength_nm);
            const gas_absorption_optical_depth = blk: {
                const continuum_density_cm3 = self.continuumCarrierDensityAtSublayer(
                    sublayer,
                    global_sublayer_index,
                );
                const continuum_optical_depth =
                    continuum_sigma *
                    continuum_density_cm3 *
                    sublayer.path_length_cm;
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
                    break :blk continuum_optical_depth + line_optical_depth;
                }

                const spectroscopy_sigma = self.spectroscopySigmaAtWavelength(
                    wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                    if (strong_line_states) |states| &states[sublayer_index] else null,
                );
                const gas_column_density_cm2 = sublayer.absorber_number_density_cm3 * sublayer.path_length_cm;
                break :blk continuum_optical_depth + spectroscopy_sigma * gas_column_density_cm2;
            };
            const gas_scattering_optical_depth =
                Rayleigh.crossSectionCm2(wavelength_nm) *
                sublayer.number_density_cm3 *
                sublayer.path_length_cm;
            const cia_sigma_cm5_per_molecule2 = self.ciaSigmaAtWavelength(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
            );
            const cia_optical_depth =
                cia_sigma_cm5_per_molecule2 *
                sublayer.oxygen_number_density_cm3 *
                sublayer.oxygen_number_density_cm3 *
                sublayer.path_length_cm;
            const aerosol_optical_depth = ParticleProfiles.scaleOpticalDepth(
                sublayer.aerosol_optical_depth,
                self.aerosol_reference_wavelength_nm,
                self.aerosol_angstrom_exponent,
                wavelength_nm,
            );
            const cloud_optical_depth = ParticleProfiles.scaleOpticalDepth(
                sublayer.cloud_optical_depth,
                self.cloud_reference_wavelength_nm,
                self.cloud_angstrom_exponent,
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
        var phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
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

    fn spectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        if (self.line_absorbers.len != 0) {
            return self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
        }
        if (self.operational_o2_lut.enabled()) {
            return operationalO2EvaluationAtWavelength(self.operational_o2_lut, wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.spectroscopy_lines) |line_list| {
            return line_list.evaluateAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        return .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    fn spectroscopySigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    ) f64 {
        if (self.line_absorbers.len != 0) {
            return self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            ).total_sigma_cm2_per_molecule;
        }
        if (self.operational_o2_lut.enabled()) {
            return self.operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.spectroscopy_lines) |line_list| {
            return line_list.sigmaAtPrepared(wavelength_nm, temperature_k, pressure_hpa, prepared_state);
        }
        return 0.0;
    }

    fn weightedSpectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
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

        if (self.operational_o2_lut.enabled() and self.oxygen_column_density_factor > 0.0) {
            const o2_evaluation = operationalO2EvaluationAtWavelength(
                self.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
            total_weight += self.oxygen_column_density_factor;
            weighted.weak_line_sigma_cm2_per_molecule +=
                o2_evaluation.weak_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.strong_line_sigma_cm2_per_molecule +=
                o2_evaluation.strong_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.line_sigma_cm2_per_molecule +=
                o2_evaluation.line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.line_mixing_sigma_cm2_per_molecule +=
                o2_evaluation.line_mixing_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.total_sigma_cm2_per_molecule +=
                o2_evaluation.total_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * self.oxygen_column_density_factor;
        }

        for (self.line_absorbers) |line_absorber| {
            if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = if (line_absorber.column_density_factor > 0.0)
                line_absorber.column_density_factor
            else
                1.0;
            const evaluation = line_absorber.line_list.evaluateAt(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
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

        if (total_weight <= 0.0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
        weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
        weighted.total_sigma_cm2_per_molecule /= total_weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
        return weighted;
    }

    fn weightedSpectroscopyEvaluationAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
        oxygen_density_cm3: f64,
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

        if (self.operational_o2_lut.enabled() and oxygen_density_cm3 > 0.0) {
            const o2_evaluation = operationalO2EvaluationAtWavelength(
                self.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
            total_weight += oxygen_density_cm3;
            weighted.weak_line_sigma_cm2_per_molecule += o2_evaluation.weak_line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.strong_line_sigma_cm2_per_molecule += o2_evaluation.strong_line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.line_sigma_cm2_per_molecule += o2_evaluation.line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.line_mixing_sigma_cm2_per_molecule += o2_evaluation.line_mixing_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.total_sigma_cm2_per_molecule += o2_evaluation.total_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * oxygen_density_cm3;
        }

        for (self.line_absorbers) |line_absorber| {
            if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = interpolatePreparedScalarAtAltitude(
                sublayers,
                line_absorber.number_densities_cm3,
                altitude_km,
            );
            if (weight <= 0.0) continue;

            const evaluation = line_absorber.line_list.evaluateAtPrepared(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                preparedStrongLineStateAtAltitude(
                    sublayers,
                    line_absorber.strong_line_states,
                    altitude_km,
                ),
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

        if (total_weight <= 0.0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
        weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
        weighted.total_sigma_cm2_per_molecule /= total_weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
        return weighted;
    }

    fn ciaSigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        if (self.operational_o2o2_lut.enabled()) {
            return self.operational_o2o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.collision_induced_absorption) |cia_table| {
            return cia_table.sigmaAt(wavelength_nm, temperature_k);
        }
        return 0.0;
    }
};

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        null,
        lut,
        null,
        null,
    );
}

pub fn prepareWithSpectroscopy(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithSpectroscopyAndCollisionInducedAbsorption(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        collision_induced_absorption,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithParticleTables(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable,
    cloud_mie: ?*const ReferenceData.MiePhaseTable,
) !PreparedOpticalState {
    try scene.validate();

    const layer_count = @max(scene.atmosphere.layer_count, @as(u32, 1));
    const sublayer_divisions = @max(@as(u32, scene.atmosphere.sublayer_divisions), @as(u32, 1));
    const layers = try allocator.alloc(PreparedLayer, layer_count);
    errdefer allocator.free(layers);
    const sublayers = try allocator.alloc(PreparedSublayer, @as(usize, layer_count) * @as(usize, sublayer_divisions));
    errdefer allocator.free(sublayers);
    const continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, cross_sections.points);
    errdefer allocator.free(continuum_points);
    const owned_cia = if (collision_induced_absorption) |cia|
        try cia.clone(allocator)
    else
        null;
    errdefer if (owned_cia) |table| {
        var owned = table;
        owned.deinit(allocator);
    };
    var owned_lines = if (spectroscopy_lines) |line_list|
        try line_list.clone(allocator)
    else
        null;
    errdefer if (owned_lines) |line_list| {
        var owned = line_list;
        owned.deinit(allocator);
    };
    const operational_o2_lut = scene.observation_model.o2_operational_lut;
    const operational_o2o2_lut = scene.observation_model.o2o2_operational_lut;
    const total_sublayer_count = @as(usize, layer_count) * @as(usize, sublayer_divisions);
    const active_line_absorbers = try collectActiveLineAbsorbers(allocator, scene);
    defer allocator.free(active_line_absorbers);
    const single_active_line_absorber = if (active_line_absorbers.len == 1)
        active_line_absorbers[0]
    else
        null;

    var owned_line_absorbers: []PreparedLineAbsorber = &.{};
    var owned_line_absorber_count: usize = 0;
    errdefer if (owned_line_absorbers.len != 0) {
        for (owned_line_absorbers[0..owned_line_absorber_count]) |*line_absorber| {
            line_absorber.deinit(allocator);
        }
        allocator.free(owned_line_absorbers);
    };

    if (owned_lines) |*line_list| {
        if (active_line_absorbers.len > 1 or (operational_o2_lut.enabled() and active_line_absorbers.len != 0)) {
            owned_line_absorbers = try allocator.alloc(PreparedLineAbsorber, active_line_absorbers.len);

            for (active_line_absorbers, 0..) |line_absorber, index| {
                var filtered = try line_list.clone(allocator);
                errdefer filtered.deinit(allocator);
                const use_operational_o2_lut = operational_o2_lut.enabled() and line_absorber.species == .o2;

                try filtered.applyRuntimeControls(
                    allocator,
                    if (line_absorber.species.hitranIndex()) |hitran_index|
                        @as(u16, hitran_index)
                    else
                        null,
                    line_absorber.controls.activeIsotopes(),
                    line_absorber.controls.activeThresholdLine(),
                    line_absorber.controls.activeCutoffCm1(),
                    if (line_absorber.species == .o2)
                        line_absorber.controls.activeLineMixingFactor()
                    else
                        0.0,
                );
                if (!use_operational_o2_lut and filtered.lines.len == 0) {
                    return error.InvalidRequest;
                }
                std.sort.pdq(
                    ReferenceData.SpectroscopyLine,
                    filtered.lines,
                    {},
                    struct {
                        fn lessThan(_: void, left: ReferenceData.SpectroscopyLine, right: ReferenceData.SpectroscopyLine) bool {
                            return left.center_wavelength_nm < right.center_wavelength_nm;
                        }
                    }.lessThan,
                );
                filtered.lines_sorted_ascending = true;
                if (!use_operational_o2_lut) {
                    try filtered.buildStrongLineMatchIndex(allocator);
                }
                const has_strong_line_states = !use_operational_o2_lut and filtered.hasStrongLineSidecars();
                const strong_line_states = if (has_strong_line_states)
                    try allocator.alloc(ReferenceData.StrongLinePreparedState, total_sublayer_count)
                else
                    null;
                errdefer if (strong_line_states) |states| allocator.free(states);
                const strong_line_state_initialized = if (has_strong_line_states)
                    try allocator.alloc(bool, total_sublayer_count)
                else
                    null;
                errdefer if (strong_line_state_initialized) |initialized| allocator.free(initialized);

                owned_line_absorbers[index] = .{
                    .species = line_absorber.species,
                    .line_list = filtered,
                    .number_densities_cm3 = try allocator.alloc(f64, total_sublayer_count),
                    .strong_line_states = strong_line_states,
                    .strong_line_state_initialized = strong_line_state_initialized,
                };
                @memset(owned_line_absorbers[index].number_densities_cm3, 0.0);
                if (owned_line_absorbers[index].strong_line_state_initialized) |initialized| @memset(initialized, false);
                owned_line_absorber_count += 1;
            }

            var owned = line_list.*;
            owned.deinit(allocator);
            owned_lines = null;
        } else {
            if (single_active_line_absorber) |line_absorber| {
                try line_list.applyRuntimeControls(
                    allocator,
                    if (line_absorber.species.hitranIndex()) |hitran_index|
                        @as(u16, hitran_index)
                    else
                        null,
                    line_absorber.controls.activeIsotopes(),
                    line_absorber.controls.activeThresholdLine(),
                    line_absorber.controls.activeCutoffCm1(),
                    if (line_absorber.species == .o2)
                        line_absorber.controls.activeLineMixingFactor()
                    else
                        0.0,
                );
                if (!operational_o2_lut.enabled() and line_list.lines.len == 0) {
                    return error.InvalidRequest;
                }
            }
            std.sort.pdq(
                ReferenceData.SpectroscopyLine,
                line_list.lines,
                {},
                struct {
                    fn lessThan(_: void, left: ReferenceData.SpectroscopyLine, right: ReferenceData.SpectroscopyLine) bool {
                        return left.center_wavelength_nm < right.center_wavelength_nm;
                    }
                }.lessThan,
            );
            line_list.lines_sorted_ascending = true;
            if (!operational_o2_lut.enabled()) {
                try line_list.buildStrongLineMatchIndex(allocator);
            }
        }
    }
    const strong_line_states = if (owned_line_absorbers.len == 0)
        if (owned_lines) |line_list|
            if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars())
                try allocator.alloc(ReferenceData.StrongLinePreparedState, total_sublayer_count)
            else
                null
        else
            null
    else
        null;
    var strong_line_state_count: usize = 0;
    errdefer if (strong_line_states) |states| {
        for (states[0..strong_line_state_count]) |*state| state.deinit(allocator);
        allocator.free(states);
    };

    const midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5;
    const active_line_species = if (owned_line_absorbers.len == 0)
        resolveActiveLineSpecies(single_active_line_absorber, owned_lines, operational_o2_lut)
    else
        null;
    const continuum_owner_species = resolveContinuumOwnerSpecies(
        active_line_species,
        owned_line_absorbers,
        operational_o2_lut,
    );
    const mean_sigma = cross_sections.meanSigmaInRange(
        scene.spectral_grid.start_nm,
        scene.spectral_grid.end_nm,
    );
    const midpoint_continuum_sigma = cross_sections.interpolateSigma(midpoint_nm);
    const air_mass_factor = lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const layer_span_km = altitude_span / @as(f64, @floatFromInt(layer_count));
    const base_single_scatter_albedo = PhaseFunctions.computeSingleScatterAlbedo(scene);

    var total_optical_depth: f64 = 0.0;
    var total_temperature_weighted: f64 = 0.0;
    var total_pressure_weighted: f64 = 0.0;
    var total_weight: f64 = 0.0;
    var air_column_density_factor: f64 = 0.0;
    var oxygen_column_density_factor: f64 = 0.0;
    var column_density_factor: f64 = 0.0;
    var cia_pair_path_factor_cm5: f64 = 0.0;
    var total_gas_optical_depth: f64 = 0.0;
    var total_cia_optical_depth: f64 = 0.0;
    var total_aerosol_optical_depth: f64 = 0.0;
    var total_cloud_optical_depth: f64 = 0.0;
    var total_scattering_optical_depth: f64 = 0.0;
    var total_d_optical_depth_d_temperature: f64 = 0.0;
    var depolarization_weighted: f64 = 0.0;

    const aerosol_sublayer_distribution = try ParticleProfiles.buildAerosolSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
    );
    defer allocator.free(aerosol_sublayer_distribution);
    const cloud_sublayer_distribution = try ParticleProfiles.buildCloudSublayerDistribution(
        allocator,
        scene,
        profile,
        layer_count,
        sublayer_divisions,
    );
    defer allocator.free(cloud_sublayer_distribution);
    const aerosol_mie_point = if (aerosol_mie) |table| table.interpolate(midpoint_nm) else null;
    const cloud_mie_point = if (cloud_mie) |table| table.interpolate(midpoint_nm) else null;
    const aerosol_phase_coefficients = if (aerosol_mie_point) |point| point.phase_coefficients else PhaseFunctions.hgPhaseCoefficients(scene.aerosol.asymmetry_factor);
    const cloud_phase_coefficients = if (cloud_mie_point) |point| point.phase_coefficients else PhaseFunctions.hgPhaseCoefficients(scene.cloud.asymmetry_factor);
    const aerosol_single_scatter_albedo = if (aerosol_mie_point) |point| point.single_scatter_albedo else scene.aerosol.single_scatter_albedo;
    const cloud_single_scatter_albedo = if (cloud_mie_point) |point| point.single_scatter_albedo else scene.cloud.single_scatter_albedo;
    const aerosol_extinction_scale = if (aerosol_mie_point) |point| point.extinction_scale else 1.0;
    const cloud_extinction_scale = if (cloud_mie_point) |point| point.extinction_scale else 1.0;

    var sublayer_write_index: usize = 0;
    for (layers, 0..) |*layer, index| {
        const layer_bottom_altitude_km = layer_span_km * @as(f64, @floatFromInt(index));
        const layer_center_altitude_km = layer_bottom_altitude_km + 0.5 * layer_span_km;
        const sublayer_weight = 1.0 / @as(f64, @floatFromInt(sublayer_divisions));

        var layer_density_weight: f64 = 0.0;
        var layer_density_sum: f64 = 0.0;
        var layer_temperature_sum: f64 = 0.0;
        var layer_pressure_sum: f64 = 0.0;
        var layer_line_sigma_sum: f64 = 0.0;
        var layer_line_mixing_sum: f64 = 0.0;
        var layer_d_cross_section_sum: f64 = 0.0;
        var layer_gas_optical_depth: f64 = 0.0;
        var layer_gas_scattering_optical_depth: f64 = 0.0;
        var layer_cia_optical_depth: f64 = 0.0;
        var layer_aerosol_optical_depth: f64 = 0.0;
        var layer_cloud_optical_depth: f64 = 0.0;

        for (0..sublayer_divisions) |sublayer_index| {
            const sublayer_fraction = (@as(f64, @floatFromInt(sublayer_index)) + 0.5) / @as(f64, @floatFromInt(sublayer_divisions));
            const altitude_km = layer_bottom_altitude_km + layer_span_km * sublayer_fraction;
            const density = profile.interpolateDensity(altitude_km);
            const pressure = profile.interpolatePressure(altitude_km);
            const temperature = profile.interpolateTemperature(altitude_km);
            const oxygen_mixing_ratio = speciesMixingRatioAtPressure(
                scene,
                .o2,
                &.{},
                pressure,
                oxygen_volume_mixing_ratio,
            ) orelse oxygen_volume_mixing_ratio;
            var absorber_density_cm3: f64 = 0.0;
            const spectroscopy_eval = if (owned_line_absorbers.len != 0) blk: {
                const delta_t = 0.5;
                var spectroscopy_weight: f64 = 0.0;
                var weighted: ReferenceData.SpectroscopyEvaluation = .{
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };

                if (operational_o2_lut.enabled()) {
                    const o2_density_cm3 = density * oxygen_mixing_ratio;
                    absorber_density_cm3 += o2_density_cm3;
                    if (o2_density_cm3 > 0.0) {
                        const o2_evaluation = PreparedOpticalState.operationalO2EvaluationAtWavelength(
                            operational_o2_lut,
                            midpoint_nm,
                            temperature,
                            pressure,
                        );
                        spectroscopy_weight += o2_density_cm3;
                        weighted.weak_line_sigma_cm2_per_molecule +=
                            o2_evaluation.weak_line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.strong_line_sigma_cm2_per_molecule +=
                            o2_evaluation.strong_line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.line_sigma_cm2_per_molecule +=
                            o2_evaluation.line_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.line_mixing_sigma_cm2_per_molecule +=
                            o2_evaluation.line_mixing_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.total_sigma_cm2_per_molecule +=
                            o2_evaluation.total_sigma_cm2_per_molecule * o2_density_cm3;
                        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                            o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * o2_density_cm3;
                    }
                }

                for (owned_line_absorbers, active_line_absorbers, 0..) |*line_absorber, active_absorber, line_absorber_index| {
                    if (operational_o2_lut.enabled() and line_absorber.species == .o2) {
                        line_absorber.number_densities_cm3[sublayer_write_index] = 0.0;
                        _ = line_absorber_index;
                        continue;
                    }
                    const absorber_mixing_ratio = speciesMixingRatioAtPressure(
                        scene,
                        line_absorber.species,
                        active_absorber.volume_mixing_ratio_profile_ppmv,
                        pressure,
                        if (line_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
                    ) orelse return error.InvalidRequest;
                    const line_absorber_density_cm3 = density * absorber_mixing_ratio;
                    line_absorber.number_densities_cm3[sublayer_write_index] = line_absorber_density_cm3;
                    absorber_density_cm3 += line_absorber_density_cm3;
                    if (line_absorber_density_cm3 <= 0.0) continue;

                    var evaluation = if (line_absorber.strong_line_states) |states| blk_eval: {
                        states[sublayer_write_index] = (try line_absorber.line_list.prepareStrongLineState(
                            allocator,
                            temperature,
                            pressure,
                        )).?;
                        line_absorber.strong_line_state_initialized.?[sublayer_write_index] = true;
                        line_absorber.strong_line_state_count += 1;
                        const prepared_evaluation = line_absorber.line_list.evaluateAtPrepared(
                            midpoint_nm,
                            temperature,
                            pressure,
                            &states[sublayer_write_index],
                        );
                        break :blk_eval prepared_evaluation;
                    } else line_absorber.line_list.evaluateAt(midpoint_nm, temperature, pressure);

                    const upper = line_absorber.line_list.evaluateAt(midpoint_nm, temperature + delta_t, pressure);
                    const lower = line_absorber.line_list.evaluateAt(
                        midpoint_nm,
                        @max(temperature - delta_t, 150.0),
                        pressure,
                    );
                    evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                        (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t);

                    spectroscopy_weight += line_absorber_density_cm3;
                    weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * line_absorber_density_cm3;
                    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * line_absorber_density_cm3;

                    const line_absorber_column_density_cm2 = line_absorber_density_cm3 * layer_span_km * centimeters_per_kilometer * sublayer_weight;
                    line_absorber.column_density_factor += line_absorber_column_density_cm2;
                    _ = line_absorber_index;
                }

                if (spectroscopy_weight <= 0.0) {
                    break :blk ReferenceData.SpectroscopyEvaluation{
                        .line_sigma_cm2_per_molecule = 0.0,
                        .line_mixing_sigma_cm2_per_molecule = 0.0,
                        .total_sigma_cm2_per_molecule = 0.0,
                        .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                    };
                }

                weighted.weak_line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.strong_line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.line_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.line_mixing_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.total_sigma_cm2_per_molecule /= spectroscopy_weight;
                weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= spectroscopy_weight;
                break :blk weighted;
            } else blk: {
                const absorber_mixing_ratio = if (active_line_species) |species|
                    speciesMixingRatioAtPressure(
                        scene,
                        species,
                        if (single_active_line_absorber) |line_absorber| line_absorber.volume_mixing_ratio_profile_ppmv else &.{},
                        pressure,
                        if (species == .o2) oxygen_volume_mixing_ratio else null,
                    ) orelse return error.InvalidRequest
                else
                    oxygen_volume_mixing_ratio;
                absorber_density_cm3 = density * absorber_mixing_ratio;

                if (operational_o2_lut.enabled()) {
                    const sigma = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure);
                    break :blk ReferenceData.SpectroscopyEvaluation{
                        .weak_line_sigma_cm2_per_molecule = sigma,
                        .strong_line_sigma_cm2_per_molecule = 0.0,
                        .line_sigma_cm2_per_molecule = sigma,
                        .line_mixing_sigma_cm2_per_molecule = 0.0,
                        .total_sigma_cm2_per_molecule = sigma,
                        .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure),
                    };
                }

                if (owned_lines) |line_list| {
                    if (strong_line_states) |states| {
                        const delta_t = 0.5;
                        states[sublayer_write_index] = (try line_list.prepareStrongLineState(
                            allocator,
                            temperature,
                            pressure,
                        )).?;
                        strong_line_state_count += 1;

                        var evaluation = line_list.evaluateAtPrepared(
                            midpoint_nm,
                            temperature,
                            pressure,
                            &states[sublayer_write_index],
                        );
                        const upper = line_list.evaluateAt(midpoint_nm, temperature + delta_t, pressure);
                        const lower = line_list.evaluateAt(
                            midpoint_nm,
                            @max(temperature - delta_t, 150.0),
                            pressure,
                        );
                        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k =
                            (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t);
                        break :blk evaluation;
                    }
                    break :blk line_list.evaluateAt(midpoint_nm, temperature, pressure);
                }

                break :blk ReferenceData.SpectroscopyEvaluation{
                    .weak_line_sigma_cm2_per_molecule = 0.0,
                    .strong_line_sigma_cm2_per_molecule = 0.0,
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };
            };
            const o2_density_cm3 = density * oxygen_mixing_ratio;
            const continuum_density_cm3 = if (owned_line_absorbers.len != 0) blk: {
                const owner_species = continuum_owner_species orelse break :blk absorber_density_cm3;
                if (operational_o2_lut.enabled() and owner_species == .o2) break :blk o2_density_cm3;
                for (owned_line_absorbers) |line_absorber| {
                    if (line_absorber.species != owner_species) continue;
                    break :blk line_absorber.number_densities_cm3[sublayer_write_index];
                }
                break :blk absorber_density_cm3;
            } else absorber_density_cm3;
            const sublayer_path_length_cm = layer_span_km * centimeters_per_kilometer * sublayer_weight;
            const gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
            const continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;
            const molecular_gas_optical_depth =
                midpoint_continuum_sigma * continuum_column_density_cm2 +
                spectroscopy_eval.total_sigma_cm2_per_molecule * gas_column_density_cm2;
            const cia_sigma_cm5_per_molecule2 = if (operational_o2o2_lut.enabled())
                operational_o2o2_lut.sigmaAt(midpoint_nm, temperature, pressure)
            else if (collision_induced_absorption) |cia_table|
                cia_table.sigmaAt(midpoint_nm, temperature)
            else
                0.0;
            const d_cia_sigma_d_temperature = if (operational_o2o2_lut.enabled())
                operational_o2o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure)
            else if (collision_induced_absorption) |cia_table|
                cia_table.dSigmaDTemperatureAt(midpoint_nm, temperature)
            else
                0.0;
            const cia_optical_depth = cia_sigma_cm5_per_molecule2 * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const gas_scattering_optical_depth =
                Rayleigh.crossSectionCm2(midpoint_nm) * density * sublayer_path_length_cm;
            const gas_absorption_optical_depth = molecular_gas_optical_depth;
            const gas_extinction_optical_depth = gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
            const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            const d_gas_optical_depth_d_temperature =
                spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * gas_column_density_cm2;
            const aerosol_optical_depth = aerosol_sublayer_distribution[sublayer_write_index] * aerosol_extinction_scale;
            const cloud_optical_depth = cloud_sublayer_distribution[sublayer_write_index] * cloud_extinction_scale;
            const aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_single_scatter_albedo;
            const cloud_scattering_optical_depth = cloud_optical_depth * cloud_single_scatter_albedo;
            const combined_phase_coefficients = PhaseFunctions.combinePhaseCoefficients(
                gas_scattering_optical_depth,
                aerosol_scattering_optical_depth,
                cloud_scattering_optical_depth,
                aerosol_phase_coefficients,
                cloud_phase_coefficients,
            );

            sublayers[sublayer_write_index] = .{
                .parent_layer_index = @intCast(index),
                .sublayer_index = @intCast(sublayer_index),
                .global_sublayer_index = @intCast(sublayer_write_index),
                .altitude_km = altitude_km,
                .pressure_hpa = pressure,
                .temperature_k = temperature,
                .number_density_cm3 = density,
                .oxygen_number_density_cm3 = density * oxygen_mixing_ratio,
                .absorber_number_density_cm3 = absorber_density_cm3,
                .path_length_cm = sublayer_path_length_cm,
                .continuum_cross_section_cm2_per_molecule = midpoint_continuum_sigma,
                .line_cross_section_cm2_per_molecule = spectroscopy_eval.line_sigma_cm2_per_molecule,
                .line_mixing_cross_section_cm2_per_molecule = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
                .cia_sigma_cm5_per_molecule2 = cia_sigma_cm5_per_molecule2,
                .cia_optical_depth = cia_optical_depth,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k,
                .gas_absorption_optical_depth = gas_absorption_optical_depth,
                .gas_scattering_optical_depth = gas_scattering_optical_depth,
                .gas_extinction_optical_depth = gas_extinction_optical_depth,
                .d_gas_optical_depth_d_temperature = d_gas_optical_depth_d_temperature,
                .d_cia_optical_depth_d_temperature = d_cia_optical_depth_d_temperature,
                .aerosol_optical_depth = aerosol_optical_depth,
                .cloud_optical_depth = cloud_optical_depth,
                .aerosol_single_scatter_albedo = aerosol_single_scatter_albedo,
                .cloud_single_scatter_albedo = cloud_single_scatter_albedo,
                .aerosol_phase_coefficients = aerosol_phase_coefficients,
                .cloud_phase_coefficients = cloud_phase_coefficients,
                .combined_phase_coefficients = combined_phase_coefficients,
            };
            layer_density_weight += density * sublayer_weight;
            layer_density_sum += density * sublayer_weight;
            layer_temperature_sum += temperature * density * sublayer_weight;
            layer_pressure_sum += pressure * density * sublayer_weight;
            layer_line_sigma_sum += spectroscopy_eval.line_sigma_cm2_per_molecule;
            layer_line_mixing_sum += spectroscopy_eval.line_mixing_sigma_cm2_per_molecule;
            layer_d_cross_section_sum += spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k;
            layer_gas_optical_depth += gas_absorption_optical_depth + gas_scattering_optical_depth;
            layer_gas_scattering_optical_depth += gas_scattering_optical_depth;
            layer_cia_optical_depth += cia_optical_depth;
            layer_aerosol_optical_depth += aerosol_optical_depth;
            layer_cloud_optical_depth += cloud_optical_depth;
            air_column_density_factor += density * sublayer_path_length_cm;
            oxygen_column_density_factor += o2_density_cm3 * sublayer_path_length_cm;
            column_density_factor += gas_column_density_cm2;
            cia_pair_path_factor_cm5 += o2_density_cm3 * o2_density_cm3 * sublayer_path_length_cm;
            total_d_optical_depth_d_temperature += d_gas_optical_depth_d_temperature + d_cia_optical_depth_d_temperature;

            sublayer_write_index += 1;
        }

        const density = layer_density_sum;
        const temperature = if (layer_density_weight == 0.0) 0.0 else layer_temperature_sum / layer_density_weight;
        const pressure = if (layer_density_weight == 0.0) 0.0 else layer_pressure_sum / layer_density_weight;
        const gas_optical_depth = layer_gas_optical_depth;
        const aerosol_optical_depth = layer_aerosol_optical_depth;
        const cloud_optical_depth = layer_cloud_optical_depth;
        const optical_depth = gas_optical_depth + layer_cia_optical_depth + aerosol_optical_depth + cloud_optical_depth;
        const aerosol_scattering = aerosol_optical_depth * aerosol_single_scatter_albedo;
        const cloud_scattering = cloud_optical_depth * cloud_single_scatter_albedo;
        const gas_scattering = layer_gas_scattering_optical_depth;
        const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
        const absorption = @max(optical_depth - scattering, 1e-9);
        const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
        const depolarization = PhaseFunctions.computeLayerDepolarization(scene, gas_scattering, aerosol_scattering, cloud_scattering);
        total_optical_depth += optical_depth;
        total_temperature_weighted += temperature * density;
        total_pressure_weighted += pressure * density;
        total_weight += density;
        total_gas_optical_depth += gas_optical_depth;
        total_cia_optical_depth += layer_cia_optical_depth;
        total_aerosol_optical_depth += aerosol_optical_depth;
        total_cloud_optical_depth += cloud_optical_depth;
        total_scattering_optical_depth += scattering;
        depolarization_weighted += depolarization * optical_depth;

        layer.* = .{
            .layer_index = @intCast(index),
            .sublayer_start_index = @intCast(index * sublayer_divisions),
            .sublayer_count = sublayer_divisions,
            .altitude_km = layer_center_altitude_km,
            .pressure_hpa = pressure,
            .temperature_k = temperature,
            .number_density_cm3 = density,
            .continuum_cross_section_cm2_per_molecule = mean_sigma,
            .line_cross_section_cm2_per_molecule = layer_line_sigma_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .line_mixing_cross_section_cm2_per_molecule = layer_line_mixing_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .cia_optical_depth = layer_cia_optical_depth,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_d_cross_section_sum / @as(f64, @floatFromInt(sublayer_divisions)),
            .gas_optical_depth = gas_optical_depth,
            .gas_scattering_optical_depth = gas_scattering,
            .aerosol_optical_depth = aerosol_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .layer_single_scatter_albedo = layer_single_scatter_albedo,
            .depolarization_factor = depolarization,
            .optical_depth = optical_depth,
        };
    }

    const effective_temperature = if (total_weight == 0.0) 0.0 else total_temperature_weighted / total_weight;
    const effective_pressure = if (total_weight == 0.0) 0.0 else total_pressure_weighted / total_weight;
    const line_means = if (owned_line_absorbers.len != 0 or operational_o2_lut.enabled()) blk: {
        var line_mean_weight: f64 = 0.0;
        var weighted: BandMeans.LineBandMeans = .{};
        if (operational_o2_lut.enabled() and oxygen_column_density_factor > 0.0) {
            const operational_mean = BandMeans.computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective_temperature,
                effective_pressure,
            );
            line_mean_weight += oxygen_column_density_factor;
            weighted.line_mean_cross_section_cm2_per_molecule += operational_mean * oxygen_column_density_factor;
        }
        for (owned_line_absorbers) |*line_absorber| {
            if (operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = line_absorber.column_density_factor;
            if (weight <= 0.0) continue;
            const means = try BandMeans.computeBandLineMeans(
                allocator,
                scene,
                &line_absorber.line_list,
                effective_temperature,
                effective_pressure,
            );
            line_mean_weight += weight;
            weighted.line_mean_cross_section_cm2_per_molecule +=
                means.line_mean_cross_section_cm2_per_molecule * weight;
            weighted.line_mixing_mean_cross_section_cm2_per_molecule +=
                means.line_mixing_mean_cross_section_cm2_per_molecule * weight;
        }
        if (line_mean_weight > 0.0) {
            weighted.line_mean_cross_section_cm2_per_molecule /= line_mean_weight;
            weighted.line_mixing_mean_cross_section_cm2_per_molecule /= line_mean_weight;
        }
        break :blk weighted;
    } else if (owned_lines) |*line_list|
        try BandMeans.computeBandLineMeans(allocator, scene, line_list, effective_temperature, effective_pressure)
    else
        BandMeans.LineBandMeans{};
    const cia_mean_sigma = if (operational_o2o2_lut.enabled())
        BandMeans.computeOperationalBandMean(
            scene,
            operational_o2o2_lut,
            @max(effective_temperature, 150.0),
            effective_pressure,
        )
    else if (collision_induced_absorption) |cia_table|
        cia_table.meanSigmaInRange(
            scene.spectral_grid.start_nm,
            scene.spectral_grid.end_nm,
            @max(effective_temperature, 150.0),
        )
    else
        0.0;

    return .{
        .layers = layers,
        .sublayers = sublayers,
        .strong_line_states = strong_line_states,
        .continuum_points = continuum_points,
        .collision_induced_absorption = owned_cia,
        .spectroscopy_lines = owned_lines,
        .line_absorbers = owned_line_absorbers,
        .continuum_owner_species = continuum_owner_species,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .mean_cross_section_cm2_per_molecule = mean_sigma + line_means.line_mean_cross_section_cm2_per_molecule + line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .cia_mean_cross_section_cm5_per_molecule2 = cia_mean_sigma,
        .effective_air_mass_factor = air_mass_factor,
        .effective_single_scatter_albedo = if (total_optical_depth == 0.0)
            base_single_scatter_albedo
        else
            total_scattering_optical_depth / total_optical_depth,
        .effective_temperature_k = effective_temperature,
        .effective_pressure_hpa = effective_pressure,
        .air_column_density_factor = air_column_density_factor,
        .oxygen_column_density_factor = oxygen_column_density_factor,
        .column_density_factor = column_density_factor,
        .cia_pair_path_factor_cm5 = cia_pair_path_factor_cm5,
        .aerosol_reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .aerosol_angstrom_exponent = scene.aerosol.angstrom_exponent,
        .cloud_reference_wavelength_nm = scene.cloud.reference_wavelength_nm,
        .cloud_angstrom_exponent = scene.cloud.angstrom_exponent,
        .gas_optical_depth = total_gas_optical_depth,
        .cia_optical_depth = total_cia_optical_depth,
        .aerosol_optical_depth = total_aerosol_optical_depth,
        .cloud_optical_depth = total_cloud_optical_depth,
        .d_optical_depth_d_temperature = total_d_optical_depth_d_temperature,
        .depolarization_factor = if (total_optical_depth == 0.0) 0.0 else depolarization_weighted / total_optical_depth,
        .total_optical_depth = total_optical_depth,
    };
}

fn collectActiveLineAbsorbers(allocator: Allocator, scene: *const Scene) ![]ActiveLineAbsorber {
    var active = std.ArrayList(ActiveLineAbsorber).empty;
    defer active.deinit(allocator);

    for (scene.absorbers.items) |absorber| {
        const species = resolvedAbsorberSpecies(absorber) orelse continue;
        if (!species.isLineAbsorbing()) continue;
        if (absorber.spectroscopy.mode != .line_by_line) continue;
        try active.append(allocator, .{
            .species = species,
            .controls = absorber.spectroscopy.line_gas_controls,
            .volume_mixing_ratio_profile_ppmv = absorber.volume_mixing_ratio_profile_ppmv,
        });
    }
    return active.toOwnedSlice(allocator);
}

fn resolvedAbsorberSpecies(absorber: AbsorberModel.Absorber) ?AbsorberModel.AbsorberSpecies {
    if (absorber.resolved_species) |species| return species;
    if (std.meta.stringToEnum(AbsorberModel.AbsorberSpecies, absorber.species)) |species| return species;
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2-o2")) return .o2_o2;
    return null;
}

fn resolveActiveLineSpecies(
    active_line_absorber: ?ActiveLineAbsorber,
    line_list: ?ReferenceData.SpectroscopyLineList,
    operational_o2_lut: OperationalCrossSectionLut,
) ?AbsorberModel.AbsorberSpecies {
    if (active_line_absorber) |line_absorber| return line_absorber.species;
    if (operational_o2_lut.enabled()) return .o2;
    const spectroscopy_lines = line_list orelse return null;
    if (spectroscopy_lines.runtime_controls.gas_index) |gas_index| {
        return speciesForHitranIndex(gas_index);
    }
    return inferLineSpecies(spectroscopy_lines.lines);
}

fn resolveContinuumOwnerSpecies(
    active_line_species: ?AbsorberModel.AbsorberSpecies,
    line_absorbers: []const PreparedLineAbsorber,
    operational_o2_lut: OperationalCrossSectionLut,
) ?AbsorberModel.AbsorberSpecies {
    if (operational_o2_lut.enabled()) return .o2;
    if (active_line_species) |species| return species;
    if (line_absorbers.len == 1) return line_absorbers[0].species;
    for (line_absorbers) |line_absorber| {
        if (line_absorber.species == .o2) return .o2;
    }
    return null;
}

fn inferLineSpecies(lines: []const ReferenceData.SpectroscopyLine) ?AbsorberModel.AbsorberSpecies {
    if (lines.len == 0) return null;
    const first_gas_index = lines[0].gas_index;
    if (first_gas_index == 0) return null;
    for (lines[1..]) |line| {
        if (line.gas_index != first_gas_index) return null;
    }
    return speciesForHitranIndex(first_gas_index);
}

fn speciesForHitranIndex(gas_index: u16) ?AbsorberModel.AbsorberSpecies {
    return switch (gas_index) {
        1 => .h2o,
        2 => .co2,
        5 => .co,
        6 => .ch4,
        7 => .o2,
        11 => .nh3,
        else => null,
    };
}

fn speciesMixingRatioAtPressure(
    scene: *const Scene,
    species: AbsorberModel.AbsorberSpecies,
    explicit_profile_ppmv: []const [2]f64,
    pressure_hpa: f64,
    default_fraction: ?f64,
) ?f64 {
    const profile_ppmv = if (explicit_profile_ppmv.len != 0)
        explicit_profile_ppmv
    else if (findAbsorberBySpecies(scene, species)) |absorber|
        absorber.volume_mixing_ratio_profile_ppmv
    else
        &.{};
    if (profile_ppmv.len != 0) {
        return interpolateMixingRatioProfileFraction(profile_ppmv, pressure_hpa);
    }
    return default_fraction;
}

fn findAbsorberBySpecies(
    scene: *const Scene,
    species: AbsorberModel.AbsorberSpecies,
) ?*const AbsorberModel.Absorber {
    for (scene.absorbers.items) |*absorber| {
        if (resolvedAbsorberSpecies(absorber.*) == species) return absorber;
    }
    return null;
}

fn interpolateMixingRatioProfileFraction(profile_ppmv: []const [2]f64, pressure_hpa: f64) f64 {
    if (profile_ppmv.len == 0) return 0.0;
    const safe_pressure_hpa = @max(pressure_hpa, 0.0);
    if (profile_ppmv.len == 1) return ppmvToFraction(profile_ppmv[0][1]);

    const first_pressure_hpa = profile_ppmv[0][0];
    const last_pressure_hpa = profile_ppmv[profile_ppmv.len - 1][0];
    const descending = first_pressure_hpa >= last_pressure_hpa;
    if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
        (!descending and safe_pressure_hpa <= first_pressure_hpa))
    {
        return ppmvToFraction(profile_ppmv[0][1]);
    }
    if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
        (!descending and safe_pressure_hpa >= last_pressure_hpa))
    {
        return ppmvToFraction(profile_ppmv[profile_ppmv.len - 1][1]);
    }

    for (profile_ppmv[0 .. profile_ppmv.len - 1], profile_ppmv[1..]) |left, right| {
        const in_segment = if (descending)
            safe_pressure_hpa <= left[0] and safe_pressure_hpa >= right[0]
        else
            safe_pressure_hpa >= left[0] and safe_pressure_hpa <= right[0];
        if (!in_segment) continue;

        const span = right[0] - left[0];
        if (span == 0.0) return ppmvToFraction(right[1]);
        const weight = (safe_pressure_hpa - left[0]) / span;
        return ppmvToFraction(left[1] + weight * (right[1] - left[1]));
    }

    return ppmvToFraction(profile_ppmv[profile_ppmv.len - 1][1]);
}

fn ppmvToFraction(value_ppmv: f64) f64 {
    return @max(value_ppmv, 0.0) * 1.0e-6;
}

test "optical preparation derives deterministic layer optical depths from typed assets" {
    const scene: Scene = .{
        .id = "optical-scene",
        .atmosphere = .{
            .layer_count = 4,
            .has_clouds = true,
            .has_aerosols = false,
        },
        .geometry = .{
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 10.0,
            .relative_azimuth_deg = 30.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var profile = ReferenceData.ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
            .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = ReferenceData.CrossSectionTable{
        .points = try std.testing.allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.17e-19 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);
    const spectroscopy = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
        .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    });
    var line_list = ReferenceData.SpectroscopyLineList{ .lines = spectroscopy };
    defer line_list.deinit(std.testing.allocator);

    var lut = ReferenceData.AirmassFactorLut{
        .points = try std.testing.allocator.dupe(ReferenceData.AirmassFactorPoint, &.{
            .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
        }),
    };
    defer lut.deinit(std.testing.allocator);

    var prepared = try prepareWithSpectroscopy(std.testing.allocator, &scene, &profile, &cross_sections, &line_list, &lut);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), prepared.layers.len);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.layers[0].optical_depth > prepared.layers[3].optical_depth);
    try std.testing.expect(prepared.column_density_factor > 1.0e24);
    try std.testing.expectEqual(@as(f64, 0.0), prepared.line_mixing_mean_cross_section_cm2_per_molecule);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);

    const input = prepared.toForwardInput(&scene);
    try std.testing.expect(input.optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), input.air_mass_factor, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), input.spectral_weight, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(465.0));

    try std.testing.expect(prepared.sublayers != null);
    try std.testing.expectEqual(prepared.sublayers.?.len, prepared.transportLayerCount());
    var transport_layers: [12]transport_common.LayerInput = undefined;
    _ = prepared.fillForwardLayersAtWavelength(&scene, 434.6, &transport_layers);
    try std.testing.expect(transport_layers[0].optical_depth > 0.0);
    try std.testing.expect(transport_layers[11].optical_depth > 0.0);
}

fn testPreparedSublayer(
    parent_layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64,
) PreparedSublayer {
    return .{
        .parent_layer_index = parent_layer_index,
        .sublayer_index = sublayer_index,
        .global_sublayer_index = global_sublayer_index,
        .altitude_km = altitude_km,
        .pressure_hpa = pressure_hpa,
        .temperature_k = temperature_k,
        .number_density_cm3 = number_density_cm3,
        .oxygen_number_density_cm3 = oxygen_number_density_cm3,
        .absorber_number_density_cm3 = absorber_number_density_cm3,
        .path_length_cm = 1.0,
        .continuum_cross_section_cm2_per_molecule = 0.0,
        .line_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_cross_section_cm2_per_molecule = 0.0,
        .cia_sigma_cm5_per_molecule2 = 0.0,
        .cia_optical_depth = 0.0,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
        .gas_absorption_optical_depth = 0.0,
        .gas_scattering_optical_depth = 0.0,
        .gas_extinction_optical_depth = 0.0,
        .d_gas_optical_depth_d_temperature = 0.0,
        .d_cia_optical_depth_d_temperature = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .aerosol_single_scatter_albedo = 0.0,
        .cloud_single_scatter_albedo = 0.0,
        .aerosol_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        .combined_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
    };
}

test "prepared scalar helpers use global sublayer slots across later layers" {
    const sublayers = [_]PreparedSublayer{
        testPreparedSublayer(0, 0, 0, 0.5, 900.0, 285.0, 2.0e19, 4.0e18, 2.0e15),
        testPreparedSublayer(0, 1, 1, 1.5, 820.0, 280.0, 1.8e19, 3.6e18, 4.0e15),
        testPreparedSublayer(1, 0, 2, 2.5, 700.0, 270.0, 1.4e19, 2.8e18, 6.0e15),
        testPreparedSublayer(1, 1, 3, 3.5, 620.0, 265.0, 1.1e19, 2.2e18, 8.0e15),
    };
    const values = [_]f64{ 2.0, 4.0, 6.0, 8.0 };

    try std.testing.expectApproxEqAbs(
        @as(f64, 6.0),
        PreparedOpticalState.preparedScalarForSublayer(&values, sublayers[2]),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 7.0),
        PreparedOpticalState.interpolatePreparedScalarAtAltitude(&sublayers, &values, 3.0),
        1.0e-12,
    );
}

test "collect active line absorbers resolves public species strings" {
    const scene: Scene = .{
        .id = "string-species-line-absorber",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 9,
        },
        .absorbers = .{
            .items = &.{
                AbsorberModel.Absorber{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                            .threshold_line_sim = 1.0e-23,
                        },
                    },
                },
            },
        },
    };

    const active = try collectActiveLineAbsorbers(std.testing.allocator, &scene);
    defer std.testing.allocator.free(active);

    try std.testing.expectEqual(@as(usize, 1), active.len);
    try std.testing.expectEqual(AbsorberModel.AbsorberSpecies.o2, active[0].species);
    try std.testing.expectEqual(@as(f64, 1.0e-23), active[0].controls.threshold_line_sim.?);
}
