// instrumentation: calculation telemetry disabled sink
// captures: nothing
// why: keep product/test builds free of Parquet capture state and row-writing API.
pub const available = false;

pub const Stage = enum(i64) {
    none = 0,
    fast = 1,
    correction = 2,
};

pub const max_state_value_count = 3;

pub const Context = struct {};
