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
