const std = @import("std");
const common = @import("compile_common.zig");
const parser = @import("parser.zig");

const MeasurementSpace = @import("../../forward_model/instrument_grid/root.zig");
const parity_runtime = @import("run.zig");
const parity_support = @import("metrics.zig");

const Allocator = std.mem.Allocator;

pub const RunSummary = struct {
    metadata: parity_runtime.Metadata,
    scene_id: []const u8,
    reference_path: []const u8,
    product_summary: MeasurementSpace.MeasurementSpaceSummary,
    comparison: parity_support.ComparisonMetrics,
};

pub fn compileOutputs(allocator: Allocator, outputs_node: ?parser.Node) ![]const parity_runtime.OutputRequest {
    if (outputs_node == null) return &.{};
    const seq = try common.expectSeq(outputs_node.?);
    var outputs = std.ArrayList(parity_runtime.OutputRequest).empty;
    errdefer outputs.deinit(allocator);
    for (seq) |item| {
        const map = try common.expectMap(item);
        try common.expectOnlyFields(map, &.{ "kind", "path" });
        const kind_text = try common.requiredString(map, "kind");
        const kind: parity_runtime.OutputKind = if (std.mem.eql(u8, kind_text, "summary_json"))
            .summary_json
        else if (std.mem.eql(u8, kind_text, "generated_spectrum_csv"))
            .generated_spectrum_csv
        else
            return error.UnsupportedOutputKind;
        try outputs.append(allocator, .{
            .kind = kind,
            .path = try common.requiredString(map, "path"),
        });
    }
    return try outputs.toOwnedSlice(allocator);
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
            "{d:.8},{e:.17},{e:.17},{e:.17}\n",
            .{ wavelength_nm, irradiance, radiance, reflectance },
        );
    }
}

fn ensureParentPath(path: []const u8) !void {
    const dirname = std.fs.path.dirname(path) orelse return;
    try std.fs.cwd().makePath(dirname);
}
