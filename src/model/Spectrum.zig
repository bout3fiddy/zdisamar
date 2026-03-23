//! Purpose:
//!   Define the canonical spectral-grid descriptor shared by scene, instrument, and
//!   measurement configuration.
//!
//! Physics:
//!   The spectral grid names the wavelength interval and sample count used to discretize
//!   radiance, irradiance, or derived spectral products.
//!
//! Vendor:
//!   `spectral grid validation stage`
//!
//! Design:
//!   The Zig model keeps the spectral grid as an explicit validated value instead of
//!   inferring it from loosely coupled wavelength arrays at every boundary.
//!
//! Invariants:
//!   Spectral bounds are finite and strictly increasing and the grid carries at least one
//!   wavelength sample.
//!
//! Validation:
//!   Grid validation delegates to the shared wavelength-range validator in `core/units`.
const errors = @import("../core/errors.zig");
const units = @import("../core/units.zig");

/// Purpose:
///   Describe a wavelength grid by interval and sample count.
pub const SpectralGrid = struct {
    // UNITS:
    //   Public spectral bounds are stored in nanometers.
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,
    sample_count: u32 = 0,

    /// Purpose:
    ///   Ensure the spectral grid has a valid wavelength interval and sample count.
    pub fn validate(self: SpectralGrid) errors.Error!void {
        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;

        if (self.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }
    }
};
