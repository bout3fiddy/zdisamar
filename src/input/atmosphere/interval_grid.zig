const std = @import("std");
const errors = @import("../../common/errors.zig");
const units = @import("../../common/units.zig");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const IntervalSemantics = types.IntervalSemantics;
pub const ParticlePlacementSemantics = types.ParticlePlacementSemantics;

// interval_grid.zig ------------------------------------------------------------------------------------------|
// Explicit atmosphere interval and particle-placement controls.                                               |
//                                                                                                             |
// data                                                                                                        |
//   VerticalInterval is one prepared support interval. IntervalGrid owns the optional interval slice.         |
//   IntervalPlacement carries aerosol or particle placement bounds.                                           |
//                                                                                                             |
// validation                                                                                                  |
//   Pressure bounds use hPa and must be ordered from top to bottom. Altitude bounds are optional but must be  |
//   present as a pair when used.                                                                              |
//                                                                                                             |
// ownership                                                                                                   |
//   IntervalGrid.deinitOwned releases the interval slice only when owns_intervals is true.                    |
// ------------------------------------------------------------------------------------------------------------|

// VerticalInterval -------------------------------------------------------------------------------------------|
// One explicit vertical support interval.                                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] top_pressure_hpa              : f64                                                                |
// [ 8..15] bottom_pressure_hpa           : f64                                                                |
// [16..23] top_altitude_km               : f64                                                                |
// [24..31] bottom_altitude_km            : f64                                                                |
// [32..39] top_pressure_variance_hpa2    : f64                                                                |
// [40..47] bottom_pressure_variance_hpa2 : f64                                                                |
// [48..51] index_1based                  : u32                                                                |
// [52..55] altitude_divisions            : u32                                                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 56 B (0.055 KiB); total = per instance * live interval count                      |
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
// ------------------------------------------------------------------------------------------------------------|

// IntervalGrid -----------------------------------------------------------------------------------------------|
// Owner/view header for explicit vertical intervals.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] intervals                  : []const VerticalInterval                                              |
// [16..19] fit_interval_index_1based  : u32                                                                   |
// [20..20] semantics                  : IntervalSemantics                                                     |
// [21..21] owns_intervals             : bool                                                                  |
// [22..23] trailing padding           : 2 B                                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   intervals stores out-of-line VerticalInterval rows. It is owned only when owns_intervals is true.         |
//                                                                                                             |
// unused bits: 16 padding + 6 enum-storage slack + 7 bool-storage slack = 29 bits                             |
// footprint: per instance = 24 B (0.023 KiB); total also includes owned interval rows                         |
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
                if (!std.math.approxEqAbs(
                    f64,
                    interval.top_pressure_hpa,
                    previous_bottom_pressure_hpa,
                    1.0e-9,
                )) {
                    return errors.Error.InvalidRequest;
                }

                if (previous_has_altitude_bounds and interval.hasAltitudeBounds() and
                    !std.math.approxEqAbs(
                        f64,
                        previous_bottom_altitude_km,
                        interval.top_altitude_km,
                        1.0e-9,
                    ))
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
// ------------------------------------------------------------------------------------------------------------|

// IntervalPlacement ------------------------------------------------------------------------------------------|
// Particle placement bounds resolved from interval-style controls.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] top_pressure_hpa      : f64                                                                        |
// [ 8..15] bottom_pressure_hpa   : f64                                                                        |
// [16..23] top_altitude_km       : f64                                                                        |
// [24..31] bottom_altitude_km    : f64                                                                        |
// [32..35] interval_index_1based : u32                                                                        |
// [36..36] semantics             : ParticlePlacementSemantics                                                 |
// [37..39] trailing padding      : 3 B                                                                        |
//                                                                                                             |
// unused bits: 24 padding + 6 enum-storage slack = 30 bits                                                    |
// footprint: per instance = 40 B (0.039 KiB); total = per instance * live placement count                     |
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
