const std = @import("std");

pub const Engine = @import("core/Engine.zig").Engine;
pub const EngineOptions = @import("core/Engine.zig").EngineOptions;
pub const Catalog = @import("core/Catalog.zig").Catalog;
pub const PlanTemplate = @import("core/Plan.zig").Template;
pub const PreparedPlan = @import("core/Plan.zig").PreparedPlan;
pub const Plan = PreparedPlan;
pub const SolverMode = @import("core/Plan.zig").SolverMode;
pub const Request = @import("core/Request.zig").Request;
pub const DiagnosticsSpec = @import("core/diagnostics.zig").DiagnosticsSpec;
pub const Diagnostics = @import("core/diagnostics.zig").Diagnostics;
pub const Result = @import("core/Result.zig").Result;
pub const Workspace = @import("core/Workspace.zig").Workspace;
pub const LogLevel = @import("core/logging.zig").Level;
pub const LogScope = @import("core/logging.zig").Scope;
pub const LogPolicy = @import("core/logging.zig").Policy;
pub const WavelengthRange = @import("core/units.zig").WavelengthRange;
pub const AngleDeg = @import("core/units.zig").AngleDeg;
pub const Scene = @import("model/Scene.zig").Scene;
pub const SceneBlueprint = @import("model/Scene.zig").Blueprint;
pub const Atmosphere = @import("model/Atmosphere.zig").Atmosphere;
pub const DataBinding = @import("model/Binding.zig").Binding;
pub const DataBindingKind = @import("model/Binding.zig").BindingKind;
pub const Geometry = @import("model/Geometry.zig").Geometry;
pub const GeometryModel = @import("model/Geometry.zig").Model;
pub const SpectralGrid = @import("model/Spectrum.zig").SpectralGrid;
pub const SpectralWindow = @import("model/Bands.zig").SpectralWindow;
pub const SpectralBand = @import("model/Bands.zig").SpectralBand;
pub const SpectralBandSet = @import("model/Bands.zig").SpectralBandSet;
pub const Absorber = @import("model/Absorber.zig").Absorber;
pub const AbsorberSet = @import("model/Absorber.zig").AbsorberSet;
pub const Spectroscopy = @import("model/Absorber.zig").Spectroscopy;
pub const SpectroscopyMode = @import("model/Absorber.zig").SpectroscopyMode;
pub const Surface = @import("model/Surface.zig").Surface;
pub const SurfaceParameter = @import("model/Surface.zig").Parameter;
pub const Cloud = @import("model/Cloud.zig").Cloud;
pub const Aerosol = @import("model/Aerosol.zig").Aerosol;
pub const Instrument = @import("model/Instrument.zig").Instrument;
pub const InstrumentLineShape = @import("model/Instrument.zig").InstrumentLineShape;
pub const InstrumentLineShapeTable = @import("model/Instrument.zig").InstrumentLineShapeTable;
pub const OperationalReferenceGrid = @import("model/Instrument.zig").OperationalReferenceGrid;
pub const OperationalSolarSpectrum = @import("model/Instrument.zig").OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = @import("model/Instrument.zig").OperationalCrossSectionLut;
pub const ObservationModel = @import("model/ObservationModel.zig").ObservationModel;
pub const reference_data = @import("model/ReferenceData.zig");
pub const ObservationRegime = @import("model/Scene.zig").ObservationRegime;
pub const DerivativeMode = @import("model/Scene.zig").DerivativeMode;
pub const InverseProblem = @import("model/Scene.zig").InverseProblem;
pub const StateVector = @import("model/Scene.zig").StateVector;
pub const StateParameter = @import("model/Scene.zig").StateParameter;
pub const StateBounds = @import("model/Scene.zig").StateBounds;
pub const StatePrior = @import("model/Scene.zig").StatePrior;
pub const StateTransform = @import("model/Scene.zig").StateTransform;
pub const MeasurementVector = @import("model/Scene.zig").MeasurementVector;
pub const Measurement = @import("model/Scene.zig").Measurement;
pub const MeasurementMask = @import("model/Scene.zig").MeasurementMask;
pub const MeasurementErrorModel = @import("model/Scene.zig").MeasurementErrorModel;
pub const InverseCovarianceBlock = @import("model/Scene.zig").CovarianceBlock;
pub const InverseFitControls = @import("model/Scene.zig").FitControls;
pub const InverseConvergence = @import("model/Scene.zig").Convergence;
pub const LayoutRequirements = @import("model/Scene.zig").LayoutRequirements;
pub const runtime = @import("runtime/root.zig");
pub const Provenance = @import("core/provenance.zig").Provenance;
pub const transport = @import("kernels/transport/root.zig");
pub const optics = @import("kernels/optics/root.zig");
pub const linalg = @import("kernels/linalg/root.zig");
pub const spectra = @import("kernels/spectra/root.zig");
pub const PluginManifest = @import("plugins/loader/manifest.zig").PluginManifest;
pub const PluginCapabilityDecl = @import("plugins/loader/manifest.zig").CapabilityDecl;
pub const PluginProviderSelection = @import("plugins/selection.zig").ProviderSelection;
pub const plugin_internal = struct {
    pub const abi_types = @import("plugins/abi/abi_types.zig");
    pub const host_api = @import("plugins/abi/host_api.zig");
    pub const dynlib = @import("plugins/loader/dynlib.zig");
    pub const resolver = @import("plugins/loader/resolver.zig");
};
pub const exporters = @import("adapters/exporters/root.zig");
pub const ingest = @import("adapters/ingest/root.zig");
pub const canonical_config = @import("adapters/canonical_config/root.zig");
pub const mission_s5p = @import("adapters/missions/s5p/root.zig");
pub const c_api = @import("api/c/bridge.zig");
pub const zig_wrappers = @import("api/zig/wrappers.zig");
pub const retrieval_modules = struct {
    pub const common = @import("retrieval/common/root.zig");
    pub const oe = @import("retrieval/oe/root.zig");
    pub const doas = @import("retrieval/doas/root.zig");
    pub const dismas = @import("retrieval/dismas/root.zig");
};

test "engine scaffold prepares a plan and returns provenance" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{});
    defer plan.deinit();
    var workspace = engine.createWorkspace("unit");
    const request = Request.init(.{
        .id = "scene-unit",
        .spectral_grid = .{ .sample_count = 8 },
    });
    var result = try engine.execute(&plan, &workspace, request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqualStrings("scene-unit", result.scene_id);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space != null);
    try std.testing.expect(result.measurement_space_product != null);
}
