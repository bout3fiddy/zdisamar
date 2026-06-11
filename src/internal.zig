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
    pub const fast_mode = @import("input/fast_mode.zig");
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
    pub const refresh_profile_lines = @import("setup/refresh_profile_lines.zig");
    pub const refresh_tables = @import("setup/refresh_tables.zig");
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
    pub const profile_line_memory = @import("cache/profile_line_memory.zig");
    pub const weak_line_cutoff_memory = @import("cache/weak_line_cutoff_memory.zig");
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
    pub const layer_depths = @import("optics/layer_depths.zig");
    pub const rayleigh = @import("optics/rayleigh.zig");
};
// ------------------------------------------------------------------------------------------------------------|

// transport --------------------------------------------------------------------------------------------------|
// Namespace-only test import wrapper for WP3 transport state modules.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// footprint: per instance = 0 B; this wrapper is used as a comptime namespace only                            |
pub const transport = struct {
    pub const jacobian_states = @import("transport/jacobian_states.zig");
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
