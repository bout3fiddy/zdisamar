const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const AtmosphereModel = @import("Atmosphere.zig");
const particle_compat = @import("../forward_model/optical_properties/particle_support.zig");
pub const AerosolType = @import("atmospheric_types.zig").AerosolType;
pub const Placement = AtmosphereModel.IntervalPlacement;
pub const FractionControl = AtmosphereModel.FractionControl;

// layout(64-bit):
//   size: 224 B, align: 8 B
//   field storage: 218 B across 13 fields; largest: fraction=88 B, placement=40 B, id=16 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 7 bool-storage slack = 55 bits
//   out-of-line: id, provider carry references/descriptors; referenced storage is not included in size
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 224 B (0.219 KiB); total also includes referenced storage above
pub const Aerosol = struct {
    id: []const u8 = "",
    aerosol_type: AerosolType = .none,
    provider: []const u8 = "",
    enabled: bool = false,
    // UNITS:
    //   Optical depth is dimensionless, the Angstrom reference wavelength is in
    //   nanometers, and any altitude geometry is in kilometers.
    optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
    layer_center_km: f64 = 2.5,
    layer_width_km: f64 = 3.0,
    placement: Placement = .{},
    fraction: FractionControl = .{},

    pub fn resolvedPlacement(self: Aerosol) Placement {
        return particle_compat.aerosolPlacement(self);
    }

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
        if (!self.placement.enabled()) {
            if (self.layer_center_km < 0.0 or self.layer_width_km <= 0.0) {
                return errors.Error.InvalidRequest;
            }
        } else {
            try self.placement.validate();
        }
        try self.fraction.validate();
        if (self.fraction.enabled and self.fraction.target != .aerosol) return errors.Error.InvalidRequest;
    }

    pub fn deinitOwned(self: *Aerosol, allocator: Allocator) void {
        self.fraction.deinitOwned(allocator);
    }
};
