// No-op telemetry sink for builds without telemetry.
pub const available = false;

pub const Stage = enum(i64) {
    none = 0,
    fast = 1,
    correction = 2,
};

pub const max_state_value_count = 3;

pub const Context = struct {};
