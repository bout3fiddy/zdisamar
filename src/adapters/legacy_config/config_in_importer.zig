const std = @import("std");
const SchemaMapper = @import("schema_mapper.zig");

pub const ParseError = SchemaMapper.ParseError;
pub const PreparedRun = SchemaMapper.PreparedRun;

pub fn parse(allocator: std.mem.Allocator, contents: []const u8) !PreparedRun {
    var prepared = PreparedRun{};
    errdefer prepared.deinit(allocator);

    prepared.owned_contents = try allocator.dupe(u8, contents);

    var lines = std.mem.splitScalar(u8, prepared.owned_contents.?, '\n');
    while (lines.next()) |raw_line| {
        const line = SchemaMapper.trimWhitespace(raw_line);
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

        const separator = std.mem.indexOfScalar(u8, line, '=') orelse return ParseError.InvalidLine;
        const key = SchemaMapper.trimWhitespace(line[0..separator]);
        const value = SchemaMapper.trimWhitespace(line[separator + 1 ..]);
        if (key.len == 0 or value.len == 0) return ParseError.InvalidLine;

        try SchemaMapper.applyValue(allocator, &prepared, key, value);
    }

    SchemaMapper.finalize(&prepared);
    return prepared;
}

test "legacy config parser maps fields onto typed runtime inputs" {
    const fixture =
        \\# sample legacy configuration
        \\workspace = import-smoke
        \\model_family = disamar_standard
        \\transport = transport.dispatcher
        \\retrieval = none
        \\solver_mode = polarized
        \\scene_id = s5p-no2
        \\spectral_start_nm = 405.0
        \\spectral_end_nm = 465.0
        \\spectral_samples = 121
        \\atmosphere_layers = 48
        \\has_clouds = yes
        \\has_aerosols = no
        \\solar_zenith_deg = 32.5
        \\viewing_zenith_deg = 9.0
        \\relative_azimuth_deg = 145.0
        \\instrument = tropomi
        \\sampling = native
        \\noise_model = shot_noise
        \\derivative_mode = semi_analytical
        \\requested_products = radiance, slant_column
        \\diagnostics.provenance = true
        \\diagnostics.jacobians = true
    ;

    var prepared = try parse(std.testing.allocator, fixture);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("import-smoke", prepared.workspace_label);
    try std.testing.expectEqualStrings("disamar_standard", prepared.plan_template.model_family);
    try std.testing.expectEqual(@as(@import("zdisamar").SolverMode, .polarized), prepared.plan_template.solver_mode);
    try std.testing.expectEqualStrings("s5p-no2", prepared.scene.id);
    try std.testing.expectEqual(@as(u32, 121), prepared.scene.spectral_grid.sample_count);
    try std.testing.expect(prepared.scene.atmosphere.has_clouds);
    try std.testing.expect(!prepared.scene.atmosphere.has_aerosols);
    try std.testing.expect(prepared.diagnostics.jacobians);
    try std.testing.expectEqual(@as(usize, 2), prepared.requested_products.items.len);
    try std.testing.expectEqualStrings("radiance", prepared.requested_products.items[0].name);
    try std.testing.expectEqualStrings("slant_column", prepared.requested_products.items[1].name);
    try std.testing.expectEqual(@as(@import("zdisamar").DerivativeMode, .semi_analytical), prepared.plan_template.scene_blueprint.derivative_mode);

    const request = prepared.toRequest();
    try std.testing.expectEqualStrings("s5p-no2", request.scene.id);
    try std.testing.expect(request.diagnostics.jacobians);
    try std.testing.expectEqual(@as(usize, 2), request.requested_products.len);
    try std.testing.expectEqual(@as(@import("zdisamar").DerivativeMode, .semi_analytical), request.expected_derivative_mode.?);
}

test "legacy config parse owns backing storage after caller frees source buffer" {
    var fixture = try std.testing.allocator.dupe(u8,
        \\workspace = owned-buffer
        \\scene_id = scene-owned
        \\spectral_samples = 8
        \\requested_products = radiance, slant_column
    );

    var prepared = try parse(std.testing.allocator, fixture);
    defer prepared.deinit(std.testing.allocator);

    std.testing.allocator.free(fixture);
    fixture = undefined;

    try std.testing.expectEqualStrings("owned-buffer", prepared.workspace_label);
    try std.testing.expectEqualStrings("scene-owned", prepared.scene.id);
    try std.testing.expectEqual(@as(u32, 8), prepared.scene.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 2), prepared.requested_products.items.len);
    try std.testing.expectEqualStrings("radiance", prepared.requested_products.items[0].name);
    try std.testing.expectEqualStrings("slant_column", prepared.requested_products.items[1].name);
}
