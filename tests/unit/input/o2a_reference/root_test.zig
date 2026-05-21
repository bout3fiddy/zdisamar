const std = @import("std");
const zdisamar = @import("zdisamar");

test "default O2A input renders and parses as strict JSON" {
    const input = zdisamar.defaultO2AInput();
    try std.testing.expectEqual(@as(u32, 701), input.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(u16, 20), input.rtm_controls.n_streams);
    try std.testing.expect(input.rtm_controls.use_spherical_correction);
    try std.testing.expect(input.rtm_controls.integrate_source_function);
    try std.testing.expectEqual(@as(u16, 0), input.rtm_controls.performance_thresholds.num_orders_max);
    try std.testing.expectEqual(@as(?u16, null), input.rtm_controls.performance_thresholds.fourier_order_cap);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0e-14),
        input.rtm_controls.performance_thresholds.fourier_tail_reflectance_epsilon,
        0.0,
    );

    const json = try zdisamar.renderDefaultO2AInputJson(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqual(null, std.mem.indexOf(u8, json, "layer_center_km"));
    try std.testing.expectEqual(null, std.mem.indexOf(u8, json, "layer_width_km"));

    var parsed = try zdisamar.parseO2AInputJson(std.testing.allocator, json);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 701), parsed.value.spectral_grid.sample_count);
    try std.testing.expectEqualStrings(
        "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
        parsed.value.inputs.vendor_reference_csv.path,
    );
    try std.testing.expectEqualStrings(
        "data/reference_data/solar/o2a_solar_reference_753_778.csv",
        parsed.value.inputs.raw_solar_reference.path,
    );
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, parsed.value.o2.isotopes_sim);
}

test "O2A JSON rejects unknown fields" {
    const json = try zdisamar.renderDefaultO2AInputJson(std.testing.allocator);
    defer std.testing.allocator.free(json);
    const with_unknown = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"unknown_field\":true,{s}",
        .{json[1..]},
    );
    defer std.testing.allocator.free(with_unknown);

    try std.testing.expectError(
        error.UnknownField,
        zdisamar.parseO2AInputJson(std.testing.allocator, with_unknown),
    );
}

test "O2A JSON rejects legacy aerosol placement fields" {
    const json = try zdisamar.renderDefaultO2AInputJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    const marker = "\"placement\"";
    const placement_index = std.mem.indexOf(u8, json, marker) orelse return error.TestUnexpectedResult;
    const with_legacy = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}\"layer_center_km\":5.4,{s}",
        .{ json[0..placement_index], json[placement_index..] },
    );
    defer std.testing.allocator.free(with_legacy);

    try std.testing.expectError(
        error.UnknownField,
        zdisamar.parseO2AInputJson(std.testing.allocator, with_legacy),
    );
}

test "O2A input validation rejects invalid sampling and assets" {
    var input = zdisamar.defaultO2AInput();
    input.spectral_grid.sample_count = 1;
    try std.testing.expectError(error.InvalidSpectralGrid, zdisamar.o2a.validateInput(&input));

    input = zdisamar.defaultO2AInput();
    input.inputs.raw_solar_reference.path = "";
    try std.testing.expectError(error.InvalidReferenceAsset, zdisamar.o2a.validateInput(&input));
}

test "O2A input validation consumes plan fields" {
    var input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "none";
    try zdisamar.o2a.validateInput(&input);

    input = zdisamar.defaultO2AInput();
    input.plan.model_family = "unsupported";
    try std.testing.expectError(error.UnsupportedModelFamily, zdisamar.o2a.validateInput(&input));

    input = zdisamar.defaultO2AInput();
    input.plan.transport_solver = "unsupported";
    try std.testing.expectError(error.UnsupportedTransportSolver, zdisamar.o2a.validateInput(&input));

    input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "unsupported";
    try std.testing.expectError(error.UnsupportedDerivativeMode, zdisamar.o2a.validateInput(&input));

    input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "semi_analytical";
    try zdisamar.o2a.validateInput(&input);
}

test "O2A plan modes are consumed when preparing the route" {
    var input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "none";

    var prepared = try zdisamar.prepareO2A(std.testing.allocator, &input);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(.scalar, prepared.route.execution_mode);
    try std.testing.expectEqual(.none, prepared.route.derivative_mode);

    input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "semi_analytical";
    var jacobian_prepared = try zdisamar.prepareO2A(std.testing.allocator, &input);
    defer jacobian_prepared.deinit(std.testing.allocator);
    try std.testing.expectEqual(.semi_analytical, jacobian_prepared.route.derivative_mode);
}

test "O2A route preparation rejects unsupported derivative mode" {
    var input = zdisamar.defaultO2AInput();
    input.plan.execution_derivative_mode = "unsupported";

    try std.testing.expectError(
        error.UnsupportedDerivativeMode,
        zdisamar.prepareO2A(std.testing.allocator, &input),
    );
}

test "default O2A validation baseline is the shared native input type" {
    const input: zdisamar.O2AInput = zdisamar.defaultO2AInput();
    try zdisamar.o2a.validateInput(&input);
    try std.testing.expectEqual(@as(u32, 701), input.spectral_grid.sample_count);
    try std.testing.expectEqualStrings(
        "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
        input.o2.line_list_asset.path,
    );
}
