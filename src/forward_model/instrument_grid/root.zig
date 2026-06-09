const std = @import("std");
const Scene = @import("../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../optical_properties/root.zig");
const common = @import("../radiative_transfer/root.zig");
const simulate_core = @import("grid_calculation/simulate.zig");

const Allocator = std.mem.Allocator;
const PreparedOpticalState = OpticsPreparation.PreparedOpticalState;
const SolveConfig = common.SolveConfig;

// root.zig --------------------------------------------------------------------------------------------------------------|
// Public facade for measurement-space spectra. Scene + prepared optics + RTM controls enter here; the dense              |
// implementation lives under grid_calculation/.                                                                          |
//                                                                                                                        |
// called by                                                                                                              |
//   src/root.zig for the public Output path                                                                              |
//   input/o2a_reference when running bundled O2 A cases                                                                  |
//                                                                                                                        |
// main paths                                                                                                             |
//   simulateProduct              -> allocate temporary ProductStorage and return an owned product                        |
//   simulateProductWithWorkspace -> reuse ProductStorage and return a borrowed view                                      |
//   simulateSummary              -> run the lightweight summary route                                                    |
//   warmProductWorkspace         -> prebuild wavelength and profile caches for repeated runs                             |
//                                                                                                                        |
// boundary                                                                                                               |
//   This file is only a facade. Spectral sampling, LABOS prefetch, convolution, reflectance assembly, and                |
//   Jacobian packing stay in grid_calculation/.                                                                          |
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

    return simulate.simulateSummary(allocator, scene, rtm_config, prepared);
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

    return simulate.simulateSummaryWithWorkspace(
        allocator,
        product_workspace,
        scene,
        rtm_config,
        prepared,
    );
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
    const view = try simulateProductWithWorkspace(
        allocator,
        &product_workspace,
        scene,
        rtm_config,
        prepared,
    );
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

    const buffers = try product_workspace.buffers(allocator, scene, rtm_config);
    const summary = try simulate_core.simulateInternal(
        allocator,
        scene,
        rtm_config,
        prepared,
        buffers,
        try product_workspace.spectralCache(allocator),
        product_workspace,
    );
    const jacobian_values = if (buffers.jacobian) |values| values else null;

    return .{
        .summary = summary,
        .wavelengths = buffers.wavelengths,
        .radiance = buffers.radiance,
        .irradiance = buffers.irradiance,
        .reflectance = buffers.reflectance,
        .jacobian = jacobian_values,
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

    _ = try product_workspace.buffers(allocator, scene, rtm_config);
    return simulate_core.warmWavelengthPlan(
        allocator,
        product_workspace,
        scene,
        prepared,
    );
}
