const std = @import("std");
const internal = @import("internal");

const jacobian = internal.rtm.jacobian_states;

test "jacobian state masks preserve fixed aerosol retrieval order" {
    try std.testing.expectEqual(@as(usize, 2), jacobian.state_count);
    try std.testing.expectEqual(@as(usize, 0), jacobian.stateIndex(.aerosol_optical_depth));
    try std.testing.expectEqual(@as(usize, 1), jacobian.stateIndex(.aerosol_layer_mid_pressure_hpa));
    try std.testing.expectEqual(@as(jacobian.StateMask, 0b11), jacobian.all_states_mask);

    const active_mask = jacobian.stateMask(.aerosol_layer_mid_pressure_hpa);
    try std.testing.expect(!jacobian.includes(active_mask, .aerosol_optical_depth));
    try std.testing.expect(jacobian.includes(active_mask, .aerosol_layer_mid_pressure_hpa));
    try std.testing.expectEqual(@as(usize, 1), jacobian.activeStateCount(active_mask));
}

test "jacobian masked vector helpers leave inactive lanes untouched" {
    var accumulator = jacobian.Vector{ 10.0, 20.0 };
    const vector = jacobian.Vector{ 1.0, 2.0 };
    const mask = jacobian.stateMask(.aerosol_optical_depth);

    jacobian.addScaledMasked(&accumulator, vector, 4.0, mask);
    try std.testing.expectEqual(jacobian.Vector{ 14.0, 20.0 }, accumulator);
    try std.testing.expectEqual(jacobian.Vector{ 2.0, 4.0 }, jacobian.scale(vector, 2.0));
    try std.testing.expectEqual(jacobian.Vector{ 2.0, 0.0 }, jacobian.scaleMasked(vector, 2.0, mask));
}
