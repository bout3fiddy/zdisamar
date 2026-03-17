const std = @import("std");
const yaml = @import("yaml.zig");
const fields = @import("document_fields.zig");
const yaml_helpers = @import("document_yaml_helpers.zig");
const PlanTemplate = @import("../../core/Plan.zig").Template;
const SolverMode = @import("../../core/Plan.zig").SolverMode;
const DiagnosticsSpec = @import("../../core/diagnostics.zig").DiagnosticsSpec;
const Binding = @import("../../model/Binding.zig").Binding;
const BindingKind = @import("../../model/Binding.zig").BindingKind;
const SpectralGrid = @import("../../model/Spectrum.zig").SpectralGrid;
const SpectralWindow = @import("../../model/Bands.zig").SpectralWindow;
const SpectralBand = @import("../../model/Bands.zig").SpectralBand;
const SpectralBandSet = @import("../../model/Bands.zig").SpectralBandSet;
const Atmosphere = @import("../../model/Atmosphere.zig").Atmosphere;
const Geometry = @import("../../model/Geometry.zig").Geometry;
const GeometryModel = @import("../../model/Geometry.zig").Model;
const Absorber = @import("../../model/Absorber.zig").Absorber;
const AbsorberSet = @import("../../model/Absorber.zig").AbsorberSet;
const Spectroscopy = @import("../../model/Absorber.zig").Spectroscopy;
const SpectroscopyMode = @import("../../model/Absorber.zig").SpectroscopyMode;
const Surface = @import("../../model/Surface.zig").Surface;
const SurfaceParameter = @import("../../model/Surface.zig").Parameter;
const Cloud = @import("../../model/Cloud.zig").Cloud;
const Aerosol = @import("../../model/Aerosol.zig").Aerosol;
const ObservationModel = @import("../../model/ObservationModel.zig").ObservationModel;
const ObservationRegime = @import("../../model/ObservationModel.zig").ObservationRegime;
const InstrumentId = @import("../../model/Instrument.zig").Id;
const BuiltinLineShapeKind = @import("../../model/Instrument.zig").BuiltinLineShapeKind;
const Scene = @import("../../model/Scene.zig").Scene;
const InverseProblem = @import("../../model/InverseProblem.zig").InverseProblem;
const DerivativeMode = @import("../../model/InverseProblem.zig").DerivativeMode;
const CovarianceBlock = @import("../../model/InverseProblem.zig").CovarianceBlock;
const FitControls = @import("../../model/InverseProblem.zig").FitControls;
const Convergence = @import("../../model/InverseProblem.zig").Convergence;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const MeasurementMask = @import("../../model/Measurement.zig").SpectralMask;
const MeasurementErrorModel = @import("../../model/Measurement.zig").ErrorModel;
const StateVector = @import("../../model/StateVector.zig").StateVector;
const StateParameter = @import("../../model/StateVector.zig").Parameter;
const StateTarget = @import("../../model/StateVector.zig").Target;
const StateTransform = @import("../../model/StateVector.zig").Transform;
const StatePrior = @import("../../model/StateVector.zig").Prior;
const StateBounds = @import("../../model/StateVector.zig").Bounds;
const ReferenceData = @import("../../model/ReferenceData.zig");
const reference_assets = @import("../ingest/reference_assets.zig");
const spectral_ascii = @import("../ingest/spectral_ascii.zig");
const spectral_ascii_runtime = @import("../ingest/spectral_ascii_runtime.zig");
const spectra_grid = @import("../../kernels/spectra/grid.zig");
const ExportFormat = @import("../exporters/format.zig").ExportFormat;
const Allocator = std.mem.Allocator;
const parseAssetKind = fields.parseAssetKind;
const parseIngestAdapter = fields.parseIngestAdapter;
const parseSolverMode = fields.parseSolverMode;
const parseDerivativeMode = fields.parseDerivativeMode;
const parseGeometryModel = fields.parseGeometryModel;
const parseObservationRegime = fields.parseObservationRegime;
const parseSamplingMode = fields.parseSamplingMode;
const parseNoiseModelKind = fields.parseNoiseModelKind;
const parseSpectroscopyMode = fields.parseSpectroscopyMode;
const parseSurfaceKind = fields.parseSurfaceKind;
const parseStateTransform = fields.parseStateTransform;
const parseProductKind = fields.parseProductKind;
const parseExportFormat = fields.parseExportFormat;
const normalizeTransportProvider = fields.normalizeTransportProvider;
const normalizeRetrievalProvider = fields.normalizeRetrievalProvider;
const normalizeSurfaceProvider = fields.normalizeSurfaceProvider;
const normalizeInstrumentProvider = fields.normalizeInstrumentProvider;
const resolveInputPath = yaml_helpers.resolveInputPath;
const pathExists = yaml_helpers.pathExists;
const cloneMapSkipping = yaml_helpers.cloneMapSkipping;
const ensureKnownFields = yaml_helpers.ensureKnownFields;
const containsString = yaml_helpers.containsString;
const expectMap = yaml_helpers.expectMap;
const expectSeq = yaml_helpers.expectSeq;
const expectString = yaml_helpers.expectString;
const expectBool = yaml_helpers.expectBool;
const expectI64 = yaml_helpers.expectI64;
const expectU64 = yaml_helpers.expectU64;
const expectF64 = yaml_helpers.expectF64;
const requiredField = yaml_helpers.requiredField;
const mapGet = yaml_helpers.mapGet;

pub const Error = error{
    UnknownField,
    MissingField,
    InvalidType,
    InvalidValue,
    InvalidReference,
    ReferenceCycle,
    MissingTemplate,
    MissingStage,
    MissingAsset,
    MissingIngest,
    MissingIngestOutput,
    MissingStageProduct,
    UnsupportedIngestAdapter,
    UnsupportedProvider,
    UnsupportedMultiplicity,
};

pub const Metadata = struct {
    id: []const u8 = "",
    workspace: []const u8 = "",
    description: []const u8 = "",
};

pub const AssetKind = fields.AssetKind;

pub const Asset = struct {
    name: []const u8,
    kind: AssetKind,
    format: []const u8,
    path: []const u8,
    resolved_path: []const u8,
};

pub const IngestAdapter = fields.IngestAdapter;

pub const Ingest = struct {
    name: []const u8,
    adapter: IngestAdapter,
    asset_name: []const u8,
    loaded_spectra: spectral_ascii.LoadedSpectra,
};

pub const ProductKind = fields.ProductKind;

pub const Product = struct {
    name: []const u8,
    kind: ProductKind,
    observable: ?MeasurementQuantity = null,
    apply_noise: bool = false,
};

pub const OutputSpec = struct {
    from: []const u8,
    format: ExportFormat,
    destination_uri: []const u8,
    include_provenance: bool = false,
};

pub const SyntheticRetrievalPolicy = struct {
    warn_if_models_are_identical: bool = true,
    require_explicit_acknowledgement_if_identical: bool = false,
};

pub const Validation = struct {
    strict_unknown_fields: bool = true,
    require_resolved_assets: bool = false,
    require_resolved_stage_references: bool = false,
    synthetic_retrieval: SyntheticRetrievalPolicy = .{},
};

pub const WarningKind = enum {
    identical_synthetic_models,
};

pub const Warning = struct {
    kind: WarningKind,
    message: []const u8,
};

pub const StageKind = enum {
    simulation,
    retrieval,
};

pub const Stage = struct {
    kind: StageKind,
    plan: PlanTemplate,
    scene: Scene,
    inverse: ?InverseProblem = null,
    products: []const Product = &[_]Product{},
    diagnostics: DiagnosticsSpec = .{},
    algorithm_name: []const u8 = "",
    algorithm_damping: []const u8 = "",
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
};

pub const Document = struct {
    owner_allocator: Allocator,
    arena_state: *std.heap.ArenaAllocator,
    source_path: []const u8,
    source_dir: []const u8,
    source_bytes: []const u8,
    root: yaml.Value,

    pub fn parseFile(allocator: Allocator, path: []const u8) !Document {
        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const absolute_path = try std.fs.cwd().realpathAlloc(arena, path);
        const file = try std.fs.openFileAbsolute(absolute_path, .{});
        defer file.close();

        const bytes = try file.readToEndAlloc(arena, 8 * 1024 * 1024);
        const root = try yaml.parse(arena, bytes);

        return .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = absolute_path,
            .source_dir = try arena.dupe(u8, std.fs.path.dirname(absolute_path) orelse "."),
            .source_bytes = bytes,
            .root = root,
        };
    }

    pub fn parse(allocator: Allocator, source_name: []const u8, base_dir: []const u8, source_bytes: []const u8) !Document {
        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const bytes = try arena.dupe(u8, source_bytes);
        const root = try yaml.parse(arena, bytes);

        return .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = try arena.dupe(u8, source_name),
            .source_dir = try arena.dupe(u8, base_dir),
            .source_bytes = bytes,
            .root = root,
        };
    }

    pub fn deinit(self: *Document) void {
        self.arena_state.deinit();
        self.owner_allocator.destroy(self.arena_state);
        self.* = undefined;
    }

    pub fn resolve(self: *const Document, allocator: Allocator) !*ResolvedExperiment {
        const resolved = try allocator.create(ResolvedExperiment);
        errdefer allocator.destroy(resolved);

        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const root_map = try expectMap(self.root);
        const validation = try decodeValidation(arena, mapGet(root_map, "validation"), decodeStrictUnknownFields(root_map));
        const strict = validation.strict_unknown_fields;
        try ensureKnownFields(root_map, &.{
            "schema_version",
            "metadata",
            "inputs",
            "templates",
            "experiment",
            "outputs",
            "validation",
        }, strict);

        const schema_version = try expectI64(requiredField(root_map, "schema_version"));
        if (schema_version != 1) return Error.InvalidValue;

        const metadata = try decodeMetadata(arena, mapGet(root_map, "metadata"), strict);
        const assets = try decodeAssets(arena, self, root_map, strict);
        const ingests = try decodeIngests(arena, root_map, assets, strict);

        const experiment_value = requiredField(root_map, "experiment");
        const experiment_map = try expectMap(experiment_value);
        try ensureKnownFields(experiment_map, &.{ "simulation", "retrieval" }, strict);

        var resolution_context = ResolveContext{
            .allocator = arena,
            .document = self,
            .root = root_map,
            .validation = validation,
            .strict_unknown_fields = strict,
            .assets = assets,
            .ingests = ingests,
        };

        const simulation = try resolution_context.resolveStage(.simulation, mapGet(experiment_map, "simulation"), null);
        const retrieval = try resolution_context.resolveStage(.retrieval, mapGet(experiment_map, "retrieval"), if (simulation) |value| &value.stage else null);
        const outputs = try decodeOutputs(
            arena,
            mapGet(root_map, "outputs"),
            simulation,
            retrieval,
            strict,
            validation,
        );
        const warnings = try buildWarnings(arena, validation, simulation, retrieval);

        resolved.* = .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = try arena.dupe(u8, self.source_path),
            .metadata = metadata,
            .assets = assets,
            .ingests = ingests,
            .simulation = if (simulation) |value| &value.stage else null,
            .retrieval = if (retrieval) |value| &value.stage else null,
            .outputs = outputs,
            .validation = validation,
            .warnings = warnings,
        };
        return resolved;
    }
};

pub const ResolvedExperiment = struct {
    owner_allocator: Allocator,
    arena_state: *std.heap.ArenaAllocator,
    source_path: []const u8,
    metadata: Metadata = .{},
    assets: []const Asset = &[_]Asset{},
    ingests: []const Ingest = &[_]Ingest{},
    simulation: ?*const Stage = null,
    retrieval: ?*const Stage = null,
    outputs: []const OutputSpec = &[_]OutputSpec{},
    validation: Validation = .{},
    warnings: []const Warning = &[_]Warning{},

    pub fn deinit(self: *ResolvedExperiment) void {
        const owner_allocator = self.owner_allocator;
        self.arena_state.deinit();
        owner_allocator.destroy(self.arena_state);
        self.* = undefined;
        owner_allocator.destroy(self);
    }

    pub fn findAsset(self: ResolvedExperiment, name: []const u8) ?Asset {
        for (self.assets) |asset| {
            if (std.mem.eql(u8, asset.name, name)) return asset;
        }
        return null;
    }

    pub fn findIngest(self: ResolvedExperiment, name: []const u8) ?Ingest {
        for (self.ingests) |ingest| {
            if (std.mem.eql(u8, ingest.name, name)) return ingest;
        }
        return null;
    }

    pub fn findProduct(self: ResolvedExperiment, name: []const u8) ?Product {
        if (self.simulation) |stage| {
            if (findStageProduct(stage.*, name)) |product| return product;
        }
        if (self.retrieval) |stage| {
            if (findStageProduct(stage.*, name)) |product| return product;
        }
        return null;
    }
};

pub fn resolveFile(allocator: Allocator, path: []const u8) !*ResolvedExperiment {
    var document = try Document.parseFile(allocator, path);
    defer document.deinit();
    return document.resolve(allocator);
}

const StageResolution = struct {
    merged: yaml.Value,
    stage: Stage,
};

const MeasurementDecode = struct {
    measurement: Measurement,
    source_name: []const u8,
};

const ObservationMetadata = struct {
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
    instrument_response_provider: []const u8 = "",
};

const InverseDecode = struct {
    inverse: InverseProblem,
    algorithm_name: []const u8 = "",
    algorithm_damping: []const u8 = "",
};

const SceneMetadata = struct {
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
    surface_model_provider: []const u8 = "",
    instrument_response_provider: []const u8 = "",
};

const ResolveContext = struct {
    allocator: Allocator,
    document: *const Document,
    root: []const yaml.Entry,
    validation: Validation,
    strict_unknown_fields: bool,
    assets: []const Asset,
    ingests: []const Ingest,

    fn resolveStage(
        self: *const ResolveContext,
        kind: StageKind,
        raw_stage: ?yaml.Value,
        simulation_stage: ?*const Stage,
    ) !?*StageResolution {
        const stage_value = raw_stage orelse return null;
        if (stage_value == .null) return null;

        var stack = std.ArrayListUnmanaged([]const u8){};
        defer stack.deinit(self.allocator);

        const resolution = try self.allocator.create(StageResolution);
        resolution.* = .{
            .merged = try self.resolveComposableNode(stage_value, &stack),
            .stage = undefined,
        };
        try self.populateStage(kind, resolution.merged, simulation_stage, &resolution.stage);
        return resolution;
    }

    fn resolveComposableNode(
        self: *const ResolveContext,
        value: yaml.Value,
        stack: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!yaml.Value {
        const map = try expectMap(value);
        const overlay = try cloneMapSkipping(self.allocator, map, &.{"from"});

        if (mapGet(map, "from")) |from_value| {
            const reference = try expectString(from_value);
            if (containsString(stack.items, reference)) return Error.ReferenceCycle;
            try stack.append(self.allocator, reference);
            defer _ = stack.pop();

            const base = try self.resolveReference(reference, stack);
            return yaml.merge(base, overlay, self.allocator);
        }

        return overlay;
    }

    fn resolveReference(
        self: *const ResolveContext,
        reference: []const u8,
        stack: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!yaml.Value {
        if (std.mem.eql(u8, reference, "experiment.simulation")) {
            const experiment_map = try expectMap(requiredField(self.root, "experiment"));
            const stage_value = mapGet(experiment_map, "simulation") orelse return Error.MissingStage;
            if (stage_value == .null) return Error.MissingStage;
            return self.resolveComposableNode(stage_value, stack);
        }
        if (std.mem.eql(u8, reference, "experiment.retrieval")) {
            const experiment_map = try expectMap(requiredField(self.root, "experiment"));
            const stage_value = mapGet(experiment_map, "retrieval") orelse return Error.MissingStage;
            if (stage_value == .null) return Error.MissingStage;
            return self.resolveComposableNode(stage_value, stack);
        }

        const templates_value = mapGet(self.root, "templates") orelse return Error.MissingTemplate;
        const templates_map = try expectMap(templates_value);
        const template_name = if (std.mem.startsWith(u8, reference, "templates."))
            reference["templates.".len..]
        else
            reference;
        const template_value = mapGet(templates_map, template_name) orelse return Error.MissingTemplate;
        return self.resolveComposableNode(template_value, stack);
    }

    fn populateStage(
        self: *const ResolveContext,
        kind: StageKind,
        merged: yaml.Value,
        simulation_stage: ?*const Stage,
        stage: *Stage,
    ) !void {
        const stage_map = try expectMap(merged);
        try ensureKnownFields(stage_map, if (kind == .simulation)
            &.{ "plan", "scene", "products", "diagnostics", "label", "description" }
        else
            &.{ "plan", "scene", "inverse", "products", "diagnostics", "label", "description" }, self.strict_unknown_fields);

        stage.* = .{
            .kind = kind,
            .plan = try decodePlan(self.allocator, mapGet(stage_map, "plan"), self.strict_unknown_fields),
            .scene = undefined,
            .products = try decodeProducts(self.allocator, mapGet(stage_map, "products"), self.strict_unknown_fields),
            .diagnostics = try decodeDiagnostics(mapGet(stage_map, "diagnostics"), self.strict_unknown_fields),
        };
        const scene_metadata = try self.populateScene(kind, mapGet(stage_map, "scene"), &stage.scene);
        stage.spectral_response_shape = scene_metadata.spectral_response_shape;
        stage.spectral_response_table_source = scene_metadata.spectral_response_table_source;
        stage.noise_seed = scene_metadata.noise_seed;

        stage.plan.providers.surface_model = normalizeSurfaceProvider(
            scene_metadata.surface_model_provider,
            stage.scene.surface.kind,
        );
        stage.plan.providers.instrument_response = normalizeInstrumentProvider(
            scene_metadata.instrument_response_provider,
            stage.scene.observation_model.instrument,
        );
        stage.plan.scene_blueprint = .{
            .id = stage.scene.id,
            .spectral_grid = stage.scene.spectral_grid,
            .observation_regime = stage.scene.observation_model.regime,
            .derivative_mode = stage.plan.scene_blueprint.derivative_mode,
            .layer_count_hint = stage.scene.atmosphere.layer_count,
            .measurement_count_hint = stage.scene.spectral_grid.sample_count,
        };

        if (kind == .retrieval) {
            const inverse_result = try self.decodeInverse(mapGet(stage_map, "inverse"), stage.scene, simulation_stage);
            stage.inverse = inverse_result.inverse;
            stage.algorithm_name = inverse_result.algorithm_name;
            stage.algorithm_damping = inverse_result.algorithm_damping;
            if (stage.inverse) |*inverse| {
                try applyAlgorithmParameters(inverse, stage.algorithm_damping);
            }
            try hydrateSceneFromIngestMeasurement(self.allocator, self.ingests, &stage.scene, inverse_result.inverse.measurements.source);
            stage.plan.providers.retrieval_algorithm = stage.plan.providers.retrieval_algorithm orelse normalizeRetrievalProvider(
                inverse_result.algorithm_name,
                stage.plan.providers.retrieval_algorithm,
            );
            stage.plan.scene_blueprint.spectral_grid = stage.scene.spectral_grid;
            stage.plan.scene_blueprint.state_parameter_count_hint = inverse_result.inverse.state_vector.count();
            stage.plan.scene_blueprint.measurement_count_hint = inverse_result.inverse.measurements.sample_count;
        }

        try ensureDistinctProducts(stage.products);
        try stage.plan.validate();
        try stage.scene.validate();
        if (stage.inverse) |inverse| try inverse.validate();
    }

    fn applyAlgorithmParameters(inverse: *InverseProblem, algorithm_damping: []const u8) !void {
        if (algorithm_damping.len == 0) return;

        const normalized: FitControls.TrustRegion = if (std.mem.eql(u8, algorithm_damping, "levenberg_marquardt"))
            .lm
        else if (std.mem.eql(u8, algorithm_damping, "lm"))
            .lm
        else
            return Error.InvalidValue;

        if (inverse.fit_controls.trust_region == .none) {
            inverse.fit_controls.trust_region = normalized;
            return;
        }
        if (inverse.fit_controls.trust_region != normalized) {
            return Error.InvalidValue;
        }
    }

    fn populateScene(
        self: *const ResolveContext,
        kind: StageKind,
        value: ?yaml.Value,
        scene: *Scene,
    ) !SceneMetadata {
        const scene_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(scene_map, &.{
            "id",
            "geometry",
            "atmosphere",
            "bands",
            "absorbers",
            "surface",
            "clouds",
            "aerosols",
            "measurement_model",
            "label",
            "description",
        }, self.strict_unknown_fields);

        var observation_model: ObservationModel = .{};
        const observation_metadata = try self.populateObservationModel(
            mapGet(scene_map, "measurement_model"),
            &observation_model,
        );
        const surface_result = try decodeSurface(self.allocator, mapGet(scene_map, "surface"), self.strict_unknown_fields);
        scene.* = .{
            .id = if (mapGet(scene_map, "id")) |scene_id| try self.allocator.dupe(u8, try expectString(scene_id)) else switch (kind) {
                .simulation => "simulation-stage",
                .retrieval => "retrieval-stage",
            },
            .geometry = try decodeGeometry(mapGet(scene_map, "geometry"), self.strict_unknown_fields),
            .atmosphere = try decodeAtmosphere(self.allocator, mapGet(scene_map, "atmosphere"), self.strict_unknown_fields),
            .bands = try decodeBands(self.allocator, mapGet(scene_map, "bands"), self.strict_unknown_fields),
            .surface = surface_result.surface,
            .cloud = try decodeCloud(mapGet(scene_map, "clouds"), self.strict_unknown_fields),
            .aerosol = try decodeAerosol(mapGet(scene_map, "aerosols"), self.strict_unknown_fields),
            .observation_model = observation_model,
        };

        scene.spectral_grid = try inferSpectralGrid(scene.bands);
        scene.observation_model.regime = observation_model.regime;
        scene.atmosphere.has_clouds = scene.cloud.enabled;
        scene.atmosphere.has_aerosols = scene.aerosol.enabled;
        scene.absorbers = try self.decodeAbsorbers(mapGet(scene_map, "absorbers"), &scene.observation_model);

        return .{
            .spectral_response_shape = observation_metadata.spectral_response_shape,
            .spectral_response_table_source = observation_metadata.spectral_response_table_source,
            .noise_seed = observation_metadata.noise_seed,
            .surface_model_provider = surface_result.provider,
            .instrument_response_provider = observation_metadata.instrument_response_provider,
        };
    }

    fn populateObservationModel(
        self: *const ResolveContext,
        value: ?yaml.Value,
        model: *ObservationModel,
    ) !ObservationMetadata {
        const model_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(model_map, &.{
            "regime",
            "instrument",
            "sampling",
            "spectral_response",
            "illumination",
            "supporting_data",
            "calibration",
            "noise",
            "label",
            "description",
        }, self.strict_unknown_fields);

        model.* = .{};
        var result: ObservationMetadata = .{};

        if (mapGet(model_map, "regime")) |regime| {
            model.regime = try parseObservationRegime(try expectString(regime));
        }

        if (mapGet(model_map, "instrument")) |instrument_value| {
            const instrument_map = try expectMap(instrument_value);
            try ensureKnownFields(instrument_map, &.{ "name", "response_provider" }, self.strict_unknown_fields);
            model.instrument = InstrumentId.parse(try expectString(requiredField(instrument_map, "name")));
            if (mapGet(instrument_map, "response_provider")) |response_provider| {
                result.instrument_response_provider = try self.allocator.dupe(u8, try expectString(response_provider));
            }
        }

        if (mapGet(model_map, "sampling")) |sampling_value| {
            const sampling_map = try expectMap(sampling_value);
            try ensureKnownFields(sampling_map, &.{ "mode", "high_resolution_step_nm", "high_resolution_half_span_nm" }, self.strict_unknown_fields);
            if (mapGet(sampling_map, "mode")) |mode| model.sampling = try parseSamplingMode(try expectString(mode));
            if (mapGet(sampling_map, "high_resolution_step_nm")) |step| model.high_resolution_step_nm = try expectF64(step);
            if (mapGet(sampling_map, "high_resolution_half_span_nm")) |span| model.high_resolution_half_span_nm = try expectF64(span);
        }

        if (mapGet(model_map, "spectral_response")) |response_value| {
            const response_map = try expectMap(response_value);
            try ensureKnownFields(response_map, &.{ "shape", "fwhm_nm", "table" }, self.strict_unknown_fields);
            if (mapGet(response_map, "shape")) |shape| {
                const shape_name = try expectString(shape);
                result.spectral_response_shape = try self.allocator.dupe(u8, shape_name);
                model.builtin_line_shape = try BuiltinLineShapeKind.parse(shape_name);
            }
            if (mapGet(response_map, "fwhm_nm")) |fwhm| model.instrument_line_fwhm_nm = try expectF64(fwhm);
            if (mapGet(response_map, "table")) |table_value| {
                const binding = try self.decodeIngestBinding(table_value);
                result.spectral_response_table_source = binding;
                model.instrument_line_shape_table = try resolveInstrumentLineShapeTable(self.ingests, binding);
            }
        }

        if (mapGet(model_map, "illumination")) |illumination_value| {
            const illumination_map = try expectMap(illumination_value);
            try ensureKnownFields(illumination_map, &.{"solar_spectrum"}, self.strict_unknown_fields);
            if (mapGet(illumination_map, "solar_spectrum")) |spectrum_value| {
                const binding = try self.decodeSourceBinding(spectrum_value);
                model.solar_spectrum_source = binding;
                if (binding.kind() == .ingest) {
                    model.operational_solar_spectrum = try resolveOperationalSolarSpectrum(self.allocator, self.ingests, binding);
                }
            }
        }

        if (mapGet(model_map, "supporting_data")) |support_value| {
            const support_map = try expectMap(support_value);
            try ensureKnownFields(support_map, &.{"weighted_reference_grid"}, self.strict_unknown_fields);
            if (mapGet(support_map, "weighted_reference_grid")) |grid_value| {
                const binding = try self.decodeIngestBinding(grid_value);
                model.weighted_reference_grid_source = binding;
                model.operational_refspec_grid = try resolveOperationalReferenceGrid(self.allocator, self.ingests, binding);
            }
        }

        if (mapGet(model_map, "calibration")) |calibration_value| {
            const calibration_map = try expectMap(calibration_value);
            try ensureKnownFields(calibration_map, &.{ "wavelength_shift_nm", "multiplicative_offset", "stray_light" }, self.strict_unknown_fields);
            if (mapGet(calibration_map, "wavelength_shift_nm")) |shift| model.wavelength_shift_nm = try expectF64(shift);
            if (mapGet(calibration_map, "multiplicative_offset")) |offset| model.multiplicative_offset = try expectF64(offset);
            if (mapGet(calibration_map, "stray_light")) |stray_light| model.stray_light = try expectF64(stray_light);
        }

        if (mapGet(model_map, "noise")) |noise_value| {
            const noise_map = try expectMap(noise_value);
            try ensureKnownFields(noise_map, &.{ "model", "seed" }, self.strict_unknown_fields);
            if (mapGet(noise_map, "model")) |noise_model| model.noise_model = try parseNoiseModelKind(try expectString(noise_model));
            if (mapGet(noise_map, "seed")) |seed| result.noise_seed = @intCast(try expectU64(seed));
        }

        return result;
    }

    fn decodeAbsorbers(self: *const ResolveContext, value: ?yaml.Value, observation_model: *ObservationModel) !AbsorberSet {
        const absorber_map = try expectMap(value orelse return Error.MissingField);
        const absorbers = try self.allocator.alloc(Absorber, absorber_map.len);

        for (absorber_map, 0..) |entry, index| {
            const item_map = try expectMap(entry.value);
            try ensureKnownFields(item_map, &.{ "species", "profile", "spectroscopy", "label", "description" }, self.strict_unknown_fields);

            var absorber: Absorber = .{
                .id = try self.allocator.dupe(u8, entry.key),
                .species = try self.allocator.dupe(u8, try expectString(requiredField(item_map, "species"))),
            };

            if (mapGet(item_map, "profile")) |profile_value| {
                const profile_map = try expectMap(profile_value);
                try ensureKnownFields(profile_map, &.{"source"}, self.strict_unknown_fields);
                if (mapGet(profile_map, "source")) |source_value| {
                    absorber.profile_source = try decodeProfileBinding(self.allocator, source_value);
                }
            } else {
                absorber.profile_source = .atmosphere;
            }

            if (mapGet(item_map, "spectroscopy")) |spectroscopy_value| {
                const spectroscopy_map = try expectMap(spectroscopy_value);
                try ensureKnownFields(spectroscopy_map, &.{
                    "model",
                    "provider",
                    "line_list_asset",
                    "line_mixing_asset",
                    "strong_lines_asset",
                    "cia_asset",
                    "operational_lut",
                }, self.strict_unknown_fields);

                absorber.spectroscopy.mode = try parseSpectroscopyMode(try expectString(requiredField(spectroscopy_map, "model")));
                if (mapGet(spectroscopy_map, "provider")) |provider| {
                    absorber.spectroscopy.provider = try self.allocator.dupe(u8, try expectString(provider));
                }
                if (mapGet(spectroscopy_map, "line_list_asset")) |line_list_asset| {
                    absorber.spectroscopy.line_list = try self.decodeAssetBinding(line_list_asset);
                }
                if (mapGet(spectroscopy_map, "line_mixing_asset")) |line_mixing_asset| {
                    absorber.spectroscopy.line_mixing = try self.decodeAssetBinding(line_mixing_asset);
                }
                if (mapGet(spectroscopy_map, "strong_lines_asset")) |strong_lines_asset| {
                    absorber.spectroscopy.strong_lines = try self.decodeAssetBinding(strong_lines_asset);
                }
                if (mapGet(spectroscopy_map, "cia_asset")) |cia_asset| {
                    absorber.spectroscopy.cia_table = try self.decodeAssetBinding(cia_asset);
                }
                if (mapGet(spectroscopy_map, "operational_lut")) |operational_lut| {
                    const binding = try self.decodeIngestBinding(operational_lut);
                    absorber.spectroscopy.operational_lut = binding;
                    if (std.mem.eql(u8, absorber.id, "o2")) {
                        observation_model.o2_operational_lut = try resolveOperationalLut(self.allocator, self.ingests, binding, "o2_operational_lut");
                    } else if (std.mem.eql(u8, absorber.id, "o2o2")) {
                        observation_model.o2o2_operational_lut = try resolveOperationalLut(self.allocator, self.ingests, binding, "o2o2_operational_lut");
                    }
                }
                absorber.spectroscopy.resolved_line_list = try resolveSpectroscopyLineList(
                    self.allocator,
                    self.assets,
                    absorber.spectroscopy,
                );
                absorber.spectroscopy.resolved_cia_table = try resolveCollisionInducedAbsorptionTable(
                    self.allocator,
                    self.assets,
                    absorber.spectroscopy.cia_table,
                );
            }

            absorbers[index] = absorber;
        }

        return .{ .items = absorbers };
    }

    fn decodeInverse(
        self: *const ResolveContext,
        value: ?yaml.Value,
        scene: Scene,
        simulation_stage: ?*const Stage,
    ) !InverseDecode {
        const inverse_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(inverse_map, &.{
            "algorithm",
            "measurement",
            "state",
            "covariance",
            "fit_controls",
            "convergence",
            "label",
            "description",
        }, self.strict_unknown_fields);

        const algorithm = try decodeAlgorithm(self.allocator, mapGet(inverse_map, "algorithm"), self.strict_unknown_fields);
        const measurement_result = try self.decodeMeasurement(mapGet(inverse_map, "measurement"), scene, simulation_stage);
        const state_vector = try decodeStateVector(self.allocator, mapGet(inverse_map, "state"), self.strict_unknown_fields);
        const covariance_blocks = try decodeCovariance(self.allocator, state_vector, mapGet(inverse_map, "covariance"), self.strict_unknown_fields);
        const fit_controls = try decodeFitControls(mapGet(inverse_map, "fit_controls"), self.strict_unknown_fields);
        const convergence = try decodeConvergence(mapGet(inverse_map, "convergence"), self.strict_unknown_fields);

        return .{
            .inverse = .{
                .id = try std.fmt.allocPrint(self.allocator, "{s}-inverse", .{scene.id}),
                .state_vector = state_vector,
                .measurements = measurement_result.measurement,
                .covariance_blocks = covariance_blocks,
                .fit_controls = fit_controls,
                .convergence = convergence,
            },
            .algorithm_name = algorithm.name,
            .algorithm_damping = algorithm.damping,
        };
    }

    fn decodeMeasurement(
        self: *const ResolveContext,
        value: ?yaml.Value,
        scene: Scene,
        simulation_stage: ?*const Stage,
    ) !MeasurementDecode {
        const measurement_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(measurement_map, &.{ "source", "observable", "mask", "error_model" }, self.strict_unknown_fields);

        const source_name = try self.allocator.dupe(u8, try expectString(requiredField(measurement_map, "source")));
        const binding = try resolveMeasurementSource(source_name, simulation_stage, self.validation, self.ingests);
        const observable = if (mapGet(measurement_map, "observable")) |observable_value|
            try parseMeasurementQuantity(try expectString(observable_value))
        else
            try inferMeasurementQuantity(source_name, binding, simulation_stage, self.ingests);
        const source_scene = if (binding.kind() == .stage_product and simulation_stage != null)
            simulation_stage.?.scene
        else
            scene;
        var measurement: Measurement = .{
            .product_name = observable.label(),
            .observable = observable,
            .sample_count = source_scene.spectral_grid.sample_count,
            .source = binding,
        };
        if (binding.kind() == .ingest) {
            measurement.sample_count = ingestMeasurementSampleCount(self.ingests, binding);
        }

        if (mapGet(measurement_map, "mask")) |mask_value| {
            measurement.mask = try decodeMeasurementMask(self.allocator, mask_value, self.strict_unknown_fields);
            measurement.sample_count = try maskedMeasurementSampleCount(source_scene, measurement.mask);
        }
        if (mapGet(measurement_map, "error_model")) |error_model| {
            measurement.error_model = try decodeMeasurementErrorModel(error_model, self.strict_unknown_fields);
        }

        return .{
            .measurement = measurement,
            .source_name = source_name,
        };
    }

    fn maskedMeasurementSampleCount(scene: Scene, mask: MeasurementMask) !u32 {
        if (mask.exclude.len == 0) return scene.spectral_grid.sample_count;

        const axis: spectra_grid.ResolvedAxis = .{
            .base = .{
                .start_nm = scene.spectral_grid.start_nm,
                .end_nm = scene.spectral_grid.end_nm,
                .sample_count = scene.spectral_grid.sample_count,
            },
            .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
        };
        try axis.validate();

        var count: u32 = 0;
        const measurement: Measurement = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = scene.spectral_grid.sample_count,
            .mask = mask,
        };
        for (0..scene.spectral_grid.sample_count) |index| {
            const wavelength_nm = try axis.sampleAt(@intCast(index));
            if (measurement.includesWavelength(wavelength_nm)) count += 1;
        }
        return count;
    }

    fn decodeAssetBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        const asset_name = try expectString(value);
        if (!hasAsset(self.assets, asset_name)) return Error.MissingAsset;
        return .{ .asset = .{ .name = try self.allocator.dupe(u8, asset_name) } };
    }

    fn decodeSourceBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        if (value == .string) {
            const source = value.string;
            if (std.mem.eql(u8, source, "bundle_default")) return .bundle_default;
            return .{ .external_observation = .{ .name = try self.allocator.dupe(u8, source) } };
        }

        const source_map = try expectMap(value);
        try ensureKnownFields(source_map, &.{ "source", "from_ingest" }, self.strict_unknown_fields);
        if (mapGet(source_map, "from_ingest")) |from_ingest| {
            return self.decodeIngestReference(try expectString(from_ingest));
        }
        if (mapGet(source_map, "source")) |source_value| {
            const source = try expectString(source_value);
            if (std.mem.eql(u8, source, "bundle_default")) return .bundle_default;
            return .{ .asset = .{ .name = try self.allocator.dupe(u8, source) } };
        }
        return Error.InvalidReference;
    }

    fn decodeIngestBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        const source_map = try expectMap(value);
        try ensureKnownFields(source_map, &.{"from_ingest"}, self.strict_unknown_fields);
        const from_ingest = try expectString(requiredField(source_map, "from_ingest"));
        return self.decodeIngestReference(from_ingest);
    }

    fn decodeIngestReference(self: *const ResolveContext, reference: []const u8) !Binding {
        const dot_index = std.mem.indexOfScalar(u8, reference, '.') orelse return Error.InvalidReference;
        const ingest_name = reference[0..dot_index];
        if (!hasIngest(self.ingests, ingest_name)) return Error.MissingIngest;
        return .{ .ingest = @import("../../model/Binding.zig").IngestRef.fromFullName(try self.allocator.dupe(u8, reference)) };
    }
};

fn decodeMetadata(allocator: Allocator, value: ?yaml.Value, strict: bool) !Metadata {
    const metadata_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(metadata_map, &.{ "id", "workspace", "description" }, strict);
    return .{
        .id = try allocator.dupe(u8, try expectString(requiredField(metadata_map, "id"))),
        .workspace = if (mapGet(metadata_map, "workspace")) |workspace|
            try allocator.dupe(u8, try expectString(workspace))
        else
            "",
        .description = if (mapGet(metadata_map, "description")) |description|
            try allocator.dupe(u8, try expectString(description))
        else
            "",
    };
}

fn decodeStrictUnknownFields(root: []const yaml.Entry) bool {
    const validation_value = mapGet(root, "validation") orelse return true;
    const validation_map = expectMap(validation_value) catch return true;
    const strict_unknown_fields = mapGet(validation_map, "strict_unknown_fields") orelse return true;
    return expectBool(strict_unknown_fields) catch true;
}

fn decodeValidation(allocator: Allocator, value: ?yaml.Value, strict: bool) !Validation {
    const validation_value = value orelse return .{};
    const validation_map = try expectMap(validation_value);
    try ensureKnownFields(validation_map, &.{
        "strict_unknown_fields",
        "require_resolved_assets",
        "require_resolved_stage_references",
        "synthetic_retrieval",
    }, strict);

    var validation: Validation = .{};
    if (mapGet(validation_map, "strict_unknown_fields")) |strict_unknown_fields| validation.strict_unknown_fields = try expectBool(strict_unknown_fields);
    if (mapGet(validation_map, "require_resolved_assets")) |require_assets| validation.require_resolved_assets = try expectBool(require_assets);
    if (mapGet(validation_map, "require_resolved_stage_references")) |require_stage_refs| validation.require_resolved_stage_references = try expectBool(require_stage_refs);
    if (mapGet(validation_map, "synthetic_retrieval")) |synthetic_retrieval| {
        const synthetic_map = try expectMap(synthetic_retrieval);
        try ensureKnownFields(synthetic_map, &.{ "warn_if_models_are_identical", "require_explicit_acknowledgement_if_identical" }, validation.strict_unknown_fields);
        if (mapGet(synthetic_map, "warn_if_models_are_identical")) |warn| validation.synthetic_retrieval.warn_if_models_are_identical = try expectBool(warn);
        if (mapGet(synthetic_map, "require_explicit_acknowledgement_if_identical")) |ack| validation.synthetic_retrieval.require_explicit_acknowledgement_if_identical = try expectBool(ack);
    }
    _ = allocator;
    return validation;
}

fn decodeAssets(allocator: Allocator, document: *const Document, root: []const yaml.Entry, strict: bool) ![]const Asset {
    const inputs_value = mapGet(root, "inputs") orelse return &[_]Asset{};
    const inputs_map = try expectMap(inputs_value);
    try ensureKnownFields(inputs_map, &.{ "assets", "ingests" }, strict);

    const assets_value = mapGet(inputs_map, "assets") orelse return &[_]Asset{};
    const assets_map = try expectMap(assets_value);
    const assets = try allocator.alloc(Asset, assets_map.len);

    for (assets_map, 0..) |entry, index| {
        const asset_map = try expectMap(entry.value);
        try ensureKnownFields(asset_map, &.{ "kind", "path", "format", "label", "description" }, strict);

        const kind_string = try expectString(requiredField(asset_map, "kind"));
        const path = try expectString(requiredField(asset_map, "path"));
        assets[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .kind = try parseAssetKind(kind_string),
            .format = try allocator.dupe(u8, try expectString(requiredField(asset_map, "format"))),
            .path = try allocator.dupe(u8, path),
            .resolved_path = try resolveInputPath(allocator, document.source_dir, path),
        };
    }

    return assets;
}

fn decodeIngests(allocator: Allocator, root: []const yaml.Entry, assets: []const Asset, strict: bool) ![]const Ingest {
    const inputs_value = mapGet(root, "inputs") orelse return &[_]Ingest{};
    const inputs_map = try expectMap(inputs_value);
    const ingests_value = mapGet(inputs_map, "ingests") orelse return &[_]Ingest{};
    const ingests_map = try expectMap(ingests_value);

    const ingests = try allocator.alloc(Ingest, ingests_map.len);
    for (ingests_map, 0..) |entry, index| {
        const ingest_map = try expectMap(entry.value);
        try ensureKnownFields(ingest_map, &.{ "adapter", "asset", "label", "description" }, strict);

        const adapter = try parseIngestAdapter(try expectString(requiredField(ingest_map, "adapter")));
        const asset_name = try expectString(requiredField(ingest_map, "asset"));
        const asset = findAsset(assets, asset_name) orelse return Error.MissingAsset;
        ingests[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .adapter = adapter,
            .asset_name = try allocator.dupe(u8, asset_name),
            .loaded_spectra = switch (adapter) {
                .spectral_ascii => try spectral_ascii.parseFile(allocator, asset.resolved_path),
            },
        };
    }
    return ingests;
}

fn decodePlan(allocator: Allocator, value: ?yaml.Value, strict: bool) !PlanTemplate {
    var template: PlanTemplate = .{};
    const plan_value = value orelse return template;
    const plan_map = try expectMap(plan_value);
    try ensureKnownFields(plan_map, &.{ "model_family", "transport", "execution", "providers" }, strict);

    if (mapGet(plan_map, "model_family")) |model_family| template.model_family = try allocator.dupe(u8, try expectString(model_family));

    if (mapGet(plan_map, "transport")) |transport_value| {
        const transport_map = try expectMap(transport_value);
        try ensureKnownFields(transport_map, &.{ "solver", "provider" }, strict);
        const solver = if (mapGet(transport_map, "solver")) |solver_value| try expectString(solver_value) else "";
        const provider = if (mapGet(transport_map, "provider")) |provider_value| try expectString(provider_value) else "";
        template.providers.transport_solver = normalizeTransportProvider(solver, provider);
    }

    if (mapGet(plan_map, "execution")) |execution_value| {
        const execution_map = try expectMap(execution_value);
        try ensureKnownFields(execution_map, &.{ "solver_mode", "derivative_mode" }, strict);
        if (mapGet(execution_map, "solver_mode")) |solver_mode| template.solver_mode = try parseSolverMode(try expectString(solver_mode));
        if (mapGet(execution_map, "derivative_mode")) |derivative_mode| template.scene_blueprint.derivative_mode = try parseDerivativeMode(try expectString(derivative_mode));
    }

    if (mapGet(plan_map, "providers")) |providers_value| {
        const providers_map = try expectMap(providers_value);
        try ensureKnownFields(providers_map, &.{
            "transport_solver",
            "retrieval_algorithm",
            "surface_model",
            "instrument_response",
            "absorber_provider",
            "noise_model",
            "diagnostics_metric",
        }, strict);
        if (mapGet(providers_map, "transport_solver")) |transport_solver| template.providers.transport_solver = try allocator.dupe(u8, try expectString(transport_solver));
        if (mapGet(providers_map, "retrieval_algorithm")) |retrieval_algorithm| template.providers.retrieval_algorithm = try allocator.dupe(u8, try expectString(retrieval_algorithm));
        if (mapGet(providers_map, "surface_model")) |surface_model| template.providers.surface_model = try allocator.dupe(u8, try expectString(surface_model));
        if (mapGet(providers_map, "instrument_response")) |instrument_response| template.providers.instrument_response = try allocator.dupe(u8, try expectString(instrument_response));
        if (mapGet(providers_map, "absorber_provider")) |absorber_provider| template.providers.absorber_provider = try allocator.dupe(u8, try expectString(absorber_provider));
        if (mapGet(providers_map, "noise_model")) |noise_model| template.providers.noise_model = try allocator.dupe(u8, try expectString(noise_model));
        if (mapGet(providers_map, "diagnostics_metric")) |diagnostics_metric| template.providers.diagnostics_metric = try allocator.dupe(u8, try expectString(diagnostics_metric));
    }
    return template;
}

fn decodeGeometry(value: ?yaml.Value, strict: bool) !Geometry {
    const geometry_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(geometry_map, &.{ "model", "solar_zenith_deg", "viewing_zenith_deg", "relative_azimuth_deg" }, strict);
    return .{
        .model = try parseGeometryModel(try expectString(requiredField(geometry_map, "model"))),
        .solar_zenith_deg = try expectF64(requiredField(geometry_map, "solar_zenith_deg")),
        .viewing_zenith_deg = try expectF64(requiredField(geometry_map, "viewing_zenith_deg")),
        .relative_azimuth_deg = try expectF64(requiredField(geometry_map, "relative_azimuth_deg")),
    };
}

fn decodeAtmosphere(allocator: Allocator, value: ?yaml.Value, strict: bool) !Atmosphere {
    const atmosphere_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(atmosphere_map, &.{ "layering", "thermodynamics", "boundary" }, strict);

    var atmosphere: Atmosphere = .{};
    if (mapGet(atmosphere_map, "layering")) |layering_value| {
        const layering_map = try expectMap(layering_value);
        try ensureKnownFields(layering_map, &.{ "layer_count", "sublayer_divisions" }, strict);
        if (mapGet(layering_map, "layer_count")) |layer_count| atmosphere.layer_count = @intCast(try expectU64(layer_count));
        if (mapGet(layering_map, "sublayer_divisions")) |sublayer_divisions| atmosphere.sublayer_divisions = @intCast(try expectU64(sublayer_divisions));
    }
    if (mapGet(atmosphere_map, "thermodynamics")) |thermodynamics_value| {
        const thermodynamics_map = try expectMap(thermodynamics_value);
        try ensureKnownFields(thermodynamics_map, &.{"profile"}, strict);
        if (mapGet(thermodynamics_map, "profile")) |profile_value| {
            const profile_map = try expectMap(profile_value);
            try ensureKnownFields(profile_map, &.{"source"}, strict);
            atmosphere.profile_source = try decodeProfileBinding(allocator, requiredField(profile_map, "source"));
        }
    }
    if (mapGet(atmosphere_map, "boundary")) |boundary_value| {
        const boundary_map = try expectMap(boundary_value);
        try ensureKnownFields(boundary_map, &.{"surface_pressure_hpa"}, strict);
        if (mapGet(boundary_map, "surface_pressure_hpa")) |surface_pressure_hpa| atmosphere.surface_pressure_hpa = try expectF64(surface_pressure_hpa);
    }
    return atmosphere;
}

fn decodeBands(allocator: Allocator, value: ?yaml.Value, strict: bool) !SpectralBandSet {
    const band_map = try expectMap(value orelse return Error.MissingField);
    const bands = try allocator.alloc(SpectralBand, band_map.len);
    for (band_map, 0..) |entry, index| {
        const band_value_map = try expectMap(entry.value);
        try ensureKnownFields(band_value_map, &.{ "start_nm", "end_nm", "step_nm", "exclude", "label", "description" }, strict);
        bands[index] = .{
            .id = try allocator.dupe(u8, entry.key),
            .start_nm = try expectF64(requiredField(band_value_map, "start_nm")),
            .end_nm = try expectF64(requiredField(band_value_map, "end_nm")),
            .step_nm = try expectF64(requiredField(band_value_map, "step_nm")),
            .exclude = try decodeWindows(allocator, mapGet(band_value_map, "exclude")),
        };
    }
    return .{ .items = bands };
}

fn decodeWindows(allocator: Allocator, value: ?yaml.Value) ![]const SpectralWindow {
    const window_value = value orelse return &[_]SpectralWindow{};
    const windows = try expectSeq(window_value);
    const decoded = try allocator.alloc(SpectralWindow, windows.len);
    for (windows, 0..) |window, index| {
        const pair = try expectSeq(window);
        if (pair.len != 2) return Error.InvalidValue;
        decoded[index] = .{
            .start_nm = try expectF64(pair[0]),
            .end_nm = try expectF64(pair[1]),
        };
    }
    return decoded;
}

const SurfaceDecode = struct {
    surface: Surface,
    provider: []const u8 = "",
};

fn decodeSurface(allocator: Allocator, value: ?yaml.Value, strict: bool) !SurfaceDecode {
    const surface_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(surface_map, &.{ "model", "provider", "albedo", "parameters", "label", "description" }, strict);

    var result: SurfaceDecode = .{
        .surface = .{
            .kind = try parseSurfaceKind(try expectString(requiredField(surface_map, "model"))),
        },
    };
    if (mapGet(surface_map, "provider")) |provider| result.provider = try allocator.dupe(u8, try expectString(provider));
    if (mapGet(surface_map, "albedo")) |albedo| result.surface.albedo = try expectF64(albedo);
    if (mapGet(surface_map, "parameters")) |parameters_value| {
        const parameters_map = try expectMap(parameters_value);
        const parameters = try allocator.alloc(SurfaceParameter, parameters_map.len);
        for (parameters_map, 0..) |entry, index| {
            parameters[index] = .{
                .name = try allocator.dupe(u8, entry.key),
                .value = try expectF64(entry.value),
            };
        }
        result.surface.parameters = parameters;
    }
    return result;
}

fn decodeCloud(value: ?yaml.Value, strict: bool) !Cloud {
    const clouds_value = value orelse return .{};
    const clouds_map = try expectMap(clouds_value);
    if (clouds_map.len == 0) return .{};
    if (clouds_map.len > 1) return Error.UnsupportedMultiplicity;

    const entry = clouds_map[0];
    const cloud_map = try expectMap(entry.value);
    try ensureKnownFields(cloud_map, &.{
        "model",
        "provider",
        "optical_thickness",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "reference_wavelength_nm",
        "top_altitude_km",
        "thickness_km",
    }, strict);

    return .{
        .id = entry.key,
        .enabled = true,
        .model = try expectString(requiredField(cloud_map, "model")),
        .provider = if (mapGet(cloud_map, "provider")) |provider| try expectString(provider) else "",
        .optical_thickness = try expectF64(requiredField(cloud_map, "optical_thickness")),
        .single_scatter_albedo = if (mapGet(cloud_map, "single_scatter_albedo")) |ssa| try expectF64(ssa) else 0.999,
        .asymmetry_factor = if (mapGet(cloud_map, "asymmetry_factor")) |asymmetry_factor| try expectF64(asymmetry_factor) else 0.85,
        .angstrom_exponent = if (mapGet(cloud_map, "angstrom_exponent")) |angstrom_exponent| try expectF64(angstrom_exponent) else 0.3,
        .reference_wavelength_nm = if (mapGet(cloud_map, "reference_wavelength_nm")) |reference_wavelength| try expectF64(reference_wavelength) else 550.0,
        .top_altitude_km = if (mapGet(cloud_map, "top_altitude_km")) |top_altitude| try expectF64(top_altitude) else 6.0,
        .thickness_km = if (mapGet(cloud_map, "thickness_km")) |thickness| try expectF64(thickness) else 1.5,
    };
}

fn decodeAerosol(value: ?yaml.Value, strict: bool) !Aerosol {
    const aerosols_value = value orelse return .{};
    const aerosols_map = try expectMap(aerosols_value);
    if (aerosols_map.len == 0) return .{};
    if (aerosols_map.len > 1) return Error.UnsupportedMultiplicity;

    const entry = aerosols_map[0];
    const aerosol_map = try expectMap(entry.value);
    try ensureKnownFields(aerosol_map, &.{
        "model",
        "provider",
        "optical_depth_550_nm",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "layer_center_km",
        "layer_width_km",
    }, strict);

    return .{
        .id = entry.key,
        .enabled = true,
        .model = try expectString(requiredField(aerosol_map, "model")),
        .provider = if (mapGet(aerosol_map, "provider")) |provider| try expectString(provider) else "",
        .optical_depth = try expectF64(requiredField(aerosol_map, "optical_depth_550_nm")),
        .single_scatter_albedo = if (mapGet(aerosol_map, "single_scatter_albedo")) |ssa| try expectF64(ssa) else 0.93,
        .asymmetry_factor = if (mapGet(aerosol_map, "asymmetry_factor")) |asymmetry_factor| try expectF64(asymmetry_factor) else 0.65,
        .angstrom_exponent = if (mapGet(aerosol_map, "angstrom_exponent")) |angstrom_exponent| try expectF64(angstrom_exponent) else 1.3,
        .layer_center_km = if (mapGet(aerosol_map, "layer_center_km")) |center| try expectF64(center) else 2.5,
        .layer_width_km = if (mapGet(aerosol_map, "layer_width_km")) |width| try expectF64(width) else 3.0,
    };
}

fn decodeProducts(allocator: Allocator, value: ?yaml.Value, strict: bool) ![]const Product {
    const products_value = value orelse return &[_]Product{};
    const products_map = try expectMap(products_value);
    const products = try allocator.alloc(Product, products_map.len);
    for (products_map, 0..) |entry, index| {
        const product_map = try expectMap(entry.value);
        try ensureKnownFields(product_map, &.{ "kind", "observable", "apply_noise", "label", "description" }, strict);
        products[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .kind = try parseProductKind(try expectString(requiredField(product_map, "kind"))),
            .observable = if (mapGet(product_map, "observable")) |observable|
                try parseMeasurementQuantity(try expectString(observable))
            else
                null,
            .apply_noise = if (mapGet(product_map, "apply_noise")) |apply_noise| try expectBool(apply_noise) else false,
        };
    }
    return products;
}

fn decodeDiagnostics(value: ?yaml.Value, strict: bool) !DiagnosticsSpec {
    const diagnostics_value = value orelse return .{};
    const diagnostics_map = try expectMap(diagnostics_value);
    try ensureKnownFields(diagnostics_map, &.{ "provenance", "jacobians" }, strict);
    return .{
        .provenance = if (mapGet(diagnostics_map, "provenance")) |provenance| try expectBool(provenance) else true,
        .jacobians = if (mapGet(diagnostics_map, "jacobians")) |jacobians| try expectBool(jacobians) else false,
    };
}

fn decodeAlgorithm(allocator: Allocator, value: ?yaml.Value, strict: bool) !struct {
    name: []const u8,
    provider: ?[]const u8,
    damping: []const u8,
} {
    const algorithm_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(algorithm_map, &.{ "name", "provider", "parameters" }, strict);

    var damping: []const u8 = "";
    if (mapGet(algorithm_map, "parameters")) |parameters_value| {
        const parameters_map = try expectMap(parameters_value);
        try ensureKnownFields(parameters_map, &.{"damping"}, strict);
        if (mapGet(parameters_map, "damping")) |damping_value| damping = try allocator.dupe(u8, try expectString(damping_value));
    }

    return .{
        .name = try allocator.dupe(u8, try expectString(requiredField(algorithm_map, "name"))),
        .provider = if (mapGet(algorithm_map, "provider")) |provider|
            try allocator.dupe(u8, try expectString(provider))
        else
            null,
        .damping = damping,
    };
}

fn decodeStateVector(allocator: Allocator, value: ?yaml.Value, strict: bool) !StateVector {
    const state_value = value orelse return StateVector{ .value_count = 0 };
    const state_map = try expectMap(state_value);
    const parameters = try allocator.alloc(StateParameter, state_map.len);
    errdefer allocator.free(parameters);

    for (state_map, 0..) |entry, index| {
        const parameter_map = try expectMap(entry.value);
        try ensureKnownFields(parameter_map, &.{ "target", "transform", "prior", "bounds", "label", "description" }, strict);
        parameters[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .target = try StateTarget.parse(try expectString(requiredField(parameter_map, "target"))),
            .transform = if (mapGet(parameter_map, "transform")) |transform| try parseStateTransform(try expectString(transform)) else .none,
            .prior = try decodePrior(mapGet(parameter_map, "prior"), strict),
            .bounds = try decodeBounds(mapGet(parameter_map, "bounds")),
        };
    }

    return .{
        .value_count = @intCast(parameters.len),
        .parameters = parameters,
    };
}

fn decodePrior(value: ?yaml.Value, strict: bool) !StatePrior {
    const prior_value = value orelse return .{};
    const prior_map = try expectMap(prior_value);
    try ensureKnownFields(prior_map, &.{ "mean", "sigma" }, strict);
    return .{
        .enabled = true,
        .mean = try expectF64(requiredField(prior_map, "mean")),
        .sigma = try expectF64(requiredField(prior_map, "sigma")),
    };
}

fn decodeBounds(value: ?yaml.Value) !StateBounds {
    const bounds_value = value orelse return .{};
    const pair = try expectSeq(bounds_value);
    if (pair.len != 2) return Error.InvalidValue;
    return .{
        .enabled = true,
        .min = try expectF64(pair[0]),
        .max = try expectF64(pair[1]),
    };
}

fn decodeCovariance(allocator: Allocator, state_vector: StateVector, value: ?yaml.Value, strict: bool) ![]const CovarianceBlock {
    const covariance_value = value orelse return &[_]CovarianceBlock{};
    const covariance_map = try expectMap(covariance_value);
    try ensureKnownFields(covariance_map, &.{"blocks"}, strict);

    const blocks_value = mapGet(covariance_map, "blocks") orelse return &[_]CovarianceBlock{};
    const blocks = try expectSeq(blocks_value);
    const decoded = try allocator.alloc(CovarianceBlock, blocks.len);
    for (blocks, 0..) |block_value, index| {
        const block_map = try expectMap(block_value);
        try ensureKnownFields(block_map, &.{ "members", "correlation" }, strict);
        const members = try expectSeq(requiredField(block_map, "members"));
        const parameter_indices = try allocator.alloc(u32, members.len);
        for (members, 0..) |member, member_index| {
            const member_name = try expectString(member);
            const parameter_index = state_vector.parameterIndex(member_name) orelse return Error.InvalidValue;
            parameter_indices[member_index] = @intCast(parameter_index);
        }
        decoded[index] = .{
            .parameter_indices = parameter_indices,
            .correlation = try expectF64(requiredField(block_map, "correlation")),
        };
    }
    return decoded;
}

fn decodeFitControls(value: ?yaml.Value, strict: bool) !FitControls {
    const fit_controls_value = value orelse return .{};
    const fit_controls_map = try expectMap(fit_controls_value);
    try ensureKnownFields(fit_controls_map, &.{ "max_iterations", "trust_region" }, strict);
    return .{
        .max_iterations = if (mapGet(fit_controls_map, "max_iterations")) |max_iterations| @intCast(try expectU64(max_iterations)) else 0,
        .trust_region = if (mapGet(fit_controls_map, "trust_region")) |trust_region|
            try parseTrustRegion(try expectString(trust_region))
        else
            .none,
    };
}

fn decodeConvergence(value: ?yaml.Value, strict: bool) !Convergence {
    const convergence_value = value orelse return .{};
    const convergence_map = try expectMap(convergence_value);
    try ensureKnownFields(convergence_map, &.{ "cost_relative", "state_relative" }, strict);
    return .{
        .cost_relative = if (mapGet(convergence_map, "cost_relative")) |cost_relative| try expectF64(cost_relative) else 0.0,
        .state_relative = if (mapGet(convergence_map, "state_relative")) |state_relative| try expectF64(state_relative) else 0.0,
    };
}

fn decodeMeasurementMask(allocator: Allocator, value: yaml.Value, strict: bool) !MeasurementMask {
    const mask_map = try expectMap(value);
    try ensureKnownFields(mask_map, &.{ "band", "exclude" }, strict);
    return .{
        .band = if (mapGet(mask_map, "band")) |band| try allocator.dupe(u8, try expectString(band)) else "",
        .exclude = try decodeWindows(allocator, mapGet(mask_map, "exclude")),
    };
}

fn decodeMeasurementErrorModel(value: yaml.Value, strict: bool) !MeasurementErrorModel {
    const error_map = try expectMap(value);
    try ensureKnownFields(error_map, &.{ "from_source_noise", "floor_radiance" }, strict);
    return .{
        .from_source_noise = if (mapGet(error_map, "from_source_noise")) |from_source_noise| try expectBool(from_source_noise) else false,
        .floor = if (mapGet(error_map, "floor_radiance")) |floor| try expectF64(floor) else 0.0,
    };
}

fn decodeOutputs(
    allocator: Allocator,
    value: ?yaml.Value,
    simulation: ?*const StageResolution,
    retrieval: ?*const StageResolution,
    strict: bool,
    validation: Validation,
) ![]const OutputSpec {
    const outputs_value = value orelse return &[_]OutputSpec{};
    const outputs = try expectSeq(outputs_value);
    const decoded = try allocator.alloc(OutputSpec, outputs.len);
    for (outputs, 0..) |output_value, index| {
        const output_map = try expectMap(output_value);
        try ensureKnownFields(output_map, &.{ "from", "format", "destination_uri", "include_provenance" }, strict);
        const source_name = try expectString(requiredField(output_map, "from"));
        if (validation.require_resolved_stage_references and
            findProductAcrossStages(simulation, retrieval, source_name) == null)
        {
            return Error.MissingStageProduct;
        }
        decoded[index] = .{
            .from = try allocator.dupe(u8, source_name),
            .format = try parseExportFormat(try expectString(requiredField(output_map, "format"))),
            .destination_uri = try allocator.dupe(u8, try expectString(requiredField(output_map, "destination_uri"))),
            .include_provenance = if (mapGet(output_map, "include_provenance")) |include_provenance| try expectBool(include_provenance) else false,
        };
    }
    return decoded;
}

fn buildWarnings(
    allocator: Allocator,
    validation: Validation,
    simulation: ?*const StageResolution,
    retrieval: ?*const StageResolution,
) ![]const Warning {
    if (simulation == null or retrieval == null) return &[_]Warning{};
    const simulation_stage = simulation.?.*;
    const retrieval_stage = retrieval.?.*;

    if (retrieval_stage.stage.inverse == null) return &[_]Warning{};
    if (retrieval_stage.stage.inverse.?.measurements.source.kind() != .stage_product) return &[_]Warning{};
    if (!validation.synthetic_retrieval.warn_if_models_are_identical) return &[_]Warning{};

    const simulation_plan = simulation_stage.merged.get("plan") orelse .null;
    const retrieval_plan = retrieval_stage.merged.get("plan") orelse .null;
    const simulation_scene = simulation_stage.merged.get("scene") orelse .null;
    const retrieval_scene = retrieval_stage.merged.get("scene") orelse .null;
    if (!simulation_plan.eql(retrieval_plan) or !simulation_scene.eql(retrieval_scene)) {
        return &[_]Warning{};
    }

    if (validation.synthetic_retrieval.require_explicit_acknowledgement_if_identical) {
        return Error.InvalidReference;
    }

    const warnings = try allocator.alloc(Warning, 1);
    warnings[0] = .{
        .kind = .identical_synthetic_models,
        .message = "simulation and retrieval model contexts are identical; review inverse-crime risk",
    };
    return warnings;
}

fn decodeProfileBinding(allocator: Allocator, value: yaml.Value) !Binding {
    if (value == .string) {
        const source = try expectString(value);
        if (std.mem.eql(u8, source, "atmosphere")) return .atmosphere;
        return .{ .asset = .{ .name = try allocator.dupe(u8, source) } };
    }
    const source_map = try expectMap(value);
    try ensureKnownFields(source_map, &.{"asset"}, true);
    const asset_name = try expectString(requiredField(source_map, "asset"));
    return .{ .asset = .{ .name = try allocator.dupe(u8, asset_name) } };
}

fn resolveMeasurementSource(
    source_name: []const u8,
    simulation_stage: ?*const Stage,
    validation: Validation,
    ingests: []const Ingest,
) !Binding {
    if (simulation_stage) |stage| {
        if (findStageProduct(stage.*, source_name) != null) {
            return .{ .stage_product = .{ .name = source_name } };
        }
    }

    if (std.mem.indexOfScalar(u8, source_name, '.')) |dot_index| {
        if (hasIngest(ingests, source_name[0..dot_index])) {
            return .{ .ingest = @import("../../model/Binding.zig").IngestRef.fromFullName(source_name) };
        }
    }

    if (validation.require_resolved_stage_references and std.mem.indexOfScalar(u8, source_name, '.') == null) {
        return Error.MissingStageProduct;
    }

    return .{ .external_observation = .{ .name = source_name } };
}

fn parseMeasurementQuantity(value: []const u8) !MeasurementQuantity {
    return MeasurementQuantity.parse(value) catch Error.InvalidValue;
}

fn parseTrustRegion(value: []const u8) !FitControls.TrustRegion {
    if (std.mem.eql(u8, value, "lm") or std.mem.eql(u8, value, "levenberg_marquardt")) {
        return .lm;
    }
    return Error.InvalidValue;
}

fn inferMeasurementQuantity(
    source_name: []const u8,
    binding: Binding,
    simulation_stage: ?*const Stage,
    ingests: []const Ingest,
) !MeasurementQuantity {
    switch (binding.kind()) {
        .stage_product => {
            const stage = simulation_stage orelse return Error.InvalidReference;
            const product = findStageProduct(stage.*, source_name) orelse return Error.MissingStageProduct;
            return product.observable orelse Error.InvalidReference;
        },
        .ingest => {
            _ = ingests;
            const ingest_ref = binding.ingestReference().?;
            return parseMeasurementQuantity(ingest_ref.output_name);
        },
        .external_observation => return parseMeasurementQuantity(source_name),
        .none, .asset, .bundle_default, .atmosphere => return Error.InvalidReference,
    }
}

fn ingestMeasurementSampleCount(ingests: []const Ingest, binding: Binding) u32 {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (std.mem.eql(u8, ingest_ref.output_name, "radiance")) return ingest.loaded_spectra.sampleCount(.radiance);
    if (std.mem.eql(u8, ingest_ref.output_name, "irradiance")) return ingest.loaded_spectra.sampleCount(.irradiance);
    return 0;
}

fn resolveInstrumentLineShapeTable(ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").InstrumentLineShapeTable {
    const ingest_ref = binding.ingestReference().?;
    const ingest = findIngest(ingests, ingest_ref.ingest_name) orelse return Error.MissingIngest;
    if (!std.mem.eql(u8, ingest_ref.output_name, "instrument_line_shape_table")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.instrument_line_shape_table;
}

fn hydrateSceneFromIngestMeasurement(
    allocator: Allocator,
    ingests: []const Ingest,
    scene: *Scene,
    binding: Binding,
) !void {
    if (binding.kind() != .ingest) return;

    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "radiance")) return;

    scene.observation_model.measured_wavelengths_nm = try ingest.loaded_spectra.wavelengthsForKind(allocator, .radiance);
    scene.observation_model.owns_measured_wavelengths = scene.observation_model.measured_wavelengths_nm.len != 0;
    scene.observation_model.reference_radiance = try spectral_ascii_runtime.channelValuesForKind(allocator, ingest.loaded_spectra, .radiance);
    scene.observation_model.owns_reference_radiance = scene.observation_model.reference_radiance.len != 0;
    scene.observation_model.ingested_noise_sigma = try ingest.loaded_spectra.noiseSigmaForKind(allocator, .radiance);
    if (!scene.observation_model.operational_solar_spectrum.enabled()) {
        scene.observation_model.operational_solar_spectrum = if (ingest.loaded_spectra.metadata.operational_solar_spectrum.enabled())
            try ingest.loaded_spectra.metadata.operational_solar_spectrum.clone(allocator)
        else
            try ingest.loaded_spectra.solarSpectrumForKind(allocator, .irradiance);
    }
    if (scene.observation_model.measured_wavelengths_nm.len != 0) {
        scene.spectral_grid.start_nm = scene.observation_model.measured_wavelengths_nm[0];
        scene.spectral_grid.end_nm = scene.observation_model.measured_wavelengths_nm[scene.observation_model.measured_wavelengths_nm.len - 1];
        scene.spectral_grid.sample_count = @intCast(scene.observation_model.measured_wavelengths_nm.len);
    }
}

fn resolveOperationalSolarSpectrum(allocator: Allocator, ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").OperationalSolarSpectrum {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "operational_solar_spectrum")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.operational_solar_spectrum.clone(allocator);
}

fn resolveOperationalReferenceGrid(allocator: Allocator, ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").OperationalReferenceGrid {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "operational_refspec_grid")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.operational_refspec_grid.clone(allocator);
}

fn resolveSpectroscopyLineList(
    allocator: Allocator,
    assets: []const Asset,
    spectroscopy: Spectroscopy,
) !?ReferenceData.SpectroscopyLineList {
    if (spectroscopy.line_list.kind() != .asset) return null;

    var line_asset = try loadResolvedAsset(allocator, assets, spectroscopy.line_list, .spectroscopy_line_list);
    defer line_asset.deinit(allocator);

    var line_list = try line_asset.toSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    const wants_sidecars = spectroscopy.strong_lines.kind() == .asset or spectroscopy.line_mixing.kind() == .asset;
    if (wants_sidecars) {
        if (spectroscopy.strong_lines.kind() != .asset or spectroscopy.line_mixing.kind() != .asset) {
            return Error.InvalidReference;
        }

        var strong_asset = try loadResolvedAsset(allocator, assets, spectroscopy.strong_lines, .spectroscopy_strong_line_set);
        defer strong_asset.deinit(allocator);
        var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
        defer strong_lines.deinit(allocator);

        var relaxation_asset = try loadResolvedAsset(allocator, assets, spectroscopy.line_mixing, .spectroscopy_relaxation_matrix);
        defer relaxation_asset.deinit(allocator);
        var relaxation_matrix = try relaxation_asset.toSpectroscopyRelaxationMatrix(allocator);
        defer relaxation_matrix.deinit(allocator);

        try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    }

    return line_list;
}

fn resolveCollisionInducedAbsorptionTable(
    allocator: Allocator,
    assets: []const Asset,
    binding: Binding,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    if (binding.kind() != .asset) return null;

    var loaded = try loadResolvedAsset(
        allocator,
        assets,
        binding,
        .collision_induced_absorption_table,
    );
    defer loaded.deinit(allocator);
    const table = try loaded.toCollisionInducedAbsorptionTable(allocator);
    return table;
}

fn loadResolvedAsset(
    allocator: Allocator,
    assets: []const Asset,
    binding: Binding,
    kind: reference_assets.AssetKind,
) !reference_assets.LoadedAsset {
    const asset = findAsset(assets, binding.name()) orelse return Error.MissingAsset;
    return reference_assets.loadExternalAsset(
        allocator,
        kind,
        asset.name,
        asset.resolved_path,
        asset.format,
    );
}

fn resolveOperationalLut(
    allocator: Allocator,
    ingests: []const Ingest,
    binding: Binding,
    expected_output: []const u8,
) !@import("../../model/Instrument.zig").OperationalCrossSectionLut {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, expected_output)) return Error.MissingIngestOutput;
    return if (std.mem.eql(u8, expected_output, "o2_operational_lut"))
        ingest.loaded_spectra.metadata.o2_operational_lut.clone(allocator)
    else
        ingest.loaded_spectra.metadata.o2o2_operational_lut.clone(allocator);
}

fn getReferencedIngest(ingests: []const Ingest, reference: @import("../../model/Binding.zig").IngestRef) Ingest {
    return findIngest(ingests, reference.ingest_name) orelse unreachable;
}

fn findAsset(assets: []const Asset, name: []const u8) ?Asset {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.name, name)) return asset;
    }
    return null;
}

fn hasAsset(assets: []const Asset, name: []const u8) bool {
    return findAsset(assets, name) != null;
}

fn findIngest(ingests: []const Ingest, name: []const u8) ?Ingest {
    for (ingests) |ingest| {
        if (std.mem.eql(u8, ingest.name, name)) return ingest;
    }
    return null;
}

fn hasIngest(ingests: []const Ingest, name: []const u8) bool {
    return findIngest(ingests, name) != null;
}

fn ensureDistinctProducts(products: []const Product) !void {
    for (products, 0..) |product, index| {
        for (products[index + 1 ..]) |other| {
            if (std.mem.eql(u8, product.name, other.name)) return Error.InvalidValue;
        }
    }
}

fn findStageProduct(stage: Stage, name: []const u8) ?Product {
    for (stage.products) |product| {
        if (std.mem.eql(u8, product.name, name)) return product;
    }
    return null;
}

fn findProductAcrossStages(simulation: ?*const StageResolution, retrieval: ?*const StageResolution, name: []const u8) ?Product {
    if (simulation) |value| {
        if (findStageProduct(value.stage, name)) |product| return product;
    }
    if (retrieval) |value| {
        if (findStageProduct(value.stage, name)) |product| return product;
    }
    return null;
}

fn inferSpectralGrid(bands: SpectralBandSet) !SpectralGrid {
    if (bands.items.len == 0) return Error.MissingField;

    var start_nm = bands.items[0].start_nm;
    var end_nm = bands.items[0].end_nm;
    var step_nm = bands.items[0].step_nm;
    for (bands.items[1..]) |band| {
        start_nm = @min(start_nm, band.start_nm);
        end_nm = @max(end_nm, band.end_nm);
        step_nm = @min(step_nm, band.step_nm);
    }

    const sample_count = @as(u32, @intFromFloat(@round(((end_nm - start_nm) / step_nm) + 1.0)));
    return .{
        .start_nm = start_nm,
        .end_nm = end_nm,
        .sample_count = sample_count,
    };
}

test "document resolves revised common example" {
    var document = try Document.parseFile(std.testing.allocator, "data/examples/zdisamar_common_use.yaml");
    defer document.deinit();

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    try std.testing.expectEqualStrings("o2a_twin_common", resolved.metadata.id);
    try std.testing.expect(resolved.simulation != null);
    try std.testing.expect(resolved.retrieval != null);
    try std.testing.expectEqual(@as(usize, 2), resolved.outputs.len);
    try std.testing.expectEqualStrings("truth_radiance", resolved.retrieval.?.inverse.?.measurements.source.name());
    try std.testing.expectEqual(@as(u32, 1301), resolved.simulation.?.scene.spectral_grid.sample_count);
}

test "document rejects unknown fields in strict mode" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: bad
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: sim
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 10
        \\        viewing_zenith_deg: 5
        \\        relative_azimuth_deg: 20
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 4
        \\      bands:
        \\        o2a:
        \\          start_nm: 758.0
        \\          end_nm: 759.0
        \\          step_nm: 0.5
        \\      surface:
        \\        model: lambertian
        \\        unknown_flag: true
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var document = try Document.parse(std.testing.allocator, "inline.yaml", ".", source);
    defer document.deinit();

    try std.testing.expectError(Error.UnknownField, document.resolve(std.testing.allocator));
}
