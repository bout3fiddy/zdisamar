pub const internal = @import("grid_calculation/internal.zig");
pub const types = @import("grid_calculation/types.zig");
pub const workspace = @import("grid_calculation/workspace.zig");
pub const cache = @import("grid_calculation/cache.zig");
pub const forward_input = @import("grid_calculation/forward_input.zig");
pub const spectral_eval = @import("grid_calculation/spectral_eval.zig");
pub const product = @import("grid_calculation/product.zig");
pub const simulate = @import("grid_calculation/simulate.zig");

pub const reflectance_export_name = types.reflectance_export_name;
pub const fitted_reflectance_export_name = types.fitted_reflectance_export_name;
pub const ProviderBindings = types.ProviderBindings;
pub const MeasurementSpaceSummary = types.MeasurementSpaceSummary;
pub const MeasurementSpaceProduct = types.MeasurementSpaceProduct;
pub const MeasurementSpaceProductView = types.MeasurementSpaceProductView;
pub const SummaryWorkspace = workspace.SummaryWorkspace;
pub const ProductWorkspace = workspace.ProductWorkspace;
pub const Error = workspace.Error;

pub fn simulateSummary(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceSummary {
    return simulate.simulateSummary(allocator, scene, route, prepared, providers);
}

pub fn simulateSummaryWithWorkspace(
    allocator: @import("std").mem.Allocator,
    summary_workspace: *SummaryWorkspace,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceSummary {
    return simulate.simulateSummaryWithWorkspace(
        allocator,
        summary_workspace,
        scene,
        route,
        prepared,
        providers,
    );
}

pub fn simulateProduct(
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceProduct {
    return product.simulateProduct(allocator, scene, route, prepared, providers);
}

pub fn simulateProductWithWorkspace(
    allocator: @import("std").mem.Allocator,
    product_workspace: *ProductWorkspace,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceProductView {
    return product.simulateProductWithWorkspace(
        allocator,
        product_workspace,
        scene,
        route,
        prepared,
        providers,
    );
}
