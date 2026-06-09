const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const AtmosphereModel = @import("Atmosphere.zig");
pub const Placement = AtmosphereModel.IntervalPlacement;
pub const FractionControl = AtmosphereModel.FractionControl;
pub const max_profile_layers: usize = 256;

// Aerosol.zig ------------------------------------------------------------------------------------------------|
// Public aerosol input rows used before optical preparation distributes particles over support sublayers.     |
//                                                                                                             |
// called from                                                                                                 |
//   Scene.validate checks scalar aerosol controls as part of public input validation.                         |
//   input/o2a_reference/root.zig exposes ProfileLayer rows for O2 A reference and benchmark cases.            |
//   state_build/context.zig validates explicit profile rows and rejects mixing them with scalar fraction      |
//   controls.                                                                                                 |
//   layer_accumulation.zig either maps scalar Aerosol placement/fraction controls through particle_profiles   |
//   or spreads explicit ProfileLayer rows across prepared sublayers by pressure overlap.                      |
//   forward_layers and state_optical_depth later read the prepared aerosol optical-depth and phase values,    |
//   including Jacobian attachment when aerosol optical depth is requested.                                    |
//                                                                                                             |
// main paths                                                                                                  |
//   ProfileLayer.validate checks explicit pressure-layer optical properties and spectral scaling inputs.      |
//   Profile.validate checks a borrowed row slice supplied by a loader or caller.                              |
//   Aerosol.validate checks scalar defaults, requires placement when scalar aerosol is enabled/non-zero, and  |
//   ensures the nested FractionControl targets aerosol when active.                                           |
//   deinitOwned only releases nested fraction arrays; explicit profile rows stay borrowed.                    |
//                                                                                                             |
// units                                                                                                       |
//   Optical depth is dimensionless. Reference wavelength is stored in nanometers. Pressure bounds are hPa.    |
// ------------------------------------------------------------------------------------------------------------|

// ProfileLayer -----------------------------------------------------------------------------------------------|
// One explicit aerosol profile layer.                                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] top_pressure_hpa       : f64                                                                       |
// [ 8..15] bottom_pressure_hpa    : f64                                                                       |
// [16..23] optical_depth          : f64                                                                       |
// [24..31] single_scatter_albedo  : f64                                                                       |
// [32..39] asymmetry_factor       : f64                                                                       |
// [40..47] angstrom_exponent      : f64                                                                       |
// [48..55] reference_wavelength_nm: f64                                                                       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 56 B (0.055 KiB); total = per instance * live profile-layer count                 |
pub const ProfileLayer = struct {
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    optical_depth: f64,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,

    pub fn validate(self: ProfileLayer) errors.Error!void {
        if (!std.math.isFinite(self.top_pressure_hpa) or
            !std.math.isFinite(self.bottom_pressure_hpa) or
            !(self.top_pressure_hpa < self.bottom_pressure_hpa) or
            self.top_pressure_hpa < 0.0)
        {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.optical_depth) or self.optical_depth < 0.0) {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.single_scatter_albedo) or
            self.single_scatter_albedo < 0.0 or
            self.single_scatter_albedo > 1.0)
        {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.asymmetry_factor) or
            self.asymmetry_factor < -1.0 or
            self.asymmetry_factor > 1.0)
        {
            return errors.Error.InvalidRequest;
        }

        if (!std.math.isFinite(self.angstrom_exponent) or
            !std.math.isFinite(self.reference_wavelength_nm) or
            self.reference_wavelength_nm <= 0.0)
        {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

// Profile ----------------------------------------------------------------------------------------------------|
// Borrowed slice header for explicit aerosol profile layers.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] layers : []const ProfileLayer                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   layers points at out-of-line profile rows; this header does not own them.                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes borrowed profile rows                       |
pub const Profile = struct {
    layers: []const ProfileLayer = &.{},

    pub fn enabled(self: Profile) bool {
        return self.layers.len != 0;
    }

    pub fn validate(self: Profile) errors.Error!void {
        for (self.layers) |layer| try layer.validate();
    }
};
// ------------------------------------------------------------------------------------------------------------|

// Aerosol ----------------------------------------------------------------------------------------------------|
// Public aerosol scalar controls plus nested interval-placement and fraction controls.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 168 B (0.164 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] optical_depth           : f64                                                                    |
// [  8.. 15] single_scatter_albedo   : f64                                                                    |
// [ 16.. 23] asymmetry_factor        : f64                                                                    |
// [ 24.. 31] angstrom_exponent       : f64                                                                    |
// [ 32.. 39] reference_wavelength_nm : f64                                                                    |
// [ 40.. 79] placement               : IntervalPlacement                                                      |
// [ 80..159] fraction                : FractionControl                                                        |
// [160..160] enabled                 : bool                                                                   |
// [161..167] trailing padding        : 7 B                                                                    |
//                                                                                                             |
// referenced storage                                                                                          |
//   fraction may point at out-of-line arrays owned by the nested FractionControl.                             |
//                                                                                                             |
// unused bits: 56 top-level padding + 7 bool-storage slack = 63 bits                                          |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 168 B (0.164 KiB); total also includes nested owned arrays                        |
pub const Aerosol = struct {
    enabled: bool = false,
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
// ------------------------------------------------------------------------------------------------------------|
