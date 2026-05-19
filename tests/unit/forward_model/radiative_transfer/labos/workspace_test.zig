const std = @import("std");
const internal = @import("internal");

const labos = internal.forward_model.radiative_transfer.labos;

test "workspace PLM basis cache grows to current phase support" {
    const allocator = std.testing.allocator;
    var workspace = labos.Workspace.init(allocator);
    defer workspace.deinit();

    const geo = labos.Geometry.init(10, 0.5, 0.75);

    _ = try workspace.fourierPlmBasisWithStatus(0, 3, &geo);
    try std.testing.expectEqual(@as(usize, 4), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 4), workspace.plm_basis_cache_valid.len);

    _ = try workspace.fourierPlmBasisWithStatus(2, 5, &geo);
    try std.testing.expectEqual(@as(usize, 6), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 6), workspace.plm_basis_cache_valid.len);

    _ = try workspace.fourierPlmBasisWithStatus(1, 3, &geo);
    try std.testing.expectEqual(@as(usize, 6), workspace.plm_basis_cache.len);
    try std.testing.expectEqual(@as(usize, 6), workspace.plm_basis_cache_valid.len);
}
