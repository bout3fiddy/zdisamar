//! Purpose:
//!   Define the canonical aerosol-layer parameters that optics preparation maps into
//!   particulate extinction and phase behavior.
//!
//! Physics:
//!   Aerosols are represented by optical depth, single-scatter albedo, asymmetry,
//!   Angstrom scaling, and a vertically localized layer profile.
//!
//! Vendor:
//!   `aerosol optical property configuration stage`
//!
//! Design:
//!   The Zig model records aerosol intent as a typed value so adapters and runtime
//!   providers can agree on one canonical representation before kernel evaluation.
//!
//! Invariants:
//!   Optical depth stays non-negative, single-scatter albedo stays within `[0, 1]`,
//!   asymmetry stays within `[-1, 1]`, and the geometric extent remains positive.
//!
//! Validation:
//!   Validation is enforced locally before aerosol settings are handed to optics
//!   preparation or provider layers.
const std = @import("std");
const errors = @import("../core/errors.zig");
const document_fields = @import("../adapters/canonical_config/document_fields.zig");

pub const AerosolType = document_fields.AerosolType;

/// Purpose:
///   Describe one aerosol layer in canonical scene coordinates.
pub const Aerosol = struct {
    id: []const u8 = "",
    aerosol_type: AerosolType = .none,
    provider: []const u8 = "",
    enabled: bool = false,
    // UNITS:
    //   Optical depth is dimensionless, the Angstrom reference wavelength is in
    //   nanometers, and layer geometry is in kilometers.
    optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
    layer_center_km: f64 = 2.5,
    layer_width_km: f64 = 3.0,

    /// Purpose:
    ///   Ensure the aerosol optical and geometric parameters remain physically meaningful.
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
