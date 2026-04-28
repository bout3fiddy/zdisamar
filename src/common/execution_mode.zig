pub const ExecutionMode = enum {
    synthetic,
    operational_measured_input,

    pub fn label(self: ExecutionMode) []const u8 {
        return @tagName(self);
    }
};
