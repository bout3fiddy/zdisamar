// calculation_telemetry_sink.zig -----------------------------------------------------------------------------|
// Disabled calculation-telemetry sink selected by normal product and test builds.                             |
//                                                                                                             |
// called by                                                                                                   |
//   telemetry.zig imports this module through the build.zig module alias when the product library, tests,     |
//   trace harnesses, and perturbation harnesses are not using the retained telemetry writer.                  |
//                                                                                                             |
// mirrored sink                                                                                               |
//   scaffolding/instrumentation/telemetry/zig/calculation_telemetry_sink.zig owns the thread-local context,   |
//   Parquet row schemas, expression catalog, counters, and row writers used by telemetry research CLIs.       |
//                                                                                                             |
// disabled path                                                                                               |
//   available=false makes telemetry.zig set enabled=false even when the module is imported. The facade then   |
//   returns at comptime before row-writing functions are called. Stage, max_state_value_count, and Context    |
//   still live here because public call sites name them through telemetry.zig regardless of build mode.       |
//                                                                                                             |
// hot path                                                                                                    |
//   Spectrum sampling, reflectance assembly, LABOS layer/order/Fourier decisions, and Jacobian columns keep   |
//   their Telemetry.* hooks in place. Normal builds carry no thread-local writes, row assembly, allocator     |
//   traffic, Parquet dependency, or sink branch.                                                              |
//                                                                                                             |
// memory                                                                                                      |
//   Context is empty in the disabled variant. There is no retained state, no thread-local context, no row     |
//   buffer, and no out-of-line storage owned by this module.                                                  |
// ------------------------------------------------------------------------------------------------------------|
pub const available = false;

// Stage ------------------------------------------------------------------------------------------------------|
// Stable stage tags using the retained telemetry sink.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] enum tag : i64                                                                                       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); used only when a caller names a stage value                      |
pub const Stage = enum(i64) {
    none = 0,
    fast = 1,
    correction = 2,
};
// ------------------------------------------------------------------------------------------------------------|

pub const max_state_value_count = 3;

// Context ----------------------------------------------------------------------------------------------------|
// Empty context row used when calculation telemetry is disabled.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 0 B (0.000 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
//   no stored fields                                                                                          |
//                                                                                                             |
// disabled path                                                                                               |
//   telemetry.zig returns this from currentContext and accepts it in setContext so product and transport code |
//   can keep one typed call surface without carrying thread-local telemetry state.                            |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 0 B; no row buffers, thread-local storage, or out-of-line payload                 |
pub const Context = struct {};
// ------------------------------------------------------------------------------------------------------------|
