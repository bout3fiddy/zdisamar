pub const internal = @import("grid_calculation/internal.zig");
pub const types = @import("grid_calculation/types.zig");
pub const storage = @import("grid_calculation/storage.zig");
pub const cache = @import("grid_calculation/cache.zig");
pub const forward_input = @import("grid_calculation/forward_input.zig");
pub const spectral_eval = @import("grid_calculation/spectral_eval.zig");
pub const product = @import("grid_calculation/product.zig");
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
    allocator: @import("std").mem.Allocator,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridProduct {
    return product.simulateProduct(allocator, scene, route, prepared, implementations);
}

pub fn simulateProductWithWorkspace(
    allocator: @import("std").mem.Allocator,
    product_workspace: *ProductStorage,
    scene: *const @import("../../input/Scene.zig").Scene,
    route: @import("../radiative_transfer/root.zig").Route,
    prepared: *const @import("../optical_properties/root.zig").PreparedOpticalState,
    implementations: Implementations,
) !InstrumentGridProductView {
    return product.simulateProductWithWorkspace(
        allocator,
        product_workspace,
        scene,
        route,
        prepared,
        implementations,
    );
}
