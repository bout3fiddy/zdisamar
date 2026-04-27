const std = @import("std");
const errors = @import("../../core/errors.zig");
const units = @import("../../core/units.zig");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const PartitionLabel = types.PartitionLabel;

pub const Subcolumn = struct {
    index_1based: u32 = 0,
    label: PartitionLabel = .unspecified,
    bottom_altitude_km: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    gaussian_nodes: []const f64 = &.{},
    gaussian_weights: []const f64 = &.{},
    owns_arrays: bool = false,

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

    pub fn deinitOwned(self: *SubcolumnLayout, allocator: Allocator) void {
        if (self.owns_subcolumns and self.subcolumns.len != 0) {
            for (@constCast(self.subcolumns)) |*subcolumn| subcolumn.deinitOwned(allocator);
            allocator.free(self.subcolumns);
        }
        self.* = .{};
    }
};
