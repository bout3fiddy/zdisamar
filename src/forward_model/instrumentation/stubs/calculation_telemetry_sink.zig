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
//   Wavelength sampling, product simulation, LABOS, and OE keep their Telemetry.* hooks in place, but normal  |
//   builds carry no thread-local writes, row assembly, allocator traffic, Parquet dependency, or sink branch. |
//                                                                                                             |
// memory                                                                                                      |
//   Context is empty in the disabled variant. There is no retained state, no thread-local context, no row     |
//   buffer, and no out-of-line storage owned by this module.                                                  |
// ------------------------------------------------------------------------------------------------------------|
pub const available = false;

pub const Stage = enum(i64) {
    none = 0,
    fast = 1,
    correction = 2,
};

pub const max_state_value_count = 3;

pub const Context = struct {};
