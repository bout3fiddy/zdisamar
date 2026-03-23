const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const PreparedOpticalState = @import("../optics/prepare.zig").PreparedOpticalState;
const common = @import("common.zig");
const Measurement = @import("measurement.zig");
const Simulate = @import("measurement/simulate.zig");
const Workspace = @import("measurement/workspace.zig");

const Allocator = std.mem.Allocator;

pub const types = Measurement.types;
pub const workspace = Measurement.workspace;
pub const forward_input = Measurement.forward_input;
pub const spectral_eval = Measurement.spectral_eval;
pub const test_support = Measurement.test_support;

pub const reflectance_export_name = Measurement.reflectance_export_name;
pub const fitted_reflectance_export_name = Measurement.fitted_reflectance_export_name;
pub const ProviderBindings = Measurement.ProviderBindings;
pub const MeasurementSpaceSummary = Measurement.MeasurementSpaceSummary;
pub const MeasurementSpaceProduct = Measurement.MeasurementSpaceProduct;
pub const Buffers = Workspace.Buffers;
pub const SummaryWorkspace = Workspace.SummaryWorkspace;
pub const Error = Measurement.Error;

pub fn simulate(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
    buffers: Buffers,
) !MeasurementSpaceSummary {
    return Simulate.simulate(allocator, scene, route, prepared, providers, buffers);
}

pub fn simulateSummary(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceSummary {
    return Measurement.simulateSummary(allocator, scene, route, prepared, providers);
}

pub fn simulateSummaryWithWorkspace(
    allocator: Allocator,
    summary_workspace: *SummaryWorkspace,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceSummary {
    return Measurement.simulateSummaryWithWorkspace(
        allocator,
        summary_workspace,
        scene,
        route,
        prepared,
        providers,
    );
}

pub fn simulateProduct(
    allocator: Allocator,
    scene: *const Scene,
    route: common.Route,
    prepared: *const PreparedOpticalState,
    providers: ProviderBindings,
) !MeasurementSpaceProduct {
    return Measurement.simulateProduct(allocator, scene, route, prepared, providers);
}

test "legacy measurement space shim preserves scratch entrypoints" {
    try std.testing.expect(@hasDecl(@This(), "Buffers"));
    try std.testing.expect(@hasDecl(@This(), "simulate"));
}
