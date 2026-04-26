//! Purpose:
//!   Materialize full measurement-space products with owned output arrays.

const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const simulate_core = @import("simulate.zig");
const Types = @import("types.zig");
const Workspace = @import("workspace.zig");

const Allocator = std.mem.Allocator;

pub fn simulateProduct(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
) Workspace.Error!Types.MeasurementSpaceProduct {
    return simulateProductWithProfile(
        allocator,
        scene,
        route,
        prepared,
        providers,
        null,
    );
}

pub fn simulateProductWithProfile(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    forward_profile: ?*Types.ForwardProfile,
) Workspace.Error!Types.MeasurementSpaceProduct {
    var workspace: Workspace.ProductWorkspace = .{};
    defer workspace.deinit(allocator);
    const view = try simulateProductWithWorkspace(
        allocator,
        &workspace,
        scene,
        route,
        prepared,
        providers,
        forward_profile,
    );
    return view.toOwned(allocator);
}

pub fn simulateProductWithWorkspace(
    allocator: Allocator,
    workspace: *Workspace.ProductWorkspace,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    providers: Types.ProviderBindings,
    forward_profile: ?*Types.ForwardProfile,
) Workspace.Error!Types.MeasurementSpaceProductView {
    const buffers = try workspace.buffers(allocator, scene, route, providers);
    const summary = try simulate_core.simulateInternal(
        allocator,
        scene,
        route,
        prepared,
        providers,
        buffers,
        try workspace.spectralCache(allocator),
        forward_profile,
    );
    return .{
        .summary = summary,
        .wavelengths = buffers.wavelengths,
        .radiance = buffers.radiance,
        .irradiance = buffers.irradiance,
        .reflectance = buffers.reflectance,
        .noise_sigma = if (buffers.noise_sigma) |sigma| sigma else &.{},
        .radiance_noise_sigma = if (buffers.radiance_noise_sigma) |sigma| sigma else &.{},
        .irradiance_noise_sigma = if (buffers.irradiance_noise_sigma) |sigma| sigma else &.{},
        .reflectance_noise_sigma = if (buffers.reflectance_noise_sigma) |sigma| sigma else &.{},
        .jacobian = if (buffers.jacobian) |values| values else null,
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
