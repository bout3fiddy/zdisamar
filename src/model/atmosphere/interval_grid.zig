const std = @import("std");
const errors = @import("../../core/errors.zig");
const units = @import("../../core/units.zig");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const IntervalSemantics = types.IntervalSemantics;
pub const ParticlePlacementSemantics = types.ParticlePlacementSemantics;

pub const VerticalInterval = struct {
    index_1based: u32 = 0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    top_altitude_km: f64 = std.math.nan(f64),
    bottom_altitude_km: f64 = std.math.nan(f64),
    top_pressure_variance_hpa2: f64 = 0.0,
    bottom_pressure_variance_hpa2: f64 = 0.0,
    altitude_divisions: u32 = 0,

    pub fn hasAltitudeBounds(self: VerticalInterval) bool {
        return std.math.isFinite(self.top_altitude_km) and std.math.isFinite(self.bottom_altitude_km);
    }

    pub fn validate(self: VerticalInterval) errors.Error!void {
        if (self.index_1based == 0) return errors.Error.InvalidRequest;
        if (self.altitude_divisions == 0) return errors.Error.InvalidRequest;

        (units.PressureRangeHpa{
            .top_hpa = self.top_pressure_hpa,
            .bottom_hpa = self.bottom_pressure_hpa,
        }).validate() catch return errors.Error.InvalidRequest;

        const has_top_altitude = std.math.isFinite(self.top_altitude_km);
        const has_bottom_altitude = std.math.isFinite(self.bottom_altitude_km);
        if (has_top_altitude != has_bottom_altitude) return errors.Error.InvalidRequest;
        if (self.hasAltitudeBounds()) {
            (units.AltitudeRangeKm{
                .bottom_km = self.bottom_altitude_km,
                .top_km = self.top_altitude_km,
            }).validate() catch return errors.Error.InvalidRequest;
        }
        if (self.top_pressure_variance_hpa2 < 0.0 or self.bottom_pressure_variance_hpa2 < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn midpointAltitudeKm(self: VerticalInterval) f64 {
        if (!self.hasAltitudeBounds()) return 0.0;
        return 0.5 * (self.top_altitude_km + self.bottom_altitude_km);
    }

    pub fn thicknessKm(self: VerticalInterval) f64 {
        if (!self.hasAltitudeBounds()) return 0.0;
        return @max(self.top_altitude_km - self.bottom_altitude_km, 0.0);
    }
};

pub const IntervalGrid = struct {
    semantics: IntervalSemantics = .none,
    fit_interval_index_1based: u32 = 0,
    intervals: []const VerticalInterval = &.{},
    owns_intervals: bool = false,

    pub fn enabled(self: IntervalGrid) bool {
        return self.intervals.len != 0;
    }

    pub fn intervalCount(self: IntervalGrid) u32 {
        return @intCast(self.intervals.len);
    }

    pub fn fitInterval(self: IntervalGrid) ?VerticalInterval {
        if (!self.enabled() or self.fit_interval_index_1based == 0) return null;
        const index = self.fit_interval_index_1based - 1;
        if (index >= self.intervals.len) return null;
        return self.intervals[index];
    }

    pub fn validate(self: IntervalGrid, fallback_sublayer_divisions: u8) errors.Error!void {
        if (!self.enabled()) {
            if (self.semantics == .explicit_pressure_bounds or self.fit_interval_index_1based != 0) {
                return errors.Error.InvalidRequest;
            }
            return;
        }
        if (self.semantics == .none) return errors.Error.InvalidRequest;

        var previous_bottom_pressure_hpa: f64 = 0.0;
        var previous_bottom_altitude_km: f64 = 0.0;
        var previous_has_altitude_bounds = false;
        for (self.intervals, 0..) |interval, index| {
            try interval.validate();
            if (interval.index_1based != index + 1) return errors.Error.InvalidRequest;
            if (index != 0) {
                if (!std.math.approxEqAbs(f64, interval.top_pressure_hpa, previous_bottom_pressure_hpa, 1.0e-9)) {
                    return errors.Error.InvalidRequest;
                }
                if (previous_has_altitude_bounds and interval.hasAltitudeBounds() and
                    !std.math.approxEqAbs(f64, previous_bottom_altitude_km, interval.top_altitude_km, 1.0e-9))
                {
                    return errors.Error.InvalidRequest;
                }
            }
            previous_bottom_pressure_hpa = interval.bottom_pressure_hpa;
            previous_bottom_altitude_km = interval.bottom_altitude_km;
            previous_has_altitude_bounds = interval.hasAltitudeBounds();
        }
        if (self.fit_interval_index_1based > self.intervals.len) return errors.Error.InvalidRequest;
        if (fallback_sublayer_divisions == 0) return errors.Error.InvalidRequest;
    }

    pub fn deinitOwned(self: *IntervalGrid, allocator: Allocator) void {
        if (self.owns_intervals and self.intervals.len != 0) allocator.free(self.intervals);
        self.* = .{};
    }
};

pub const IntervalPlacement = struct {
    semantics: ParticlePlacementSemantics = .none,
    interval_index_1based: u32 = 0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    top_altitude_km: f64 = std.math.nan(f64),
    bottom_altitude_km: f64 = std.math.nan(f64),

    pub fn enabled(self: IntervalPlacement) bool {
        return self.semantics != .none;
    }

    pub fn hasAltitudeBounds(self: IntervalPlacement) bool {
        return std.math.isFinite(self.top_altitude_km) and std.math.isFinite(self.bottom_altitude_km);
    }

    pub fn validate(self: IntervalPlacement) errors.Error!void {
        if (!self.enabled()) return;

        switch (self.semantics) {
            .none => {},
            .altitude_center_width_approximation => {
                (units.AltitudeRangeKm{
                    .bottom_km = self.bottom_altitude_km,
                    .top_km = self.top_altitude_km,
                }).validate() catch return errors.Error.InvalidRequest;
            },
            .explicit_interval_bounds => {
                if (self.interval_index_1based == 0) return errors.Error.InvalidRequest;
                (units.PressureRangeHpa{
                    .top_hpa = self.top_pressure_hpa,
                    .bottom_hpa = self.bottom_pressure_hpa,
                }).validate() catch return errors.Error.InvalidRequest;
                const has_top_altitude = std.math.isFinite(self.top_altitude_km);
                const has_bottom_altitude = std.math.isFinite(self.bottom_altitude_km);
                if (has_top_altitude != has_bottom_altitude) return errors.Error.InvalidRequest;
                if (self.hasAltitudeBounds()) {
                    (units.AltitudeRangeKm{
                        .bottom_km = self.bottom_altitude_km,
                        .top_km = self.top_altitude_km,
                    }).validate() catch return errors.Error.InvalidRequest;
                }
            },
        }
    }

    pub fn midpointAltitudeKm(self: IntervalPlacement) f64 {
        if (!self.hasAltitudeBounds()) return 0.0;
        return 0.5 * (self.top_altitude_km + self.bottom_altitude_km);
    }

    pub fn thicknessKm(self: IntervalPlacement) f64 {
        if (!self.hasAltitudeBounds()) return 0.0;
        return @max(self.top_altitude_km - self.bottom_altitude_km, 0.0);
    }
};
