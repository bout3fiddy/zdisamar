const gauss_angles = @import("gauss_angles.zig");

pub const max_gauss: usize = gauss_angles.max_gauss;
pub const max_extra_streams: usize = gauss_angles.max_extra_streams;
pub const max_stream_count: usize = gauss_angles.max_stream_count;
pub const max_matrix_entries: usize = gauss_angles.max_pair_count;

// rows.zig -------------------------------------------------------------------------------------------------- |
// Fixed LABOS stream rows shared by matrix kernels, layer reflection/transmission, orders, and reflectance.   |
//                                                                                                             |
// runtime                                                                                                     |
//   These rows own no heap memory. The transport workspace will retain slices of these fixed rows so the      |
//   per-wavelength LABOS solve writes caller-owned or workspace-owned storage without allocation.             |
// ------------------------------------------------------------------------------------------------------------|

// Mat --------------------------------------------------------------------------------------------------------|
// Small dense LABOS stream matrix. Rows and columns are direction indexes.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1160 B (1.133 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1151] data : [144]f64                                                                                |
// [1152..1159] n    : usize                                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 19 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 1160 B (1.133 KiB); total = per instance * live instance count                    |
pub const Mat = struct {
    data: [max_matrix_entries]f64,
    n: usize,

    pub fn zero(n: usize) Mat {
        // zero ---------------------------------------------------------------------------------------------- |
        // Return a zero matrix with fixed storage and active size n.                                          |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .data = .{0.0} ** max_matrix_entries, .n = n };
    }

    pub fn identity(n: usize) Mat {
        // identity ------------------------------------------------------------------------------------------ |
        // Return an n by n identity matrix in the fixed LABOS matrix storage.                                 |
        // ----------------------------------------------------------------------------------------------------|
        var matrix = zero(n);

        for (0..n) |index| {
            matrix.set(index, index, 1.0);
        }

        return matrix;
    }

    pub fn get(self: *const Mat, row: usize, col: usize) f64 {
        // get ----------------------------------------------------------------------------------------------- |
        // Read one matrix entry from row-major active-size storage.                                           |
        // ----------------------------------------------------------------------------------------------------|
        return self.data[row * self.n + col];
    }

    pub fn set(self: *Mat, row: usize, col: usize, value: f64) void {
        // set ----------------------------------------------------------------------------------------------- |
        // Write one matrix entry into row-major active-size storage.                                          |
        // ----------------------------------------------------------------------------------------------------|
        self.data[row * self.n + col] = value;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// Vec --------------------------------------------------------------------------------------------------------|
// One stream vector over every LABOS direction used by a geometry.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..95] data : [12]f64                                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache line(s) at 64 B per line                                                                |
// footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count                      |
pub const Vec = struct {
    data: [max_stream_count]f64,

    pub fn zero(n: usize) Vec {
        // zero ---------------------------------------------------------------------------------------------- |
        // Return a zero vector; n is retained to match matrix construction call sites.                        |
        // ----------------------------------------------------------------------------------------------------|
        _ = n;
        return .{ .data = .{0.0} ** max_stream_count };
    }

    pub fn get(self: *const Vec, index: usize) f64 {
        // get ----------------------------------------------------------------------------------------------- |
        // Read one stream value.                                                                              |
        // ----------------------------------------------------------------------------------------------------|
        return self.data[index];
    }

    pub fn set(self: *Vec, index: usize, value: f64) void {
        // set ----------------------------------------------------------------------------------------------- |
        // Write one stream value.                                                                             |
        // ----------------------------------------------------------------------------------------------------|
        self.data[index] = value;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// Vec2 -------------------------------------------------------------------------------------------------------|
// Two stream vectors stored side by side for paired U and D radiation columns.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 192 B (0.188 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 95] col[0] : Vec                                                                                     |
// [ 96..191] col[1] : Vec                                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 3 cache line(s) at 64 B per line                                                                |
// footprint: per instance = 192 B (0.188 KiB); total = per instance * live instance count                     |
pub const Vec2 = struct {
    col: [2]Vec,

    pub fn zero(n: usize) Vec2 {
        // zero ---------------------------------------------------------------------------------------------- |
        // Return two zero vectors with the same active direction shape.                                       |
        // ----------------------------------------------------------------------------------------------------|
        return .{ .col = .{ Vec.zero(n), Vec.zero(n) } };
    }
};
// ------------------------------------------------------------------------------------------------------------|

// LayerRT ----------------------------------------------------------------------------------------------------|
// Reflection and transmission matrices for one atmospheric layer at one Fourier term.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2320 B (2.266 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1159] R : Mat                                                                                        |
// [1160..2319] T : Mat                                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 37 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 2320 B (2.266 KiB); total = per instance * live instance count                    |
pub const LayerRT = struct {
    R: Mat,
    T: Mat,
};
// ------------------------------------------------------------------------------------------------------------|

// UDField ----------------------------------------------------------------------------------------------------|
// Direct beam E plus upward U and downward D fields at one interface.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 480 B (0.469 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 95] E : Vec                                                                                          |
// [ 96..287] U : Vec2                                                                                         |
// [288..479] D : Vec2                                                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 8 cache line(s) at 64 B per line                                                                |
// footprint: per instance = 480 B (0.469 KiB); total = per instance * live instance count                     |
pub const UDField = struct {
    E: Vec,
    U: Vec2,
    D: Vec2,
};
// ------------------------------------------------------------------------------------------------------------|

// UDLocal ----------------------------------------------------------------------------------------------------|
// Local upward and downward source sums used by integrated-source weighting.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 384 B (0.375 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..191] U : Vec2                                                                                         |
// [192..383] D : Vec2                                                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 6 cache line(s) at 64 B per line                                                                |
// footprint: per instance = 384 B (0.375 KiB); total = per instance * live instance count                     |
pub const UDLocal = struct {
    U: Vec2,
    D: Vec2,
};
// ------------------------------------------------------------------------------------------------------------|
