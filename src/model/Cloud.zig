//! Purpose:
//!   Define the canonical cloud-layer parameters that transport preparation
//!   converts into particulate optical properties.
//!
//! Physics:
//!   Clouds are represented by optical thickness, single-scatter albedo,
//!   asymmetry, Angstrom scaling, and either explicit interval placement or a
//!   compatibility fallback top-altitude and thickness description.
//!
//! Vendor:
//!   `cloud optical property configuration stage`
//!
//! Design:
//!   The Zig model records cloud intent as a typed value so adapters can map
//!   vendor or mission-specific controls into one canonical representation
//!   before optics kernels run.
//!
//! Invariants:
//!   Optical thickness stays non-negative, single-scatter albedo stays within
//!   `[0, 1]`, asymmetry stays within `[-1, 1]`, and explicit placement or
//!   fraction metadata remains physically meaningful.
//!
//! Validation:
//!   Validation is enforced locally before cloud settings are handed to optics
//!   preparation or provider layers.
const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const AtmosphereModel = @import("Atmosphere.zig");
const document_fields = @import("../adapters/canonical_config/document_fields.zig");

pub const CloudType = document_fields.CloudType;
pub const Placement = AtmosphereModel.IntervalPlacement;
pub const FractionControl = AtmosphereModel.FractionControl;

/// Purpose:
///   Describe one cloud layer in canonical scene coordinates.
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

    /// Purpose:
    ///   Resolve the active cloud placement, using the legacy altitude geometry
    ///   only when explicit interval bounds are absent.
    pub fn resolvedPlacement(self: Cloud) Placement {
        if (self.placement.enabled()) return self.placement;
        return .{
            .semantics = .altitude_center_width_approximation,
            .top_altitude_km = self.top_altitude_km,
            .bottom_altitude_km = @max(self.top_altitude_km - self.thickness_km, 0.0),
        };
    }

    /// Purpose:
    ///   Ensure the cloud optical and geometric parameters remain physically meaningful.
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

    /// Purpose:
    ///   Release any allocator-owned fraction arrays.
    pub fn deinitOwned(self: *Cloud, allocator: Allocator) void {
        self.fraction.deinitOwned(allocator);
    }
};
