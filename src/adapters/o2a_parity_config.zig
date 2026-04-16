//! Purpose:
//!   Parse, validate, resolve, and execute the narrow live YAML surface for the
//!   retained O2A vendor-parity case.
//!
//! Physics:
//!   The supported YAML subset expresses the same O2 A-band forcing case that
//!   the vendored DISAMAR `Config_O2_with_CIA.in` drives today: geometry,
//!   interval-grid semantics, aerosol placement, O2 line-gas controls, O2-O2
//!   CIA enablement, and the scalar RTM control bundle used by the parity lane.
//!
//! Vendor:
//!   `readConfigFileModule::GENERAL/INSTRUMENT/ATMOSPHERIC_INTERVALS/AEROSOL/O2/O2-O2`
//!   and `verifyConfigFileModule::fit-interval and interval-grid checks`
//!
//! Design:
//!   This adapter intentionally supports only the executable O2A parity subset.
//!   It parses a strict indentation-based YAML subset into a lightweight node
//!   tree, resolves template inheritance, then compiles the merged stage into
//!   the typed runtime contract consumed by the O2A vendor-parity runner.
//!
//! Invariants:
//!   Unknown keys are rejected, stage references must resolve, asset references
//!   must resolve, and every declared control must either affect the resolved
//!   runtime or fail explicitly.
//!
//! Validation:
//!   Unit tests in this file cover strict unknown-field handling, template
//!   inheritance, asset resolution, semantic mapping, and CLI-style execution
//!   through the resolved parity runner.

const std = @import("std");
const parity_runtime = @import("../o2a/data/vendor_parity_runtime.zig");

const AtmosphereModel = @import("../model/Atmosphere.zig");
const MeasurementSpace = @import("../kernels/transport/measurement.zig");
const RtmControls = @import("../kernels/transport/common.zig").RtmControls;
const SpectralGrid = @import("../model/Spectrum.zig").SpectralGrid;
const parity_support = @import("../o2a/data/vendor_parity_support.zig");

const Allocator = std.mem.Allocator;

pub const LoadedResolvedCase = struct {
    arena: std.heap.ArenaAllocator,
    root: Node,
    resolved: parity_runtime.ResolvedVendorO2ACase,

    pub fn deinit(self: *LoadedResolvedCase) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const RunSummary = struct {
    metadata: parity_runtime.Metadata,
    scene_id: []const u8,
    reference_path: []const u8,
    product_summary: MeasurementSpace.MeasurementSpaceSummary,
    comparison: parity_support.ComparisonMetrics,
};

pub fn loadResolvedCaseFromFile(
    allocator: Allocator,
    path: []const u8,
) !LoadedResolvedCase {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    const bytes = try std.fs.cwd().readFileAlloc(arena_allocator, path, 512 * 1024);
    const root = try parseDocument(arena_allocator, bytes);
    const resolved = try compileResolvedCase(arena_allocator, root);
    return .{
        .arena = arena,
        .root = root,
        .resolved = resolved,
    };
}

pub fn renderResolvedJson(
    allocator: Allocator,
    resolved: *const parity_runtime.ResolvedVendorO2ACase,
) ![]u8 {
    const isotopes_u32 = try allocator.alloc(u32, resolved.o2.isotopes_sim.len);
    defer allocator.free(isotopes_u32);
    for (resolved.o2.isotopes_sim, 0..) |value, index| isotopes_u32[index] = value;

    const json_view = .{
        .metadata = resolved.metadata,
        .plan = resolved.plan,
        .inputs = resolved.inputs,
        .scene_id = resolved.scene_id,
        .spectral_grid = resolved.spectral_grid,
        .layer_count = resolved.layer_count,
        .sublayer_divisions = resolved.sublayer_divisions,
        .surface_pressure_hpa = resolved.surface_pressure_hpa,
        .fit_interval_index_1based = resolved.fit_interval_index_1based,
        .intervals = resolved.intervals,
        .surface_albedo = resolved.surface_albedo,
        .geometry = resolved.geometry,
        .aerosol = resolved.aerosol,
        .observation = resolved.observation,
        .o2 = .{
            .line_list_asset = resolved.o2.line_list_asset,
            .line_mixing_asset = resolved.o2.line_mixing_asset,
            .strong_lines_asset = resolved.o2.strong_lines_asset,
            .line_mixing_factor = resolved.o2.line_mixing_factor,
            .isotopes_sim = isotopes_u32,
            .threshold_line_sim = resolved.o2.threshold_line_sim,
            .cutoff_sim_cm1 = resolved.o2.cutoff_sim_cm1,
        },
        .o2o2 = resolved.o2o2,
        .rtm_controls = resolved.rtm_controls,
        .outputs = resolved.outputs,
        .validation = resolved.validation,
    };
    return try std.fmt.allocPrint(
        allocator,
        "{f}\n",
        .{std.json.fmt(json_view, .{ .whitespace = .indent_2 })},
    );
}

pub fn runResolvedCaseAndWriteOutputs(
    allocator: Allocator,
    resolved: *const parity_runtime.ResolvedVendorO2ACase,
) !RunSummary {
    var reflectance_case = try parity_support.runResolvedVendorO2AReflectanceCase(allocator, resolved);
    defer reflectance_case.deinit(allocator);

    const comparison = parity_support.computeComparisonMetrics(
        &reflectance_case.product,
        reflectance_case.reference,
        0.0,
    );

    const summary: RunSummary = .{
        .metadata = resolved.metadata,
        .scene_id = resolved.scene_id,
        .reference_path = resolved.inputs.vendor_reference_csv.path,
        .product_summary = reflectance_case.product.summary,
        .comparison = comparison,
    };

    for (resolved.outputs) |output| {
        switch (output.kind) {
            .summary_json => try writeSummaryJson(output.path, summary),
            .generated_spectrum_csv => try writeGeneratedSpectrumCsv(output.path, &reflectance_case.product),
        }
    }

    return summary;
}

const Node = union(enum) {
    map: []MapEntry,
    seq: []Node,
    scalar: []const u8,
};

const MapEntry = struct {
    key: []const u8,
    value: Node,
    line: usize,
};

const Line = struct {
    number: usize,
    indent: usize,
    text: []const u8,
};

const KeyValueSplit = struct {
    key: []const u8,
    value: ?[]const u8,
};

const Parser = struct {
    allocator: Allocator,
    lines: []const Line,
    index: usize = 0,

    fn parse(self: *Parser) anyerror!Node {
        return self.parseBlock(0);
    }

    fn parseBlock(self: *Parser, indent: usize) anyerror!Node {
        if (self.index >= self.lines.len) return error.UnexpectedEndOfYaml;
        const line = self.lines[self.index];
        if (line.indent < indent) return error.InvalidYamlIndentation;
        if (line.indent > indent) return error.InvalidYamlIndentation;
        if (isSequenceLine(line.text)) return self.parseSequence(indent);
        return self.parseMap(indent);
    }

    fn parseMap(self: *Parser, indent: usize) anyerror!Node {
        var entries = std.ArrayList(MapEntry).empty;
        errdefer entries.deinit(self.allocator);

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent) break;
            if (line.indent > indent) return error.InvalidYamlIndentation;
            if (isSequenceLine(line.text)) break;

            const split = splitKeyValue(line.text) orelse return error.InvalidYamlSyntax;
            self.index += 1;
            const value = if (split.value) |inline_value|
                Node{ .scalar = inline_value }
            else if (self.index < self.lines.len and self.lines[self.index].indent > indent)
                try self.parseBlock(indent + 2)
            else
                Node{ .scalar = "" };

            try entries.append(self.allocator, .{
                .key = split.key,
                .value = value,
                .line = line.number,
            });
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }

    fn parseSequence(self: *Parser, indent: usize) anyerror!Node {
        var items = std.ArrayList(Node).empty;
        errdefer items.deinit(self.allocator);

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent) break;
            if (line.indent > indent) return error.InvalidYamlIndentation;
            if (!isSequenceLine(line.text)) break;

            const rest = std.mem.trimLeft(u8, line.text[1..], " ");
            if (rest.len == 0) {
                self.index += 1;
                try items.append(self.allocator, try self.parseBlock(indent + 2));
                continue;
            }

            if (splitKeyValue(rest)) |inline_map_entry| {
                self.index += 1;
                try items.append(self.allocator, try self.parseInlineSequenceMap(indent, line.number, inline_map_entry));
                continue;
            }

            self.index += 1;
            try items.append(self.allocator, .{ .scalar = rest });
        }

        return .{ .seq = try items.toOwnedSlice(self.allocator) };
    }

    fn parseInlineSequenceMap(
        self: *Parser,
        indent: usize,
        line_number: usize,
        first_entry: KeyValueSplit,
    ) anyerror!Node {
        var entries = std.ArrayList(MapEntry).empty;
        errdefer entries.deinit(self.allocator);

        const first_value = if (first_entry.value) |inline_value|
            Node{ .scalar = inline_value }
        else if (self.index < self.lines.len and self.lines[self.index].indent > indent)
            try self.parseBlock(indent + 4)
        else
            Node{ .scalar = "" };
        try entries.append(self.allocator, .{
            .key = first_entry.key,
            .value = first_value,
            .line = line_number,
        });

        while (self.index < self.lines.len) {
            const line = self.lines[self.index];
            if (line.indent < indent + 2) break;
            if (line.indent > indent + 2) return error.InvalidYamlIndentation;
            if (isSequenceLine(line.text)) break;

            const split = splitKeyValue(line.text) orelse return error.InvalidYamlSyntax;
            self.index += 1;
            const value = if (split.value) |inline_value|
                Node{ .scalar = inline_value }
            else if (self.index < self.lines.len and self.lines[self.index].indent > indent + 2)
                try self.parseBlock(indent + 4)
            else
                Node{ .scalar = "" };
            try entries.append(self.allocator, .{
                .key = split.key,
                .value = value,
                .line = line.number,
            });
        }

        return .{ .map = try entries.toOwnedSlice(self.allocator) };
    }
};

fn parseDocument(allocator: Allocator, bytes: []const u8) !Node {
    var lines = std.ArrayList(Line).empty;
    defer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, bytes, '\n');
    var line_number: usize = 1;
    while (iter.next()) |raw_line| : (line_number += 1) {
        const trimmed_right = std.mem.trimRight(u8, raw_line, "\r ");
        if (trimmed_right.len == 0) continue;
        const trimmed_left = std.mem.trimLeft(u8, trimmed_right, " ");
        if (trimmed_left.len == 0 or trimmed_left[0] == '#') continue;
        const indent = trimmed_right.len - trimmed_left.len;
        if ((indent % 2) != 0) return error.InvalidYamlIndentation;
        if (std.mem.indexOfScalar(u8, trimmed_right, '\t') != null) return error.InvalidYamlIndentation;
        try lines.append(allocator, .{
            .number = line_number,
            .indent = indent,
            .text = trimmed_left,
        });
    }

    if (lines.items.len == 0) return error.EmptyYamlDocument;
    var parser = Parser{
        .allocator = allocator,
        .lines = try lines.toOwnedSlice(allocator),
    };
    return parser.parse();
}

fn compileResolvedCase(
    allocator: Allocator,
    root: Node,
) !parity_runtime.ResolvedVendorO2ACase {
    const root_map = try expectMap(root);
    try expectOnlyFields(root_map, &.{
        "schema_version",
        "metadata",
        "inputs",
        "templates",
        "experiment",
        "outputs",
        "validation",
    });

    if (try requiredU32(root_map, "schema_version") != 1) return error.UnsupportedSchemaVersion;
    const metadata_node = try requiredField(root_map, "metadata");
    const inputs_node = try requiredField(root_map, "inputs");
    const templates_node = try requiredField(root_map, "templates");
    const experiment_node = try requiredField(root_map, "experiment");
    const outputs_node = try optionalField(root_map, "outputs");
    const validation_node = try requiredField(root_map, "validation");

    const metadata = try compileMetadata(try expectMap(metadata_node));
    const validation = try compileValidation(try expectMap(validation_node));
    const asset_catalog = try compileAssets(allocator, inputs_node);

    const experiment_map = try expectMap(experiment_node);
    try expectOnlyFields(experiment_map, &.{"simulation"});
    const simulation_node = try requiredField(experiment_map, "simulation");
    const simulation_map = try expectMap(simulation_node);
    try expectOnlyFields(simulation_map, &.{ "from", "plan", "scene" });
    const template_name = try requiredString(simulation_map, "from");

    const template_map = try expectMap(templates_node);
    const template_node = findField(template_map, template_name) orelse return error.UnknownTemplateReference;
    const template_fields = try expectMap(template_node.value);
    try expectOnlyFields(template_fields, &.{ "plan", "scene" });

    const merged_plan = try mergeOptionalNodes(
        allocator,
        try optionalField(template_fields, "plan"),
        try optionalField(simulation_map, "plan"),
    );
    const merged_scene = try mergeOptionalNodes(
        allocator,
        try optionalField(template_fields, "scene"),
        try optionalField(simulation_map, "scene"),
    );

    const plan = try compilePlan(try expectMap(merged_plan.?));
    const scene = try compileScene(allocator, try expectMap(merged_scene.?), asset_catalog);
    const outputs = try compileOutputs(allocator, outputs_node);

    return .{
        .metadata = metadata,
        .plan = plan,
        .inputs = scene.inputs,
        .scene_id = scene.scene_id,
        .spectral_grid = scene.spectral_grid,
        .layer_count = scene.layer_count,
        .sublayer_divisions = scene.sublayer_divisions,
        .surface_pressure_hpa = scene.surface_pressure_hpa,
        .fit_interval_index_1based = scene.fit_interval_index_1based,
        .intervals = scene.intervals,
        .surface_albedo = scene.surface_albedo,
        .geometry = scene.geometry,
        .aerosol = scene.aerosol,
        .observation = scene.observation,
        .o2 = scene.o2,
        .o2o2 = scene.o2o2,
        .rtm_controls = scene.rtm_controls,
        .outputs = outputs,
        .validation = validation,
    };
}

const CompiledScene = struct {
    inputs: parity_runtime.InputsSpec,
    scene_id: []const u8,
    spectral_grid: SpectralGrid,
    layer_count: u32,
    sublayer_divisions: u8,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: u32,
    intervals: []const AtmosphereModel.VerticalInterval,
    surface_albedo: f64,
    geometry: parity_runtime.GeometrySpec,
    aerosol: parity_runtime.AerosolSpec,
    observation: parity_runtime.ObservationSpec,
    o2: parity_runtime.LineGasSpec,
    o2o2: parity_runtime.CiaSpec,
    rtm_controls: RtmControls,
};

const AssetBinding = struct {
    id: []const u8,
    asset: parity_runtime.ExternalAsset,
};

fn compileMetadata(map: []const MapEntry) !parity_runtime.Metadata {
    try expectOnlyFields(map, &.{ "id", "workspace", "description" });
    return .{
        .id = try requiredString(map, "id"),
        .workspace = try requiredString(map, "workspace"),
        .description = try optionalString(map, "description") orelse "",
    };
}

fn compileValidation(map: []const MapEntry) !parity_runtime.ValidationPolicy {
    try expectOnlyFields(map, &.{
        "strict_unknown_fields",
        "require_resolved_assets",
        "require_resolved_stage_references",
    });
    const strict_unknown_fields = try requiredBool(map, "strict_unknown_fields");
    const require_resolved_assets = try requiredBool(map, "require_resolved_assets");
    const require_resolved_stage_references = try requiredBool(map, "require_resolved_stage_references");
    if (!strict_unknown_fields or !require_resolved_assets or !require_resolved_stage_references) {
        return error.UnsupportedValidationPolicy;
    }
    return .{
        .strict_unknown_fields = strict_unknown_fields,
        .require_resolved_assets = require_resolved_assets,
        .require_resolved_stage_references = require_resolved_stage_references,
    };
}

fn compileAssets(allocator: Allocator, inputs_node: Node) ![]const AssetBinding {
    const inputs_map = try expectMap(inputs_node);
    try expectOnlyFields(inputs_map, &.{"assets"});
    const assets_node = try requiredField(inputs_map, "assets");
    const assets_map = try expectMap(assets_node);

    var assets = std.ArrayList(AssetBinding).empty;
    errdefer assets.deinit(allocator);
    for (assets_map) |entry| {
        const asset_map = try expectMap(entry.value);
        try expectOnlyFields(asset_map, &.{ "kind", "path", "format" });
        if (!std.mem.eql(u8, try requiredString(asset_map, "kind"), "file")) {
            return error.UnsupportedAssetKind;
        }
        try assets.append(allocator, .{
            .id = entry.key,
            .asset = .{
                .id = entry.key,
                .path = try requiredString(asset_map, "path"),
                .format = try requiredString(asset_map, "format"),
            },
        });
    }
    return try assets.toOwnedSlice(allocator);
}

fn compilePlan(map: []const MapEntry) !parity_runtime.PlanSpec {
    try expectOnlyFields(map, &.{ "model_family", "transport", "execution" });
    const model_family = try requiredString(map, "model_family");
    if (!std.mem.eql(u8, model_family, "disamar_standard")) return error.UnsupportedModelFamily;

    const transport_map = try expectMap(try requiredField(map, "transport"));
    try expectOnlyFields(transport_map, &.{"solver"});
    const transport_solver = try requiredString(transport_map, "solver");
    if (!std.mem.eql(u8, transport_solver, "dispatcher")) return error.UnsupportedTransportSolver;

    const execution_map = try expectMap(try requiredField(map, "execution"));
    try expectOnlyFields(execution_map, &.{ "solver_mode", "derivative_mode" });
    const solver_mode = try requiredString(execution_map, "solver_mode");
    const derivative_mode = try requiredString(execution_map, "derivative_mode");
    if (!std.mem.eql(u8, solver_mode, "scalar")) return error.UnsupportedExecutionMode;
    if (!std.mem.eql(u8, derivative_mode, "none")) return error.UnsupportedDerivativeMode;

    return .{
        .model_family = model_family,
        .transport_solver = transport_solver,
        .execution_solver_mode = solver_mode,
        .execution_derivative_mode = derivative_mode,
    };
}

fn compileScene(
    allocator: Allocator,
    map: []const MapEntry,
    assets: []const AssetBinding,
) !CompiledScene {
    try expectOnlyFields(map, &.{
        "id",
        "geometry",
        "atmosphere",
        "bands",
        "absorbers",
        "surface",
        "aerosols",
        "measurement_model",
        "rtm",
    });

    const geometry = try compileGeometry(try expectMap(try requiredField(map, "geometry")));
    const atmosphere = try compileAtmosphere(allocator, try expectMap(try requiredField(map, "atmosphere")));
    const spectral_grid = try compileBands(try expectMap(try requiredField(map, "bands")));
    const absorbers_map = try expectMap(try requiredField(map, "absorbers"));
    const o2 = try compileO2(allocator, absorbers_map, assets);
    const o2o2 = try compileO2O2(absorbers_map, assets);
    const surface_albedo = try compileSurface(try expectMap(try requiredField(map, "surface")));
    const aerosol = try compileAerosol(try expectMap(try requiredField(map, "aerosols")));
    const observation = try compileObservation(try expectMap(try requiredField(map, "measurement_model")), assets);
    const rtm_controls = try compileRtmControls(try expectMap(try requiredField(map, "rtm")));

    const atmosphere_profile_asset = try lookupAsset(assets, try requiredString(atmosphere.profile_source_map, "asset"));
    const solar_reference_asset = try lookupAsset(assets, observation.solar_reference_asset_id);
    if (!std.mem.eql(u8, solar_reference_asset.id, "vendor_reference_csv")) {
        return error.UnsupportedSolarReferenceAsset;
    }
    const airmass_factor_lut = try lookupAsset(assets, "airmass_factor_lut");

    return .{
        .inputs = .{
            .atmosphere_profile = atmosphere_profile_asset,
            .vendor_reference_csv = solar_reference_asset,
            .airmass_factor_lut = airmass_factor_lut,
        },
        .scene_id = try requiredString(map, "id"),
        .spectral_grid = spectral_grid,
        .layer_count = atmosphere.layer_count,
        .sublayer_divisions = atmosphere.sublayer_divisions,
        .surface_pressure_hpa = atmosphere.surface_pressure_hpa,
        .fit_interval_index_1based = atmosphere.fit_interval_index_1based,
        .intervals = atmosphere.intervals,
        .surface_albedo = surface_albedo,
        .geometry = geometry,
        .aerosol = aerosol,
        .observation = observation,
        .o2 = o2,
        .o2o2 = o2o2,
        .rtm_controls = rtm_controls,
    };
}

const CompiledAtmosphere = struct {
    layer_count: u32,
    sublayer_divisions: u8,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: u32,
    intervals: []const AtmosphereModel.VerticalInterval,
    profile_source_map: []const MapEntry,
};

fn compileGeometry(map: []const MapEntry) !parity_runtime.GeometrySpec {
    try expectOnlyFields(map, &.{ "model", "solar_zenith_deg", "viewing_zenith_deg", "relative_azimuth_deg" });
    const model_text = try requiredString(map, "model");
    if (!std.mem.eql(u8, model_text, "pseudo_spherical")) return error.UnsupportedGeometryModel;
    return .{
        .model = .pseudo_spherical,
        .solar_zenith_deg = try requiredF64(map, "solar_zenith_deg"),
        .viewing_zenith_deg = try requiredF64(map, "viewing_zenith_deg"),
        .relative_azimuth_deg = try requiredF64(map, "relative_azimuth_deg"),
    };
}

fn compileAtmosphere(allocator: Allocator, map: []const MapEntry) !CompiledAtmosphere {
    try expectOnlyFields(map, &.{ "layering", "thermodynamics", "boundary", "interval_grid" });
    const layering_map = try expectMap(try requiredField(map, "layering"));
    try expectOnlyFields(layering_map, &.{ "layer_count", "sublayer_divisions" });

    const thermodynamics_map = try expectMap(try requiredField(map, "thermodynamics"));
    try expectOnlyFields(thermodynamics_map, &.{"profile"});
    const profile_map = try expectMap(try requiredField(thermodynamics_map, "profile"));
    try expectOnlyFields(profile_map, &.{"source"});
    const source_map = try expectMap(try requiredField(profile_map, "source"));
    try expectOnlyFields(source_map, &.{"asset"});

    const boundary_map = try expectMap(try requiredField(map, "boundary"));
    try expectOnlyFields(boundary_map, &.{"surface_pressure_hpa"});

    const interval_grid_map = try expectMap(try requiredField(map, "interval_grid"));
    try expectOnlyFields(interval_grid_map, &.{ "semantics", "fit_interval_index_1based", "intervals" });
    if (!std.mem.eql(u8, try requiredString(interval_grid_map, "semantics"), "explicit_pressure_bounds")) {
        return error.UnsupportedIntervalSemantics;
    }
    const intervals_node = try requiredField(interval_grid_map, "intervals");
    const interval_nodes = try expectSeq(intervals_node);
    var intervals = std.ArrayList(AtmosphereModel.VerticalInterval).empty;
    errdefer intervals.deinit(allocator);
    for (interval_nodes) |interval_node| {
        const interval_map = try expectMap(interval_node);
        try expectOnlyFields(interval_map, &.{ "index_1based", "top_pressure_hpa", "bottom_pressure_hpa", "altitude_divisions" });
        try intervals.append(allocator, .{
            .index_1based = try requiredU32(interval_map, "index_1based"),
            .top_pressure_hpa = try requiredF64(interval_map, "top_pressure_hpa"),
            .bottom_pressure_hpa = try requiredF64(interval_map, "bottom_pressure_hpa"),
            .altitude_divisions = try requiredU32(interval_map, "altitude_divisions"),
        });
    }

    return .{
        .layer_count = try requiredU32(layering_map, "layer_count"),
        .sublayer_divisions = try requiredU8(layering_map, "sublayer_divisions"),
        .surface_pressure_hpa = try requiredF64(boundary_map, "surface_pressure_hpa"),
        .fit_interval_index_1based = try requiredU32(interval_grid_map, "fit_interval_index_1based"),
        .intervals = try intervals.toOwnedSlice(allocator),
        .profile_source_map = source_map,
    };
}

fn compileBands(map: []const MapEntry) !SpectralGrid {
    try expectOnlyFields(map, &.{"o2a"});
    const o2a_map = try expectMap(try requiredField(map, "o2a"));
    try expectOnlyFields(o2a_map, &.{ "start_nm", "end_nm", "sample_count", "step_nm" });
    const start_nm = try requiredF64(o2a_map, "start_nm");
    const end_nm = try requiredF64(o2a_map, "end_nm");
    const sample_count = if (try optionalField(o2a_map, "sample_count")) |node|
        try parseU32(node)
    else if (try optionalField(o2a_map, "step_nm")) |node|
        try sampleCountFromStep(start_nm, end_nm, try parseF64(node))
    else
        return error.MissingSpectralSampling;
    return .{
        .start_nm = start_nm,
        .end_nm = end_nm,
        .sample_count = sample_count,
    };
}

fn sampleCountFromStep(start_nm: f64, end_nm: f64, step_nm: f64) !u32 {
    if (!std.math.isFinite(step_nm) or step_nm <= 0.0) return error.InvalidSpectralSampling;
    const approximate = ((end_nm - start_nm) / step_nm) + 1.0;
    const rounded = @round(approximate);
    if (!std.math.approxEqAbs(f64, approximate, rounded, 1.0e-9)) return error.InvalidSpectralSampling;
    return @intFromFloat(rounded);
}

fn compileO2(
    allocator: Allocator,
    absorbers_map: []const MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.LineGasSpec {
    const o2_map = try expectMap((try findRequiredField(absorbers_map, "o2")).value);
    try expectOnlyFields(o2_map, &.{ "species", "spectroscopy" });
    if (!std.mem.eql(u8, try requiredString(o2_map, "species"), "o2")) return error.UnsupportedAbsorberSpecies;

    const spectroscopy_map = try expectMap(try requiredField(o2_map, "spectroscopy"));
    try expectOnlyFields(spectroscopy_map, &.{
        "model",
        "line_list_asset",
        "line_mixing_asset",
        "strong_lines_asset",
        "line_mixing_factor",
        "isotopes_sim",
        "threshold_line_sim",
        "cutoff_sim_cm1",
    });
    if (!std.mem.eql(u8, try requiredString(spectroscopy_map, "model"), "line_by_line")) {
        return error.UnsupportedSpectroscopyModel;
    }

    const isotopes = if (try optionalField(spectroscopy_map, "isotopes_sim")) |node|
        try parseInlineU8List(allocator, try parseString(node))
    else
        try allocator.dupe(u8, &.{});

    return .{
        .line_list_asset = try lookupAsset(assets, try requiredString(spectroscopy_map, "line_list_asset")),
        .line_mixing_asset = try lookupAsset(assets, try requiredString(spectroscopy_map, "line_mixing_asset")),
        .strong_lines_asset = try lookupAsset(assets, try requiredString(spectroscopy_map, "strong_lines_asset")),
        .line_mixing_factor = try optionalF64(spectroscopy_map, "line_mixing_factor"),
        .isotopes_sim = isotopes,
        .threshold_line_sim = try optionalF64(spectroscopy_map, "threshold_line_sim"),
        .cutoff_sim_cm1 = try optionalF64(spectroscopy_map, "cutoff_sim_cm1"),
    };
}

fn compileO2O2(
    absorbers_map: []const MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.CiaSpec {
    const o2o2_entry = try findRequiredField(absorbers_map, "o2o2");
    const o2o2_map = try expectMap(o2o2_entry.value);
    try expectOnlyFields(o2o2_map, &.{ "species", "spectroscopy" });
    if (!std.mem.eql(u8, try requiredString(o2o2_map, "species"), "o2o2")) return error.UnsupportedAbsorberSpecies;

    const spectroscopy_map = try expectMap(try requiredField(o2o2_map, "spectroscopy"));
    try expectOnlyFields(spectroscopy_map, &.{ "model", "cia_asset", "enabled" });
    if (!std.mem.eql(u8, try requiredString(spectroscopy_map, "model"), "cia")) return error.UnsupportedSpectroscopyModel;
    const enabled = (try optionalBool(spectroscopy_map, "enabled")) orelse true;
    return .{
        .enabled = enabled,
        .cia_asset = if (enabled) try lookupAsset(assets, try requiredString(spectroscopy_map, "cia_asset")) else null,
    };
}

fn compileSurface(map: []const MapEntry) !f64 {
    try expectOnlyFields(map, &.{ "model", "albedo", "provider" });
    if (!std.mem.eql(u8, try requiredString(map, "model"), "lambertian")) return error.UnsupportedSurfaceModel;
    if (try optionalString(map, "provider")) |provider| {
        if (!std.mem.eql(u8, provider, "builtin.lambertian_surface")) return error.UnsupportedSurfaceProvider;
    }
    return try requiredF64(map, "albedo");
}

fn compileAerosol(map: []const MapEntry) !parity_runtime.AerosolSpec {
    try expectOnlyFields(map, &.{"plume"});
    const plume_map = try expectMap(try requiredField(map, "plume"));
    try expectOnlyFields(plume_map, &.{
        "model",
        "optical_depth_550_nm",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "layer_center_km",
        "layer_width_km",
        "placement",
    });
    if (!std.mem.eql(u8, try requiredString(plume_map, "model"), "hg_scattering")) return error.UnsupportedAerosolModel;

    const placement_map = try expectMap(try requiredField(plume_map, "placement"));
    try expectOnlyFields(placement_map, &.{ "semantics", "interval_index_1based", "top_pressure_hpa", "bottom_pressure_hpa" });
    if (!std.mem.eql(u8, try requiredString(placement_map, "semantics"), "explicit_interval_bounds")) {
        return error.UnsupportedAerosolPlacement;
    }

    return .{
        .optical_depth = try requiredF64(plume_map, "optical_depth_550_nm"),
        .single_scatter_albedo = try requiredF64(plume_map, "single_scatter_albedo"),
        .asymmetry_factor = try requiredF64(plume_map, "asymmetry_factor"),
        .angstrom_exponent = try requiredF64(plume_map, "angstrom_exponent"),
        .reference_wavelength_nm = 550.0,
        .layer_center_km = try requiredF64(plume_map, "layer_center_km"),
        .layer_width_km = try requiredF64(plume_map, "layer_width_km"),
        .placement = .{
            .semantics = .explicit_interval_bounds,
            .interval_index_1based = try requiredU32(placement_map, "interval_index_1based"),
            .top_pressure_hpa = try requiredF64(placement_map, "top_pressure_hpa"),
            .bottom_pressure_hpa = try requiredF64(placement_map, "bottom_pressure_hpa"),
        },
    };
}

fn compileObservation(
    map: []const MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.ObservationSpec {
    try expectOnlyFields(map, &.{
        "regime",
        "instrument",
        "sampling",
        "spectral_response",
        "illumination",
        "calibration",
        "noise",
    });
    if (!std.mem.eql(u8, try requiredString(map, "regime"), "nadir")) return error.UnsupportedObservationRegime;

    const instrument_map = try expectMap(try requiredField(map, "instrument"));
    try expectOnlyFields(instrument_map, &.{"name"});
    const sampling_map = try expectMap(try requiredField(map, "sampling"));
    try expectOnlyFields(sampling_map, &.{
        "mode",
        "high_resolution_step_nm",
        "high_resolution_half_span_nm",
        "adaptive_reference_grid",
    });
    if (!std.mem.eql(u8, try requiredString(sampling_map, "mode"), "native")) return error.UnsupportedSamplingMode;

    const adaptive_map = try expectMap(try requiredField(sampling_map, "adaptive_reference_grid"));
    try expectOnlyFields(adaptive_map, &.{ "points_per_fwhm", "strong_line_min_divisions", "strong_line_max_divisions" });

    const response_map = try expectMap(try requiredField(map, "spectral_response"));
    try expectOnlyFields(response_map, &.{ "shape", "fwhm_nm" });
    if (!std.mem.eql(u8, try requiredString(response_map, "shape"), "flat_top_n4")) return error.UnsupportedInstrumentLineShape;

    const illumination_map = try expectMap(try requiredField(map, "illumination"));
    try expectOnlyFields(illumination_map, &.{"solar_spectrum"});
    const solar_spectrum_map = try expectMap(try requiredField(illumination_map, "solar_spectrum"));
    try expectOnlyFields(solar_spectrum_map, &.{"from_reference_asset"});
    const solar_reference_asset_id = try requiredString(solar_spectrum_map, "from_reference_asset");
    _ = try lookupAsset(assets, solar_reference_asset_id);

    const calibration_map = try expectMap(try requiredField(map, "calibration"));
    try expectOnlyFields(calibration_map, &.{ "wavelength_shift_nm", "multiplicative_offset", "stray_light" });
    if (!std.math.approxEqAbs(f64, try requiredF64(calibration_map, "wavelength_shift_nm"), 0.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }
    if (!std.math.approxEqAbs(f64, try requiredF64(calibration_map, "multiplicative_offset"), 1.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }
    if (!std.math.approxEqAbs(f64, try requiredF64(calibration_map, "stray_light"), 0.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }

    const noise_map = try expectMap(try requiredField(map, "noise"));
    try expectOnlyFields(noise_map, &.{"model"});
    if (!std.mem.eql(u8, try requiredString(noise_map, "model"), "none")) return error.UnsupportedNoiseModel;

    return .{
        .instrument_name = try requiredString(instrument_map, "name"),
        .regime = .nadir,
        .sampling = .native,
        .noise_model = .none,
        .instrument_line_fwhm_nm = try requiredF64(response_map, "fwhm_nm"),
        .builtin_line_shape = .flat_top_n4,
        .high_resolution_step_nm = try requiredF64(sampling_map, "high_resolution_step_nm"),
        .high_resolution_half_span_nm = try requiredF64(sampling_map, "high_resolution_half_span_nm"),
        .adaptive_reference_grid = .{
            .points_per_fwhm = try requiredU16(adaptive_map, "points_per_fwhm"),
            .strong_line_min_divisions = try requiredU16(adaptive_map, "strong_line_min_divisions"),
            .strong_line_max_divisions = try requiredU16(adaptive_map, "strong_line_max_divisions"),
        },
        .solar_reference_asset_id = solar_reference_asset_id,
    };
}

fn compileRtmControls(map: []const MapEntry) !RtmControls {
    try expectOnlyFields(map, &.{
        "scattering",
        "n_streams",
        "use_adding",
        "num_orders_max",
        "fourier_floor_scalar",
        "threshold_conv_first",
        "threshold_conv_mult",
        "threshold_doubl",
        "threshold_mul",
        "use_spherical_correction",
        "integrate_source_function",
        "renorm_phase_function",
        "stokes_dimension",
    });
    if (!std.mem.eql(u8, try requiredString(map, "scattering"), "multiple")) return error.UnsupportedScatteringMode;
    return .{
        .scattering = .multiple,
        .n_streams = try requiredU16(map, "n_streams"),
        .use_adding = try requiredBool(map, "use_adding"),
        .num_orders_max = try requiredU16(map, "num_orders_max"),
        .fourier_floor_scalar = try requiredU16(map, "fourier_floor_scalar"),
        .threshold_conv_first = try requiredF64(map, "threshold_conv_first"),
        .threshold_conv_mult = try requiredF64(map, "threshold_conv_mult"),
        .threshold_doubl = try requiredF64(map, "threshold_doubl"),
        .threshold_mul = try requiredF64(map, "threshold_mul"),
        .use_spherical_correction = try requiredBool(map, "use_spherical_correction"),
        .integrate_source_function = try requiredBool(map, "integrate_source_function"),
        .renorm_phase_function = try requiredBool(map, "renorm_phase_function"),
        .stokes_dimension = try requiredU8(map, "stokes_dimension"),
    };
}

fn compileOutputs(allocator: Allocator, outputs_node: ?Node) ![]const parity_runtime.OutputRequest {
    if (outputs_node == null) return &.{};
    const seq = try expectSeq(outputs_node.?);
    var outputs = std.ArrayList(parity_runtime.OutputRequest).empty;
    errdefer outputs.deinit(allocator);
    for (seq) |item| {
        const map = try expectMap(item);
        try expectOnlyFields(map, &.{ "kind", "path" });
        const kind_text = try requiredString(map, "kind");
        const kind: parity_runtime.OutputKind = if (std.mem.eql(u8, kind_text, "summary_json"))
            .summary_json
        else if (std.mem.eql(u8, kind_text, "generated_spectrum_csv"))
            .generated_spectrum_csv
        else
            return error.UnsupportedOutputKind;
        try outputs.append(allocator, .{
            .kind = kind,
            .path = try requiredString(map, "path"),
        });
    }
    return try outputs.toOwnedSlice(allocator);
}

fn mergeOptionalNodes(allocator: Allocator, base: ?Node, override: ?Node) !?Node {
    if (base == null) return override;
    if (override == null) return base;
    return try mergeNodes(allocator, base.?, override.?);
}

fn mergeNodes(allocator: Allocator, base: Node, override: Node) !Node {
    return switch (base) {
        .map => |base_map| switch (override) {
            .map => |override_map| blk: {
                var merged = std.ArrayList(MapEntry).empty;
                errdefer merged.deinit(allocator);

                for (base_map) |entry| {
                    if (findField(override_map, entry.key)) |override_entry| {
                        try merged.append(allocator, .{
                            .key = entry.key,
                            .value = try mergeNodes(allocator, entry.value, override_entry.value),
                            .line = override_entry.line,
                        });
                    } else {
                        try merged.append(allocator, entry);
                    }
                }
                for (override_map) |entry| {
                    if (findField(base_map, entry.key) == null) try merged.append(allocator, entry);
                }
                break :blk Node{ .map = try merged.toOwnedSlice(allocator) };
            },
            else => override,
        },
        else => override,
    };
}

fn writeSummaryJson(path: []const u8, summary: RunSummary) !void {
    try ensureParentPath(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var writer = file.writer(&.{});
    try std.json.Stringify.value(summary, .{ .whitespace = .indent_2 }, &writer.interface);
    try writer.interface.flush();
}

fn writeGeneratedSpectrumCsv(
    path: []const u8,
    product: *const MeasurementSpace.MeasurementSpaceProduct,
) !void {
    try ensureParentPath(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};
    try writer.interface.writeAll("wavelength_nm,irradiance,radiance,reflectance\n");
    for (product.wavelengths, product.irradiance, product.radiance, product.reflectance) |wavelength_nm, irradiance, radiance, reflectance| {
        try writer.interface.print(
            "{d:.8},{e:.12},{e:.12},{e:.12}\n",
            .{ wavelength_nm, irradiance, radiance, reflectance },
        );
    }
}

fn ensureParentPath(path: []const u8) !void {
    const dirname = std.fs.path.dirname(path) orelse return;
    try std.fs.cwd().makePath(dirname);
}

fn lookupAsset(assets: []const AssetBinding, id: []const u8) !parity_runtime.ExternalAsset {
    for (assets) |entry| {
        if (std.mem.eql(u8, entry.id, id)) return entry.asset;
    }
    return error.UnknownAssetReference;
}

fn expectMap(node: Node) ![]const MapEntry {
    return switch (node) {
        .map => |value| value,
        else => error.ExpectedMap,
    };
}

fn expectSeq(node: Node) ![]const Node {
    return switch (node) {
        .seq => |value| value,
        else => error.ExpectedSequence,
    };
}

fn parseString(node: Node) ![]const u8 {
    return switch (node) {
        .scalar => |raw| unquoteScalar(raw),
        else => error.ExpectedScalar,
    };
}

fn parseBool(node: Node) !bool {
    const text = try parseString(node);
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return error.InvalidBoolean;
}

fn parseF64(node: Node) !f64 {
    return std.fmt.parseFloat(f64, try parseString(node));
}

fn parseU32(node: Node) !u32 {
    return std.fmt.parseInt(u32, try parseString(node), 10);
}

fn parseU16(node: Node) !u16 {
    return std.fmt.parseInt(u16, try parseString(node), 10);
}

fn parseU8(node: Node) !u8 {
    return std.fmt.parseInt(u8, try parseString(node), 10);
}

fn parseInlineU8List(allocator: Allocator, text: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, text, " ");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return error.InvalidInlineList;
    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " ");
    if (inner.len == 0) return &.{};
    var items = std.ArrayList(u8).empty;
    errdefer items.deinit(allocator);

    var iter = std.mem.splitScalar(u8, inner, ',');
    while (iter.next()) |part| {
        const value = try std.fmt.parseInt(u8, std.mem.trim(u8, part, " "), 10);
        try items.append(allocator, value);
    }
    return try items.toOwnedSlice(allocator);
}

fn requiredField(map: []const MapEntry, key: []const u8) !Node {
    return (try findRequiredField(map, key)).value;
}

fn optionalField(map: []const MapEntry, key: []const u8) !?Node {
    if (findField(map, key)) |entry| return entry.value;
    return null;
}

fn requiredString(map: []const MapEntry, key: []const u8) ![]const u8 {
    return parseString(try requiredField(map, key));
}

fn optionalString(map: []const MapEntry, key: []const u8) !?[]const u8 {
    if (try optionalField(map, key)) |node| return try parseString(node);
    return null;
}

fn requiredBool(map: []const MapEntry, key: []const u8) !bool {
    return parseBool(try requiredField(map, key));
}

fn optionalBool(map: []const MapEntry, key: []const u8) !?bool {
    if (try optionalField(map, key)) |node| return try parseBool(node);
    return null;
}

fn requiredF64(map: []const MapEntry, key: []const u8) !f64 {
    return parseF64(try requiredField(map, key));
}

fn optionalF64(map: []const MapEntry, key: []const u8) !?f64 {
    if (try optionalField(map, key)) |node| return try parseF64(node);
    return null;
}

fn requiredU32(map: []const MapEntry, key: []const u8) !u32 {
    return parseU32(try requiredField(map, key));
}

fn requiredU16(map: []const MapEntry, key: []const u8) !u16 {
    return parseU16(try requiredField(map, key));
}

fn requiredU8(map: []const MapEntry, key: []const u8) !u8 {
    return parseU8(try requiredField(map, key));
}

fn expectOnlyFields(map: []const MapEntry, allowed_keys: []const []const u8) !void {
    for (map) |entry| {
        var allowed = false;
        for (allowed_keys) |allowed_key| {
            if (std.mem.eql(u8, entry.key, allowed_key)) {
                allowed = true;
                break;
            }
        }
        if (!allowed) return error.UnsupportedField;
    }
}

fn findField(map: []const MapEntry, key: []const u8) ?MapEntry {
    var found: ?MapEntry = null;
    for (map) |entry| {
        if (!std.mem.eql(u8, entry.key, key)) continue;
        if (found != null) return null;
        found = entry;
    }
    return found;
}

fn findRequiredField(map: []const MapEntry, key: []const u8) !MapEntry {
    var found: ?MapEntry = null;
    for (map) |entry| {
        if (!std.mem.eql(u8, entry.key, key)) continue;
        if (found != null) return error.DuplicateField;
        found = entry;
    }
    return found orelse error.MissingRequiredField;
}

fn splitKeyValue(text: []const u8) ?KeyValueSplit {
    const colon_index = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    const key = std.mem.trim(u8, text[0..colon_index], " ");
    if (key.len == 0) return null;
    const raw_value = std.mem.trim(u8, text[colon_index + 1 ..], " ");
    return .{
        .key = key,
        .value = if (raw_value.len == 0) null else raw_value,
    };
}

fn isSequenceLine(text: []const u8) bool {
    return text.len != 0 and text[0] == '-';
}

fn unquoteScalar(text: []const u8) []const u8 {
    if (text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or (text[0] == '\'' and text[text.len - 1] == '\''))) {
        return text[1 .. text.len - 1];
    }
    return text;
}

test "parity yaml parser rejects unknown root fields" {
    const yaml =
        \\schema_version: 1
        \\metadata:
        \\  id: t
        \\  workspace: w
        \\inputs:
        \\  assets: {}
        \\templates: {}
        \\experiment:
        \\  simulation:
        \\    from: base
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_assets: true
        \\  require_resolved_stage_references: true
        \\extra: 1
    ;
    const root = try parseDocument(std.testing.allocator, yaml);
    try std.testing.expectError(error.UnsupportedField, compileResolvedCase(std.testing.allocator, root));
}
