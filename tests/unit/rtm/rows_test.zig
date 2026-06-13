const std = @import("std");

const internal = @import("internal");

const rows = internal.rtm.rows;

// RowsLayoutEvidence ---------------------------------------------------------------------------------------- |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] mat_size      : usize                                                                              |
// [ 8..15] vec_size      : usize                                                                              |
// [16..23] vec2_size     : usize                                                                              |
// [24..31] layer_rt_size : usize                                                                              |
// [32..39] ud_field_size : usize                                                                              |
// [40..47] ud_local_size : usize                                                                              |
const RowsLayoutEvidence = struct {
    mat_size: usize,
    vec_size: usize,
    vec2_size: usize,
    layer_rt_size: usize,
    ud_field_size: usize,
    ud_local_size: usize,
};
// ------------------------------------------------------------------------------------------------------------|

const old_rows_layout = RowsLayoutEvidence{
    .mat_size = 1160,
    .vec_size = 96,
    .vec2_size = 192,
    .layer_rt_size = 2320,
    .ud_field_size = 480,
    .ud_local_size = 384,
};

test "transport rows preserve LABOS fixed storage sizes" {
    try std.testing.expectEqual(@as(usize, 10), rows.max_gauss);
    try std.testing.expectEqual(@as(usize, 2), rows.max_extra_streams);
    try std.testing.expectEqual(@as(usize, 12), rows.max_stream_count);
    try std.testing.expectEqual(@as(usize, 144), rows.max_matrix_entries);

    try std.testing.expectEqual(old_rows_layout.mat_size, @sizeOf(rows.Mat));
    try std.testing.expectEqual(old_rows_layout.vec_size, @sizeOf(rows.Vec));
    try std.testing.expectEqual(old_rows_layout.vec2_size, @sizeOf(rows.Vec2));
    try std.testing.expectEqual(old_rows_layout.layer_rt_size, @sizeOf(rows.LayerRT));
    try std.testing.expectEqual(old_rows_layout.ud_field_size, @sizeOf(rows.UDField));
    try std.testing.expectEqual(old_rows_layout.ud_local_size, @sizeOf(rows.UDLocal));
}

test "transport matrix rows use active-size row-major indexing" {
    var matrix = rows.Mat.zero(6);
    try std.testing.expectEqual(@as(usize, 6), matrix.n);
    for (matrix.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }

    matrix.set(2, 4, 7.25);
    try std.testing.expectEqual(@as(f64, 7.25), matrix.get(2, 4));
    try std.testing.expectEqual(@as(f64, 7.25), matrix.data[2 * 6 + 4]);

    const identity = rows.Mat.identity(6);
    for (0..6) |row| {
        for (0..6) |col| {
            const expected: f64 = if (row == col) 1.0 else 0.0;
            try std.testing.expectEqual(expected, identity.get(row, col));
        }
    }
    try std.testing.expectEqual(@as(f64, 0.0), identity.data[6 * 6]);
}

test "transport vector rows expose zero and get-set behavior" {
    var vector = rows.Vec.zero(6);
    for (vector.data) |value| {
        try std.testing.expectEqual(@as(f64, 0.0), value);
    }

    vector.set(5, -1.5);
    try std.testing.expectEqual(@as(f64, -1.5), vector.get(5));

    const pair = rows.Vec2.zero(6);
    for (pair.col) |column| {
        for (column.data) |value| {
            try std.testing.expectEqual(@as(f64, 0.0), value);
        }
    }
}

test "transport nested field rows carry matrix and vector row groups" {
    const n: usize = 6;
    const layer = rows.LayerRT{
        .R = rows.Mat.identity(n),
        .T = rows.Mat.zero(n),
    };
    try std.testing.expectEqual(@as(f64, 1.0), layer.R.get(3, 3));
    try std.testing.expectEqual(@as(f64, 0.0), layer.T.get(3, 3));

    var field = rows.UDField{
        .E = rows.Vec.zero(n),
        .U = rows.Vec2.zero(n),
        .D = rows.Vec2.zero(n),
    };
    field.E.set(1, 0.25);
    field.U.col[0].set(2, 0.5);
    field.D.col[1].set(3, 0.75);
    try std.testing.expectEqual(@as(f64, 0.25), field.E.get(1));
    try std.testing.expectEqual(@as(f64, 0.5), field.U.col[0].get(2));
    try std.testing.expectEqual(@as(f64, 0.75), field.D.col[1].get(3));

    var local = rows.UDLocal{
        .U = rows.Vec2.zero(n),
        .D = rows.Vec2.zero(n),
    };
    local.U.col[1].set(4, 1.25);
    local.D.col[0].set(5, 1.5);
    try std.testing.expectEqual(@as(f64, 1.25), local.U.col[1].get(4));
    try std.testing.expectEqual(@as(f64, 1.5), local.D.col[0].get(5));
}
