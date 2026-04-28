const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const AtmosphereModel = @import("Atmosphere.zig");
const particle_compat = @import("../forward_model/optical_properties/particle_support.zig");
pub const CloudType = @import("../o2a/support/enums.zig").CloudType;
pub const Placement = AtmosphereModel.IntervalPlacement;
pub const FractionControl = AtmosphereModel.FractionControl;

pub const Cloud = struct {
    id: []const u8 = "",
    cloud_type: CloudType = .none,
    provider: []const u8 = "",
    enabled: bool = false,
    // UNITS:
    //   Optical thickness is dimensionless, the Angstrom reference wavelength is in
    //   nanometers, and altitude/thickness are in kilometers.
    optical_thickness: f64 = 0.0,
    single_scatter_albedo: f64 = 0.999,
    asymmetry_factor: f64 = 0.85,
    angstrom_exponent: f64 = 0.3,
    reference_wavelength_nm: f64 = 550.0,
    top_altitude_km: f64 = 6.0,
    thickness_km: f64 = 1.5,
    placement: Placement = .{},
    fraction: FractionControl = .{},

    pub fn resolvedPlacement(self: Cloud) Placement {
        return particle_compat.cloudPlacement(self);
    }

    pub fn validate(self: Cloud) errors.Error!void {
        if (self.optical_thickness < 0.0) {
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
            if (self.top_altitude_km < 0.0 or self.thickness_km <= 0.0) {
                return errors.Error.InvalidRequest;
            }
        } else {
            try self.placement.validate();
        }
        try self.fraction.validate();
        if (self.fraction.enabled and self.fraction.target != .cloud) return errors.Error.InvalidRequest;
    }

    pub fn deinitOwned(self: *Cloud, allocator: Allocator) void {
        self.fraction.deinitOwned(allocator);
    }
};
