const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../optical_properties/root.zig");
const common = @import("../radiative_transfer/root.zig");
const simulate_core = @import("grid_calculation/simulate.zig");

const Allocator = std.mem.Allocator;
const PreparedOpticalState = OpticsPreparation.PreparedOpticalState;
const SolveConfig = common.SolveConfig;

// root.zig --------------------------------------------------------------------------------------------------------------|
// Public facade for measurement-space spectra. Scene, PreparedOpticalState, and RTM controls enter here; the             |
// dense implementation stays under grid_calculation/. This file keeps the external flow small while allowing             |
// storage-backed callers to reuse expensive wavelength/profile/preflight work.                                           |
//                                                                                                                        |
// called by                                                                                                              |
//   src/root.zig uses simulateProductWithWorkspace for the public Output path. input/o2a_reference uses both             |
//   one-shot and workspace routes for bundled O2 A cases. optimal_estimation keeps ProductStorage across trial           |
//   states so repeated forward calls do not rebuild caches unnecessarily.                                                |
//                                                                                                                        |
// route map                                                                                                              |
//   simulateProduct              -> allocate temporary ProductStorage, run borrowed route, clone owned product           |
//   simulateProductWithWorkspace -> reuse ProductStorage and return a view borrowed from workspace buffers               |
//   simulateSummary              -> run the lightweight summary route without retaining public product arrays            |
//   simulateSummaryWithWorkspace -> summary mode with retained workspace buffers/profile caches                          |
//   warmProductWorkspace         -> prebuild buffers, wavelength plans, and profile caches for repeated runs             |
//                                                                                                                        |
// ownership boundary                                                                                                     |
//   InstrumentGridProduct owns its arrays. InstrumentGridProductView borrows ProductStorage arrays and is valid          |
//   only until the next workspace mutation or deinit. This facade preserves that distinction so API callers can          |
//   choose simple owned output or retrieval-friendly workspace reuse.                                                    |
//                                                                                                                        |
// implementation boundary                                                                                                |
//   Spectral sampling, LABOS prefetch, convolution, reflectance assembly, cache invalidation, and Jacobian packing       |
//   stay in grid_calculation/. This file re-exports the stable types and forwards into those modules.                    |
// -----------------------------------------------------------------------------------------------------------------------|

pub const types = @import("grid_calculation/types.zig");
pub const storage = @import("grid_calculation/storage.zig");
pub const cache = @import("grid_calculation/cache.zig");
pub const forward_input = @import("grid_calculation/forward_input.zig");
pub const spectral_eval = @import("grid_calculation/spectral_eval.zig");
pub const simulate = @import("grid_calculation/simulate.zig");

pub const reflectance_export_name = types.reflectance_export_name;
pub const fitted_reflectance_export_name = types.fitted_reflectance_export_name;
pub const InstrumentGridSummary = types.InstrumentGridSummary;
pub const InstrumentGridProduct = types.InstrumentGridProduct;
pub const InstrumentGridProductView = types.InstrumentGridProductView;
pub const ProductStorage = storage.ProductStorage;
pub const Error = storage.Error;

// ProductWorkspaceRequest -----------------------------------------------------------------------------------------------|
// Borrowed public-facade inputs for a product run backed by reusable ProductStorage.                                     |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 104 B (0.102 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] product_workspace : *ProductStorage                                                                         |
// [  8.. 15] scene             : *const Scene                                                                            |
// [ 16.. 95] rtm_config        : SolveConfig                                                                             |
// [ 96..103] prepared          : *const PreparedOpticalState                                                             |
//                                                                                                                        |
// referenced storage: ProductStorage owns reusable rows; scene and prepared are read-only borrowed inputs.               |
// unused bits: inherited from nested SolveConfig layout                                                                  |
// cache span: 2 cache lines at 64 B per line                                                                             |
// footprint: per instance = 104 B (0.102 KiB); total excludes retained workspace storage                                 |
const ProductWorkspaceRequest = struct {
    product_workspace: *ProductStorage,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
};
// -----------------------------------------------------------------------------------------------------------------------|

// WarmProductWorkspaceRequest -------------------------------------------------------------------------------------------|
// Borrowed public-facade inputs used to prebuild reusable product buffers and plan caches.                               |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 104 B (0.102 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0..  7] product_workspace : *ProductStorage                                                                         |
// [  8.. 15] scene             : *const Scene                                                                            |
// [ 16.. 95] rtm_config        : SolveConfig                                                                             |
// [ 96..103] prepared          : *const PreparedOpticalState                                                             |
//                                                                                                                        |
// referenced storage: ProductStorage owns reusable rows; scene and prepared are read-only borrowed inputs.               |
// unused bits: inherited from nested SolveConfig layout                                                                  |
// cache span: 2 cache lines at 64 B per line                                                                             |
// footprint: per instance = 104 B (0.102 KiB); total excludes retained workspace storage                                 |
const WarmProductWorkspaceRequest = struct {
    product_workspace: *ProductStorage,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
};
// -----------------------------------------------------------------------------------------------------------------------|

pub fn simulateSummary(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
) !InstrumentGridSummary {
    // simulateSummary ---------------------------------------------------------------------------------------------------|
    // Run the summary route with temporary storage. Use this when the caller only needs scalar mean values               |
    // and does not want to retain product arrays.                                                                        |
    // -------------------------------------------------------------------------------------------------------------------|

    const request = simulate_core.SummaryRequest{
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
    return simulate_core.simulateSummaryFromRequest(allocator, &request);
}

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    product_workspace: *ProductStorage,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
) !InstrumentGridSummary {
    // simulateSummaryWithWorkspace --------------------------------------------------------------------------------------|
    // Run summary mode while reusing ProductStorage. The workspace keeps buffers, wavelength plans, and                  |
    // profile caches warm across repeated retrieval iterations.                                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    const request = simulate_core.SummaryWorkspaceRequest{
        .storage = product_workspace,
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
    return simulate_core.simulateSummaryWithWorkspaceFromRequest(allocator, &request);
}

pub fn simulateProduct(
    allocator: Allocator,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
) !InstrumentGridProduct {
    // simulateProduct ---------------------------------------------------------------------------------------------------|
    // Convenience owner path. Allocate a short-lived ProductStorage, run the borrowed product route, then                |
    // clone the result into caller-owned arrays before returning.                                                        |
    // -------------------------------------------------------------------------------------------------------------------|

    var product_workspace: ProductStorage = .{};
    defer product_workspace.deinit(allocator);
    const request = ProductWorkspaceRequest{
        .product_workspace = &product_workspace,
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
    const view = try simulateProductWithWorkspaceFromRequest(allocator, &request);
    return view.toOwned(allocator);
}

pub fn simulateProductWithWorkspace(
    allocator: Allocator,
    product_workspace: *ProductStorage,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
) !InstrumentGridProductView {
    // simulateProductWithWorkspace --------------------------------------------------------------------------------------|
    // Main facade route. ProductStorage owns reusable buffers; the returned view borrows those buffers until             |
    // the next workspace mutation or deinit.                                                                             |
    //                                                                                                                    |
    // flow                                                                                                               |
    //   ProductStorage.buffers -> simulateInternal -> borrowed InstrumentGridProductView                                 |
    //                                                                                                                    |
    // output                                                                                                             |
    //   Measurement-space arrays are stored in the workspace. Prepared optical-property scalars are copied               |
    //   into the view so downstream output code can report the physical state used for the spectrum.                     |
    // -------------------------------------------------------------------------------------------------------------------|

    const request = ProductWorkspaceRequest{
        .product_workspace = product_workspace,
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
    return simulateProductWithWorkspaceFromRequest(allocator, &request);
}

fn simulateProductWithWorkspaceFromRequest(
    allocator: Allocator,
    request: *const ProductWorkspaceRequest,
) !InstrumentGridProductView {
    // simulateProductWithWorkspaceFromRequest ---------------------------------------------------------------------------|
    // Run the product route from one borrowed facade request. The workspace owns reusable buffers and the                |
    // returned product view borrows those buffers until the workspace is mutated or released.                            |
    // -------------------------------------------------------------------------------------------------------------------|

    const buffer_request = storage.BufferHintRequest{
        .scene = request.scene,
        .rtm_config = &request.rtm_config,
    };
    const buffers = try request.product_workspace.buffersFromHint(allocator, &buffer_request);
    const simulation_request = simulate_core.SimulationRunRequest{
        .scene = request.scene,
        .rtm_config = request.rtm_config,
        .prepared = request.prepared,
        .buffers = buffers,
        .evaluation_cache = try request.product_workspace.spectralCache(allocator),
        .wavelength_plan_storage = request.product_workspace,
    };
    const summary = try simulate_core.simulateInternal(allocator, &simulation_request);
    const jacobian_values = if (buffers.jacobian) |values| values else null;

    return .{
        .summary = summary,
        .wavelengths = buffers.wavelengths,
        .radiance = buffers.radiance,
        .irradiance = buffers.irradiance,
        .reflectance = buffers.reflectance,
        .jacobian = jacobian_values,
        .jacobian_state_mask = buffers.jacobian_state_mask,
        .effective_air_mass_factor = request.prepared.effective_air_mass_factor,
        .effective_single_scatter_albedo = request.prepared.effective_single_scatter_albedo,
        .effective_temperature_k = request.prepared.effective_temperature_k,
        .effective_pressure_hpa = request.prepared.effective_pressure_hpa,
        .gas_optical_depth = request.prepared.gas_optical_depth,
        .cia_optical_depth = request.prepared.cia_optical_depth,
        .aerosol_optical_depth = request.prepared.aerosol_optical_depth,
        .total_optical_depth = request.prepared.total_optical_depth,
        .depolarization_factor = request.prepared.depolarization_factor,
        .d_optical_depth_d_temperature = request.prepared.d_optical_depth_d_temperature,
    };
}

pub fn warmProductWorkspace(
    allocator: Allocator,
    product_workspace: *ProductStorage,
    scene: *const Scene,
    rtm_config: SolveConfig,
    prepared: *const PreparedOpticalState,
) !void {
    // warmProductWorkspace ----------------------------------------------------------------------------------------------|
    // Prepare reusable buffers and wavelength/profile caches without producing a spectrum. This moves first              |
    // use allocation and plan construction out of the next measured run.                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    const request = WarmProductWorkspaceRequest{
        .product_workspace = product_workspace,
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
    return warmProductWorkspaceFromRequest(allocator, &request);
}

fn warmProductWorkspaceFromRequest(
    allocator: Allocator,
    request: *const WarmProductWorkspaceRequest,
) !void {
    // warmProductWorkspaceFromRequest -----------------------------------------------------------------------------------|
    // Prebuild buffers and retained wavelength-plan state from one borrowed facade request.                              |
    // -------------------------------------------------------------------------------------------------------------------|

    const buffer_request = storage.BufferHintRequest{
        .scene = request.scene,
        .rtm_config = &request.rtm_config,
    };
    _ = try request.product_workspace.buffersFromHint(allocator, &buffer_request);
    const warm_request = simulate_core.WarmWavelengthPlanRequest{
        .storage = request.product_workspace,
        .scene = request.scene,
        .prepared = request.prepared,
    };
    return simulate_core.warmWavelengthPlanFromRequest(allocator, &warm_request);
}
