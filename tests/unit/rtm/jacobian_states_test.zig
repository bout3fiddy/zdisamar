const std = @import("std");
const internal = @import("internal");

const jacobian = internal.rtm.jacobian_states;

test "jacobian states preserve fixed aerosol retrieval order" {
    try std.testing.expectEqual(@as(usize, 2), jacobian.state_count);
    try std.testing.expectEqual(@as(usize, 0), jacobian.stateIndex(.aerosol_optical_depth));
    try std.testing.expectEqual(@as(usize, 1), jacobian.stateIndex(.aerosol_layer_mid_pressure_hpa));
}

test "jacobian vector helpers operate on both fixed lanes" {
    var accumulator = jacobian.Vector{ 10.0, 20.0 };
    const vector = jacobian.Vector{ 1.0, 2.0 };

    jacobian.addScaled(&accumulator, vector, 4.0);
    try std.testing.expectEqual(jacobian.Vector{ 14.0, 28.0 }, accumulator);
    try std.testing.expectEqual(jacobian.Vector{ 2.0, 4.0 }, jacobian.scale(vector, 2.0));
}
