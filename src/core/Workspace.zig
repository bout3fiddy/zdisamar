pub const Workspace = struct {
    label: []const u8,
    reset_count: u64 = 0,

    pub fn init(label: []const u8) Workspace {
        return .{ .label = label };
    }

    pub fn reset(self: *Workspace) void {
        self.reset_count += 1;
    }
};
