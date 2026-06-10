const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

// Bands.zig --------------------------------------------------------------------------------------------------|
// Spectral band and exclusion-window input rows used to constrain scene wavelength ranges.                    |
//                                                                                                             |
// used by                                                                                                     |
//   Scene.validate checks band lists and matches explicit operational support counts                          |
//   O2 A reference scene builders carry one primary band beside operational support data                      |
//   validation/tests exercise exclusion ordering before product wavelength plans are built                    |
//                                                                                                             |
// main paths                                                                                                  |
//   SpectralWindow.validate checks one wavelength interval                                                    |
//   SpectralBand.validate checks band bounds, positive step, and ordered in-band exclusions                   |
//   SpectralBandSet.validate rejects duplicate ids; clone/deinitOwned manage band and exclusion storage       |
//                                                                                                             |
// boundary                                                                                                    |
//   These rows describe requested spectral ranges only. Product wavelength grids are built later from Scene   |
//   spectral_grid and observation_model controls. Band exclusions are validated metadata here, not the        |
//   measurement mask consumed by Measurement.zig.                                                             |
//                                                                                                             |
// memory                                                                                                      |
//   SpectralBandSet is a slice header. Cloned sets own band rows; cloned bands own exclusion rows and borrow  |
//   their id string from the parsed or caller-owned input model.                                              |
// ------------------------------------------------------------------------------------------------------------|

// SpectralWindow ---------------------------------------------------------------------------------------------|
// One wavelength interval in nanometers.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] start_nm : f64                                                                                      |
// [8..15] end_nm   : f64                                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total = per instance * live window count                        |
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
// ------------------------------------------------------------------------------------------------------------|

// SpectralBand -----------------------------------------------------------------------------------------------|
// One named spectral band plus optional exclusion windows.                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] id       : []const u8                                                                              |
// [16..23] start_nm : f64                                                                                     |
// [24..31] end_nm   : f64                                                                                     |
// [32..39] step_nm  : f64                                                                                     |
// [40..55] exclude  : []const SpectralWindow                                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   id points at name bytes. exclude points at out-of-line SpectralWindow rows owned by cloned bands.         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 56 B (0.055 KiB); total also includes referenced id/exclusion storage             |
pub const SpectralBand = struct {
    id: []const u8 = "",
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
// ------------------------------------------------------------------------------------------------------------|

// SpectralBandSet --------------------------------------------------------------------------------------------|
// Owner/view header for a band list.                                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] items : []const SpectralBand                                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   items points at out-of-line SpectralBand rows owned by cloned band sets.                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced band rows                        |
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
// ------------------------------------------------------------------------------------------------------------|
