const std = @import("std");
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
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
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
        if (self.strong_line_states) |states| {
            for (states) |*state| state.deinit(allocator);
            allocator.free(states);
        }
        allocator.free(self.continuum_points);
        if (self.collision_induced_absorption) |cia| {
            var owned_cia = cia;
            owned_cia.deinit(allocator);
        }
        if (self.spectroscopy_lines) |line_list| {
            var owned = line_list;
            owned.deinit(allocator);
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
        const line_sigma = if (self.operational_o2_lut.enabled())
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

    fn quadratureCarrierForNormalizedSupport(
        sublayers: []const PreparedSublayer,
        layer_inputs: []const transport_common.LayerInput,
        total_span_km: f64,
        normalized_support_start: f64,
        normalized_support_end: f64,
    ) PreparedQuadratureCarrier {
        const default: PreparedQuadratureCarrier = .{
            .ksca = 0.0,
            .phase_coefficients = [_]f64{ 1.0, 0.0, 0.0, 0.0 },
        };
        if (sublayers.len == 0 or layer_inputs.len != sublayers.len or total_span_km <= 0.0) return default;

        const support_start_km =
            std.math.clamp(normalized_support_start, 0.0, 1.0) * total_span_km;
        const support_end_km =
            std.math.clamp(normalized_support_end, 0.0, 1.0) * total_span_km;
        const support_span_km = support_end_km - support_start_km;
        if (support_span_km <= 0.0) return default;

        var cumulative_km: f64 = 0.0;
        var support_scattering_optical_depth: f64 = 0.0;
        var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;

        for (sublayers, layer_inputs) |sublayer, layer_input| {
            const span_km = @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            const next_cumulative_km = cumulative_km + span_km;
            const overlap_km =
                @min(support_end_km, next_cumulative_km) - @max(support_start_km, cumulative_km);
            if (overlap_km > 0.0 and span_km > 0.0) {
                const scattering_optical_depth = @max(layer_input.scattering_optical_depth, 0.0);
                const overlap_scattering_optical_depth = overlap_km * scattering_optical_depth / span_km;
                support_scattering_optical_depth += overlap_scattering_optical_depth;
                for (0..phase_coefficient_count) |index| {
                    phase_numerator[index] +=
                        overlap_scattering_optical_depth * layer_input.phase_coefficients[index];
                }
            }
            cumulative_km = next_cumulative_km;
        }

        if (support_scattering_optical_depth <= 0.0) return default;

        var phase_coefficients = [_]f64{0.0} ** phase_coefficient_count;
        for (0..phase_coefficient_count) |index| {
            phase_coefficients[index] =
                phase_numerator[index] / support_scattering_optical_depth;
        }
        phase_coefficients[0] = 1.0;

        return .{
            .ksca = support_scattering_optical_depth / support_span_km,
            .phase_coefficients = phase_coefficients,
        };
    }

    pub fn fillRtmQuadratureAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        _: f64,
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

            const active_count = count - 1;
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
            var normalized_support_start: f64 = 0.0;
            for (0..active_count) |node_index| {
                const level = start + 1 + node_index;
                const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
                const normalized_support_end = normalized_support_start + 0.5 * rule.weights[node_index];
                const carrier = quadratureCarrierForNormalizedSupport(
                    sublayers[start..stop],
                    layer_inputs[start..stop],
                    total_span_km,
                    normalized_support_start,
                    normalized_support_end,
                );
                rtm_levels[level].altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
                rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
                rtm_levels[level].ksca = carrier.ksca;
                rtm_levels[level].phase_coefficients = carrier.phase_coefficients;
                raw_scattering_sum += rtm_levels[level].weightedScattering();
                normalized_support_start = normalized_support_end;
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
    ) bool {
        const sublayers = self.sublayers orelse return false;
        if (attenuation_layers.len < sublayers.len or
            attenuation_samples.len < sublayers.len or
            level_sample_starts.len != solver_layer_count + 1)
        {
            return false;
        }

        _ = self.fillForwardLayersAtWavelength(scene, wavelength_nm, attenuation_layers[0..sublayers.len]);
        for (sublayers, attenuation_layers[0..sublayers.len], 0..) |sublayer, attenuation_layer, index| {
            attenuation_samples[index] = .{
                .altitude_km = sublayer.altitude_km,
                .thickness_km = @max(sublayer.path_length_cm / centimeters_per_kilometer, 0.0),
                .optical_depth = @max(attenuation_layer.optical_depth, 0.0),
            };
        }

        level_sample_starts[0] = 0;
        if (solver_layer_count == sublayers.len) {
            for (1..solver_layer_count) |ilevel| {
                level_sample_starts[ilevel] = ilevel;
            }
        } else if (solver_layer_count == self.layers.len) {
            for (1..solver_layer_count) |ilevel| {
                level_sample_starts[ilevel] = @intCast(self.layers[ilevel].sublayer_start_index);
            }
        } else {
            return false;
        }
        level_sample_starts[solver_layer_count] = sublayers.len;
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
            (self.column_density_factor / oxygen_volume_mixing_ratio);
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
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    ) EvaluatedLayer {
        var breakdown: OpticalDepthBreakdown = .{};
        var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
        const gas_phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
        const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };

        for (sublayers, 0..) |sublayer, sublayer_index| {
            const continuum_sigma = continuum_table.interpolateSigma(wavelength_nm);
            const spectroscopy_sigma = self.spectroscopySigmaAtWavelength(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
                if (strong_line_states) |states| &states[sublayer_index] else null,
            );
            const gas_column_density_cm2 = sublayer.oxygen_number_density_cm3 * sublayer.path_length_cm;
            const gas_absorption_optical_depth =
                (continuum_sigma + spectroscopy_sigma) *
                gas_column_density_cm2;
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
        if (self.operational_o2_lut.enabled()) {
            const sigma = self.operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
            return .{
                .weak_line_sigma_cm2_per_molecule = sigma,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = sigma,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = sigma,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = self.operational_o2_lut.dSigmaDTemperatureAt(
                    wavelength_nm,
                    temperature_k,
                    pressure_hpa,
                ),
            };
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
        if (self.operational_o2_lut.enabled()) {
            return self.operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.spectroscopy_lines) |line_list| {
            return line_list.sigmaAtPrepared(wavelength_nm, temperature_k, pressure_hpa, prepared_state);
        }
        return 0.0;
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
    if (owned_lines) |*line_list| {
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
    const strong_line_states = if (owned_lines) |line_list|
        if (!operational_o2_lut.enabled() and line_list.hasStrongLineSidecars())
            try allocator.alloc(ReferenceData.StrongLinePreparedState, @as(usize, layer_count) * @as(usize, sublayer_divisions))
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
            const spectroscopy_eval = if (operational_o2_lut.enabled())
                ReferenceData.SpectroscopyEvaluation{
                    .weak_line_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .strong_line_sigma_cm2_per_molecule = 0.0,
                    .line_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = operational_o2_lut.sigmaAt(midpoint_nm, temperature, pressure),
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = operational_o2_lut.dSigmaDTemperatureAt(midpoint_nm, temperature, pressure),
                }
            else if (owned_lines) |line_list|
                if (strong_line_states) |states| blk: {
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
                } else line_list.evaluateAt(midpoint_nm, temperature, pressure)
            else
                ReferenceData.SpectroscopyEvaluation{
                    .line_sigma_cm2_per_molecule = 0.0,
                    .line_mixing_sigma_cm2_per_molecule = 0.0,
                    .total_sigma_cm2_per_molecule = 0.0,
                    .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
                };
            const o2_density_cm3 = density * oxygen_volume_mixing_ratio;
            const sublayer_path_length_cm = layer_span_km * centimeters_per_kilometer * sublayer_weight;
            const gas_column_density_cm2 = o2_density_cm3 * sublayer_path_length_cm;
            const molecular_gas_optical_depth =
                (midpoint_continuum_sigma + spectroscopy_eval.total_sigma_cm2_per_molecule) *
                gas_column_density_cm2;
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
                .altitude_km = altitude_km,
                .pressure_hpa = pressure,
                .temperature_k = temperature,
                .number_density_cm3 = density,
                .oxygen_number_density_cm3 = o2_density_cm3,
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
    const line_means = if (operational_o2_lut.enabled())
        BandMeans.LineBandMeans{
            .line_mean_cross_section_cm2_per_molecule = BandMeans.computeOperationalBandMean(
                scene,
                operational_o2_lut,
                effective_temperature,
                effective_pressure,
            ),
            .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        }
    else if (owned_lines) |*line_list|
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
