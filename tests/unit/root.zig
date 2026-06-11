const std = @import("std");
const internal = @import("internal");

test {
    _ = @import("input/o2_case_test.zig");
    _ = @import("input/hitran_partition_tables_test.zig");
    _ = @import("assets/readers_test.zig");
    _ = @import("common/units_test.zig");
    _ = @import("common/math/gauss_legendre_test.zig");
    _ = @import("common/math/spline_test.zig");
    _ = @import("setup/o2_run_tables_test.zig");
    _ = @import("cache/profile_line_memory_test.zig");
    _ = @import("cache/weak_line_cutoff_memory_test.zig");
    _ = @import("optics/curved_sun_path_test.zig");
    _ = @import("optics/layer_depths_test.zig");
    _ = @import("optics/source_levels_test.zig");
    _ = @import("transport/controls_test.zig");
    _ = @import("transport/gauss_angles_test.zig");
    _ = @import("transport/jacobian_states_test.zig");
    _ = @import("transport/layer_reflect_transmit_test.zig");
    _ = @import("transport/matrix_12x10_test.zig");
    _ = @import("transport/phase_timing_test.zig");
    _ = @import("transport/rows_test.zig");
    _ = @import("instrumentation/facades_test.zig");
}

test "public root exposes only WP2 setup surface" {
    const zdisamar = internal.public;

    try std.testing.expect(@hasDecl(zdisamar, "O2Case"));
    try std.testing.expect(@hasDecl(zdisamar, "O2RunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "ProfileLineValues"));
    try std.testing.expect(@hasDecl(zdisamar, "defaultO2Case"));
    try std.testing.expect(@hasDecl(zdisamar, "buildReferenceO2RunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "buildReferenceProfileLineValues"));

    try std.testing.expect(!@hasDecl(zdisamar, "Scene"));
    try std.testing.expect(!@hasDecl(zdisamar, "PreparedOpticalState"));
    try std.testing.expect(!@hasDecl(zdisamar, "ProductStorage"));
    try std.testing.expect(!@hasDecl(zdisamar, "run"));
    try std.testing.expect(!@hasDecl(zdisamar, "prepare"));
}
