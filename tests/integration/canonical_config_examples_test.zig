const std = @import("std");
const zdisamar = @import("zdisamar");

test "canonical config resolves revised common and expert examples" {
    var common = try zdisamar.canonical_config.resolveFile(
        std.testing.allocator,
        "data/examples/zdisamar_common_use.yaml",
    );
    defer common.deinit();

    try std.testing.expectEqualStrings("o2a_twin_common", common.metadata.id);
    try std.testing.expect(common.simulation != null);
    try std.testing.expect(common.retrieval != null);
    try std.testing.expectEqual(@as(usize, 0), common.ingests.len);
    try std.testing.expectEqual(@as(usize, 2), common.outputs.len);
    try std.testing.expectEqualStrings("truth_radiance", common.retrieval.?.inverse.?.measurements.source.name);
    try std.testing.expectEqual(zdisamar.DataBindingKind.stage_product, common.retrieval.?.inverse.?.measurements.source.kind);
    try std.testing.expectEqual(@as(u32, 1301), common.simulation.?.scene.spectral_grid.sample_count);
    try std.testing.expect(common.warnings.len == 0);

    var expert = try zdisamar.canonical_config.resolveFile(
        std.testing.allocator,
        "data/examples/zdisamar_expert_o2a.yaml",
    );
    defer expert.deinit();

    try std.testing.expectEqualStrings("s5p_o2a_twin_expert", expert.metadata.id);
    try std.testing.expectEqual(@as(usize, 7), expert.assets.len);
    try std.testing.expectEqual(@as(usize, 2), expert.ingests.len);
    try std.testing.expect(expert.simulation != null);
    try std.testing.expect(expert.retrieval != null);
    try std.testing.expectEqual(@as(?u64, 424242), expert.simulation.?.noise_seed);
    try std.testing.expectEqualStrings("table", expert.retrieval.?.spectral_response_shape);
    try std.testing.expectEqualStrings(
        "isrf_demo.instrument_line_shape_table",
        expert.retrieval.?.spectral_response_table_source.name,
    );
    try std.testing.expect(expert.retrieval.?.scene.observation_model.operational_refspec_grid.enabled());
    try std.testing.expect(expert.retrieval.?.scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expect(expert.retrieval.?.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(expert.retrieval.?.scene.observation_model.o2o2_operational_lut.enabled());
    try std.testing.expect(expert.retrieval.?.scene.observation_model.instrument_line_shape_table.nominal_count > 0);
    try std.testing.expectEqual(@as(usize, 3), expert.outputs.len);
}
