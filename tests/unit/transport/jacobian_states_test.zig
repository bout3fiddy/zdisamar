const std = @import("std");
const internal = @import("internal");

const jacobian = internal.transport.jacobian_states;

test "jacobian state masks preserve old fixed state order" {
    try std.testing.expectEqual(@as(usize, 3), jacobian.state_count);
    try std.testing.expectEqual(@as(usize, 0), jacobian.stateIndex(.surface_albedo));
    try std.testing.expectEqual(@as(usize, 1), jacobian.stateIndex(.aerosol_optical_depth));
    try std.testing.expectEqual(@as(usize, 2), jacobian.stateIndex(.aerosol_layer_mid_pressure_hpa));
    try std.testing.expectEqual(@as(jacobian.StateMask, 0b111), jacobian.all_states_mask);

    const active_mask = jacobian.stateMask(.surface_albedo) |
        jacobian.stateMask(.aerosol_layer_mid_pressure_hpa);
    try std.testing.expect(jacobian.includes(active_mask, .surface_albedo));
    try std.testing.expect(!jacobian.includes(active_mask, .aerosol_optical_depth));
    try std.testing.expectEqual(@as(usize, 2), jacobian.activeStateCount(active_mask));
    try std.testing.expectEqual(
        @as(?usize, 1),
        jacobian.activeStateIndex(active_mask, .aerosol_layer_mid_pressure_hpa),
    );
    try std.testing.expectEqual(
        @as(?jacobian.State, .aerosol_layer_mid_pressure_hpa),
        jacobian.activeStateAt(active_mask, 1),
    );
}

test "jacobian masked vector helpers leave inactive lanes untouched" {
    var accumulator = jacobian.Vector{ 10.0, 20.0, 30.0 };
    const vector = jacobian.Vector{ 1.0, 2.0, 3.0 };
    const mask = jacobian.stateMask(.surface_albedo) | jacobian.stateMask(.aerosol_optical_depth);

    jacobian.addScaledMasked(&accumulator, vector, 4.0, mask);
    try std.testing.expectEqual(jacobian.Vector{ 14.0, 28.0, 30.0 }, accumulator);
    try std.testing.expectEqual(jacobian.Vector{ 2.0, 4.0, 0.0 }, jacobian.scaleMasked(vector, 2.0, mask));
}
