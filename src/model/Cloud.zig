const std = @import("std");
const errors = @import("../core/errors.zig");

pub const Cloud = struct {
    id: []const u8 = "",
    model: []const u8 = "",
    provider: []const u8 = "",
    enabled: bool = false,
    optical_thickness: f64 = 0.0,
    single_scatter_albedo: f64 = 0.999,
    asymmetry_factor: f64 = 0.85,
    angstrom_exponent: f64 = 0.3,
    reference_wavelength_nm: f64 = 550.0,
    top_altitude_km: f64 = 6.0,
    thickness_km: f64 = 1.5,

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
        if (self.top_altitude_km < 0.0 or self.thickness_km <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};
