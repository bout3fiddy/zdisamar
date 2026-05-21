const std = @import("std");
const errors = @import("../../common/errors.zig");
const Binding = @import("../Binding.zig").Binding;
const Allocator = std.mem.Allocator;
const IntervalGrid = @import("interval_grid.zig").IntervalGrid;

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 95 B across 6 fields; largest: profile_source=56 B, interval_grid=24 B; padding: 1 B (8 bits)
//   unused bits: 8 padding + 7 bool-storage slack = 15 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
pub const Atmosphere = struct {
    layer_count: u32 = 0,
    sublayer_divisions: u8 = 3,
    has_aerosols: bool = false,
    profile_source: Binding = .none,
    surface_pressure_hpa: f64 = 0.0,
    interval_grid: IntervalGrid = .{},

    pub fn preparedLayerCount(self: Atmosphere) u32 {
        if (self.interval_grid.enabled()) return self.interval_grid.intervalCount();
        return self.layer_count;
    }

    pub fn validate(self: Atmosphere) errors.Error!void {
        try self.profile_source.validate();
        try self.interval_grid.validate(self.sublayer_divisions);

        if (self.preparedLayerCount() == 0 and
            (self.has_aerosols or self.profile_source.enabled() or self.surface_pressure_hpa != 0.0))
        {
            return errors.Error.InvalidRequest;
        }

        if (self.sublayer_divisions == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.surface_pressure_hpa != 0.0 and
            (!std.math.isFinite(self.surface_pressure_hpa) or self.surface_pressure_hpa <= 0.0))
        {
            return errors.Error.InvalidRequest;
        }
        if (self.interval_grid.enabled() and self.layer_count != 0 and self.layer_count != self.interval_grid.intervalCount()) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *Atmosphere, allocator: Allocator) void {
        self.interval_grid.deinitOwned(allocator);
    }
};
