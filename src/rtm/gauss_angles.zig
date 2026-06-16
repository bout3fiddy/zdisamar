const gauss_legendre = @import("../common/math/gauss_legendre.zig");

pub const max_gauss: usize = 10;
pub const max_extra_streams: usize = 2;
pub const max_stream_count: usize = max_gauss + max_extra_streams;
pub const max_pair_count: usize = max_stream_count * max_stream_count;

const direction_pair_floor: f64 = 1.0e-12;
const equal_stream_delta: f64 = 1.0e-6;

pub const Error = error{
    InvalidGaussCount,
};

// gauss_angles.zig ------------------------------------------------------------------------------------------ |
// LABOS stream direction geometry for one solar/viewing angle pair.                                           |
//                                                                                                             |
//   The Gauss nodes come from the DISAMAR division-point helper.                                         |
//                                                                                                             |
// numerical guards                                                                                            |
//   direction_pair_floor = 1.0e-12 keeps plus/same-stream denominators finite.                                |
//   equal_stream_delta = 1.0e-6 selects the limiting expression for nearly equal stream cosines.              |
// ------------------------------------------------------------------------------------------------------------|

// GaussGeometry ----------------------------------------------------------------------------------------------|
// Direction grid and precomputed direction-pair factors for one LABOS solve geometry.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2832 B (2.766 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..   7] n_gauss     : usize                                                                            |
// [   8..  15] stream_count: usize                                                                            |
// [  16.. 111] u           : [12]f64                                                                          |
// [ 112.. 207] w           : [12]f64                                                                          |
// [ 208.. 287] ug          : [10]f64                                                                          |
// [ 288.. 367] wg          : [10]f64                                                                          |
// [ 368..1519] dmu_plus    : [144]f64                                                                         |
// [1520..2671] dmu_min     : [144]f64                                                                         |
// [2672..2815] dmu_same    : [144]bool                                                                        |
// [2816..2823] solar_mu    : f64                                                                              |
// [2824..2831] view_mu     : f64                                                                              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 45 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 2832 B (2.766 KiB); total = per instance * live instance count                    |
pub const GaussGeometry = struct {
    n_gauss: usize,
    stream_count: usize,
    u: [max_stream_count]f64,
    w: [max_stream_count]f64,
    ug: [max_gauss]f64,
    wg: [max_gauss]f64,
    dmu_plus: [max_pair_count]f64,
    dmu_min: [max_pair_count]f64,
    dmu_same: [max_pair_count]bool,
    solar_mu: f64,
    view_mu: f64,

    pub fn init(n_gauss: usize, solar_mu: f64, view_mu: f64) Error!GaussGeometry {
        // init ---------------------------------------------------------------------------------------------- |
        // Build the LABOS direction grid for one solar/viewing geometry.                                      |
        //                                                                                                     |
        // direction indexes                                                                                   |
        //   0 .. n_gauss - 1 : Gaussian quadrature streams                                                    |
        //   viewIndex()        : viewing stream                                                               |
        //   solarIndex()       : solar stream                                                                 |
        //                                                                                                     |
        // math                                                                                                |
        //   stream_weight = sqrt(2 * mu * quadrature_weight)                                                  |
        //   dmu_plus      = 0.25 / max(mu_row + mu_col, direction_pair_floor)                                 |
        //   dmu_min       = 0.25 / (mu_row - mu_col), or the same-stream limiting expression below            |
        //   same stream    = abs(mu_row - mu_col) < equal_stream_delta                                        |
        // ----------------------------------------------------------------------------------------------------|
        if (n_gauss == 0 or n_gauss > max_gauss) return error.InvalidGaussCount;

        var nodes_01: [max_gauss]f64 = undefined;
        var weights_01: [max_gauss]f64 = undefined;
        gauss_legendre.fillDisamarDivPoints01(
            @intCast(n_gauss),
            nodes_01[0..],
            weights_01[0..],
        ) catch return error.InvalidGaussCount;

        var geometry: GaussGeometry = undefined;
        geometry.n_gauss = n_gauss;
        geometry.stream_count = n_gauss + max_extra_streams;
        geometry.solar_mu = solar_mu;
        geometry.view_mu = view_mu;

        for (0..n_gauss) |stream_index| {
            const mu = nodes_01[stream_index];
            const quadrature_weight = weights_01[stream_index];

            geometry.u[stream_index] = mu;
            geometry.w[stream_index] = @sqrt(2.0 * mu * quadrature_weight);
            geometry.ug[stream_index] = mu;
            geometry.wg[stream_index] = quadrature_weight;
        }

        geometry.u[n_gauss] = view_mu;
        geometry.w[n_gauss] = 1.0;
        geometry.u[n_gauss + 1] = solar_mu;
        geometry.w[n_gauss + 1] = 1.0;

        for (geometry.stream_count..max_stream_count) |stream_index| {
            geometry.u[stream_index] = 0.0;
            geometry.w[stream_index] = 0.0;
        }

        for (geometry.n_gauss..max_gauss) |stream_index| {
            geometry.ug[stream_index] = 0.0;
            geometry.wg[stream_index] = 0.0;
        }

        for (0..geometry.stream_count) |col| {
            const mu_col = geometry.u[col];

            for (0..geometry.stream_count) |row| {
                const mu_row = geometry.u[row];
                const index = geometry.pairIndex(row, col);
                const delta_mu = mu_row - mu_col;
                const same_stream = @abs(delta_mu) < equal_stream_delta;

                geometry.dmu_plus[index] =
                    0.25 / @max(mu_row + mu_col, direction_pair_floor);
                geometry.dmu_same[index] = same_stream;
                geometry.dmu_min[index] = if (same_stream)
                    0.25 / @max(mu_row * mu_col, direction_pair_floor)
                else
                    0.25 / delta_mu;
            }
        }

        return geometry;
    }

    pub fn viewIndex(self: *const GaussGeometry) usize {
        // viewIndex ----------------------------------------------------------------------------------------- |
        // The viewing stream is stored directly after the Gaussian quadrature streams.                        |
        // ----------------------------------------------------------------------------------------------------|
        return self.n_gauss;
    }

    pub fn solarIndex(self: *const GaussGeometry) usize {
        // solarIndex ---------------------------------------------------------------------------------------- |
        // The solar stream is stored directly after the viewing stream.                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.n_gauss + 1;
    }

    pub fn pairIndex(self: *const GaussGeometry, row: usize, col: usize) usize {
        // pairIndex ----------------------------------------------------------------------------------------- |
        // Direction-pair arrays use row-major active-stream indexing.                                         |
        // ----------------------------------------------------------------------------------------------------|
        return row * self.stream_count + col;
    }
};
// ------------------------------------------------------------------------------------------------------------|
