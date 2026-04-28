const std = @import("std");
const internal = @import("internal");

test "vendor partition tables interpolate representative isotopologues and preserve q(t0)/q(t)" {
    const representative_codes = [_]i32{ 161, 626, 26, 211, 66, 4111 };
    for (representative_codes) |code| {
        const ratio_260 = internal.hitran_partition_tables.ratioT0OverT(code, 260.0, 296.0).?;
        try std.testing.expect(ratio_260 > 1.0);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            internal.hitran_partition_tables.ratioT0OverT(code, 296.0, 296.0).?,
            1e-12,
        );
    }
}

test "vendor partition tables follow spline anchors between tabulated temperatures" {
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.552060213472179),
        internal.hitran_partition_tables.ratioT0OverT(66, 190.5, 296.0).?,
        1.0e-14,
    );
}

test "O2 partition ratio follows DISAMAR endpoint-secant spline" {
    const ratio = internal.hitran_partition_tables.ratioT0OverT(66, 165.1, 296.0) orelse unreachable;
    try std.testing.expectApproxEqAbs(@as(f64, 1.7894420791035657), ratio, 1.0e-14);
}

test "O2 isotope 67 preserves DISAMAR default-real partition literals" {
    const ratio = internal.hitran_partition_tables.ratioT0OverT(67, 190.5, 296.0) orelse unreachable;
    try std.testing.expectApproxEqAbs(@as(f64, 1.5610005510908784), ratio, 1.0e-14);
}
