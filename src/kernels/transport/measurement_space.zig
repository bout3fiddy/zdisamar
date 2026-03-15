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
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;

const Allocator = std.mem.Allocator;
const default_integration_sample_count: usize = 5;
const max_integration_sample_count: usize = 17;

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

pub const MeasurementSpaceProduct = struct {
    summary: MeasurementSpaceSummary,
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    noise_sigma: []f64,
    jacobian: ?[]f64 = null,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    cloud_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn deinit(self: *MeasurementSpaceProduct, allocator: Allocator) void {
        allocator.free(self.wavelengths);
        allocator.free(self.radiance);
        allocator.free(self.irradiance);
        allocator.free(self.reflectance);
        allocator.free(self.noise_sigma);
        if (self.jacobian) |values| allocator.free(values);
        self.* = undefined;
    }
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

const OperationalInstrumentIntegration = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};

const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: f64 = 0.0,
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
    const slit_kernel = slitKernelForScene(scene);
    const uses_integrated_sampling = usesIntegratedInstrumentSampling(scene);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const safe_span = if (span_nm <= 0.0) 1.0 else span_nm;

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var noise_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;

    for (0..sample_count) |index| {
        const nominal_wavelength_nm = try spectral_grid.sampleAt(@intCast(index));
        const wavelength_nm = calibration.shiftedWavelength(
            calibration_config,
            nominal_wavelength_nm,
        );
        buffers.wavelengths[index] = wavelength_nm;

        const phase = if (sample_count <= 1)
            0.0
        else
            @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(sample_count - 1));

        const integrated = try integrateForwardAtNominal(
            scene,
            route,
            prepared,
            wavelength_nm,
            phase,
            safe_span,
            instrumentIntegrationForWavelength(scene, nominal_wavelength_nm),
        );
        buffers.scratch[index] = integrated.radiance;
        if (uses_integrated_sampling) {
            if (buffers.jacobian) |jacobian| jacobian[index] = integrated.jacobian;
        }
    }
    if (uses_integrated_sampling) {
        @memcpy(buffers.radiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.radiance);
    }
    try calibration.applySignal(calibration_config, buffers.radiance, buffers.radiance);

    for (0..sample_count) |index| {
        const wavelength_nm = buffers.wavelengths[index];
        const nominal_wavelength_nm = try spectral_grid.sampleAt(@intCast(index));
        buffers.scratch[index] = integrateIrradianceAtNominal(
            scene,
            prepared,
            wavelength_nm,
            safe_span,
            instrumentIntegrationForWavelength(scene, nominal_wavelength_nm),
        );
    }
    if (uses_integrated_sampling) {
        @memcpy(buffers.irradiance, buffers.scratch);
    } else {
        try convolution.apply(buffers.scratch, slit_kernel[0..], buffers.irradiance);
    }
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
        if (uses_integrated_sampling) {
            for (jacobian) |value| jacobian_sum += value;
        } else {
            for (0..sample_count) |index| {
                const phase = if (sample_count <= 1)
                    0.0
                else
                    @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(sample_count - 1));
                const input = configuredForwardInput(scene, prepared, buffers.wavelengths[index], phase);
                const forward = try dispatcher.executePrepared(route, input);
                buffers.scratch[index] = if (forward.jacobian_column) |value|
                    value * (1.0 + 0.05 * phase)
                else
                    0.0;
            }
            try convolution.apply(buffers.scratch, slit_kernel[0..], jacobian);
            for (jacobian) |value| jacobian_sum += value;
        }
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
    var product = try simulateProduct(allocator, scene, route, prepared);
    defer product.deinit(allocator);
    return product.summary;
}

pub fn simulateProduct(
    allocator: Allocator,
    scene: Scene,
    route: common.Route,
    prepared: PreparedOpticalState,
) Error!MeasurementSpaceProduct {
    const sample_count: usize = @intCast(scene.spectral_grid.sample_count);

    const wavelengths = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(wavelengths);
    const radiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(reflectance);
    const scratch = try allocator.alloc(f64, sample_count);
    defer allocator.free(scratch);
    const noise_sigma = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(noise_sigma);

    const jacobian = if (route.derivative_mode == .none)
        null
    else
        try allocator.alloc(f64, sample_count);
    errdefer if (jacobian) |values| allocator.free(values);

    const summary = try simulate(scene, route, prepared, .{
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .scratch = scratch,
        .jacobian = jacobian,
        .noise_sigma = noise_sigma,
    });

    return .{
        .summary = summary,
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = noise_sigma,
        .jacobian = jacobian,
        .effective_air_mass_factor = prepared.effective_air_mass_factor,
        .effective_single_scatter_albedo = prepared.effective_single_scatter_albedo,
        .effective_temperature_k = prepared.effective_temperature_k,
        .effective_pressure_hpa = prepared.effective_pressure_hpa,
        .gas_optical_depth = prepared.gas_optical_depth,
        .cia_optical_depth = prepared.cia_optical_depth,
        .aerosol_optical_depth = prepared.aerosol_optical_depth,
        .cloud_optical_depth = prepared.cloud_optical_depth,
        .total_optical_depth = prepared.total_optical_depth,
        .depolarization_factor = prepared.depolarization_factor,
        .d_optical_depth_d_temperature = prepared.d_optical_depth_d_temperature,
    };
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
        .wavelength_shift_nm = if (scene.observation_model.wavelength_shift_nm != 0.0)
            scene.observation_model.wavelength_shift_nm
        else if (std.mem.eql(u8, scene.observation_model.sampling, "operational"))
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

fn usesIntegratedInstrumentSampling(scene: Scene) bool {
    return scene.observation_model.instrument_line_fwhm_nm > 0.0 or
        scene.observation_model.instrument_line_shape.sample_count > 0 or
        scene.observation_model.instrument_line_shape_table.nominal_count > 0;
}

fn instrumentIntegrationForWavelength(scene: Scene, nominal_wavelength_nm: f64) OperationalInstrumentIntegration {
    if (!usesIntegratedInstrumentSampling(scene)) {
        return .{
            .enabled = false,
            .sample_count = 1,
            .offsets_nm = [_]f64{0.0} ** max_integration_sample_count,
            .weights = [_]f64{0.0} ** max_integration_sample_count,
        };
    }

    if (scene.observation_model.instrument_line_shape_table.nearestNominalIndex(nominal_wavelength_nm)) |nominal_index| {
        const table = scene.observation_model.instrument_line_shape_table;
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sample_count = @min(@as(usize, table.sample_count), max_line_shape_samples);
        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_nm[index] = table.offsets_nm[index];
            weights[index] = table.weightAt(nominal_index, index);
            weight_sum += weights[index];
        }
        if (weight_sum > 0.0) {
            for (0..sample_count) |index| weights[index] /= weight_sum;
        } else {
            weights[0] = 1.0;
            return .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = offsets_nm,
                .weights = weights,
            };
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    if (scene.observation_model.instrument_line_shape.sample_count > 0) {
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sample_count = @min(
            @as(usize, scene.observation_model.instrument_line_shape.sample_count),
            max_line_shape_samples,
        );
        var weight_sum: f64 = 0.0;
        for (0..sample_count) |index| {
            offsets_nm[index] = scene.observation_model.instrument_line_shape.offsets_nm[index];
            weights[index] = scene.observation_model.instrument_line_shape.weights[index];
            weight_sum += weights[index];
        }
        if (weight_sum > 0.0) {
            for (0..sample_count) |index| weights[index] /= weight_sum;
        } else {
            weights[0] = 1.0;
            return .{
                .enabled = true,
                .sample_count = 1,
                .offsets_nm = offsets_nm,
                .weights = weights,
            };
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    if (scene.observation_model.high_resolution_step_nm > 0.0 and scene.observation_model.high_resolution_half_span_nm > 0.0) {
        var offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
        var weights = [_]f64{0.0} ** max_integration_sample_count;
        const sigma_nm = @max(scene.observation_model.instrument_line_fwhm_nm / 2.354820045, 1.0e-4);
        const step_nm = scene.observation_model.high_resolution_step_nm;
        const half_span_nm = scene.observation_model.high_resolution_half_span_nm;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            offsets_nm[sample_count] = offset_nm;
            const weight = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
            weights[sample_count] = weight;
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += weights[index];
        if (total_weight <= 0.0) {
            offsets_nm[0] = 0.0;
            weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| weights[index] /= total_weight;
        }
        return .{
            .enabled = true,
            .sample_count = sample_count,
            .offsets_nm = offsets_nm,
            .weights = weights,
        };
    }

    const sigma_nm = @max(scene.observation_model.instrument_line_fwhm_nm / 2.354820045, 1.0e-4);
    const offsets_nm: [default_integration_sample_count]f64 = .{
        -2.0 * sigma_nm,
        -1.0 * sigma_nm,
        0.0,
        1.0 * sigma_nm,
        2.0 * sigma_nm,
    };

    var full_offsets_nm = [_]f64{0.0} ** max_integration_sample_count;
    var weights = [_]f64{0.0} ** max_integration_sample_count;
    var total_weight: f64 = 0.0;
    for (offsets_nm, 0..) |offset_nm, index| {
        full_offsets_nm[index] = offset_nm;
        const value = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
        weights[index] = value;
        total_weight += value;
    }
    for (0..default_integration_sample_count) |index| weights[index] /= total_weight;

    return .{
        .enabled = true,
        .sample_count = default_integration_sample_count,
        .offsets_nm = full_offsets_nm,
        .weights = weights,
    };
}

fn configuredForwardInput(
    scene: Scene,
    prepared: PreparedOpticalState,
    wavelength_nm: f64,
    phase: f64,
) common.ForwardInput {
    var input = prepared.toForwardInputAtWavelength(scene, wavelength_nm);
    input.spectral_weight = 1.0 + 0.08 * @cos(2.0 * std.math.pi * phase);
    input.air_mass_factor = prepared.effective_air_mass_factor * (0.98 + 0.04 * @sin(std.math.pi * phase));
    input.optical_depth *= 0.85 + 0.30 * phase;
    input.single_scatter_albedo = std.math.clamp(
        prepared.effective_single_scatter_albedo - 0.03 * phase,
        0.4,
        0.999,
    );
    return input;
}

fn radianceFromForward(
    scene: Scene,
    prepared: PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
    phase: f64,
    forward: common.ForwardResult,
) f64 {
    const solar_term = 1.0 + 0.18 * @cos(2.0 * std.math.pi * ((wavelength_nm - scene.spectral_grid.start_nm) / safe_span));
    const ring_term = 0.01 * @sin(4.0 * std.math.pi * phase);
    const surface_gain = 0.75 + 0.50 * scene.surface.albedo;
    const aerosol_optical_depth = prepared.aerosolOpticalDepthAtWavelength(wavelength_nm);
    const cloud_optical_depth = prepared.cloudOpticalDepthAtWavelength(wavelength_nm);
    const aerosol_attenuation = 1.0 + 0.35 * aerosol_optical_depth;
    const cloud_attenuation = 1.0 + 0.20 * cloud_optical_depth;
    const depolarization_scale = 1.0 - 0.15 * prepared.depolarization_factor;

    return (forward.toa_radiance * surface_gain * depolarization_scale * (0.92 + 0.08 * solar_term)) /
        (aerosol_attenuation * cloud_attenuation) +
        ring_term;
}

fn irradianceAtWavelength(
    scene: Scene,
    prepared: PreparedOpticalState,
    wavelength_nm: f64,
    safe_span: f64,
) f64 {
    const source_irradiance = if (scene.observation_model.operational_solar_spectrum.enabled())
        scene.observation_model.operational_solar_spectrum.interpolateIrradiance(wavelength_nm)
    else
        1.2 + 0.25 * @cos(std.math.pi * ((wavelength_nm - scene.spectral_grid.start_nm) / safe_span));
    const aerosol_attenuation = 1.0 + 0.15 * prepared.aerosolOpticalDepthAtWavelength(wavelength_nm);
    const cloud_attenuation = 1.0 + 0.10 * prepared.cloudOpticalDepthAtWavelength(wavelength_nm);
    return @max(
        (source_irradiance * @exp(-0.15 * prepared.totalOpticalDepthAtWavelength(wavelength_nm))) / (aerosol_attenuation * cloud_attenuation),
        1e-6,
    );
}

fn integrateForwardAtNominal(
    scene: Scene,
    route: common.Route,
    prepared: PreparedOpticalState,
    nominal_wavelength_nm: f64,
    phase: f64,
    safe_span: f64,
    integration: OperationalInstrumentIntegration,
) Error!ForwardIntegratedSample {
    if (!integration.enabled) {
        const input = configuredForwardInput(scene, prepared, nominal_wavelength_nm, phase);
        const forward = try dispatcher.executePrepared(route, input);
        return .{
            .radiance = radianceFromForward(scene, prepared, nominal_wavelength_nm, safe_span, phase, forward),
            .jacobian = if (forward.jacobian_column) |value| value * (1.0 + 0.05 * phase) else 0.0,
        };
    }

    var radiance_sum: f64 = 0.0;
    var jacobian_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        const wavelength_nm = nominal_wavelength_nm + offset_nm;
        const input = configuredForwardInput(scene, prepared, wavelength_nm, phase);
        const forward = try dispatcher.executePrepared(route, input);
        radiance_sum += weight * radianceFromForward(scene, prepared, wavelength_nm, safe_span, phase, forward);
        if (forward.jacobian_column) |value| {
            jacobian_sum += weight * value * (1.0 + 0.05 * phase);
        }
    }

    return .{
        .radiance = radiance_sum,
        .jacobian = jacobian_sum,
    };
}

fn integrateIrradianceAtNominal(
    scene: Scene,
    prepared: PreparedOpticalState,
    nominal_wavelength_nm: f64,
    safe_span: f64,
    integration: OperationalInstrumentIntegration,
) f64 {
    if (!integration.enabled) {
        return irradianceAtWavelength(scene, prepared, nominal_wavelength_nm, safe_span);
    }

    var irradiance_sum: f64 = 0.0;
    for (0..integration.sample_count) |index| {
        const offset_nm = integration.offsets_nm[index];
        const weight = integration.weights[index];
        irradiance_sum += weight * irradianceAtWavelength(
            scene,
            prepared,
            nominal_wavelength_nm + offset_nm,
            safe_span,
        );
    }
    return irradiance_sum;
}

fn slitKernelForScene(scene: Scene) [5]f64 {
    if (scene.observation_model.instrument_line_fwhm_nm <= 0.0) {
        return .{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    }

    const sample_spacing_nm = if (scene.spectral_grid.sample_count <= 1)
        1.0
    else
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    const sigma_samples = std.math.clamp(
        scene.observation_model.instrument_line_fwhm_nm / @max(sample_spacing_nm, 1e-6) / 2.354820045,
        0.3,
        2.5,
    );

    var kernel: [5]f64 = undefined;
    var sum: f64 = 0.0;
    for (0..kernel.len) |index| {
        const offset = @as(f64, @floatFromInt(@as(i32, @intCast(index)) - 2));
        const value = @exp(-0.5 * std.math.pow(f64, offset / sigma_samples, 2.0));
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}

fn buildTestPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(@import("../optics/prepare.zig").PreparedLayer, &.{
            .{ .layer_index = 0, .altitude_km = 2.0, .pressure_hpa = 820.0, .temperature_k = 280.0, .number_density_cm3 = 2.0e19, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 1.0e-20, .line_mixing_cross_section_cm2_per_molecule = 2.0e-21, .cia_optical_depth = 0.03, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23, .gas_optical_depth = 0.12, .aerosol_optical_depth = 0.05, .cloud_optical_depth = 0.03, .layer_single_scatter_albedo = 0.94, .depolarization_factor = 0.03, .optical_depth = 0.2 },
            .{ .layer_index = 1, .altitude_km = 10.0, .pressure_hpa = 280.0, .temperature_k = 240.0, .number_density_cm3 = 6.0e18, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 5.0e-21, .line_mixing_cross_section_cm2_per_molecule = 1.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24, .cia_optical_depth = 0.0, .gas_optical_depth = 0.07, .aerosol_optical_depth = 0.02, .cloud_optical_depth = 0.01, .layer_single_scatter_albedo = 0.96, .depolarization_factor = 0.02, .optical_depth = 0.1 },
        }),
        .continuum_points = try allocator.dupe(@import("../../model/ReferenceData.zig").CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.0e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.0e-19 },
        }),
        .collision_induced_absorption = .{
            .scale_factor_cm5_per_molecule2 = 1.0e-46,
            .points = try allocator.dupe(@import("../../model/ReferenceData.zig").CollisionInducedAbsorptionPoint, &.{
                .{ .wavelength_nm = 405.0, .a0 = 0.5, .a1 = 0.0, .a2 = 0.0 },
                .{ .wavelength_nm = 465.0, .a0 = 1.5, .a1 = 0.0, .a2 = 0.0 },
            }),
        },
        .spectroscopy_lines = .{
            .lines = try allocator.dupe(@import("../../model/ReferenceData.zig").SpectroscopyLine, &.{
                .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.04, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.06 },
            }),
        },
        .mean_cross_section_cm2_per_molecule = 5.0e-19,
        .line_mean_cross_section_cm2_per_molecule = 7.5e-21,
        .line_mixing_mean_cross_section_cm2_per_molecule = 1.5e-21,
        .cia_mean_cross_section_cm5_per_molecule2 = 1.0e-46,
        .effective_air_mass_factor = 1.25,
        .effective_single_scatter_albedo = 0.92,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 550.0,
        .column_density_factor = 6.0e0,
        .cia_pair_path_factor_cm5 = 4.0e42,
        .aerosol_reference_wavelength_nm = 550.0,
        .aerosol_angstrom_exponent = 1.3,
        .cloud_reference_wavelength_nm = 550.0,
        .cloud_angstrom_exponent = 0.3,
        .gas_optical_depth = 0.19,
        .cia_optical_depth = 0.03,
        .aerosol_optical_depth = 0.07,
        .cloud_optical_depth = 0.04,
        .d_optical_depth_d_temperature = -1.5e-4,
        .depolarization_factor = 0.025,
        .total_optical_depth = 0.3,
    };
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
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
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

test "measurement-space product materializes spectral vectors and physical fields" {
    const scene: Scene = .{
        .id = "measurement-product",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
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
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, scene, route, prepared);
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 12), product.summary.sample_count);
    try std.testing.expectEqual(@as(usize, 12), product.wavelengths.len);
    try std.testing.expect(product.radiance[0] > 0.0);
    try std.testing.expect(product.irradiance[0] > 0.0);
    try std.testing.expect(product.reflectance[0] > 0.0);
    try std.testing.expect(product.noise_sigma[0] > 0.0);
    try std.testing.expect(product.jacobian != null);
    try std.testing.expectEqual(prepared.total_optical_depth, product.total_optical_depth);
    try std.testing.expectEqual(prepared.effective_air_mass_factor, product.effective_air_mass_factor);
    try std.testing.expectEqual(prepared.cia_optical_depth, product.cia_optical_depth);
}

test "measurement-space uses external high-resolution solar spectra when operational metadata provides one" {
    const scene: Scene = .{
        .id = "measurement-operational-solar",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "operational",
            .noise_model = "s5p_operational",
            .operational_solar_spectrum = .{
                .wavelengths_nm = &[_]f64{ 405.0, 435.0, 465.0 },
                .irradiance = &[_]f64{ 1.0e14, 2.0e14, 3.0e14 },
            },
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

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, scene, route, prepared);
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(product.irradiance[0] < product.irradiance[1]);
    try std.testing.expect(product.irradiance[1] < product.irradiance[2]);
    try std.testing.expect(product.reflectance[0] > product.reflectance[2]);
}

test "measurement-space operational integration uses high-resolution instrument sampling" {
    const plain_scene: Scene = .{
        .id = "measurement-plain",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = "synthetic",
            .regime = .nadir,
            .sampling = "native",
            .noise_model = "shot_noise",
        },
        .atmosphere = .{
            .layer_count = 12,
        },
    };
    const operational_scene: Scene = .{
        .id = "measurement-operational",
        .spectral_grid = plain_scene.spectral_grid,
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
        },
        .atmosphere = plain_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var plain_product = try simulateProduct(std.testing.allocator, plain_scene, route, prepared);
    defer plain_product.deinit(std.testing.allocator);
    var operational_product = try simulateProduct(std.testing.allocator, operational_scene, route, prepared);
    defer operational_product.deinit(std.testing.allocator);

    try std.testing.expect(operational_product.wavelengths[0] > plain_product.wavelengths[0]);
    try std.testing.expect(operational_product.radiance[0] != plain_product.radiance[0]);
    try std.testing.expect(operational_product.irradiance[0] != plain_product.irradiance[0]);
    try std.testing.expect(operational_product.jacobian != null);
}

test "measurement-space operational integration honors explicit isrf table weights" {
    const gaussian_scene: Scene = .{
        .id = "measurement-operational-gaussian",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
        },
        .atmosphere = .{
            .layer_count = 12,
        },
    };
    const table_scene: Scene = .{
        .id = "measurement-operational-table",
        .spectral_grid = gaussian_scene.spectral_grid,
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = .{ -0.32, -0.16, 0.0, 0.16, 0.32, 0.0, 0.0, 0.0, 0.0 },
                .weights = .{ 0.08, 0.24, 0.36, 0.22, 0.10, 0.0, 0.0, 0.0, 0.0 },
            },
        },
        .atmosphere = gaussian_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var gaussian_product = try simulateProduct(std.testing.allocator, gaussian_scene, route, prepared);
    defer gaussian_product.deinit(std.testing.allocator);
    var table_product = try simulateProduct(std.testing.allocator, table_scene, route, prepared);
    defer table_product.deinit(std.testing.allocator);

    try std.testing.expect(table_product.radiance[0] != gaussian_product.radiance[0]);
    try std.testing.expect(table_product.irradiance[0] != gaussian_product.irradiance[0]);
    try std.testing.expect(table_product.jacobian != null);
}

test "measurement-space operational integration selects wavelength-indexed isrf rows" {
    const global_shape_scene: Scene = .{
        .id = "measurement-operational-global-shape",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 407.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = .{ -0.32, -0.16, 0.0, 0.16, 0.32, 0.0, 0.0, 0.0, 0.0 },
                .weights = .{ 0.08, 0.24, 0.36, 0.22, 0.10, 0.0, 0.0, 0.0, 0.0 },
            },
        },
        .atmosphere = .{
            .layer_count = 12,
        },
    };
    var indexed_table = @import("../../model/Instrument.zig").InstrumentLineShapeTable{};
    indexed_table.nominal_count = 3;
    indexed_table.sample_count = 5;
    indexed_table.nominal_wavelengths_nm[0] = 405.0;
    indexed_table.nominal_wavelengths_nm[1] = 406.0;
    indexed_table.nominal_wavelengths_nm[2] = 407.0;
    indexed_table.offsets_nm = .{ -0.32, -0.16, 0.0, 0.16, 0.32, 0.0, 0.0, 0.0, 0.0 };
    for ([5]f64{ 0.08, 0.24, 0.36, 0.22, 0.10 }, 0..) |value, index| indexed_table.setWeight(0, index, value);
    for ([5]f64{ 0.18, 0.30, 0.30, 0.15, 0.07 }, 0..) |value, index| indexed_table.setWeight(1, index, value);
    for ([5]f64{ 0.05, 0.18, 0.34, 0.26, 0.17 }, 0..) |value, index| indexed_table.setWeight(2, index, value);
    const indexed_table_scene: Scene = .{
        .id = "measurement-operational-indexed-table",
        .spectral_grid = global_shape_scene.spectral_grid,
        .observation_model = .{
            .instrument = "tropomi",
            .regime = .nadir,
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = global_shape_scene.observation_model.instrument_line_shape,
            .instrument_line_shape_table = indexed_table,
        },
        .atmosphere = global_shape_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var global_shape_product = try simulateProduct(std.testing.allocator, global_shape_scene, route, prepared);
    defer global_shape_product.deinit(std.testing.allocator);
    var indexed_table_product = try simulateProduct(std.testing.allocator, indexed_table_scene, route, prepared);
    defer indexed_table_product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(global_shape_product.radiance[0], indexed_table_product.radiance[0], 1e-12);
    try std.testing.expect(global_shape_product.radiance[1] != indexed_table_product.radiance[1]);
    try std.testing.expect(global_shape_product.radiance[2] != indexed_table_product.radiance[2]);
}
