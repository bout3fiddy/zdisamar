//! Purpose:
//!   Define named spectral bands and exclusion windows used to subset measurements and
//!   reference assets.
//!
//! Physics:
//!   Bands describe wavelength intervals and masked subwindows on the public nanometer
//!   grid before optics preparation converts them into kernel-specific selectors.
//!
//! Vendor:
//!   `spectral band selection stage`
//!
//! Design:
//!   The Zig model treats bands as explicit typed values with owned exclusion windows
//!   rather than scattering ad hoc band metadata across adapters and measurement setup.
//!
//! Invariants:
//!   Band ids are unique within a set, spectral bounds are finite and increasing, and
//!   excluded windows remain ordered within the parent band interval.
//!
//! Validation:
//!   Unit tests below cover duplicate-band detection and invalid exclusion windows.
const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");

/// Purpose:
///   Describe one excluded wavelength interval inside a broader band.
pub const SpectralWindow = struct {
    start_nm: f64 = 0.0,
    end_nm: f64 = 0.0,

    /// Purpose:
    ///   Ensure the exclusion window spans a valid wavelength interval.
    pub fn validate(self: SpectralWindow) errors.Error!void {
        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;
    }
};

/// Purpose:
///   Describe a named wavelength band and any subwindows to exclude from it.
pub const SpectralBand = struct {
    id: []const u8 = "",
    // UNITS:
    //   Band bounds and step are expressed in nanometers on the canonical spectral grid.
    start_nm: f64 = 0.0,
    end_nm: f64 = 0.0,
    step_nm: f64 = 0.0,
    exclude: []const SpectralWindow = &[_]SpectralWindow{},

    /// Purpose:
    ///   Ensure the band id, bounds, step, and excluded windows are consistent.
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

    /// Purpose:
    ///   Duplicate the excluded-window list into allocator-owned storage.
    pub fn clone(self: SpectralBand, allocator: Allocator) !SpectralBand {
        return .{
            .id = self.id,
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
            .step_nm = self.step_nm,
            .exclude = try allocator.dupe(SpectralWindow, self.exclude),
        };
    }

    /// Purpose:
    ///   Release allocator-owned exclusion windows.
    pub fn deinitOwned(self: *SpectralBand, allocator: Allocator) void {
        if (self.exclude.len != 0) allocator.free(self.exclude);
        self.* = .{};
    }
};

/// Purpose:
///   Hold a validated set of uniquely named spectral bands.
pub const SpectralBandSet = struct {
    items: []const SpectralBand = &[_]SpectralBand{},

    /// Purpose:
    ///   Ensure each band is valid and no band id is repeated.
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

    /// Purpose:
    ///   Duplicate the full band set into allocator-owned storage.
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

    /// Purpose:
    ///   Release allocator-owned band and exclusion-window storage.
    pub fn deinitOwned(self: *SpectralBandSet, allocator: Allocator) void {
        for (self.items) |band| {
            var owned_band = band;
            owned_band.deinitOwned(allocator);
        }
        if (self.items.len != 0) allocator.free(self.items);
        self.* = .{};
    }
};

test "spectral band set rejects duplicate ids and invalid exclusion windows" {
    const valid: SpectralBandSet = .{
        .items = &[_]SpectralBand{
            .{
                .id = "o2a",
                .start_nm = 758.0,
                .end_nm = 771.0,
                .step_nm = 0.01,
                .exclude = &[_]SpectralWindow{
                    .{ .start_nm = 759.35, .end_nm = 759.55 },
                    .{ .start_nm = 770.50, .end_nm = 770.80 },
                },
            },
        },
    };
    try valid.validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (SpectralBandSet{
            .items = &[_]SpectralBand{
                .{ .id = "o2a", .start_nm = 758.0, .end_nm = 771.0, .step_nm = 0.01 },
                .{ .id = "o2a", .start_nm = 405.0, .end_nm = 465.0, .step_nm = 0.1 },
            },
        }).validate(),
    );

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (SpectralBand{
            .id = "o2a",
            .start_nm = 758.0,
            .end_nm = 771.0,
            .step_nm = 0.01,
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 759.8, .end_nm = 760.0 },
                .{ .start_nm = 759.9, .end_nm = 760.1 },
            },
        }).validate(),
    );
}
