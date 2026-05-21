const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const AtmosphereModel = @import("Atmosphere.zig");
pub const Placement = AtmosphereModel.IntervalPlacement;
pub const FractionControl = AtmosphereModel.FractionControl;

// layout(64-bit):
//   size: 160 B, align: 8 B
//   field storage: 158 B across 8 fields; largest: fraction=80 B, placement=40 B; padding: 2 B (16 bits)
//   unused bits: 16 padding + 7 bool-storage slack = 23 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 160 B (0.156 KiB); total = per instance * live instance count
pub const Aerosol = struct {
    enabled: bool = false,
    // UNITS:
    //   Optical depth is dimensionless and the Angstrom reference wavelength is
    //   in nanometers.
    optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
    placement: Placement = .{},
    fraction: FractionControl = .{},

    pub fn validate(self: Aerosol) errors.Error!void {
        if (self.optical_depth < 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.single_scatter_albedo < 0.0 or self.single_scatter_albedo > 1.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.asymmetry_factor < -1.0 or self.asymmetry_factor > 1.0) {
            return errors.Error.InvalidRequest;
        }
        if (!std.math.isFinite(self.angstrom_exponent) or self.reference_wavelength_nm <= 0.0) {
            return errors.Error.InvalidRequest;
        }
        if (self.enabled or self.optical_depth > 0.0) {
            if (!self.placement.enabled()) return errors.Error.InvalidRequest;
            try self.placement.validate();
        } else if (self.placement.enabled()) {
            try self.placement.validate();
        }
        try self.fraction.validate();
        if (self.fraction.enabled and self.fraction.target != .aerosol) return errors.Error.InvalidRequest;
    }

    pub fn deinitOwned(self: *Aerosol, allocator: Allocator) void {
        self.fraction.deinitOwned(allocator);
    }
};
