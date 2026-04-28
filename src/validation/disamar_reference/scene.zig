const std = @import("std");
const parser = @import("parser.zig");
const common = @import("compile_common.zig");
const scene_inputs = @import("scene_inputs.zig");
const output = @import("output.zig");

const AtmosphereModel = @import("../../input/Atmosphere.zig");
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const RadiativeTransferControls = @import("../../forward_model/radiative_transfer/root.zig").RadiativeTransferControls;
const parity_runtime = @import("run.zig");

const Allocator = std.mem.Allocator;

pub fn compileResolvedCase(
    allocator: Allocator,
    root: parser.Node,
) !parity_runtime.ResolvedVendorO2ACase {
    const root_map = try common.expectMap(root);
    try common.expectOnlyFields(root_map, &.{
        "schema_version",
        "metadata",
        "inputs",
        "templates",
        "experiment",
        "outputs",
        "validation",
    });

    if (try common.requiredU32(root_map, "schema_version") != 1) return error.UnsupportedSchemaVersion;
    const metadata_node = try common.requiredField(root_map, "metadata");
    const inputs_node = try common.requiredField(root_map, "inputs");
    const templates_node = try common.requiredField(root_map, "templates");
    const experiment_node = try common.requiredField(root_map, "experiment");
    const outputs_node = try common.optionalField(root_map, "outputs");
    const validation_node = try common.requiredField(root_map, "validation");

    const metadata = try compileMetadata(try common.expectMap(metadata_node));
    const validation = try compileValidation(try common.expectMap(validation_node));
    const asset_catalog = try scene_inputs.compileAssets(allocator, inputs_node);

    const experiment_map = try common.expectMap(experiment_node);
    try common.expectOnlyFields(experiment_map, &.{"simulation"});
    const simulation_node = try common.requiredField(experiment_map, "simulation");
    const simulation_map = try common.expectMap(simulation_node);
    try common.expectOnlyFields(simulation_map, &.{ "from", "plan", "scene" });
    const template_name = try common.requiredString(simulation_map, "from");

    const template_map = try common.expectMap(templates_node);
    const template_node = common.findField(template_map, template_name) orelse return error.UnknownTemplateReference;
    const template_fields = try common.expectMap(template_node.value);
    try common.expectOnlyFields(template_fields, &.{ "plan", "scene" });

    const merged_plan = try common.mergeOptionalNodes(
        allocator,
        try common.optionalField(template_fields, "plan"),
        try common.optionalField(simulation_map, "plan"),
    );
    const merged_scene = try common.mergeOptionalNodes(
        allocator,
        try common.optionalField(template_fields, "scene"),
        try common.optionalField(simulation_map, "scene"),
    );

    const plan = try compilePlan(try common.expectMap(merged_plan.?));
    const scene = try compileScene(allocator, try common.expectMap(merged_scene.?), asset_catalog);
    const outputs = try output.compileOutputs(allocator, outputs_node);

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
    rtm_controls: RadiativeTransferControls,
};

const CompiledAtmosphere = struct {
    layer_count: u32,
    sublayer_divisions: u8,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: u32,
    intervals: []const AtmosphereModel.VerticalInterval,
    profile_source_map: []const parser.MapEntry,
};

fn compileMetadata(map: []const parser.MapEntry) !parity_runtime.Metadata {
    try common.expectOnlyFields(map, &.{ "id", "workspace", "description" });
    return .{
        .id = try common.requiredString(map, "id"),
        .workspace = try common.requiredString(map, "workspace"),
        .description = try common.optionalString(map, "description") orelse "",
    };
}

fn compileValidation(map: []const parser.MapEntry) !parity_runtime.ValidationPolicy {
    try common.expectOnlyFields(map, &.{
        "strict_unknown_fields",
        "require_resolved_assets",
        "require_resolved_stage_references",
    });
    const strict_unknown_fields = try common.requiredBool(map, "strict_unknown_fields");
    const require_resolved_assets = try common.requiredBool(map, "require_resolved_assets");
    const require_resolved_stage_references = try common.requiredBool(map, "require_resolved_stage_references");
    if (!strict_unknown_fields or !require_resolved_assets or !require_resolved_stage_references) {
        return error.UnsupportedValidationPolicy;
    }
    return .{
        .strict_unknown_fields = strict_unknown_fields,
        .require_resolved_assets = require_resolved_assets,
        .require_resolved_stage_references = require_resolved_stage_references,
    };
}

fn compilePlan(map: []const parser.MapEntry) !parity_runtime.PlanSpec {
    try common.expectOnlyFields(map, &.{ "model_family", "transport", "execution" });
    const model_family = try common.requiredString(map, "model_family");
    if (!std.mem.eql(u8, model_family, "disamar_standard")) return error.UnsupportedModelFamily;

    const transport_map = try common.expectMap(try common.requiredField(map, "transport"));
    try common.expectOnlyFields(transport_map, &.{"solver"});
    const transport_solver = try common.requiredString(transport_map, "solver");
    if (!std.mem.eql(u8, transport_solver, "dispatcher")) return error.UnsupportedTransportSolver;

    const execution_map = try common.expectMap(try common.requiredField(map, "execution"));
    try common.expectOnlyFields(execution_map, &.{ "solver_mode", "derivative_mode" });
    const solver_mode = try common.requiredString(execution_map, "solver_mode");
    const derivative_mode = try common.requiredString(execution_map, "derivative_mode");
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
    map: []const parser.MapEntry,
    assets: []const scene_inputs.AssetBinding,
) !CompiledScene {
    try common.expectOnlyFields(map, &.{
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

    const geometry = try compileGeometry(try common.expectMap(try common.requiredField(map, "geometry")));
    const atmosphere = try compileAtmosphere(allocator, try common.expectMap(try common.requiredField(map, "atmosphere")));
    const spectral_grid = try compileBands(try common.expectMap(try common.requiredField(map, "bands")));
    const absorbers_map = try common.expectMap(try common.requiredField(map, "absorbers"));
    const o2 = try scene_inputs.compileO2(allocator, absorbers_map, assets);
    const o2o2 = try scene_inputs.compileO2O2(absorbers_map, assets);
    const surface_albedo = try scene_inputs.compileSurface(try common.expectMap(try common.requiredField(map, "surface")));
    const aerosol = try scene_inputs.compileAerosol(try common.expectMap(try common.requiredField(map, "aerosols")));
    const observation = try scene_inputs.compileObservation(try common.expectMap(try common.requiredField(map, "measurement_model")), assets);
    const rtm_controls = try scene_inputs.compileRadiativeTransferControls(try common.expectMap(try common.requiredField(map, "rtm")));

    const atmosphere_profile_asset = try lookupAsset(assets, try common.requiredString(atmosphere.profile_source_map, "asset"));
    const solar_reference_asset = try lookupAsset(assets, observation.solar_reference_asset_id);
    const vendor_reference_csv = try lookupAsset(assets, "vendor_reference_csv");
    const airmass_factor_lut = try lookupAsset(assets, "airmass_factor_lut");

    return .{
        .inputs = .{
            .atmosphere_profile = atmosphere_profile_asset,
            .vendor_reference_csv = vendor_reference_csv,
            .raw_solar_reference = solar_reference_asset,
            .airmass_factor_lut = airmass_factor_lut,
        },
        .scene_id = try common.requiredString(map, "id"),
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

fn compileGeometry(map: []const parser.MapEntry) !parity_runtime.GeometrySpec {
    try common.expectOnlyFields(map, &.{ "model", "solar_zenith_deg", "viewing_zenith_deg", "relative_azimuth_deg" });
    const model_text = try common.requiredString(map, "model");
    if (!std.mem.eql(u8, model_text, "pseudo_spherical")) return error.UnsupportedGeometryModel;
    return .{
        .model = .pseudo_spherical,
        .solar_zenith_deg = try common.requiredF64(map, "solar_zenith_deg"),
        .viewing_zenith_deg = try common.requiredF64(map, "viewing_zenith_deg"),
        .relative_azimuth_deg = try common.requiredF64(map, "relative_azimuth_deg"),
    };
}

fn compileAtmosphere(allocator: Allocator, map: []const parser.MapEntry) !CompiledAtmosphere {
    try common.expectOnlyFields(map, &.{ "layering", "thermodynamics", "boundary", "interval_grid" });
    const layering_map = try common.expectMap(try common.requiredField(map, "layering"));
    try common.expectOnlyFields(layering_map, &.{ "layer_count", "sublayer_divisions" });

    const thermodynamics_map = try common.expectMap(try common.requiredField(map, "thermodynamics"));
    try common.expectOnlyFields(thermodynamics_map, &.{"profile"});
    const profile_map = try common.expectMap(try common.requiredField(thermodynamics_map, "profile"));
    try common.expectOnlyFields(profile_map, &.{"source"});
    const source_map = try common.expectMap(try common.requiredField(profile_map, "source"));
    try common.expectOnlyFields(source_map, &.{"asset"});

    const boundary_map = try common.expectMap(try common.requiredField(map, "boundary"));
    try common.expectOnlyFields(boundary_map, &.{"surface_pressure_hpa"});

    const interval_grid_map = try common.expectMap(try common.requiredField(map, "interval_grid"));
    try common.expectOnlyFields(interval_grid_map, &.{ "semantics", "fit_interval_index_1based", "intervals" });
    if (!std.mem.eql(u8, try common.requiredString(interval_grid_map, "semantics"), "explicit_pressure_bounds")) {
        return error.UnsupportedIntervalSemantics;
    }
    const intervals_node = try common.requiredField(interval_grid_map, "intervals");
    const interval_nodes = try common.expectSeq(intervals_node);
    var intervals = std.ArrayList(AtmosphereModel.VerticalInterval).empty;
    errdefer intervals.deinit(allocator);
    for (interval_nodes) |interval_node| {
        const interval_map = try common.expectMap(interval_node);
        try common.expectOnlyFields(interval_map, &.{ "index_1based", "top_pressure_hpa", "bottom_pressure_hpa", "altitude_divisions" });
        try intervals.append(allocator, .{
            .index_1based = try common.requiredU32(interval_map, "index_1based"),
            .top_pressure_hpa = try common.requiredF64(interval_map, "top_pressure_hpa"),
            .bottom_pressure_hpa = try common.requiredF64(interval_map, "bottom_pressure_hpa"),
            .altitude_divisions = try common.requiredU32(interval_map, "altitude_divisions"),
        });
    }

    return .{
        .layer_count = try common.requiredU32(layering_map, "layer_count"),
        .sublayer_divisions = try common.requiredU8(layering_map, "sublayer_divisions"),
        .surface_pressure_hpa = try common.requiredF64(boundary_map, "surface_pressure_hpa"),
        .fit_interval_index_1based = try common.requiredU32(interval_grid_map, "fit_interval_index_1based"),
        .intervals = try intervals.toOwnedSlice(allocator),
        .profile_source_map = source_map,
    };
}

fn compileBands(map: []const parser.MapEntry) !SpectralGrid {
    try common.expectOnlyFields(map, &.{"o2a"});
    const o2a_map = try common.expectMap(try common.requiredField(map, "o2a"));
    try common.expectOnlyFields(o2a_map, &.{ "start_nm", "end_nm", "sample_count", "step_nm" });
    const start_nm = try common.requiredF64(o2a_map, "start_nm");
    const end_nm = try common.requiredF64(o2a_map, "end_nm");
    const sample_count = if (try common.optionalField(o2a_map, "sample_count")) |node|
        try common.parseU32(node)
    else if (try common.optionalField(o2a_map, "step_nm")) |node|
        try sampleCountFromStep(start_nm, end_nm, try common.parseF64(node))
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

fn lookupAsset(assets: []const scene_inputs.AssetBinding, id: []const u8) !parity_runtime.ExternalAsset {
    for (assets) |entry| {
        if (std.mem.eql(u8, entry.id, id)) return entry.asset;
    }
    return error.UnknownAssetReference;
}
