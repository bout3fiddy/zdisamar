const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const transport_common = @import("../transport/common.zig");

const Allocator = std.mem.Allocator;

pub const PreparedLayer = struct {
    layer_index: u32,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    layer_single_scatter_albedo: f64,
    depolarization_factor: f64,
    optical_depth: f64,
};

pub const PreparedOpticalState = struct {
    layers: []PreparedLayer,
    continuum_points: []ReferenceData.CrossSectionPoint,
    spectroscopy_lines: ?[]ReferenceData.SpectroscopyLine,
    mean_cross_section_cm2_per_molecule: f64,
    line_mean_cross_section_cm2_per_molecule: f64,
    line_mixing_mean_cross_section_cm2_per_molecule: f64,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    column_density_factor: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    cloud_reference_wavelength_nm: f64,
    cloud_angstrom_exponent: f64,
    gas_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        allocator.free(self.layers);
        allocator.free(self.continuum_points);
        if (self.spectroscopy_lines) |lines| allocator.free(lines);
        self.* = undefined;
    }

    pub fn toForwardInput(self: PreparedOpticalState, scene: Scene) transport_common.ForwardInput {
        return self.toForwardInputAtWavelength(
            scene,
            (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        );
    }

    pub fn toForwardInputAtWavelength(
        self: PreparedOpticalState,
        scene: Scene,
        wavelength_nm: f64,
    ) transport_common.ForwardInput {
        const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
        const spectral_weight = if (scene.spectral_grid.sample_count == 0) 1.0 else span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count));
        return .{
            .wavelength_nm = wavelength_nm,
            .spectral_weight = @max(spectral_weight, 1.0),
            .air_mass_factor = self.effective_air_mass_factor,
            .optical_depth = self.totalOpticalDepthAtWavelength(wavelength_nm),
            .single_scatter_albedo = self.effective_single_scatter_albedo,
        };
    }

    pub fn totalCrossSectionAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        const continuum = (ReferenceData.CrossSectionTable{
            .points = self.continuum_points,
        }).interpolateSigma(wavelength_nm);
        const line_sigma = if (self.spectroscopy_lines) |lines|
            (ReferenceData.SpectroscopyLineList{ .lines = lines }).evaluateAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else
            0.0;
        return continuum + line_sigma;
    }

    pub fn gasOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.totalCrossSectionAtWavelength(wavelength_nm) * self.column_density_factor;
    }

    pub fn aerosolOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return scaleOpticalDepth(
            self.aerosol_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            wavelength_nm,
        );
    }

    pub fn cloudOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return scaleOpticalDepth(
            self.cloud_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            wavelength_nm,
        );
    }

    pub fn totalOpticalDepthAtWavelength(self: PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.gasOpticalDepthAtWavelength(wavelength_nm) +
            self.aerosolOpticalDepthAtWavelength(wavelength_nm) +
            self.cloudOpticalDepthAtWavelength(wavelength_nm);
    }
};

pub fn prepare(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    lut: ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithSpectroscopy(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        lut,
    );
}

pub fn prepareWithSpectroscopy(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList,
    lut: ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    try scene.validate();

    const layer_count = @max(scene.atmosphere.layer_count, @as(u32, 1));
    const layers = try allocator.alloc(PreparedLayer, layer_count);
    errdefer allocator.free(layers);
    const continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, cross_sections.points);
    errdefer allocator.free(continuum_points);
    const owned_lines = if (spectroscopy_lines) |line_list|
        try allocator.dupe(ReferenceData.SpectroscopyLine, line_list.lines)
    else
        null;
    errdefer if (owned_lines) |lines| allocator.free(lines);

    const midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5;
    const mean_sigma = cross_sections.meanSigmaInRange(
        scene.spectral_grid.start_nm,
        scene.spectral_grid.end_nm,
    );
    const air_mass_factor = lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const base_single_scatter_albedo = computeSingleScatterAlbedo(scene);

    var total_optical_depth: f64 = 0.0;
    var total_temperature_weighted: f64 = 0.0;
    var total_pressure_weighted: f64 = 0.0;
    var total_weight: f64 = 0.0;
    var column_density_factor: f64 = 0.0;
    var total_gas_optical_depth: f64 = 0.0;
    var total_aerosol_optical_depth: f64 = 0.0;
    var total_cloud_optical_depth: f64 = 0.0;
    var total_d_optical_depth_d_temperature: f64 = 0.0;
    var depolarization_weighted: f64 = 0.0;

    const aerosol_distribution = try buildAerosolDistribution(allocator, scene, profile, layer_count);
    defer allocator.free(aerosol_distribution);
    const cloud_distribution = try buildCloudDistribution(allocator, scene, profile, layer_count);
    defer allocator.free(cloud_distribution);

    for (layers, 0..) |*layer, index| {
        const layer_fraction = (@as(f64, @floatFromInt(index)) + 0.5) / @as(f64, @floatFromInt(layer_count));
        const altitude_km = altitude_span * layer_fraction;
        const density = profile.interpolateDensity(altitude_km);
        const pressure = profile.interpolatePressure(altitude_km);
        const temperature = profile.interpolateTemperature(altitude_km);
        const spectroscopy_eval = if (spectroscopy_lines) |line_list|
            line_list.evaluateAt(midpoint_nm, temperature, pressure)
        else
            ReferenceData.SpectroscopyEvaluation{
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        const gas_optical_depth = (mean_sigma + spectroscopy_eval.total_sigma_cm2_per_molecule) * density * air_mass_factor * 1.0e-18;
        const aerosol_optical_depth = aerosol_distribution[index];
        const cloud_optical_depth = cloud_distribution[index];
        const optical_depth = gas_optical_depth + aerosol_optical_depth + cloud_optical_depth;
        const aerosol_scattering = aerosol_optical_depth * scene.aerosol.single_scatter_albedo;
        const cloud_scattering = cloud_optical_depth * scene.cloud.single_scatter_albedo;
        const gas_scattering = gas_optical_depth * 0.08;
        const scattering = aerosol_scattering + cloud_scattering + gas_scattering;
        const absorption = @max(optical_depth - scattering, 1e-9);
        const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
        const depolarization = computeLayerDepolarization(scene, aerosol_optical_depth, cloud_optical_depth, gas_optical_depth);
        total_optical_depth += optical_depth;
        total_temperature_weighted += temperature * density;
        total_pressure_weighted += pressure * density;
        total_weight += density;
        column_density_factor += density * air_mass_factor * 1.0e-18;
        total_gas_optical_depth += gas_optical_depth;
        total_aerosol_optical_depth += aerosol_optical_depth;
        total_cloud_optical_depth += cloud_optical_depth;
        total_d_optical_depth_d_temperature += spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k * density * air_mass_factor * 1.0e-18;
        depolarization_weighted += depolarization * optical_depth;

        layer.* = .{
            .layer_index = @intCast(index),
            .altitude_km = altitude_km,
            .pressure_hpa = pressure,
            .temperature_k = temperature,
            .number_density_cm3 = density,
            .continuum_cross_section_cm2_per_molecule = mean_sigma,
            .line_cross_section_cm2_per_molecule = spectroscopy_eval.line_sigma_cm2_per_molecule,
            .line_mixing_cross_section_cm2_per_molecule = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k,
            .gas_optical_depth = gas_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .layer_single_scatter_albedo = layer_single_scatter_albedo,
            .depolarization_factor = depolarization,
            .optical_depth = optical_depth,
        };
    }

    const effective_temperature = if (total_weight == 0.0) 0.0 else total_temperature_weighted / total_weight;
    const effective_pressure = if (total_weight == 0.0) 0.0 else total_pressure_weighted / total_weight;
    const line_means = if (spectroscopy_lines) |line_list|
        computeBandLineMeans(scene, line_list, effective_temperature, effective_pressure)
    else
        LineBandMeans{};

    return .{
        .layers = layers,
        .continuum_points = continuum_points,
        .spectroscopy_lines = owned_lines,
        .mean_cross_section_cm2_per_molecule = mean_sigma + line_means.line_mean_cross_section_cm2_per_molecule + line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .line_mean_cross_section_cm2_per_molecule = line_means.line_mean_cross_section_cm2_per_molecule,
        .line_mixing_mean_cross_section_cm2_per_molecule = line_means.line_mixing_mean_cross_section_cm2_per_molecule,
        .effective_air_mass_factor = air_mass_factor,
        .effective_single_scatter_albedo = base_single_scatter_albedo,
        .effective_temperature_k = effective_temperature,
        .effective_pressure_hpa = effective_pressure,
        .column_density_factor = column_density_factor,
        .aerosol_reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .aerosol_angstrom_exponent = scene.aerosol.angstrom_exponent,
        .cloud_reference_wavelength_nm = scene.cloud.reference_wavelength_nm,
        .cloud_angstrom_exponent = scene.cloud.angstrom_exponent,
        .gas_optical_depth = total_gas_optical_depth,
        .aerosol_optical_depth = total_aerosol_optical_depth,
        .cloud_optical_depth = total_cloud_optical_depth,
        .d_optical_depth_d_temperature = total_d_optical_depth_d_temperature,
        .depolarization_factor = if (total_optical_depth == 0.0) 0.0 else depolarization_weighted / total_optical_depth,
        .total_optical_depth = total_optical_depth,
    };
}

fn computeSingleScatterAlbedo(scene: Scene) f64 {
    const gas_ssa: f64 = 0.92;
    const aerosol_ssa = if (scene.atmosphere.has_aerosols) scene.aerosol.single_scatter_albedo else gas_ssa;
    const cloud_ssa = if (scene.atmosphere.has_clouds) scene.cloud.single_scatter_albedo else gas_ssa;
    const aerosol_weight: f64 = if (scene.atmosphere.has_aerosols) 0.20 else 0.0;
    const cloud_weight: f64 = if (scene.atmosphere.has_clouds) 0.30 else 0.0;
    const gas_weight: f64 = 1.0 - aerosol_weight - cloud_weight;
    return std.math.clamp(gas_weight * gas_ssa + aerosol_weight * aerosol_ssa + cloud_weight * cloud_ssa, 0.3, 0.999);
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

    var prepared = try prepareWithSpectroscopy(std.testing.allocator, scene, profile, cross_sections, line_list, lut);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), prepared.layers.len);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.layers[0].optical_depth > prepared.layers[3].optical_depth);
    try std.testing.expect(prepared.column_density_factor > 0.0);
    try std.testing.expect(prepared.line_mixing_mean_cross_section_cm2_per_molecule != 0.0);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);

    const input = prepared.toForwardInput(scene);
    try std.testing.expect(input.optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), input.air_mass_factor, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(420.0));
}

const LineBandMeans = struct {
    line_mean_cross_section_cm2_per_molecule: f64 = 0.0,
    line_mixing_mean_cross_section_cm2_per_molecule: f64 = 0.0,
};

fn computeBandLineMeans(
    scene: Scene,
    line_list: ReferenceData.SpectroscopyLineList,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) LineBandMeans {
    const sample_count = @max(scene.spectral_grid.sample_count, @as(u32, 1));
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const wavelength_step = if (sample_count <= 1) 0.0 else span_nm / @as(f64, @floatFromInt(sample_count - 1));

    var line_sum: f64 = 0.0;
    var line_mixing_sum: f64 = 0.0;
    for (0..sample_count) |index| {
        const wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * @as(f64, @floatFromInt(index));
        const evaluation = line_list.evaluateAt(
            wavelength_nm,
            @max(effective_temperature_k, 150.0),
            @max(effective_pressure_hpa, 1.0),
        );
        line_sum += evaluation.line_sigma_cm2_per_molecule;
        line_mixing_sum += evaluation.line_mixing_sigma_cm2_per_molecule;
    }

    return .{
        .line_mean_cross_section_cm2_per_molecule = line_sum / @as(f64, @floatFromInt(sample_count)),
        .line_mixing_mean_cross_section_cm2_per_molecule = line_mixing_sum / @as(f64, @floatFromInt(sample_count)),
    };
}

fn scaleOpticalDepth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) f64 {
    if (optical_depth == 0.0) return 0.0;
    const safe_wavelength = @max(wavelength_nm, 1.0);
    const safe_reference = @max(reference_wavelength_nm, 1.0);
    return optical_depth * std.math.pow(f64, safe_reference / safe_wavelength, angstrom_exponent);
}

fn buildAerosolDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
) ![]f64 {
    const weights = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(weights);

    if (!scene.atmosphere.has_aerosols or !scene.aerosol.enabled or scene.aerosol.optical_depth == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    for (weights, 0..) |*slot, index| {
        const layer_fraction = (@as(f64, @floatFromInt(index)) + 0.5) / @as(f64, @floatFromInt(layer_count));
        const altitude_km = altitude_span * layer_fraction;
        const delta = (altitude_km - scene.aerosol.layer_center_km) / scene.aerosol.layer_width_km;
        const weight = @exp(-0.5 * delta * delta);
        slot.* = weight;
        total_weight += weight;
    }
    if (total_weight == 0.0) total_weight = 1.0;
    for (weights) |*slot| slot.* = scene.aerosol.optical_depth * (slot.* / total_weight);
    return weights;
}

fn buildCloudDistribution(
    allocator: Allocator,
    scene: Scene,
    profile: ReferenceData.ClimatologyProfile,
    layer_count: u32,
) ![]f64 {
    const weights = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(weights);

    if (!scene.atmosphere.has_clouds or !scene.cloud.enabled or scene.cloud.optical_thickness == 0.0) {
        @memset(weights, 0.0);
        return weights;
    }

    var total_weight: f64 = 0.0;
    const altitude_span = @max(profile.maxAltitude(), 1.0);
    const cloud_center_km = scene.cloud.top_altitude_km - 0.5 * scene.cloud.thickness_km;
    for (weights, 0..) |*slot, index| {
        const layer_fraction = (@as(f64, @floatFromInt(index)) + 0.5) / @as(f64, @floatFromInt(layer_count));
        const altitude_km = altitude_span * layer_fraction;
        const delta = (altitude_km - cloud_center_km) / @max(scene.cloud.thickness_km * 0.5, 0.25);
        const weight = @exp(-0.5 * delta * delta);
        slot.* = weight;
        total_weight += weight;
    }
    if (total_weight == 0.0) total_weight = 1.0;
    for (weights) |*slot| slot.* = scene.cloud.optical_thickness * (slot.* / total_weight);
    return weights;
}

fn computeLayerDepolarization(scene: Scene, aerosol_tau: f64, cloud_tau: f64, gas_tau: f64) f64 {
    const total = gas_tau + aerosol_tau + cloud_tau;
    if (total == 0.0) return 0.0;
    const gas_fraction = gas_tau / total;
    const aerosol_fraction = aerosol_tau / total;
    const cloud_fraction = cloud_tau / total;
    return gas_fraction * 0.0279 +
        aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor)) +
        cloud_fraction * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor));
}
