//! Purpose:
//!   Define the canonical atmosphere configuration that sizes vertical structure and
//!   points to profile sources for the scene.
//!
//! Physics:
//!   This file captures the coarse atmospheric layering and optional cloud/aerosol
//!   presence flags that downstream transport and optics preparation expand into full
//!   thermodynamic and constituent profiles.
//!
//! Vendor:
//!   `atmosphere profile and layer-count setup`
//!
//! Design:
//!   The Zig model keeps atmospheric structure as an explicit typed record with validated
//!   bindings instead of relying on mutable config readers or implicit defaults.
//!
//! Invariants:
//!   Non-empty atmosphere-dependent settings require a positive layer count, sublayer
//!   divisions stay nonzero, and specified surface pressure is finite and positive.
//!
//! Validation:
//!   Unit tests below cover profile-source validation, positive pressure, and layer-count
//!   requirements for optional aerosol/cloud content.
const std = @import("std");
const errors = @import("../core/errors.zig");
const Binding = @import("Binding.zig").Binding;

/// Purpose:
///   Describe the vertical atmosphere configuration for one scene.
pub const Atmosphere = struct {
    layer_count: u32 = 0,
    sublayer_divisions: u8 = 3,
    has_clouds: bool = false,
    has_aerosols: bool = false,
    profile_source: Binding = .none,
    // UNITS:
    //   Surface pressure is expressed in hectopascals to match the canonical
    //   configuration surface and common meteorological products.
    surface_pressure_hpa: f64 = 0.0,

    /// Purpose:
    ///   Ensure the atmosphere configuration is internally consistent.
    pub fn validate(self: Atmosphere) errors.Error!void {
        try self.profile_source.validate();

        if (self.layer_count == 0 and
            (self.has_clouds or self.has_aerosols or self.profile_source.enabled() or self.surface_pressure_hpa != 0.0))
        {
            // INVARIANT:
            //   Any request for profiles or particulate structure implies a concrete
            //   layered atmosphere allocation.
            return errors.Error.InvalidRequest;
        }

        if (self.sublayer_divisions == 0) {
            return errors.Error.InvalidRequest;
        }
        if (self.surface_pressure_hpa != 0.0 and
            (!std.math.isFinite(self.surface_pressure_hpa) or self.surface_pressure_hpa <= 0.0))
        {
            return errors.Error.InvalidRequest;
        }
    }
};

test "atmosphere validates profile source and positive surface pressure" {
    try (Atmosphere{
        .layer_count = 48,
        .profile_source = .{ .asset = .{ .name = "us_standard_profile" } },
        .surface_pressure_hpa = 1013.0,
    }).validate();

    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{ .surface_pressure_hpa = -1.0 }).validate(),
    );
    try @import("std").testing.expectError(
        errors.Error.InvalidRequest,
        (Atmosphere{
            .has_aerosols = true,
            .layer_count = 0,
        }).validate(),
    );
    try (Atmosphere{
        .layer_count = 48,
        .sublayer_divisions = 12,
    }).validate();
}
