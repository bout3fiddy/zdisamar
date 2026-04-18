//! Purpose:
//!   Compile scene-scoped input bindings and absorber/observation controls for the O2A parity lane.

const std = @import("std");
const common = @import("o2a_parity_compile_common.zig");

const parity_runtime = @import("../o2a/data/vendor_parity_runtime.zig");
const RtmControls = @import("../kernels/transport/common.zig").RtmControls;
const parser = @import("o2a_parity_parser.zig");

const Allocator = std.mem.Allocator;

pub const AssetBinding = struct {
    id: []const u8,
    asset: parity_runtime.ExternalAsset,
};

pub fn compileAssets(allocator: Allocator, inputs_node: parser.Node) ![]const AssetBinding {
    const inputs_map = try common.expectMap(inputs_node);
    try common.expectOnlyFields(inputs_map, &.{"assets"});
    const assets_node = try common.requiredField(inputs_map, "assets");
    const assets_map = try common.expectMap(assets_node);

    var assets = std.ArrayList(AssetBinding).empty;
    errdefer assets.deinit(allocator);
    for (assets_map) |entry| {
        const asset_map = try common.expectMap(entry.value);
        try common.expectOnlyFields(asset_map, &.{ "kind", "path", "format" });
        if (!std.mem.eql(u8, try common.requiredString(asset_map, "kind"), "file")) {
            return error.UnsupportedAssetKind;
        }
        try assets.append(allocator, .{
            .id = entry.key,
            .asset = .{
                .id = entry.key,
                .path = try common.requiredString(asset_map, "path"),
                .format = try common.requiredString(asset_map, "format"),
            },
        });
    }
    return try assets.toOwnedSlice(allocator);
}

pub fn compileO2(
    allocator: Allocator,
    absorbers_map: []const parser.MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.LineGasSpec {
    const o2_map = try common.expectMap((try common.findRequiredField(absorbers_map, "o2")).value);
    try common.expectOnlyFields(o2_map, &.{ "species", "spectroscopy" });
    if (!std.mem.eql(u8, try common.requiredString(o2_map, "species"), "o2")) return error.UnsupportedAbsorberSpecies;

    const spectroscopy_map = try common.expectMap(try common.requiredField(o2_map, "spectroscopy"));
    try common.expectOnlyFields(spectroscopy_map, &.{
        "model",
        "line_list_asset",
        "line_mixing_asset",
        "strong_lines_asset",
        "line_mixing_factor",
        "isotopes_sim",
        "threshold_line_sim",
        "cutoff_sim_cm1",
    });
    if (!std.mem.eql(u8, try common.requiredString(spectroscopy_map, "model"), "line_by_line")) {
        return error.UnsupportedSpectroscopyModel;
    }

    const isotopes = if (try common.optionalField(spectroscopy_map, "isotopes_sim")) |node|
        try common.parseInlineU8List(allocator, try common.parseString(node))
    else
        try allocator.dupe(u8, &.{});

    return .{
        .line_list_asset = try lookupAsset(assets, try common.requiredString(spectroscopy_map, "line_list_asset")),
        .line_mixing_asset = try lookupAsset(assets, try common.requiredString(spectroscopy_map, "line_mixing_asset")),
        .strong_lines_asset = try lookupAsset(assets, try common.requiredString(spectroscopy_map, "strong_lines_asset")),
        .line_mixing_factor = try common.optionalF64(spectroscopy_map, "line_mixing_factor"),
        .isotopes_sim = isotopes,
        .threshold_line_sim = try common.optionalF64(spectroscopy_map, "threshold_line_sim"),
        .cutoff_sim_cm1 = try common.optionalF64(spectroscopy_map, "cutoff_sim_cm1"),
    };
}

pub fn compileO2O2(
    absorbers_map: []const parser.MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.CiaSpec {
    const o2o2_entry = try common.findRequiredField(absorbers_map, "o2o2");
    const o2o2_map = try common.expectMap(o2o2_entry.value);
    try common.expectOnlyFields(o2o2_map, &.{ "species", "spectroscopy" });
    if (!std.mem.eql(u8, try common.requiredString(o2o2_map, "species"), "o2o2")) return error.UnsupportedAbsorberSpecies;

    const spectroscopy_map = try common.expectMap(try common.requiredField(o2o2_map, "spectroscopy"));
    try common.expectOnlyFields(spectroscopy_map, &.{ "model", "cia_asset", "enabled" });
    if (!std.mem.eql(u8, try common.requiredString(spectroscopy_map, "model"), "cia")) return error.UnsupportedSpectroscopyModel;
    const enabled = (try common.optionalBool(spectroscopy_map, "enabled")) orelse true;
    return .{
        .enabled = enabled,
        .cia_asset = if (enabled) try lookupAsset(assets, try common.requiredString(spectroscopy_map, "cia_asset")) else null,
    };
}

pub fn compileSurface(map: []const parser.MapEntry) !f64 {
    try common.expectOnlyFields(map, &.{ "model", "albedo", "provider" });
    if (!std.mem.eql(u8, try common.requiredString(map, "model"), "lambertian")) return error.UnsupportedSurfaceModel;
    if (try common.optionalString(map, "provider")) |provider| {
        if (!std.mem.eql(u8, provider, "builtin.lambertian_surface")) return error.UnsupportedSurfaceProvider;
    }
    return try common.requiredF64(map, "albedo");
}

pub fn compileAerosol(map: []const parser.MapEntry) !parity_runtime.AerosolSpec {
    try common.expectOnlyFields(map, &.{"plume"});
    const plume_map = try common.expectMap(try common.requiredField(map, "plume"));
    try common.expectOnlyFields(plume_map, &.{
        "model",
        "optical_depth_550_nm",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "layer_center_km",
        "layer_width_km",
        "placement",
    });
    if (!std.mem.eql(u8, try common.requiredString(plume_map, "model"), "hg_scattering")) return error.UnsupportedAerosolModel;

    const placement_map = try common.expectMap(try common.requiredField(plume_map, "placement"));
    try common.expectOnlyFields(placement_map, &.{ "semantics", "interval_index_1based", "top_pressure_hpa", "bottom_pressure_hpa" });
    if (!std.mem.eql(u8, try common.requiredString(placement_map, "semantics"), "explicit_interval_bounds")) {
        return error.UnsupportedAerosolPlacement;
    }

    return .{
        .optical_depth = try common.requiredF64(plume_map, "optical_depth_550_nm"),
        .single_scatter_albedo = try common.requiredF64(plume_map, "single_scatter_albedo"),
        .asymmetry_factor = try common.requiredF64(plume_map, "asymmetry_factor"),
        .angstrom_exponent = try common.requiredF64(plume_map, "angstrom_exponent"),
        .reference_wavelength_nm = 550.0,
        .layer_center_km = try common.requiredF64(plume_map, "layer_center_km"),
        .layer_width_km = try common.requiredF64(plume_map, "layer_width_km"),
        .placement = .{
            .semantics = .explicit_interval_bounds,
            .interval_index_1based = try common.requiredU32(placement_map, "interval_index_1based"),
            .top_pressure_hpa = try common.requiredF64(placement_map, "top_pressure_hpa"),
            .bottom_pressure_hpa = try common.requiredF64(placement_map, "bottom_pressure_hpa"),
        },
    };
}

pub fn compileObservation(
    map: []const parser.MapEntry,
    assets: []const AssetBinding,
) !parity_runtime.ObservationSpec {
    try common.expectOnlyFields(map, &.{
        "regime",
        "instrument",
        "sampling",
        "spectral_response",
        "illumination",
        "calibration",
        "noise",
    });
    if (!std.mem.eql(u8, try common.requiredString(map, "regime"), "nadir")) return error.UnsupportedObservationRegime;

    const instrument_map = try common.expectMap(try common.requiredField(map, "instrument"));
    try common.expectOnlyFields(instrument_map, &.{"name"});
    const sampling_map = try common.expectMap(try common.requiredField(map, "sampling"));
    try common.expectOnlyFields(sampling_map, &.{
        "mode",
        "high_resolution_step_nm",
        "high_resolution_half_span_nm",
        "adaptive_reference_grid",
    });
    if (!std.mem.eql(u8, try common.requiredString(sampling_map, "mode"), "native")) return error.UnsupportedSamplingMode;

    const adaptive_map = try common.expectMap(try common.requiredField(sampling_map, "adaptive_reference_grid"));
    try common.expectOnlyFields(adaptive_map, &.{ "points_per_fwhm", "strong_line_min_divisions", "strong_line_max_divisions" });

    const response_map = try common.expectMap(try common.requiredField(map, "spectral_response"));
    try common.expectOnlyFields(response_map, &.{ "shape", "fwhm_nm" });
    if (!std.mem.eql(u8, try common.requiredString(response_map, "shape"), "flat_top_n4")) return error.UnsupportedInstrumentLineShape;

    const illumination_map = try common.expectMap(try common.requiredField(map, "illumination"));
    try common.expectOnlyFields(illumination_map, &.{"solar_spectrum"});
    const solar_spectrum_map = try common.expectMap(try common.requiredField(illumination_map, "solar_spectrum"));
    try common.expectOnlyFields(solar_spectrum_map, &.{"from_reference_asset"});
    const solar_reference_asset_id = try common.requiredString(solar_spectrum_map, "from_reference_asset");
    _ = try lookupAsset(assets, solar_reference_asset_id);

    const calibration_map = try common.expectMap(try common.requiredField(map, "calibration"));
    try common.expectOnlyFields(calibration_map, &.{ "wavelength_shift_nm", "multiplicative_offset", "stray_light" });
    if (!std.math.approxEqAbs(f64, try common.requiredF64(calibration_map, "wavelength_shift_nm"), 0.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }
    if (!std.math.approxEqAbs(f64, try common.requiredF64(calibration_map, "multiplicative_offset"), 1.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }
    if (!std.math.approxEqAbs(f64, try common.requiredF64(calibration_map, "stray_light"), 0.0, 1.0e-12)) {
        return error.UnsupportedCalibrationControl;
    }

    const noise_map = try common.expectMap(try common.requiredField(map, "noise"));
    try common.expectOnlyFields(noise_map, &.{"model"});
    if (!std.mem.eql(u8, try common.requiredString(noise_map, "model"), "none")) return error.UnsupportedNoiseModel;

    return .{
        .instrument_name = try common.requiredString(instrument_map, "name"),
        .regime = .nadir,
        .sampling = .native,
        .noise_model = .none,
        .instrument_line_fwhm_nm = try common.requiredF64(response_map, "fwhm_nm"),
        .builtin_line_shape = .flat_top_n4,
        .high_resolution_step_nm = try common.requiredF64(sampling_map, "high_resolution_step_nm"),
        .high_resolution_half_span_nm = try common.requiredF64(sampling_map, "high_resolution_half_span_nm"),
        .adaptive_reference_grid = .{
            .points_per_fwhm = try common.requiredU16(adaptive_map, "points_per_fwhm"),
            .strong_line_min_divisions = try common.requiredU16(adaptive_map, "strong_line_min_divisions"),
            .strong_line_max_divisions = try common.requiredU16(adaptive_map, "strong_line_max_divisions"),
        },
        .solar_reference_asset_id = solar_reference_asset_id,
    };
}

pub fn compileRtmControls(map: []const parser.MapEntry) !RtmControls {
    try common.expectOnlyFields(map, &.{
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
    if (!std.mem.eql(u8, try common.requiredString(map, "scattering"), "multiple")) return error.UnsupportedScatteringMode;
    return .{
        .scattering = .multiple,
        .n_streams = try common.requiredU16(map, "n_streams"),
        .use_adding = try common.requiredBool(map, "use_adding"),
        .num_orders_max = try common.requiredU16(map, "num_orders_max"),
        .fourier_floor_scalar = try common.requiredU16(map, "fourier_floor_scalar"),
        .threshold_conv_first = try common.requiredF64(map, "threshold_conv_first"),
        .threshold_conv_mult = try common.requiredF64(map, "threshold_conv_mult"),
        .threshold_doubl = try common.requiredF64(map, "threshold_doubl"),
        .threshold_mul = try common.requiredF64(map, "threshold_mul"),
        .use_spherical_correction = try common.requiredBool(map, "use_spherical_correction"),
        .integrate_source_function = try common.requiredBool(map, "integrate_source_function"),
        .renorm_phase_function = try common.requiredBool(map, "renorm_phase_function"),
        .stokes_dimension = try common.requiredU8(map, "stokes_dimension"),
    };
}

fn lookupAsset(assets: []const AssetBinding, id: []const u8) !parity_runtime.ExternalAsset {
    for (assets) |entry| {
        if (std.mem.eql(u8, entry.id, id)) return entry.asset;
    }
    return error.UnknownAssetReference;
}
