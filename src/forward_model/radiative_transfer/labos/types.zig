const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");

// types.zig -------------------------------------------------------------------------------------------------|
// Core LABOS data shapes for stream matrices, direction geometry, layer reflection/transmission, local       |
// radiation fields, and phase-kernel rows. The implementation files use these rows as fixed-capacity stack   |
// or workspace storage while `n`, `n_gauss`, and `nmutot` tell each loop how much of the storage is active.  |
//                                                                                                            |
// called by                                                                                                  |
//   attenuation.zig reads Geometry stream directions for survival tables                                     |
//   layers.zig writes LayerRT matrices and source fields for each atmospheric layer                          |
//   orders.zig streams UDField/UDLocal rows through scattering orders                                        |
//   reflectance.zig integrates Fourier/order results into top-of-atmosphere reflectance                      |
//   workspace.zig allocates retained slices of these rows for repeated wavelength solves                     |
//                                                                                                            |
// direction indexes                                                                                          |
//   0 .. n_gauss - 1 : Gaussian quadrature streams                                                           |
//   Geometry.viewIdx()  : viewing stream                                                                     |
//   n_gauss + 1        : solar stream                                                                        |
//                                                                                                            |
// row groups                                                                                                 |
//   Mat/Vec/Vec2        : fixed stream linear algebra used by layer doubling and q-series solves             |
//   Geometry            : direction grid plus precomputed pair factors used by attenuation and layer math    |
//   LayerRT             : per-layer reflection/transmission matrices for one Fourier term                    |
//   UDField/UDLocal     : direct/up/down fields used by scattering-order and integrated-source routes        |
//   PhaseKernel*        : phase rows imported through phase_basis.zig and re-exported by basis.zig           |
//                                                                                                            |
// storage                                                                                                    |
//   Matrix/vector storage is fixed at the LABOS maximum size. Each value also carries active counts where    |
//   later loops need them. This keeps hot routines allocation-free after the caller prepares a workspace and |
//   lets fixed 12x10 kernels use compile-time bounds while generic routes share the same row shapes.         |
// -----------------------------------------------------------------------------------------------------------|

pub const max_gauss: usize = 10;
pub const max_extra: usize = 2;
pub const max_nmutot: usize = max_gauss + max_extra;
pub const max_n2: usize = max_nmutot * max_nmutot;
pub const max_phase_coef: usize = phase_functions.phase_coefficient_count;

const direction_pair_floor: f64 = 1.0e-12;
const equal_stream_delta: f64 = 1.0e-6;

// Mat -------------------------------------------------------------------------------------------------------|
// Small dense LABOS stream matrix. Rows and columns are direction indexes.                                   |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 1160 B (1.133 KiB), align: 8 B                                                                       |
//                                                                                                            |
// memory                                                                                                     |
// [   0..1151] data : [144]f64                                                                               |
// [1152..1159] n    : usize                                                                                  |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 19 cache line(s) at 64 B per line                                                              |
// footprint: per instance = 1160 B (1.133 KiB); total = per instance * live instance count                   |
pub const Mat = struct {
    data: [max_n2]f64,
    n: usize,

    const Self = @This();

    pub fn zero(n: usize) Self {
        // Mat.zero ------------------------------------------------------------------------------------------|
        // Return a zero matrix with fixed storage and active size n.                                         |
        // ---------------------------------------------------------------------------------------------------|

        return .{ .data = .{0.0} ** max_n2, .n = n };
    }

    pub fn identity(n: usize) Self {
        // Mat.identity --------------------------------------------------------------------------------------|
        // Return an n by n identity matrix in the fixed LABOS matrix storage.                                |
        // ---------------------------------------------------------------------------------------------------|

        var matrix = zero(n);

        for (0..n) |index| {
            matrix.set(index, index, 1.0);
        }

        return matrix;
    }

    pub fn get(self: *const Self, row: usize, col: usize) f64 {
        // Mat.get -------------------------------------------------------------------------------------------|
        // Read one matrix entry from row-major storage.                                                      |
        // ---------------------------------------------------------------------------------------------------|

        return self.data[row * self.n + col];
    }

    pub fn set(self: *Self, row: usize, col: usize, val: f64) void {
        // Mat.set -------------------------------------------------------------------------------------------|
        // Write one matrix entry into row-major storage.                                                     |
        // ---------------------------------------------------------------------------------------------------|

        self.data[row * self.n + col] = val;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// Vec -------------------------------------------------------------------------------------------------------|
// One stream vector over every LABOS direction used by a geometry.                                           |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 96 B (0.094 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..95] data : [12]f64                                                                                    |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count                     |
pub const Vec = struct {
    data: [max_nmutot]f64,

    pub fn zero(n: usize) Vec {
        // Vec.zero ------------------------------------------------------------------------------------------|
        // Return a zero vector. The n argument keeps vector construction shaped like matrix construction.    |
        // ---------------------------------------------------------------------------------------------------|

        _ = n;
        return .{ .data = .{0.0} ** max_nmutot };
    }

    pub fn get(self: *const Vec, index: usize) f64 {
        // Vec.get -------------------------------------------------------------------------------------------|
        // Read one stream value.                                                                             |
        // ---------------------------------------------------------------------------------------------------|

        return self.data[index];
    }

    pub fn set(self: *Vec, index: usize, val: f64) void {
        // Vec.set -------------------------------------------------------------------------------------------|
        // Write one stream value.                                                                            |
        // ---------------------------------------------------------------------------------------------------|

        self.data[index] = val;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// Vec2 ------------------------------------------------------------------------------------------------------|
// Two stream vectors stored side by side. LABOS uses this for the two radiation columns in U and D fields.   |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 192 B (0.188 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 95] col[0] : Vec                                                                                    |
// [ 96..191] col[1] : Vec                                                                                    |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 3 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 192 B (0.188 KiB); total = per instance * live instance count                    |
pub const Vec2 = struct {
    col: [2]Vec,

    pub fn zero(n: usize) Vec2 {
        // Vec2.zero -----------------------------------------------------------------------------------------|
        // Return two zero vectors with the same active direction shape.                                      |
        // ---------------------------------------------------------------------------------------------------|

        return .{
            .col = .{ Vec.zero(n), Vec.zero(n) },
        };
    }
};
// -----------------------------------------------------------------------------------------------------------|

// LayerRT ---------------------------------------------------------------------------------------------------|
// Reflection and transmission matrices for one atmospheric layer at one Fourier term.                        |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 2320 B (2.266 KiB), align: 8 B                                                                       |
//                                                                                                            |
// memory                                                                                                     |
// [   0..1159] R : Mat                                                                                       |
// [1160..2319] T : Mat                                                                                       |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 37 cache line(s) at 64 B per line                                                              |
// footprint: per instance = 2320 B (2.266 KiB); total = per instance * live instance count                   |
pub const LayerRT = struct {
    R: Mat,
    T: Mat,
};
// -----------------------------------------------------------------------------------------------------------|

// UDField ---------------------------------------------------------------------------------------------------|
// Direct beam E plus upward U and downward D fields at one interface.                                        |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 480 B (0.469 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 95] E : Vec                                                                                         |
// [ 96..287] U : Vec2                                                                                        |
// [288..479] D : Vec2                                                                                        |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 8 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 480 B (0.469 KiB); total = per instance * live instance count                    |
pub const UDField = struct {
    E: Vec,
    U: Vec2,
    D: Vec2,
};
// -----------------------------------------------------------------------------------------------------------|

// UDLocal ---------------------------------------------------------------------------------------------------|
// Local upward and downward source sums used by integrated-source weighting.                                 |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 384 B (0.375 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..191] U : Vec2                                                                                        |
// [192..383] D : Vec2                                                                                        |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 6 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 384 B (0.375 KiB); total = per instance * live instance count                    |
pub const UDLocal = struct {
    U: Vec2,
    D: Vec2,
};
// -----------------------------------------------------------------------------------------------------------|

// Geometry --------------------------------------------------------------------------------------------------|
// Direction grid and precomputed direction-pair factors for one solar/viewing geometry.                      |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 2832 B (2.766 KiB), align: 8 B                                                                       |
//                                                                                                            |
// memory                                                                                                     |
// [   0..   7] n_gauss     : usize                                                                           |
// [   8..  15] nmutot      : usize                                                                           |
// [  16.. 111] u           : [12]f64                                                                         |
// [ 112.. 207] w           : [12]f64                                                                         |
// [ 208.. 287] ug          : [10]f64                                                                         |
// [ 288.. 367] wg          : [10]f64                                                                         |
// [ 368..1519] dmu_plus    : [144]f64                                                                        |
// [1520..2671] dmu_min     : [144]f64                                                                        |
// [2672..2815] dmu_same    : [144]bool                                                                       |
// [2816..2823] mu0         : f64                                                                             |
// [2824..2831] muv         : f64                                                                             |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 45 cache line(s) at 64 B per line                                                              |
// footprint: per instance = 2832 B (2.766 KiB); total = per instance * live instance count                   |
pub const Geometry = struct {
    n_gauss: usize,
    nmutot: usize,
    u: [max_nmutot]f64,
    w: [max_nmutot]f64,
    ug: [max_gauss]f64,
    wg: [max_gauss]f64,
    dmu_plus: [max_n2]f64,
    dmu_min: [max_n2]f64,
    dmu_same: [max_n2]bool,
    mu0: f64,
    muv: f64,

    pub fn init(n_gauss: usize, mu0: f64, muv: f64) Geometry {
        // Geometry.init -------------------------------------------------------------------------------------|
        // Build the LABOS direction grid for one solar/viewing geometry. Steps:                              |
        //                                                                                                    |
        //   1. fill Gauss-Legendre streams on [0, 1]                                                         |
        //   2. append the viewing stream and solar stream                                                    |
        //   3. precompute direction weights and direction-pair factors                                       |
        //                                                                                                    |
        // direction indexes                                                                                  |
        //   0 .. n_gauss - 1 : Gaussian quadrature streams                                                   |
        //   n_gauss           : viewing stream                                                               |
        //   n_gauss + 1       : solar stream                                                                 |
        //                                                                                                    |
        // math                                                                                               |
        //   stream_weight = sqrt(2 * mu * quadrature_weight)                                                 |
        //   dmu_plus      = 0.25 / (mu_row + mu_col)                                                         |
        //                                                                                                    |
        //   dmu_min uses the ordinary difference except when two streams are nearly equal. The equal-stream  |
        //   expression is the LABOS limiting form used by the transmission term.                             |
        //                                                                                                    |
        //     ordinary     : dmu_min = 0.25 / (mu_row - mu_col)                                              |
        //     equal stream : dmu_min = 0.25 / (mu_row * mu_col)                                              |
        //                                                                                                    |
        // numbers                                                                                            |
        //   direction_pair_floor = 1.0e-12 keeps divisions finite for exact-zero sums/products.              |
        //   equal_stream_delta   = 1.0e-6 marks two direction cosines as the same stream.                    |
        // ---------------------------------------------------------------------------------------------------|

        var nodes_01: [max_gauss]f64 = undefined;
        var weights_01: [max_gauss]f64 = undefined;
        gauss_legendre.fillDisamarDivPoints01(
            @intCast(n_gauss),
            nodes_01[0..],
            weights_01[0..],
        ) catch unreachable;

        var geo: Geometry = undefined;
        geo.n_gauss = n_gauss;
        geo.nmutot = n_gauss + max_extra;
        geo.mu0 = mu0;
        geo.muv = muv;

        for (0..n_gauss) |stream_index| {
            const mu = nodes_01[stream_index];
            const quadrature_weight = weights_01[stream_index];

            geo.u[stream_index] = mu;
            geo.w[stream_index] = @sqrt(2.0 * mu * quadrature_weight);
            geo.ug[stream_index] = mu;
            geo.wg[stream_index] = quadrature_weight;
        }

        geo.u[n_gauss] = muv;
        geo.w[n_gauss] = 1.0;
        geo.u[n_gauss + 1] = mu0;
        geo.w[n_gauss + 1] = 1.0;

        for (geo.nmutot..max_nmutot) |stream_index| {
            geo.u[stream_index] = 0.0;
            geo.w[stream_index] = 0.0;
        }

        for (geo.n_gauss..max_gauss) |stream_index| {
            geo.ug[stream_index] = 0.0;
            geo.wg[stream_index] = 0.0;
        }

        for (0..geo.nmutot) |col| {
            const mu_col = geo.u[col];

            for (0..geo.nmutot) |row| {
                const mu_row = geo.u[row];
                const pair_index = row * geo.nmutot + col;
                const delta_mu = mu_row - mu_col;
                const same_stream = @abs(delta_mu) < equal_stream_delta;

                geo.dmu_plus[pair_index] = 0.25 / @max(mu_row + mu_col, direction_pair_floor);
                geo.dmu_same[pair_index] = same_stream;

                geo.dmu_min[pair_index] = if (same_stream)
                    0.25 / @max(mu_row * mu_col, direction_pair_floor)
                else
                    0.25 / delta_mu;
            }
        }

        return geo;
    }

    pub fn viewIdx(self: *const Geometry) usize {
        // Geometry.viewIdx ----------------------------------------------------------------------------------|
        // The viewing stream is stored directly after the Gaussian quadrature streams.                       |
        // ---------------------------------------------------------------------------------------------------|

        return self.n_gauss;
    }
};
// -----------------------------------------------------------------------------------------------------------|
