const std = @import("std");
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const Scene = @import("../../model/Scene.zig").Scene;

pub const SummaryEvaluator = struct {
    context: *const anyopaque,
    evaluate: *const fn (context: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary,
};

pub fn defaultEvaluator() SummaryEvaluator {
    return .{
        .context = undefined,
        .evaluate = evaluateSurrogateSummary,
    };
}

fn evaluateSurrogateSummary(_: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary {
    const sample_count = @max(scene.spectral_grid.sample_count, 8);
    const wavelength_start_nm = if (scene.spectral_grid.start_nm != 0.0) scene.spectral_grid.start_nm else 405.0;
    const wavelength_end_nm = if (scene.spectral_grid.end_nm > wavelength_start_nm)
        scene.spectral_grid.end_nm
    else
        wavelength_start_nm + 60.0;
    const albedo = std.math.clamp(scene.surface.albedo, 0.01, 0.95);
    const aerosol_depth = if (scene.aerosol.enabled) scene.aerosol.optical_depth else 0.0;
    const cloud_depth = if (scene.cloud.enabled) scene.cloud.optical_thickness else 0.0;
    const mu0 = @max(@cos(std.math.degreesToRadians(scene.geometry.solar_zenith_deg)), 0.15);
    const muv = @max(@cos(std.math.degreesToRadians(scene.geometry.viewing_zenith_deg)), 0.15);
    const geometry_scale = @as(f64, 0.85) + @as(f64, 0.25) * (mu0 + muv);
    const regime_scale = switch (scene.observation_model.regime) {
        .nadir => @as(f64, 1.0),
        .limb => @as(f64, 0.93),
        .occultation => @as(f64, 0.89),
    };

    const irradiance = @as(f64, 1.55) + @as(f64, 0.35) * mu0;
    const attenuation = @as(f64, 1.0) + @as(f64, 0.45) * aerosol_depth + @as(f64, 0.08) * cloud_depth;
    const mean_radiance = (@as(f64, 0.55) + @as(f64, 1.35) * albedo + @as(f64, 0.08) * geometry_scale) * regime_scale / attenuation;
    const mean_reflectance = std.math.clamp(mean_radiance / @max(irradiance, @as(f64, 1e-6)), @as(f64, 0.02), @as(f64, 0.98));
    const mean_noise_sigma = @as(f64, 0.02) + @as(f64, 0.03) * (@as(f64, 1.0) - albedo) + @as(f64, 0.01) * aerosol_depth + @as(f64, 0.004) * cloud_depth;
    const mean_jacobian = @as(f64, 0.04) + @as(f64, 0.015) * geometry_scale + @as(f64, 0.005) * @min(aerosol_depth + cloud_depth, @as(f64, 4.0));

    return .{
        .sample_count = sample_count,
        .wavelength_start_nm = wavelength_start_nm,
        .wavelength_end_nm = wavelength_end_nm,
        .mean_radiance = mean_radiance,
        .mean_irradiance = irradiance,
        .mean_reflectance = mean_reflectance,
        .mean_noise_sigma = mean_noise_sigma,
        .mean_jacobian = mean_jacobian,
    };
}
