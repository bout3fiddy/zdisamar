const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../optical_properties/root.zig");
const common = @import("../radiative_transfer/root.zig");
const simulate_core = @import("grid_calculation/simulate.zig");

pub const types = @import("grid_calculation/types.zig");
pub const storage = @import("grid_calculation/storage.zig");
pub const cache = @import("grid_calculation/cache.zig");
pub const forward_input = @import("grid_calculation/forward_input.zig");
pub const spectral_eval = @import("grid_calculation/spectral_eval.zig");
pub const simulate = @import("grid_calculation/simulate.zig");

pub const reflectance_export_name = types.reflectance_export_name;
pub const fitted_reflectance_export_name = types.fitted_reflectance_export_name;
pub const Implementations = types.Implementations;
pub const InstrumentGridSummary = types.InstrumentGridSummary;
pub const InstrumentGridProduct = types.InstrumentGridProduct;
pub const InstrumentGridProductView = types.InstrumentGridProductView;
pub const SummaryStorage = storage.SummaryStorage;
pub const ProductStorage = storage.ProductStorage;
pub const Error = storage.Error;

pub fn simulateSummary(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridSummary {
    return simulate.simulateSummary(allocator, scene, route, prepared, implementations);
}

pub fn simulateSummaryWithWorkspace(
    allocator: @import("std").mem.Allocator,
    summary_workspace: *SummaryStorage,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridSummary {
    return simulate.simulateSummaryWithWorkspace(
        allocator,
        summary_workspace,
        scene,
        route,
        prepared,
        implementations,
    );
}

pub fn simulateProduct(
    allocator: std.mem.Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridProduct {
    var product_workspace: ProductStorage = .{};
    defer product_workspace.deinit(allocator);
    const view = try simulateProductWithWorkspace(
        allocator,
        &product_workspace,
        scene,
        route,
        prepared,
        implementations,
    );
    return view.toOwned(allocator);
}

pub fn simulateProductWithWorkspace(
    allocator: std.mem.Allocator,
    product_workspace: *ProductStorage,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridProductView {
    const buffers = try product_workspace.buffers(allocator, scene, route);
    const summary = try simulate_core.simulateInternal(
        allocator,
        scene,
        route,
        prepared,
        implementations,
        buffers,
        try product_workspace.spectralCache(allocator),
        product_workspace,
    );
    return .{
        .summary = summary,
        .wavelengths = buffers.wavelengths,
        .radiance = buffers.radiance,
        .irradiance = buffers.irradiance,
        .reflectance = buffers.reflectance,
        .jacobian = if (buffers.jacobian) |values| values else null,
        .jacobian_state_mask = buffers.jacobian_state_mask,
        .effective_air_mass_factor = prepared.effective_air_mass_factor,
        .effective_single_scatter_albedo = prepared.effective_single_scatter_albedo,
        .effective_temperature_k = prepared.effective_temperature_k,
        .effective_pressure_hpa = prepared.effective_pressure_hpa,
        .gas_optical_depth = prepared.gas_optical_depth,
        .cia_optical_depth = prepared.cia_optical_depth,
        .aerosol_optical_depth = prepared.aerosol_optical_depth,
        .total_optical_depth = prepared.total_optical_depth,
        .depolarization_factor = prepared.depolarization_factor,
        .d_optical_depth_d_temperature = prepared.d_optical_depth_d_temperature,
    };
}

pub fn warmProductWorkspace(
    allocator: std.mem.Allocator,
    product_workspace: *ProductStorage,
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    implementations: Implementations,
) !void {
    _ = try product_workspace.buffers(allocator, scene, route);
    return simulate_core.warmWavelengthPlan(
        allocator,
        product_workspace,
        scene,
        prepared,
        implementations,
    );
}
