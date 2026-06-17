const std = @import("std");
const internal = @import("internal");

const retrieval = internal.retrieval.root;

test "native retrieval layouts match canonical optimal-estimation value owners" {
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(retrieval.StateScalar));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(retrieval.PressureLayerPlacement));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(retrieval.PressureState));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(retrieval.RetrievalState));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(retrieval.PressureAltitudeProfile));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(retrieval.MeasuredReflectanceRows));
    try std.testing.expectEqual(@as(usize, 256), @sizeOf(retrieval.RetrievalIterationScratch));
    try std.testing.expectEqual(@as(usize, 184), @sizeOf(retrieval.Result));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(retrieval.BatchResult));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(retrieval.BatchOutput));
    try std.testing.expectEqual(@as(usize, 168), @sizeOf(retrieval.FastmodeBatchResult));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(retrieval.Controls));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(retrieval.StateSpace));
}
