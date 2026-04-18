//! Purpose:
//!   Own the retained ingest-side solar-spectrum fallback rules.
//!
//! Physics:
//!   Converts measured irradiance samples into an operational solar spectrum
//!   only when legacy ingest metadata omits an explicit operational spectrum.
//!
//! Vendor:
//!   `spectral ASCII operational solar compatibility`
//!
//! Design:
//!   Keep fallback synthesis separate from the typed runtime artifact builder
//!   so the normal metadata path stays explicit.
//!
//! Invariants:
//!   Metadata-provided operational solar spectra always take precedence over
//!   synthesized irradiance-backed fallbacks.
//!
//! Validation:
//!   Spectral ASCII runtime tests cover metadata-driven and synthesized-solar
//!   operational support materialization.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;

pub fn fallbackSolarFromMeasuredIrradiance(measured_irradiance: anytype) OperationalSolarSpectrum {
    if (measured_irradiance) |irradiance| {
        return .{
            .wavelengths_nm = irradiance.wavelengths_nm,
            .irradiance = irradiance.values,
        };
    }
    return .{};
}

pub fn resolveOperationalSolarSpectrum(
    allocator: Allocator,
    metadata_solar: OperationalSolarSpectrum,
    fallback_solar: *const OperationalSolarSpectrum,
) !OperationalSolarSpectrum {
    if (metadata_solar.enabled()) return metadata_solar.clone(allocator);
    return fallback_solar.clone(allocator);
}
