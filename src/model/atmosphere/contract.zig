const std = @import("std");
const errors = @import("../../core/errors.zig");
const Binding = @import("../Binding.zig").Binding;
const Allocator = std.mem.Allocator;
const IntervalGrid = @import("interval_grid.zig").IntervalGrid;
const SubcolumnLayout = @import("subcolumns.zig").SubcolumnLayout;

pub const Atmosphere = struct {
    layer_count: u32 = 0,
    sublayer_divisions: u8 = 3,
    has_clouds: bool = false,
    has_aerosols: bool = false,
    profile_source: Binding = .none,
    surface_pressure_hpa: f64 = 0.0,
    interval_grid: IntervalGrid = .{},
    subcolumns: SubcolumnLayout = .{},

    pub fn preparedLayerCount(self: Atmosphere) u32 {
        if (self.interval_grid.enabled()) return self.interval_grid.intervalCount();
        return self.layer_count;
    }

    pub fn validate(self: Atmosphere) errors.Error!void {
        try self.profile_source.validate();
        try self.interval_grid.validate(self.sublayer_divisions);
        try self.subcolumns.validate();

        if (self.preparedLayerCount() == 0 and
            (self.has_clouds or self.has_aerosols or self.profile_source.enabled() or self.surface_pressure_hpa != 0.0))
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
        self.subcolumns.deinitOwned(allocator);
    }
};
