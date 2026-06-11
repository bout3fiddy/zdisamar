const std = @import("std");
const internal = @import("internal");

test "WeakLineCutoffMemory keeps support wavelengths and wavenumbers together" {
    var memory: internal.cache.weak_line_cutoff_memory.WeakLineCutoffMemory = .{};
    defer memory.deinit(std.testing.allocator);

    const wavelengths = [_]f64{ 755.0, 760.0, 776.0 };
    try memory.replaceFromSupport(std.testing.allocator, wavelengths[0..]);

    try std.testing.expect(memory.valid());
    try std.testing.expectEqual(@as(usize, 3), memory.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(1.0e7 / 760.0, memory.wavenumbers_cm1[1], 1.0e-12);
}
