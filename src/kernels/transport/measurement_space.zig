const std = @import("std");
const core_errors = @import("../../core/errors.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../optics/prepare.zig").PreparedOpticalState;
const grid = @import("../spectra/grid.zig");
const calibration = @import("../spectra/calibration.zig");
const convolution = @import("../spectra/convolution.zig");
const noise = @import("../spectra/noise.zig");
const common = @import("common.zig");
const dispatcher = @import("dispatcher.zig");

const Allocator = std.mem.Allocator;

pub const MeasurementSpaceSummary = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
    mean_noise_sigma: f64,
    mean_jacobian: ?f64 = null,
};

pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    jacobian: ?[]f64 = null,
    noise_sigma: ?[]f64 = null,
};

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

pub fn simulate(
    scene: Scene,
    route: common.Route,
    prepared: PreparedOpticalState,
    buffers: Buffers,
) Error!MeasurementSpaceSummary {
    try scene.validate();
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
    try validateBuffers(sample_count, buffers);

    const spectral_grid: grid.SpectralGrid = .{
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .sample_count = scene.spectral_grid.sample_count,
    };
    try spectral_grid.validate();

    const calibration_config = calibrationForScene(scene);
    const slit_kernel = [_]f64{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var noise_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;

    for (0..sample_count) |index| {
        const wavelength_nm = calibration.shiftedWavelength(
            calibration_config,
            try spectral_grid.sampleAt(@intCast(index)),
        );
        buffers.wavelengths[index] = wavelength_nm;

        const phase = if (sample_count <= 1)
            0.0
        else
            @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(sample_count - 1));

        var input = prepared.toForwardInputAtWavelength(scene, wavelength_nm);
        input.spectral_weight = 1.0 + 0.08 * @cos(2.0 * std.math.pi * phase);
        input.air_mass_factor = prepared.effective_air_mass_factor * (0.98 + 0.04 * @sin(std.math.pi * phase));
        input.optical_depth *= 0.85 + 0.30 * phase;
        input.single_scatter_albedo = std.math.clamp(
            prepared.effective_single_scatter_albedo - 0.03 * phase,
            0.4,
            0.999,
        );

        const forward = try dispatcher.executePrepared(route, input);
        const solar_term = 1.0 + 0.18 * @cos(2.0 * std.math.pi * ((wavelength_nm - scene.spectral_grid.start_nm) / safe_span));
        const ring_term = 0.01 * @sin(4.0 * std.math.pi * phase);
        const surface_gain = 0.75 + 0.50 * scene.surface.albedo;
        const aerosol_optical_depth = prepared.aerosolOpticalDepthAtWavelength(wavelength_nm);
        const cloud_optical_depth = prepared.cloudOpticalDepthAtWavelength(wavelength_nm);
        const aerosol_attenuation = 1.0 + 0.35 * aerosol_optical_depth;
        const cloud_attenuation = 1.0 + 0.20 * cloud_optical_depth;
        const depolarization_scale = 1.0 - 0.15 * prepared.depolarization_factor;

        buffers.scratch[index] =
            (forward.toa_radiance * surface_gain * depolarization_scale * (0.92 + 0.08 * solar_term)) /
            (aerosol_attenuation * cloud_attenuation) +
            ring_term;
    }
    try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.radiance);
    try calibration.applySignal(calibration_config, buffers.radiance, buffers.radiance);

    for (0..sample_count) |index| {
        const wavelength_nm = buffers.wavelengths[index];
        const irradiance_shape = 1.2 + 0.25 * @cos(std.math.pi * ((wavelength_nm - scene.spectral_grid.start_nm) / safe_span));
        const aerosol_attenuation = 1.0 + 0.15 * prepared.aerosolOpticalDepthAtWavelength(wavelength_nm);
        const cloud_attenuation = 1.0 + 0.10 * prepared.cloudOpticalDepthAtWavelength(wavelength_nm);
        buffers.scratch[index] = @max(
            (irradiance_shape * @exp(-0.15 * prepared.totalOpticalDepthAtWavelength(wavelength_nm))) / (aerosol_attenuation * cloud_attenuation),
            1e-6,
        );
    }
    try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.irradiance);
    try calibration.applySignal(calibration_config, buffers.irradiance, buffers.irradiance);

    for (0..sample_count) |index| {
        buffers.reflectance[index] = buffers.radiance[index] / @max(buffers.irradiance[index], 1e-9);
        radiance_sum += buffers.radiance[index];
        irradiance_sum += buffers.irradiance[index];
        reflectance_sum += buffers.reflectance[index];
    }

    if (buffers.noise_sigma) |noise_sigma| {
        try noise.shotNoiseStd(buffers.radiance, electronsPerCount(scene), noise_sigma);
        for (noise_sigma) |value| noise_sum += value;
    }

    var mean_jacobian: ?f64 = null;
    if (buffers.jacobian) |jacobian| {
        for (0..sample_count) |index| {
            const phase = if (sample_count <= 1)
                0.0
            else
                @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(sample_count - 1));
            var input = prepared.toForwardInputAtWavelength(scene, buffers.wavelengths[index]);
            input.spectral_weight = 1.0 + 0.08 * @cos(2.0 * std.math.pi * phase);
            input.air_mass_factor = prepared.effective_air_mass_factor * (0.98 + 0.04 * @sin(std.math.pi * phase));
            input.optical_depth *= 0.85 + 0.30 * phase;
            input.single_scatter_albedo = std.math.clamp(
                prepared.effective_single_scatter_albedo - 0.03 * phase,
                0.4,
                0.999,
            );
            const forward = try dispatcher.executePrepared(route, input);
            buffers.scratch[index] = if (forward.jacobian_column) |value|
                value * (1.0 + 0.05 * phase)
            else
                0.0;
        }
        try convolution.apply(buffers.scratch, slit_kernel[0..], jacobian);
        for (jacobian) |value| jacobian_sum += value;
        mean_jacobian = jacobian_sum / @as(f64, @floatFromInt(sample_count));
    }

    return .{
        .sample_count = @intCast(sample_count),
        .wavelength_start_nm = buffers.wavelengths[0],
        .wavelength_end_nm = buffers.wavelengths[sample_count - 1],
        .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_noise_sigma = if (buffers.noise_sigma != null)
            noise_sum / @as(f64, @floatFromInt(sample_count))
        else
            0.0,
        .mean_jacobian = mean_jacobian,
    };
}

pub fn simulateSummary(
    allocator: Allocator,
    scene: Scene,
    route: common.Route,
    prepared: PreparedOpticalState,
) Error!MeasurementSpaceSummary {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);

    const wavelengths = try allocator.alloc(f64, sample_count);
    defer allocator.free(wavelengths);
    const radiance = try allocator.alloc(f64, sample_count);
    defer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, sample_count);
    defer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, sample_count);
    defer allocator.free(reflectance);
    const scratch = try allocator.alloc(f64, sample_count);
    defer allocator.free(scratch);
    const noise_sigma = try allocator.alloc(f64, sample_count);
    defer allocator.free(noise_sigma);

    const jacobian = if (route.derivative_mode == .none)
        null
    else
        try allocator.alloc(f64, sample_count);
    defer if (jacobian) |values| allocator.free(values);

    return simulate(scene, route, prepared, .{
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .scratch = scratch,
        .jacobian = jacobian,
        .noise_sigma = noise_sigma,
    });
}

fn validateBuffers(sample_count: usize, buffers: Buffers) Error!void {
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count)
    {
        return error.ShapeMismatch;
    }
    if (buffers.jacobian) |jacobian| {
        if (jacobian.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.noise_sigma) |noise_sigma| {
        if (noise_sigma.len != sample_count) return error.ShapeMismatch;
    }
}

fn calibrationForScene(scene: Scene) calibration.Calibration {
    return .{
        .gain = switch (scene.observation_model.regime) {
            .nadir => 1.0,
            .limb => 1.04,
            .occultation => 1.02,
        },
        .offset = 0.0,
        .wavelength_shift_nm = if (std.mem.eql(u8, scene.observation_model.sampling, "operational"))
            0.02
        else
            0.0,
    };
}

fn electronsPerCount(scene: Scene) f64 {
    if (std.mem.eql(u8, scene.observation_model.noise_model, "shot_noise")) return 2.0;
    if (std.mem.eql(u8, scene.observation_model.noise_model, "s5p_operational")) return 3.5;
    return 1.0;
}

test "measurement-space simulation composes transport, calibration, convolution, and noise" {
    const scene: Scene = .{
        .id = "measurement-space",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = "synthetic",
            .regime = .nadir,
            .sampling = "operational",
            .noise_model = "shot_noise",
        },
        .atmosphere = .{
            .layer_count = 12,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = PreparedOpticalState{
        .layers = try std.testing.allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
                .{ .layer_index = 0, .altitude_km = 2.0, .pressure_hpa = 820.0, .temperature_k = 280.0, .number_density_cm3 = 2.0e19, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 1.0e-20, .line_mixing_cross_section_cm2_per_molecule = 2.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23, .gas_optical_depth = 0.12, .aerosol_optical_depth = 0.05, .cloud_optical_depth = 0.03, .layer_single_scatter_albedo = 0.94, .depolarization_factor = 0.03, .optical_depth = 0.2 },
                .{ .layer_index = 1, .altitude_km = 10.0, .pressure_hpa = 280.0, .temperature_k = 240.0, .number_density_cm3 = 6.0e18, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 5.0e-21, .line_mixing_cross_section_cm2_per_molecule = 1.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24, .gas_optical_depth = 0.07, .aerosol_optical_depth = 0.02, .cloud_optical_depth = 0.01, .layer_single_scatter_albedo = 0.96, .depolarization_factor = 0.02, .optical_depth = 0.1 },
            }),
        .continuum_points = try std.testing.allocator.dupe(@import("../../model/ReferenceData.zig").CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.0e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.0e-19 },
        }),
        .spectroscopy_lines = try std.testing.allocator.dupe(@import("../../model/ReferenceData.zig").SpectroscopyLine, &.{
            .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.04, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.06 },
        }),
        .mean_cross_section_cm2_per_molecule = 5.0e-19,
        .line_mean_cross_section_cm2_per_molecule = 7.5e-21,
        .line_mixing_mean_cross_section_cm2_per_molecule = 1.5e-21,
        .effective_air_mass_factor = 1.25,
        .effective_single_scatter_albedo = 0.92,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 550.0,
        .column_density_factor = 6.0e0,
        .aerosol_reference_wavelength_nm = 550.0,
        .aerosol_angstrom_exponent = 1.3,
        .cloud_reference_wavelength_nm = 550.0,
        .cloud_angstrom_exponent = 0.3,
        .gas_optical_depth = 0.19,
        .aerosol_optical_depth = 0.07,
        .cloud_optical_depth = 0.04,
        .d_optical_depth_d_temperature = -1.5e-4,
        .depolarization_factor = 0.025,
        .total_optical_depth = 0.3,
    };
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, scene, route, prepared);
    try std.testing.expectEqual(@as(u32, 16), summary.sample_count);
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
    try std.testing.expect(summary.mean_reflectance < 10.0);
    try std.testing.expect(summary.mean_noise_sigma > 0.0);
    try std.testing.expect(summary.mean_jacobian != null);
}
