const std = @import("std");
const internal = @import("internal");

const labos = internal.forward_model.radiative_transfer.labos;
const common = internal.forward_model.radiative_transfer;
const phase_functions = internal.forward_model.optical_properties.shared.phase_functions;

test "workspace PLM basis cache grows to active Fourier support" {
    const allocator = std.testing.allocator;
    var workspace = labos.Workspace.init(allocator);
    defer workspace.deinit();

    const geo = labos.Geometry.init(10, 0.5, 0.75);

    _ = try workspace.fourierPlmBasisWithStatus(0, labos.max_phase_coef - 1, 2, &geo);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache_valid.len);

    _ = try workspace.fourierPlmBasisWithStatus(2, 5, 2, &geo);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache_valid.len);

    _ = try workspace.fourierPlmBasisWithStatus(1, 3, 2, &geo);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 3), workspace.plm_basis_cache_valid.len);
}

test "workspace layer effective scattering suffix uses active phase stride" {
    const allocator = std.testing.allocator;
    var workspace = labos.Workspace.init(allocator);
    defer workspace.deinit();

    const phase_stride = 4;
    const suffixes = try workspace.layerEffectiveScatteringSuffix(2, phase_stride);
    try std.testing.expectEqual(@as(usize, 8), suffixes.len);

    const layer0_phase = phase_functions.phaseCoefficientsFromCompact(.{ 1.0, 0.2, 0.3, 0.4 });
    const layer1_phase = phase_functions.phaseCoefficientsFromCompact(.{ 1.0, 0.1, 0.0, 0.0 });
    const layers = [_]common.LayerInput{
        .{ .phase_coefficients = layer0_phase },
        .{ .phase_coefficients = layer1_phase },
    };
    const max_indices = [_]usize{ 3, 1 };

    labos.internal.layers.fillLayerEffectiveScatteringSuffixes(
        suffixes,
        &layers,
        &max_indices,
        phase_stride,
    );

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), suffixes[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2 / 3.0), suffixes[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3 / 5.0), suffixes[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4 / 7.0), suffixes[3], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), suffixes[4], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1 / 3.0), suffixes[5], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), suffixes[6], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), suffixes[7], 1.0e-12);

    const capped_suffixes = try workspace.layerEffectiveScatteringSuffix(2, 2);
    labos.internal.layers.fillLayerEffectiveScatteringSuffixes(
        capped_suffixes,
        &layers,
        &max_indices,
        2,
    );

    try std.testing.expectApproxEqAbs(@as(f64, 1.0), capped_suffixes[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2 / 3.0), capped_suffixes[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), capped_suffixes[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1 / 3.0), capped_suffixes[3], 1.0e-12);
}
