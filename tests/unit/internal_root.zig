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

    _ = @import("common/units_test.zig");
    _ = @import("common/lut_controls_test.zig");
    _ = @import("common/math/quadrature/gauss_legendre_test.zig");
    _ = @import("common/math/linalg/cholesky_test.zig");
    _ = @import("common/math/linalg/small_dense_test.zig");
    _ = @import("common/math/interpolation/spline_test.zig");

    _ = @import("forward_model/instrument_grid/spectral_math/calibration_test.zig");
    _ = @import("forward_model/instrument_grid/spectral_math/convolution_test.zig");
    _ = @import("forward_model/instrument_grid/spectral_math/grid_test.zig");
    _ = @import("forward_model/instrument_grid/spectral_math/noise_test.zig");
    _ = @import("forward_model/instrument_grid/spectral_math/sampling_test.zig");
    _ = @import("forward_model/optical_properties/shared/phase_functions_test.zig");
    _ = @import("forward_model/optical_properties/shared/band_means_test.zig");

    _ = @import("forward_model/radiative_transfer/derivatives_test.zig");
    _ = @import("forward_model/radiative_transfer/dispatcher_test.zig");
    _ = @import("forward_model/radiative_transfer/common_route_test.zig");
    _ = @import("forward_model/radiative_transfer/labos/orders_test.zig");
    _ = @import("forward_model/radiative_transfer/labos/reflectance_test.zig");
    _ = @import("forward_model/instrument_grid/grid_calculation/spectral_eval_test.zig");
    _ = @import("forward_model/instrument_grid/grid_calculation/storage_test.zig");

    _ = @import("bands_test.zig");
    _ = @import("binding_test.zig");
    _ = @import("geometry_test.zig");
    _ = @import("inverse_problem_test.zig");
    _ = @import("state_vector_test.zig");
    _ = @import("surface_test.zig");
    _ = @import("measurement_model_test.zig");

    _ = @import("reference/airmass_phase_test.zig");
    _ = @import("reference/cia_test.zig");
    _ = @import("reference/climatology_test.zig");
    _ = @import("reference/cross_sections_test.zig");
    _ = @import("reference/rayleigh_test.zig");

    _ = @import("input/reference_data/ingest/root_test.zig");
    _ = @import("input/reference_data/ingest/reference_assets_test.zig");
    _ = @import("input/reference_data/ingest/reference_assets_loaded_asset_test.zig");
    _ = @import("validation/disamar_reference/parser_test.zig");
    _ = @import("forward_model/implementations/surface_test.zig");

    _ = @import("forward_model/optical_properties/state_build/layer_accumulation_test.zig");
    _ = @import("forward_model/optical_properties/state_build/carrier_eval_test.zig");
    _ = @import("forward_model/optical_properties/state_build/forward_layers_test.zig");
    _ = @import("forward_model/optical_properties/state_build/pseudo_spherical_test.zig");
    _ = @import("forward_model/optical_properties/state_build/rtm_quadrature_test.zig");
    _ = @import("forward_model/optical_properties/state_build/root_test.zig");
    _ = @import("forward_model/optical_properties/state_build/source_interfaces_test.zig");
    _ = @import("forward_model/implementations/instrument/integration_test.zig");
    _ = @import("forward_model/implementations/noise_test.zig");
    _ = @import("forward_model/implementations/radiative_transfer_test.zig");

    _ = @import("forward_model/radiative_transfer/labos/layers_test.zig");
    _ = @import("forward_model/radiative_transfer/adding/root_test.zig");
    _ = @import("forward_model/instrument_grid/grid_calculation/root_test.zig");
    _ = @import("forward_model/instrument_grid/grid_calculation/spectral_forward_test.zig");
}
