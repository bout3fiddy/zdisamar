//! Purpose:
//!   Define the canonical atmosphere configuration that sizes vertical structure,
//!   preserves explicit interval semantics, and carries later retrieval-facing
//!   subcolumn metadata for the scene.
//!
//! Physics:
//!   This file captures pressure-bounded interval grids, fit-interval identity,
//!   optional cloud or aerosol fraction controls, and subcolumn partition
//!   support in addition to the coarse layering controls consumed by transport
//!   preparation.
//!
//! Vendor:
//!   `atmosphere profile and layer-count setup`
//!
//! Design:
//!   The Zig model keeps atmospheric structure as an explicit typed record with
//!   validated bindings instead of relying on mutable config readers or
//!   implicit defaults.
//!
//! Invariants:
//!   Interval bounds must remain positive and ordered from low pressure to high
//!   pressure, fit-interval references must stay within the active grid, and
//!   subcolumn boundaries must remain monotonic in altitude.
//!
//! Validation:
//!   Unit tests below cover profile-source validation, interval-grid semantics,
//!   positive pressure, and subcolumn ownership invariants.
const std = @import("std");
const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");
const Binding = @import("Binding.zig").Binding;
const Allocator = std.mem.Allocator;

pub const IntervalSemantics = enum {
    none,
    altitude_layering_approximation,
    explicit_pressure_bounds,
};

pub const ParticlePlacementSemantics = enum {
    none,
    altitude_center_width_approximation,
    explicit_interval_bounds,
};

pub const FractionTarget = enum {
    none,
    cloud,
    aerosol,
};

pub const FractionKind = enum {
    none,
    wavel_independent,
    wavel_dependent,
};

pub const PartitionLabel = enum {
    unspecified,
    boundary_layer,
    free_troposphere,
    fit_interval,
    stratosphere,
};

pub const VerticalInterval = struct {
    index_1based: u32 = 0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    top_pressure_variance_hpa2: f64 = 0.0,
    bottom_pressure_variance_hpa2: f64 = 0.0,
    altitude_divisions: u32 = 0,

    /// Purpose:
    ///   Ensure one pressure-bounded interval remains physically consistent.
    pub fn validate(self: VerticalInterval) errors.Error!void {
        if (self.index_1based == 0) return errors.Error.InvalidRequest;
        if (self.altitude_divisions == 0) return errors.Error.InvalidRequest;

        (units.PressureRangeHpa{
            .top_hpa = self.top_pressure_hpa,
            .bottom_hpa = self.bottom_pressure_hpa,
        }).validate() catch return errors.Error.InvalidRequest;

        if ((self.top_altitude_km != 0.0 or self.bottom_altitude_km != 0.0)) {
            (units.AltitudeRangeKm{
                .bottom_km = self.bottom_altitude_km,
                .top_km = self.top_altitude_km,
            }).validate() catch return errors.Error.InvalidRequest;
        }
        if (self.top_pressure_variance_hpa2 < 0.0 or self.bottom_pressure_variance_hpa2 < 0.0) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Return the altitude midpoint if both altitude bounds are known.
    pub fn midpointAltitudeKm(self: VerticalInterval) f64 {
        return 0.5 * (self.top_altitude_km + self.bottom_altitude_km);
    }

    /// Purpose:
    ///   Return the altitude thickness if both bounds are known.
    pub fn thicknessKm(self: VerticalInterval) f64 {
        return @max(self.top_altitude_km - self.bottom_altitude_km, 0.0);
    }
};

pub const IntervalGrid = struct {
    semantics: IntervalSemantics = .none,
    fit_interval_index_1based: u32 = 0,
    intervals: []const VerticalInterval = &.{},
    owns_intervals: bool = false,

    /// Purpose:
    ///   Report whether the atmosphere carries an explicit interval grid.
    pub fn enabled(self: IntervalGrid) bool {
        return self.intervals.len != 0;
    }

    /// Purpose:
    ///   Report the number of active pressure intervals.
    pub fn intervalCount(self: IntervalGrid) u32 {
        return @intCast(self.intervals.len);
    }

    /// Purpose:
    ///   Return the fit interval when present.
    pub fn fitInterval(self: IntervalGrid) ?VerticalInterval {
        if (!self.enabled() or self.fit_interval_index_1based == 0) return null;
        const index = self.fit_interval_index_1based - 1;
        if (index >= self.intervals.len) return null;
        return self.intervals[index];
    }

    /// Purpose:
    ///   Validate the interval grid against the enclosing atmosphere.
    pub fn validate(self: IntervalGrid, fallback_sublayer_divisions: u8) errors.Error!void {
        if (!self.enabled()) {
            if (self.semantics == .explicit_pressure_bounds or self.fit_interval_index_1based != 0) {
                return errors.Error.InvalidRequest;
            }
            return;
        }
        if (self.semantics == .none) return errors.Error.InvalidRequest;

        var previous_bottom_pressure_hpa: f64 = 0.0;
        for (self.intervals, 0..) |interval, index| {
            try interval.validate();
            if (interval.index_1based != index + 1) return errors.Error.InvalidRequest;
            if (index != 0 and interval.top_pressure_hpa < previous_bottom_pressure_hpa) {
                return errors.Error.InvalidRequest;
            }
            previous_bottom_pressure_hpa = interval.bottom_pressure_hpa;
        }
        if (self.fit_interval_index_1based > self.intervals.len) return errors.Error.InvalidRequest;
        if (fallback_sublayer_divisions == 0) return errors.Error.InvalidRequest;
    }

    /// Purpose:
    ///   Release any allocator-owned interval storage.
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
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,

    /// Purpose:
    ///   Report whether the particle placement uses explicit interval metadata.
    pub fn enabled(self: IntervalPlacement) bool {
        return self.semantics != .none;
    }

    /// Purpose:
    ///   Validate the placement metadata.
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
                if (self.top_altitude_km != 0.0 or self.bottom_altitude_km != 0.0) {
                    (units.AltitudeRangeKm{
                        .bottom_km = self.bottom_altitude_km,
                        .top_km = self.top_altitude_km,
                    }).validate() catch return errors.Error.InvalidRequest;
                }
            },
        }
    }

    /// Purpose:
    ///   Return the altitude midpoint implied by the placement.
    pub fn midpointAltitudeKm(self: IntervalPlacement) f64 {
        return 0.5 * (self.top_altitude_km + self.bottom_altitude_km);
    }

    /// Purpose:
    ///   Return the altitude thickness implied by the placement.
    pub fn thicknessKm(self: IntervalPlacement) f64 {
        return @max(self.top_altitude_km - self.bottom_altitude_km, 0.0);
    }
};

pub const FractionControl = struct {
    enabled: bool = false,
    target: FractionTarget = .none,
    kind: FractionKind = .none,
    threshold_cloud_fraction: f64 = 0.0,
    threshold_variance: f64 = 0.0,
    wavelengths_nm: []const f64 = &.{},
    values: []const f64 = &.{},
    apriori_values: []const f64 = &.{},
    variance_values: []const f64 = &.{},
    owns_arrays: bool = false,

    /// Purpose:
    ///   Validate the fraction control metadata.
    pub fn validate(self: FractionControl) errors.Error!void {
        if (!self.enabled) {
            if (self.target != .none or self.kind != .none or self.values.len != 0 or self.apriori_values.len != 0 or self.variance_values.len != 0) {
                return errors.Error.InvalidRequest;
            }
            return;
        }
        if (self.target == .none or self.kind == .none) return errors.Error.InvalidRequest;
        if (self.values.len == 0) return errors.Error.InvalidRequest;
        if (self.kind == .wavel_independent and self.values.len != 1) return errors.Error.InvalidRequest;
        if (self.kind == .wavel_dependent and self.wavelengths_nm.len != self.values.len) return errors.Error.InvalidRequest;
        if (self.apriori_values.len != 0 and self.apriori_values.len != self.values.len) return errors.Error.InvalidRequest;
        if (self.variance_values.len != 0 and self.variance_values.len != self.values.len) return errors.Error.InvalidRequest;
        for (self.values) |value| {
            if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) return errors.Error.InvalidRequest;
        }
        for (self.apriori_values) |value| {
            if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) return errors.Error.InvalidRequest;
        }
        for (self.variance_values) |value| {
            if (!std.math.isFinite(value) or value < 0.0) return errors.Error.InvalidRequest;
        }
        for (self.wavelengths_nm) |wavelength_nm| {
            if (!std.math.isFinite(wavelength_nm) or wavelength_nm <= 0.0) return errors.Error.InvalidRequest;
        }
        if (self.threshold_cloud_fraction < 0.0 or self.threshold_cloud_fraction > 1.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.threshold_variance < 0.0) return errors.Error.InvalidRequest;
    }

    /// Purpose:
    ///   Resolve the effective fraction at one wavelength.
    pub fn valueAtWavelength(self: FractionControl, wavelength_nm: f64) f64 {
        if (!self.enabled or self.values.len == 0) return 0.0;
        if (self.kind != .wavel_dependent or self.wavelengths_nm.len == 0) {
            return std.math.clamp(self.values[0], 0.0, 1.0);
        }
        if (wavelength_nm <= self.wavelengths_nm[0]) return std.math.clamp(self.values[0], 0.0, 1.0);
        for (self.wavelengths_nm[0 .. self.wavelengths_nm.len - 1], self.wavelengths_nm[1..], 0..) |left, right, index| {
            if (wavelength_nm > right) continue;
            const span = right - left;
            if (span <= 0.0) return std.math.clamp(self.values[index + 1], 0.0, 1.0);
            const weight = std.math.clamp((wavelength_nm - left) / span, 0.0, 1.0);
            return std.math.clamp(
                self.values[index] + weight * (self.values[index + 1] - self.values[index]),
                0.0,
                1.0,
            );
        }
        return std.math.clamp(self.values[self.values.len - 1], 0.0, 1.0);
    }

    /// Purpose:
    ///   Duplicate the fraction metadata into allocator-owned storage.
    pub fn clone(self: FractionControl, allocator: Allocator) !FractionControl {
        const wavelengths_nm = if (self.wavelengths_nm.len != 0)
            try allocator.dupe(f64, self.wavelengths_nm)
        else
            &.{};
        errdefer if (self.wavelengths_nm.len != 0) allocator.free(wavelengths_nm);

        const values = if (self.values.len != 0)
            try allocator.dupe(f64, self.values)
        else
            &.{};
        errdefer if (self.values.len != 0) allocator.free(values);

        const apriori_values = if (self.apriori_values.len != 0)
            try allocator.dupe(f64, self.apriori_values)
        else
            &.{};
        errdefer if (self.apriori_values.len != 0) allocator.free(apriori_values);

        const variance_values = if (self.variance_values.len != 0)
            try allocator.dupe(f64, self.variance_values)
        else
            &.{};
        errdefer if (self.variance_values.len != 0) allocator.free(variance_values);

        return .{
            .enabled = self.enabled,
            .target = self.target,
            .kind = self.kind,
            .threshold_cloud_fraction = self.threshold_cloud_fraction,
            .threshold_variance = self.threshold_variance,
            .wavelengths_nm = wavelengths_nm,
            .values = values,
            .apriori_values = apriori_values,
            .variance_values = variance_values,
            .owns_arrays = wavelengths_nm.len != 0 or values.len != 0 or apriori_values.len != 0 or variance_values.len != 0,
        };
    }

    /// Purpose:
    ///   Release any allocator-owned fraction arrays.
    pub fn deinitOwned(self: *FractionControl, allocator: Allocator) void {
        if (!self.owns_arrays) {
            self.* = .{};
            return;
        }
        if (self.wavelengths_nm.len != 0) allocator.free(self.wavelengths_nm);
        if (self.values.len != 0) allocator.free(self.values);
        if (self.apriori_values.len != 0) allocator.free(self.apriori_values);
        if (self.variance_values.len != 0) allocator.free(self.variance_values);
        self.* = .{};
    }
};

pub const Subcolumn = struct {
    index_1based: u32 = 0,
    label: PartitionLabel = .unspecified,
    bottom_altitude_km: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    gaussian_nodes: []const f64 = &.{},
    gaussian_weights: []const f64 = &.{},
    owns_arrays: bool = false,

    /// Purpose:
    ///   Ensure one retrieval-facing subcolumn remains self-consistent.
    pub fn validate(self: Subcolumn) errors.Error!void {
        if (self.index_1based == 0) return errors.Error.InvalidRequest;
        (units.AltitudeRangeKm{
            .bottom_km = self.bottom_altitude_km,
            .top_km = self.top_altitude_km,
        }).validate() catch return errors.Error.InvalidRequest;
        if (self.gaussian_nodes.len != self.gaussian_weights.len) return errors.Error.InvalidRequest;
        for (self.gaussian_nodes) |node| {
            if (!std.math.isFinite(node)) return errors.Error.InvalidRequest;
        }
        for (self.gaussian_weights) |weight| {
            if (!std.math.isFinite(weight) or weight < 0.0) return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Release any allocator-owned Gaussian support arrays.
    pub fn deinitOwned(self: *Subcolumn, allocator: Allocator) void {
        if (self.owns_arrays) {
            if (self.gaussian_nodes.len != 0) allocator.free(self.gaussian_nodes);
            if (self.gaussian_weights.len != 0) allocator.free(self.gaussian_weights);
        }
        self.* = .{};
    }
};

pub const SubcolumnLayout = struct {
    enabled: bool = false,
    boundary_layer_top_pressure_hpa: f64 = 0.0,
    boundary_layer_top_altitude_km: f64 = 0.0,
    tropopause_pressure_hpa: f64 = 0.0,
    tropopause_altitude_km: f64 = 0.0,
    subcolumns: []const Subcolumn = &.{},
    owns_subcolumns: bool = false,

    /// Purpose:
    ///   Validate the subcolumn layout and Gaussian support metadata.
    pub fn validate(self: SubcolumnLayout) errors.Error!void {
        if (!self.enabled) {
            if (self.subcolumns.len != 0) return errors.Error.InvalidRequest;
            return;
        }
        if (self.boundary_layer_top_pressure_hpa < 0.0 or self.tropopause_pressure_hpa < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.boundary_layer_top_altitude_km < 0.0 or self.tropopause_altitude_km < 0.0) {
            return errors.Error.InvalidRequest;
        }

        var previous_top_km: f64 = 0.0;
        for (self.subcolumns, 0..) |subcolumn, index| {
            try subcolumn.validate();
            if (subcolumn.index_1based != index + 1) return errors.Error.InvalidRequest;
            if (index != 0 and subcolumn.bottom_altitude_km < previous_top_km) {
                return errors.Error.InvalidRequest;
            }
            previous_top_km = subcolumn.top_altitude_km;
        }
    }

    /// Purpose:
    ///   Resolve the partition label for a layer midpoint.
    pub fn labelForAltitude(self: SubcolumnLayout, altitude_km: f64) PartitionLabel {
        if (!self.enabled or self.subcolumns.len == 0) return .unspecified;
        for (self.subcolumns) |subcolumn| {
            if (altitude_km >= subcolumn.bottom_altitude_km and altitude_km <= subcolumn.top_altitude_km) {
                return subcolumn.label;
            }
        }
        return if (altitude_km < self.subcolumns[0].bottom_altitude_km)
            self.subcolumns[0].label
        else
            self.subcolumns[self.subcolumns.len - 1].label;
    }

    /// Purpose:
    ///   Release any allocator-owned subcolumn storage.
    pub fn deinitOwned(self: *SubcolumnLayout, allocator: Allocator) void {
        if (self.owns_subcolumns and self.subcolumns.len != 0) {
            for (@constCast(self.subcolumns)) |*subcolumn| subcolumn.deinitOwned(allocator);
            allocator.free(self.subcolumns);
        }
        self.* = .{};
    }
};

/// Purpose:
///   Describe the vertical atmosphere configuration for one scene.
pub const Atmosphere = struct {
    layer_count: u32 = 0,
    sublayer_divisions: u8 = 3,
    has_clouds: bool = false,
    has_aerosols: bool = false,
    profile_source: Binding = .none,
    // UNITS:
    //   Surface pressure is expressed in hectopascals to match the canonical
    //   configuration surface and common meteorological products.
    surface_pressure_hpa: f64 = 0.0,
    interval_grid: IntervalGrid = .{},
    subcolumns: SubcolumnLayout = .{},

    /// Purpose:
    ///   Report the active preparation-layer count.
    pub fn preparedLayerCount(self: Atmosphere) u32 {
        if (self.interval_grid.enabled()) return self.interval_grid.intervalCount();
        return self.layer_count;
    }

    /// Purpose:
    ///   Ensure the atmosphere configuration is internally consistent.
    pub fn validate(self: Atmosphere) errors.Error!void {
        try self.profile_source.validate();
        try self.interval_grid.validate(self.sublayer_divisions);
        try self.subcolumns.validate();

        if (self.preparedLayerCount() == 0 and
            (self.has_clouds or self.has_aerosols or self.profile_source.enabled() or self.surface_pressure_hpa != 0.0))
        {
            // INVARIANT:
            //   Any request for profiles or particulate structure implies a concrete
            //   atmosphere allocation, whether the scene uses legacy altitude layers or
            //   explicit pressure-bounded intervals.
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

    /// Purpose:
    ///   Release any allocator-owned interval or subcolumn state.
    pub fn deinitOwned(self: *Atmosphere, allocator: Allocator) void {
        self.interval_grid.deinitOwned(allocator);
        self.subcolumns.deinitOwned(allocator);
    }
};

test "atmosphere validates profile source and positive surface pressure" {
    try (Atmosphere{
        .layer_count = 48,
        .profile_source = .{ .asset = .{ .name = "us_standard_profile" } },
        .surface_pressure_hpa = 1013.0,
    }).validate();

    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{ .surface_pressure_hpa = -1.0 }).validate(),
    );
    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{
            .has_aerosols = true,
            .layer_count = 0,
        }).validate(),
    );
    try (Atmosphere{
        .layer_count = 48,
        .sublayer_divisions = 12,
    }).validate();
}

test "atmosphere accepts explicit pressure-bounded intervals and fit interval state" {
    try (Atmosphere{
        .layer_count = 2,
        .interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = 2,
            .intervals = &.{
                VerticalInterval{
                    .index_1based = 1,
                    .top_pressure_hpa = 120.0,
                    .bottom_pressure_hpa = 450.0,
                    .top_altitude_km = 12.0,
                    .bottom_altitude_km = 6.5,
                    .altitude_divisions = 2,
                },
                VerticalInterval{
                    .index_1based = 2,
                    .top_pressure_hpa = 450.0,
                    .bottom_pressure_hpa = 1013.0,
                    .top_altitude_km = 6.5,
                    .bottom_altitude_km = 0.0,
                    .altitude_divisions = 4,
                },
            },
        },
    }).validate();
}

test "atmosphere rejects malformed interval and subcolumn metadata" {
    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{
            .interval_grid = .{
                .semantics = .explicit_pressure_bounds,
                .fit_interval_index_1based = 2,
                .intervals = &.{
                    VerticalInterval{
                        .index_1based = 1,
                        .top_pressure_hpa = 700.0,
                        .bottom_pressure_hpa = 500.0,
                        .altitude_divisions = 2,
                    },
                },
            },
        }).validate(),
    );
    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{
            .layer_count = 1,
            .subcolumns = .{
                .enabled = true,
                .subcolumns = &.{
                    Subcolumn{
                        .index_1based = 1,
                        .label = .boundary_layer,
                        .bottom_altitude_km = 2.0,
                        .top_altitude_km = 1.0,
                    },
                },
            },
        }).validate(),
    );
}

fn cloneFractionControlWithAllocator(allocator: Allocator) !void {
    const control: FractionControl = .{
        .enabled = true,
        .target = .aerosol,
        .kind = .wavel_dependent,
        .threshold_cloud_fraction = 0.25,
        .threshold_variance = 0.1,
        .wavelengths_nm = &.{ 760.0, 761.0 },
        .values = &.{ 0.20, 0.60 },
        .apriori_values = &.{ 0.25, 0.55 },
        .variance_values = &.{ 0.01, 0.04 },
    };

    var cloned = try control.clone(allocator);
    defer cloned.deinitOwned(allocator);

    try std.testing.expect(cloned.owns_arrays);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), cloned.valueAtWavelength(760.5), 1.0e-12);
}

test "fraction control clone cleans up across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneFractionControlWithAllocator,
        .{},
    );
}
