// internal.zig -----------------------------------------------------------------------------------------------|
// Test access router for WP2 setup, asset, cache, common, input, and instrumentation modules.                 |
//                                                                                                             |
// Product callers use src/root.zig. Tests use this file to reach small table builders without widening API.   |
// public package surface before later work packages add public forward-model entry points.                    |
// ------------------------------------------------------------------------------------------------------------|

pub const public = @import("root.zig");

// common -----------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for shared support modules.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const common = struct {
    pub const errors = @import("common/errors.zig");
    pub const hashing = @import("common/hashing.zig");
    pub const memory = @import("common/memory.zig");
    pub const worker_partition = @import("common/worker_partition.zig");

    // math ---------------------------------------------------------------------------------------------------|
    // Namespace-only test import wrapper for shared math helpers.                                             |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 0 B (0.000 KiB), align: 1 B                                                                       |
    //                                                                                                         |
    // memory                                                                                                  |
    //   no stored fields                                                                                      |
    pub const math = struct {
        pub const gauss_legendre = @import("common/math/gauss_legendre.zig");
        pub const spline = @import("common/math/spline.zig");
    };
    // --------------------------------------------------------------------------------------------------------|

    pub const units = @import("common/units.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// input ------------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for typed input/default modules.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const input = struct {
    pub const defaults = @import("input/defaults.zig");
    pub const hitran_partition_tables = @import("input/hitran_partition_tables.zig");
    pub const json = @import("input/json.zig");
    pub const o2_case = @import("input/o2_case.zig");
    pub const validate = @import("input/validate.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// assets -----------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for asset readers.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const assets = struct {
    pub const readers = @import("assets/readers.zig");
    pub const root = @import("assets/root.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// setup ------------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for setup table builders.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const setup = struct {
    pub const aerosol_tables = @import("setup/aerosol_tables.zig");
    pub const atmosphere_layers = @import("setup/atmosphere_layers.zig");
    pub const cia_table = @import("setup/cia_table.zig");
    pub const instrument_tables = @import("setup/instrument_tables.zig");
    pub const line_tables = @import("setup/line_tables.zig");
    pub const o2_run_tables = @import("setup/o2_run_tables.zig");
    pub const phase_table = @import("setup/phase_table.zig");
    pub const solar_table = @import("setup/solar_table.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// cache ------------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for retained setup/cache memory modules.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const cache = struct {
    pub const forward_worker_pool = @import("cache/forward_worker_pool.zig");
    pub const o2_session_memory = @import("cache/o2_session_memory.zig");
    pub const profile_line_memory = @import("cache/profile_line_memory.zig");
    pub const radiance_memory = @import("cache/radiance_memory.zig");
    pub const solar_irradiance_memory = @import("cache/solar_irradiance_memory.zig");
    pub const spectrum_memory = @import("cache/spectrum_memory.zig");
    pub const transport_worker_memory = @import("cache/transport_worker_memory.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// optics -----------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for WP3 optical-depth fill modules.                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const optics = struct {
    pub const cia_absorption = @import("optics/cia_absorption.zig");
    pub const curved_sun_path = @import("optics/curved_sun_path.zig");
    pub const layer_depths = @import("optics/layer_depths.zig");
    pub const rayleigh = @import("optics/rayleigh.zig");
    pub const source_levels = @import("optics/source_levels.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// output -----------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for public output owner rows.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const output = struct {
    pub const atmospheric_budget = @import("output/atmospheric_budget.zig");
    pub const instrument_response = @import("output/instrument_response.zig");
    pub const o2_line_contributions = @import("output/o2_line_contributions.zig");
    pub const o2_o2_cia = @import("output/o2_o2_cia.zig");
    pub const spectrum = @import("output/spectrum.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// retrieval --------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for WP5 retrieval state-space and result owners.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const retrieval = struct {
    pub const algebra = @import("retrieval/algebra.zig");
    pub const root = @import("retrieval/root.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// rtm --------------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for WP3 RTM state modules.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const rtm = struct {
    pub const attenuation = @import("rtm/attenuation.zig");
    pub const controls = @import("rtm/controls.zig");
    pub const gauss_angles = @import("rtm/gauss_angles.zig");
    pub const jacobian_states = @import("rtm/jacobian_states.zig");
    pub const layer_reflect_transmit = @import("rtm/layer_reflect_transmit.zig");
    pub const matrix_12x10 = @import("rtm/matrix_12x10.zig");
    pub const phase_basis = @import("rtm/phase_basis.zig");
    pub const phase_timing = @import("rtm/phase_timing.zig");
    pub const reflectance = @import("rtm/reflectance.zig");
    pub const rows = @import("rtm/rows.zig");
    pub const scattering_orders = @import("rtm/scattering_orders.zig");
    pub const solve = @import("rtm/solve.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// spectrum ---------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for WP3 spectrum sampling and exact wavelength modules.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const spectrum = struct {
    pub const instrument_average = @import("spectrum/instrument_average.zig");
    pub const radiance_results = @import("spectrum/radiance_results.zig");
    pub const radiance_wavelengths = @import("spectrum/radiance_wavelengths.zig");
    pub const sampling_table = @import("spectrum/sampling_table.zig");
    pub const solar_lookup = @import("spectrum/solar_lookup.zig");
    pub const spectrum_run = @import("spectrum/spectrum_run.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// validation -------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for validation-only WP3 metric helpers.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const validation = struct {
    pub const o2a_band_metrics = @import("validation/o2a_band_metrics.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// instrumentation --------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for instrumentation facades.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const instrumentation = struct {
    pub const sensitivity = @import("instrumentation/sensitivity.zig");
    pub const telemetry = @import("instrumentation/telemetry.zig");
    pub const trace = @import("instrumentation/trace.zig");
};
// ------------------------------------------------------------------------------------------------------------|
