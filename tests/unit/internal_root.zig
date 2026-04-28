// Zig discovers `test` blocks from a file only when the file is referenced
// from a construct that is semantically analyzed. A bare top-level
// `const _x = @import(...);` is lazily skipped if `_x` is never read, so the
// imported tests would silently disappear. A `test` block forces analysis.
test {
    _ = @import("atmosphere_test.zig");
    _ = @import("absorber_test.zig");
    _ = @import("hitran_partition_tables_test.zig");
    _ = @import("instrument_test.zig");
    _ = @import("measurement_test.zig");
    _ = @import("reference_data_test.zig");
    _ = @import("scene_test.zig");

    _ = @import("core/units_test.zig");
    _ = @import("core/lut_controls_test.zig");
    _ = @import("kernels/quadrature/gauss_legendre_test.zig");
    _ = @import("kernels/linalg/cholesky_test.zig");
    _ = @import("kernels/linalg/small_dense_test.zig");
    _ = @import("kernels/interpolation/spline_test.zig");

    _ = @import("kernels/spectra/calibration_test.zig");
    _ = @import("kernels/spectra/convolution_test.zig");
    _ = @import("kernels/spectra/grid_test.zig");
    _ = @import("kernels/spectra/noise_test.zig");
    _ = @import("kernels/spectra/sampling_test.zig");
    _ = @import("kernels/optics/prepare/phase_functions_test.zig");
    _ = @import("kernels/optics/prepare/band_means_test.zig");

    _ = @import("kernels/transport/derivatives_test.zig");
    _ = @import("kernels/transport/dispatcher_test.zig");
    _ = @import("kernels/transport/common_route_test.zig");
    _ = @import("kernels/transport/labos/orders_test.zig");
    _ = @import("kernels/transport/labos/reflectance_test.zig");
    _ = @import("kernels/transport/measurement/spectral_eval_test.zig");
    _ = @import("kernels/transport/measurement/workspace_test.zig");
}
