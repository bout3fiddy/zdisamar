const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: start_nm=8 B, end_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const SpectralWindow = struct {
    start_nm: f64 = 0.0,
    end_nm: f64 = 0.0,

    pub fn validate(self: SpectralWindow) errors.Error!void {
        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;
    }
};

// layout(64-bit):
//   size: 56 B, align: 8 B
//   field storage: 56 B across 5 fields; largest: id=16 B, exclude=16 B, start_nm=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, exclude carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 56 B (0.055 KiB); total also includes referenced storage above
pub const SpectralBand = struct {
    id: []const u8 = "",
    // UNITS:
    //   Band bounds and step are expressed in nanometers on the canonical spectral grid.
    start_nm: f64 = 0.0,
    end_nm: f64 = 0.0,
    step_nm: f64 = 0.0,
    exclude: []const SpectralWindow = &[_]SpectralWindow{},

    pub fn validate(self: SpectralBand) errors.Error!void {
        if (self.id.len == 0 or !std.math.isFinite(self.step_nm) or self.step_nm <= 0.0) {
            return errors.Error.InvalidRequest;
        }

        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;

        var previous_end_nm: f64 = self.start_nm;
        for (self.exclude) |window| {
            try window.validate();
            if (window.start_nm < self.start_nm or
                window.end_nm > self.end_nm or
                window.start_nm < previous_end_nm)
            {
                return errors.Error.InvalidRequest;
            }
            previous_end_nm = window.end_nm;
        }
    }

    pub fn clone(self: SpectralBand, allocator: Allocator) !SpectralBand {
        return .{
            .id = self.id,
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
            .step_nm = self.step_nm,
            .exclude = try allocator.dupe(SpectralWindow, self.exclude),
        };
    }

    pub fn deinitOwned(self: *SpectralBand, allocator: Allocator) void {
        if (self.exclude.len != 0) allocator.free(self.exclude);
        self.* = .{};
    }
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: items=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: items carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
pub const SpectralBandSet = struct {
    items: []const SpectralBand = &[_]SpectralBand{},

    pub fn validate(self: SpectralBandSet) errors.Error!void {
        for (self.items, 0..) |band, index| {
            try band.validate();
            for (self.items[index + 1 ..]) |other| {
                if (std.mem.eql(u8, band.id, other.id)) {
                    return errors.Error.InvalidRequest;
                }
            }
        }
    }

    pub fn clone(self: SpectralBandSet, allocator: Allocator) !SpectralBandSet {
        var items = try allocator.alloc(SpectralBand, self.items.len);
        errdefer allocator.free(items);

        for (self.items, 0..) |band, index| {
            items[index] = try band.clone(allocator);
            errdefer {
                var cleanup_index = index + 1;
                while (cleanup_index > 0) {
                    cleanup_index -= 1;
                    items[cleanup_index].deinitOwned(allocator);
                }
            }
        }

        return .{ .items = items };
    }

    pub fn deinitOwned(self: *SpectralBandSet, allocator: Allocator) void {
        for (self.items) |band| {
            var owned_band = band;
            owned_band.deinitOwned(allocator);
        }
        if (self.items.len != 0) allocator.free(self.items);
        self.* = .{};
    }
};
