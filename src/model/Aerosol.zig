const std = @import("std");
const errors = @import("../core/errors.zig");

pub const Aerosol = struct {
    id: []const u8 = "",
    model: []const u8 = "",
    provider: []const u8 = "",
    enabled: bool = false,
    optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
    layer_center_km: f64 = 2.5,
    layer_width_km: f64 = 3.0,

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
        if (self.layer_center_km < 0.0 or self.layer_width_km <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};
