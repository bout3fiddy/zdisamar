const std = @import("std");
const common = @import("contracts.zig");
const forward_model = @import("forward_model.zig");
const state_access = @import("state_access.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const StateTarget = @import("../../model/Scene.zig").StateTarget;
const ResolvedAxis = @import("../../kernels/spectra/grid.zig").ResolvedAxis;
const SpectralGrid = @import("../../kernels/spectra/grid.zig").SpectralGrid;
const ExecutionMode = @import("../../kernels/transport/common.zig").ExecutionMode;
const MeasurementSpace = @import("../../kernels/transport/measurement_space.zig");
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const MeasurementSpaceSummary = MeasurementSpace.MeasurementSpaceSummary;
const Allocator = std.mem.Allocator;

pub const FeatureVector = struct {
    values: [3]f64 = .{ 0.0, 0.0, 0.0 },
    len: usize,
};

pub fn testEvaluator() forward_model.Evaluator {
    return .{
        .context = undefined,
        .evaluateSummary = evaluateSyntheticSummary,
        .evaluateProduct = evaluateSyntheticProduct,
    };
}

pub fn anchorState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    method: common.Method,
    observed: MeasurementSpaceSummary,
) common.Error![]f64 {
    const layout = try state_access.resolveStateLayout(problem);
    return anchorStateWithLayout(allocator, problem, method, observed, layout);
}

pub fn anchorStateWithLayout(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    method: common.Method,
    observed: MeasurementSpaceSummary,
    layout: state_access.ResolvedStateLayout,
) common.Error![]f64 {
    const seeded = try state_access.seedStateWithLayout(allocator, problem, layout);
    errdefer allocator.free(seeded);

    const anchored = try allocator.alloc(f64, seeded.len);
    for (seeded, 0..) |seed, index| {
        const accessor = layout.at(index);
        if (stateParameter(problem, index)) |parameter| {
            anchored[index] = anchorForAccessor(seed, accessor.target, observed, method);
            anchored[index] = clampStateValue(parameter, anchored[index]);
        } else {
            anchored[index] = anchorForAccessor(seed, accessor.target, observed, method);
        }
    }
    allocator.free(seeded);
    return anchored;
}

pub fn observedSummary(
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
) common.Error!MeasurementSpaceSummary {
    if (problem.observed_measurement) |observed| return observed.summary();

    return evaluator.evaluateSummary(evaluator.context, problem.scene) catch |err| switch (err) {
        error.OutOfMemory => common.Error.OutOfMemory,
        error.InvalidRequest => common.Error.InvalidRequest,
        else => common.Error.InvalidRequest,
    };
}

pub fn summarizeState(
    problem: common.RetrievalProblem,
    method: common.Method,
    state: []const f64,
    evaluator: forward_model.Evaluator,
) common.Error!MeasurementSpaceSummary {
    const layout = try state_access.resolveStateLayout(problem);
    return summarizeStateWithLayout(problem, method, state, evaluator, layout);
}

pub fn summarizeStateWithLayout(
    problem: common.RetrievalProblem,
    method: common.Method,
    state: []const f64,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
) common.Error!MeasurementSpaceSummary {
    _ = executionMode(problem, method);
    const scene = try state_access.sceneForStateWithLayout(problem, state, layout);
    return evaluator.evaluateSummary(evaluator.context, scene) catch |err| switch (err) {
        error.OutOfMemory => common.Error.OutOfMemory,
        error.InvalidRequest => common.Error.InvalidRequest,
        else => common.Error.InvalidRequest,
    };
}

pub fn featureVector(
    summary: MeasurementSpaceSummary,
    method: common.Method,
) FeatureVector {
    return switch (method) {
        .oe => .{
            .values = .{
                summary.mean_radiance,
                summary.mean_reflectance,
                0.0,
            },
            .len = 2,
        },
        .doas => .{
            .values = .{
                std.math.log(
                    f64,
                    std.math.e,
                    @max(summary.mean_irradiance / @max(summary.mean_radiance, 1e-9), 1e-9),
                ),
                summary.mean_noise_sigma,
                0.0,
            },
            .len = 2,
        },
        .dismas => .{
            .values = .{
                summary.mean_radiance,
                summary.mean_reflectance,
                summary.mean_noise_sigma + @abs(summary.mean_jacobian orelse 0.0),
            },
            .len = 3,
        },
    };
}

pub fn residualNorm(lhs: FeatureVector, rhs: FeatureVector) f64 {
    var total: f64 = 0.0;
    const len = @min(lhs.len, rhs.len);
    for (0..len) |index| {
        const delta = lhs.values[index] - rhs.values[index];
        total += delta * delta;
    }
    return std.math.sqrt(total);
}

const SyntheticSample = struct {
    radiance: f64,
    irradiance: f64,
    reflectance: f64,
    noise_sigma: f64,
};

fn stateParameter(problem: common.RetrievalProblem, index: usize) ?@import("../../model/Scene.zig").StateParameter {
    if (problem.inverse_problem.state_vector.parameters.len == 0) return null;
    return problem.inverse_problem.state_vector.parameters[index];
}

fn clampStateValue(parameter: @import("../../model/Scene.zig").StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

fn anchorForAccessor(
    seed: f64,
    target: StateTarget,
    observed: MeasurementSpaceSummary,
    method: common.Method,
) f64 {
    const method_scale = switch (method) {
        .oe => @as(f64, 1.0),
        .doas => @as(f64, 0.65),
        .dismas => @as(f64, 1.2),
    };
    const radiance = observed.mean_radiance;
    const reflectance = observed.mean_reflectance;
    const jacobian = observed.mean_jacobian orelse observed.mean_noise_sigma;

    return switch (target) {
        .unset => unreachable,
        .surface_albedo => std.math.clamp(0.5 * seed + 0.5 * reflectance * method_scale, 0.0, 1.0),
        .aerosol_optical_depth_550_nm => @max(0.01, seed * 0.7 + method_scale * (0.08 + 0.12 / @max(radiance, 0.1))),
        .aerosol_layer_center_km => @max(0.0, seed * 0.8 + method_scale * (2.0 + 4.0 * reflectance)),
        .aerosol_layer_width_km => @max(0.1, seed * 0.8 + method_scale * (0.8 + 0.4 * reflectance)),
        .cloud_optical_thickness => @max(0.0, seed * 0.75 + method_scale * (0.15 + observed.mean_noise_sigma)),
        .wavelength_shift_nm => std.math.clamp(seed * 0.5 + 0.08 * jacobian, -0.2, 0.2),
        .multiplicative_offset => std.math.clamp(1.0 + 0.03 * (radiance - 1.0), 0.9, 1.1),
        .stray_light => std.math.clamp(0.002 * observed.mean_noise_sigma, -0.01, 0.01),
    };
}

fn executionMode(problem: common.RetrievalProblem, method: common.Method) ExecutionMode {
    return switch (method) {
        .dismas => .polarized,
        .oe, .doas => switch (problem.scene.observation_model.regime) {
            .nadir => .scalar,
            .limb, .occultation => .polarized,
        },
    };
}

fn evaluateSyntheticSummary(_: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary {
    const axis = try resolvedAxis(scene);
    const sample_count = @as(usize, @intCast(scene.spectral_grid.sample_count));
    const mu0 = @max(@cos(std.math.degreesToRadians(scene.geometry.solar_zenith_deg)), 0.15);

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var sigma_sum: f64 = 0.0;
    var first_wavelength_nm: f64 = 0.0;
    var last_wavelength_nm: f64 = 0.0;

    for (0..sample_count) |index| {
        const wavelength_nm = try axis.sampleAt(@intCast(index));
        const sample = syntheticSample(scene, wavelength_nm, mu0);
        if (index == 0) first_wavelength_nm = wavelength_nm;
        last_wavelength_nm = wavelength_nm;
        radiance_sum += sample.radiance;
        irradiance_sum += sample.irradiance;
        reflectance_sum += sample.reflectance;
        sigma_sum += sample.noise_sigma;
    }

    return .{
        .sample_count = @intCast(sample_count),
        .wavelength_start_nm = first_wavelength_nm,
        .wavelength_end_nm = last_wavelength_nm,
        .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
        .mean_noise_sigma = sigma_sum / @as(f64, @floatFromInt(sample_count)),
    };
}

fn evaluateSyntheticProduct(
    allocator: Allocator,
    _: *const anyopaque,
    scene: Scene,
) anyerror!MeasurementSpaceProduct {
    const axis = resolvedAxis(scene) catch return error.InvalidRequest;
    const sample_count = @as(usize, @intCast(scene.spectral_grid.sample_count));

    const wavelengths = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(wavelengths);
    const radiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(radiance);
    const irradiance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(irradiance);
    const reflectance = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(reflectance);
    const noise_sigma = try allocator.alloc(f64, sample_count);
    errdefer allocator.free(noise_sigma);

    const mu0 = @max(@cos(std.math.degreesToRadians(scene.geometry.solar_zenith_deg)), 0.15);
    const aerosol_tau = if (scene.aerosol.enabled) scene.aerosol.optical_depth else 0.0;

    var radiance_sum: f64 = 0.0;
    var irradiance_sum: f64 = 0.0;
    var reflectance_sum: f64 = 0.0;
    var sigma_sum: f64 = 0.0;

    for (0..sample_count) |index| {
        const nominal_nm = try axis.sampleAt(@intCast(index));
        wavelengths[index] = nominal_nm;
        const sample = syntheticSample(scene, nominal_nm, mu0);
        irradiance[index] = sample.irradiance;
        radiance[index] = sample.radiance;
        reflectance[index] = sample.reflectance;
        noise_sigma[index] = sample.noise_sigma;

        radiance_sum += radiance[index];
        irradiance_sum += irradiance[index];
        reflectance_sum += reflectance[index];
        sigma_sum += noise_sigma[index];
    }

    return .{
        .summary = .{
            .sample_count = @intCast(sample_count),
            .wavelength_start_nm = wavelengths[0],
            .wavelength_end_nm = wavelengths[sample_count - 1],
            .mean_radiance = radiance_sum / @as(f64, @floatFromInt(sample_count)),
            .mean_irradiance = irradiance_sum / @as(f64, @floatFromInt(sample_count)),
            .mean_reflectance = reflectance_sum / @as(f64, @floatFromInt(sample_count)),
            .mean_noise_sigma = sigma_sum / @as(f64, @floatFromInt(sample_count)),
        },
        .wavelengths = wavelengths,
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = reflectance,
        .noise_sigma = noise_sigma,
        .effective_air_mass_factor = 1.0 / mu0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 270.0,
        .effective_pressure_hpa = 700.0,
        .gas_optical_depth = 0.1,
        .cia_optical_depth = 0.01,
        .aerosol_optical_depth = aerosol_tau,
        .cloud_optical_depth = if (scene.cloud.enabled) scene.cloud.optical_thickness else 0.0,
        .total_optical_depth = 0.11 + aerosol_tau,
        .depolarization_factor = 0.0,
        .d_optical_depth_d_temperature = 0.0,
    };
}

fn syntheticSample(scene: Scene, nominal_wavelength_nm: f64, mu0: f64) SyntheticSample {
    const continuum_level = std.math.clamp(scene.surface.albedo, 0.01, 0.95);
    const aerosol_tau = if (scene.aerosol.enabled) scene.aerosol.optical_depth else 0.0;
    const aerosol_height = if (scene.aerosol.enabled) scene.aerosol.layer_center_km else 2.5;
    const aerosol_width = if (scene.aerosol.enabled) scene.aerosol.layer_width_km else 1.0;
    const shift_nm = scene.observation_model.wavelength_shift_nm;
    const multiplicative_offset = if (scene.observation_model.multiplicative_offset > 0.0)
        scene.observation_model.multiplicative_offset
    else
        1.0;
    const stray_light = scene.observation_model.stray_light;
    const wavelength_nm = nominal_wavelength_nm + shift_nm;

    const continuum = 4.85e14 * (1.0 + 0.002 * (wavelength_nm - 764.0));
    const broad_trough = 0.42 * gaussian(wavelength_nm, 762.7 + 0.03 * aerosol_height, 1.55 + 0.1 * aerosol_width);
    const narrow_lines =
        0.38 * gaussian(wavelength_nm, 760.55, 0.12) +
        0.45 * gaussian(wavelength_nm, 761.15, 0.10) +
        0.52 * gaussian(wavelength_nm, 761.95, 0.11) +
        0.66 * gaussian(wavelength_nm, 762.95, 0.10) +
        0.72 * gaussian(wavelength_nm, 763.75, 0.09) +
        0.75 * gaussian(wavelength_nm, 764.55, 0.08) +
        0.61 * gaussian(wavelength_nm, 765.35, 0.10);
    const aerosol_modifier = 1.0 + 0.65 * aerosol_tau + 0.04 * aerosol_height;
    const absorption = std.math.clamp(broad_trough + aerosol_modifier * narrow_lines, 0.0, 0.98);

    const irradiance = continuum;
    const radiance = multiplicative_offset * continuum * continuum_level * mu0 * (1.0 - absorption) / std.math.pi +
        stray_light * continuum * 0.02;
    return .{
        .radiance = radiance,
        .irradiance = irradiance,
        .reflectance = (radiance * std.math.pi) / @max(irradiance * mu0, 1.0e-12),
        .noise_sigma = @max(1.0e-6, 0.002 * @sqrt(@abs(radiance))),
    };
}

fn resolvedAxis(scene: Scene) !ResolvedAxis {
    const base: SpectralGrid = .{
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .sample_count = scene.spectral_grid.sample_count,
    };
    const axis: ResolvedAxis = .{
        .base = base,
        .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
    };
    try axis.validate();
    return axis;
}

fn gaussian(x: f64, center: f64, sigma: f64) f64 {
    const normalized = (x - center) / @max(sigma, 1.0e-6);
    return std.math.exp(-0.5 * normalized * normalized);
}

test "surrogate forward module supports canonical multi-parameter state application" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "surrogate-forward",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .observation_model = .{ .instrument = "synthetic", .regime = .nadir },
        },
        .inverse_problem = .{
            .id = "surrogate-forward",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.02 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 32,
                .source = .{ .kind = .stage_product, .name = "truth_radiance" },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 32,
            .summary = .{
                .sample_count = 32,
                .wavelength_start_nm = 405.0,
                .wavelength_end_nm = 465.0,
                .mean_radiance = 1.1,
                .mean_irradiance = 2.0,
                .mean_reflectance = 0.55,
                .mean_noise_sigma = 0.08,
                .mean_jacobian = 0.06,
            },
        },
    };

    const layout = try state_access.resolveStateLayout(problem);
    const anchored = try anchorStateWithLayout(std.testing.allocator, problem, .oe, problem.observed_measurement.?.summary, layout);
    defer std.testing.allocator.free(anchored);

    const scene = try state_access.sceneForStateWithLayout(problem, anchored, layout);
    try std.testing.expect(scene.aerosol.enabled);
    try std.testing.expect(scene.observation_model.wavelength_shift_nm != 0.0);
}
