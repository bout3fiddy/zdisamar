pub const internal = @import("measurement/internal.zig");
pub const types = @import("measurement/types.zig");
pub const workspace = @import("measurement/workspace.zig");
pub const cache = @import("measurement/cache.zig");
pub const forward_input = @import("measurement/forward_input.zig");
pub const spectral_eval = @import("measurement/spectral_eval.zig");
pub const product = @import("measurement/product.zig");
pub const simulate = @import("measurement/simulate.zig");

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
    scene: *const @import("../../model/Scene.zig").Scene,
    route: @import("common.zig").Route,
    prepared: *const @import("../optics/preparation.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceSummary {
    return simulate.simulateSummary(allocator, scene, route, prepared, providers);
}

pub fn simulateSummaryWithWorkspace(
    allocator: @import("std").mem.Allocator,
    summary_workspace: *SummaryWorkspace,
    scene: *const @import("../../model/Scene.zig").Scene,
    route: @import("common.zig").Route,
    prepared: *const @import("../optics/preparation.zig").PreparedOpticalState,
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
    scene: *const @import("../../model/Scene.zig").Scene,
    route: @import("common.zig").Route,
    prepared: *const @import("../optics/preparation.zig").PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceProduct {
    return product.simulateProduct(allocator, scene, route, prepared, providers);
}

pub fn simulateProductWithWorkspace(
    allocator: @import("std").mem.Allocator,
    product_workspace: *ProductWorkspace,
    scene: *const @import("../../model/Scene.zig").Scene,
    route: @import("common.zig").Route,
    prepared: *const @import("../optics/preparation.zig").PreparedOpticalState,
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

test {
    _ = types;
    _ = workspace;
    _ = cache;
    _ = forward_input;
    _ = spectral_eval;
    _ = product;
    _ = simulate;
}
