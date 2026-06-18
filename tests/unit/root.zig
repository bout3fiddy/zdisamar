// Aggregator root for the retained `test-unit` suite. This file only wires test
// files into one compilation; the assertions themselves live in the imported
// `*_test.zig` files named for what they verify.
test {
    _ = @import("input/scene_test.zig");
    _ = @import("input/hitran_partition_tables_test.zig");
    _ = @import("assets/readers_test.zig");
    _ = @import("common/units_test.zig");
    _ = @import("common/memory_test.zig");
    _ = @import("common/worker_partition_test.zig");
    _ = @import("common/math/gauss_legendre_test.zig");
    _ = @import("common/math/spline_test.zig");
    _ = @import("setup/run_tables_test.zig");
    _ = @import("setup/phase_table_test.zig");
    _ = @import("cache/forward_worker_pool_test.zig");
    _ = @import("cache/session_memory_test.zig");
    _ = @import("cache/profile_line_memory_test.zig");
    _ = @import("cache/radiance_memory_test.zig");
    _ = @import("cache/solar_irradiance_memory_test.zig");
    _ = @import("cache/spectrum_memory_test.zig");
    _ = @import("cache/transport_worker_memory_test.zig");
    _ = @import("optics/curved_sun_path_test.zig");
    _ = @import("optics/layer_depths_test.zig");
    _ = @import("optics/source_levels_test.zig");
    _ = @import("rtm/attenuation_test.zig");
    _ = @import("rtm/controls_test.zig");
    _ = @import("rtm/gauss_angles_test.zig");
    _ = @import("rtm/jacobian_states_test.zig");
    _ = @import("rtm/layer_reflect_transmit_test.zig");
    _ = @import("rtm/matrix_12x10_test.zig");
    _ = @import("rtm/phase_basis_test.zig");
    _ = @import("instrumentation/cost_timing_test.zig");
    _ = @import("rtm/reflectance_test.zig");
    _ = @import("rtm/rows_test.zig");
    _ = @import("rtm/scattering_orders_test.zig");
    _ = @import("rtm/solve_test.zig");
    _ = @import("spectrum/instrument_average_test.zig");
    _ = @import("spectrum/radiance_results_test.zig");
    _ = @import("spectrum/radiance_wavelengths_test.zig");
    _ = @import("spectrum/sampling_table_test.zig");
    _ = @import("spectrum/solar_lookup_test.zig");
    _ = @import("spectrum/spectrum_run_test.zig");
    _ = @import("output/atmospheric_budget_test.zig");
    _ = @import("retrieval/state_layout_test.zig");
    _ = @import("retrieval/pressure_profile_test.zig");
    _ = @import("retrieval/measured_reflectance_rows_test.zig");
    _ = @import("retrieval/retrieval_state_validation_test.zig");
    _ = @import("retrieval/iteration_math_test.zig");
    _ = @import("validation/band_metrics_test.zig");
    _ = @import("instrumentation/facades_test.zig");
    _ = @import("public_surface_test.zig");
    _ = @import("session_reuse_parity_test.zig");
}
