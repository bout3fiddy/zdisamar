//! Purpose:
//!   Public Zig entrypoint for the typed radiative-transfer scaffold.
//!
//! Physics:
//!   Re-exports the canonical scene, request/result, retrieval, and measurement-domain types
//!   that make up the engine-facing scientific API.
//!
//! Vendor:
//!   `public scaffold surface`
//!
//! Design:
//!   Keep the stable public surface here while runtime internals, plugin ABI details, and test
//!   helpers stay behind explicit opt-in imports.
//!
//! Invariants:
//!   Public consumers see typed `Engine -> Plan -> Workspace -> Request -> Result` contracts and
//!   do not gain implicit access to runtime or native-plugin internals.
//!
//! Validation:
//!   The root-level import tests in this file verify the intended public/exported surface.

const std = @import("std");
const build_options = @import("build_options");

pub const Engine = @import("core/Engine.zig").Engine;
pub const EngineOptions = @import("core/Engine.zig").EngineOptions;
pub const Catalog = @import("core/Catalog.zig").Catalog;
pub const PlanTemplate = @import("core/Plan.zig").Template;
pub const PreparedPlan = @import("core/Plan.zig").PreparedPlan;
pub const SolverMode = @import("core/Plan.zig").SolverMode;
pub const ExecutionMode = @import("core/execution_mode.zig").ExecutionMode;
pub const LutMode = @import("core/lut_controls.zig").Mode;
pub const LutControls = @import("core/lut_controls.zig").Controls;
pub const LutCompatibilityKey = @import("core/lut_controls.zig").CompatibilityKey;
pub const Request = @import("core/Request.zig").Request;
pub const BorrowedMeasurementProduct = @import("core/Request.zig").Request.BorrowedMeasurementProduct;
pub const MeasuredSpectrum = @import("core/Request.zig").Request.MeasuredSpectrum;
pub const MeasuredInput = @import("core/Request.zig").Request.MeasuredInput;
pub const MeasurementBinding = @import("core/Request.zig").Request.MeasurementBinding;
pub const RequestedProductKind = @import("core/Request.zig").Request.RequestedProductKind;
pub const RequestedProduct = @import("core/Request.zig").Request.RequestedProduct;
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
pub const InstrumentId = @import("model/Instrument.zig").Id;
pub const InstrumentLineShape = @import("model/Instrument.zig").InstrumentLineShape;
pub const InstrumentLineShapeTable = @import("model/Instrument.zig").InstrumentLineShapeTable;
pub const OperationalReferenceGrid = @import("model/Instrument.zig").OperationalReferenceGrid;
pub const OperationalSolarSpectrum = @import("model/Instrument.zig").OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = @import("model/Instrument.zig").OperationalCrossSectionLut;
pub const OperationalBandSupport = @import("model/Instrument.zig").Instrument.OperationalBandSupport;
pub const ObservationModel = @import("model/ObservationModel.zig").ObservationModel;
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
pub const MeasurementQuantity = @import("model/Measurement.zig").Quantity;
pub const MeasurementMask = @import("model/Scene.zig").MeasurementMask;
pub const MeasurementErrorModel = @import("model/Scene.zig").MeasurementErrorModel;
pub const InverseCovarianceBlock = @import("model/Scene.zig").CovarianceBlock;
pub const InverseFitControls = @import("model/Scene.zig").FitControls;
pub const InverseConvergence = @import("model/Scene.zig").Convergence;
pub const LayoutRequirements = @import("model/Scene.zig").LayoutRequirements;
pub const Provenance = @import("core/provenance.zig").Provenance;
pub const exporters = @import("adapters/exporters/root.zig");
pub const ingest = @import("adapters/ingest/root.zig");
pub const canonical_config = @import("adapters/canonical_config/root.zig");
pub const mission_s5p = @import("adapters/missions/s5p/root.zig");

pub const test_support = if (build_options.enable_test_support) struct {
    pub const runtime = @import("runtime/root.zig");
    pub const c_api = @import("api/c/bridge.zig");
    pub const zig_wrappers = @import("api/zig/wrappers.zig");
    pub const retrieval = @import("retrieval/root.zig");
    pub const builtin_exporters_catalog = @import("plugins/builtin/exporters/catalog.zig");
    pub const exporter_spec = @import("adapters/exporters/spec.zig");
    pub const reference_data = @import("model/ReferenceData.zig");
    pub const kernels = struct {
        pub const transport = @import("kernels/transport/root.zig");
        pub const optics = @import("kernels/optics/root.zig");
        pub const linalg = @import("kernels/linalg/root.zig");
        pub const spectra = @import("kernels/spectra/root.zig");
    };

    pub const plugin_internal = struct {
        pub const abi_types = @import("plugins/abi/abi_types.zig");
        pub const host_api = @import("plugins/abi/host_api.zig");
        pub const dynlib = @import("plugins/loader/dynlib.zig");
        pub const resolver = @import("plugins/loader/resolver.zig");
        pub const manifest = @import("plugins/loader/manifest.zig");
        pub const providers = @import("plugins/providers/root.zig");
    };
} else struct {};

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
    var result = try engine.execute(&plan, &workspace, &request);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(Result.Status.success, result.status);
    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqual(ExecutionMode.synthetic, result.execution_mode);
    try std.testing.expectEqualStrings("scene-unit", result.scene_id);
    try std.testing.expectEqualStrings("builtin.dispatcher", result.provenance.solver_route);
    try std.testing.expect(result.measurement_space != null);
    try std.testing.expect(result.measurement_space_product != null);
}

test "public root does not re-export runtime or ABI internals by default" {
    try std.testing.expect(!@hasDecl(@This(), "runtime"));
    try std.testing.expect(@hasDecl(@This(), "test_support"));
    try std.testing.expect(!@hasDecl(@This().test_support, "runtime"));
    try std.testing.expect(!@hasDecl(@This(), "_internal"));
    try std.testing.expect(!@hasDecl(@This(), "plugin_internal"));
    try std.testing.expect(!@hasDecl(@This(), "c_api"));
    try std.testing.expect(!@hasDecl(@This(), "zig_wrappers"));
    try std.testing.expect(!@hasDecl(@This(), "retrieval_modules"));
    try std.testing.expect(!@hasDecl(@This(), "transport"));
    try std.testing.expect(!@hasDecl(@This(), "optics"));
    try std.testing.expect(!@hasDecl(@This(), "spectra"));
    try std.testing.expect(!@hasDecl(@This(), "reference_data"));
    try std.testing.expect(!@hasDecl(@This(), "PluginManifest"));
    try std.testing.expect(!@hasDecl(@This(), "PluginCapabilityDecl"));
    try std.testing.expect(!@hasDecl(@This(), "PluginProviderSelection"));
}
