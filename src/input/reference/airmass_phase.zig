const std = @import("std");
const Allocator = std.mem.Allocator;

// airmass_phase.zig ------------------------------------------------------------------------------------------|
// Reference airmass and phase-support helpers used while preparing O2 A optical state.                        |
//                                                                                                             |
// called by                                                                                                   |
//   bundled/assets.zig and o2a_reference/run.zig load AirmassFactorLut rows from reference assets.            |
//   absorbers.zig resolves one airmass factor for the scene geometry before spectroscopy state is prepared.   |
//   prepared_state.zig/finalize.zig carry PhaseSupportKind for downstream aerosol/Rayleigh phase handling.    |
//                                                                                                             |
// main paths                                                                                                  |
//   nearest                         -> scene angles -> nearest reference airmass support row                  |
//   providesSupportOnly             -> marker for reference assets that are support data, not physics tables  |
//   spectralProfileFromOpticalDepth -> optical-depth proxy samples -> normalized airmass-shaped profile       |
//                                                                                                             |
// hot path                                                                                                    |
//   nearest runs once during optical-state preparation. spectralProfileFromOpticalDepth writes one f64 per    |
//   wavelength when reference support materializes a profile from proxy optical-depth samples.                |
//                                                                                                             |
// ownership                                                                                                   |
//   AirmassFactorLut owns the row storage returned by the reference-data loader and releases it in deinit.    |
// ------------------------------------------------------------------------------------------------------------|

pub const PhaseSupportKind = enum {
    none,
    analytic_hg,
};

// AirmassFactorPoint -----------------------------------------------------------------------------------------|
// One angular support row for nearest-neighbor scene lookup.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_zenith_deg       : f64                                                                       |
// [ 8..15] view_zenith_deg        : f64                                                                       |
// [16..23] relative_azimuth_deg   : f64                                                                       |
// [24..31] airmass_factor         : f64                                                                       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live row count                           |
pub const AirmassFactorPoint = struct {
    solar_zenith_deg: f64,
    view_zenith_deg: f64,
    relative_azimuth_deg: f64,
    airmass_factor: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// AirmassFactorLut -------------------------------------------------------------------------------------------|
// Owner header for airmass support rows.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] points : []AirmassFactorPoint                                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   points stores out-of-line AirmassFactorPoint rows and is released by deinit.                              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes owned point rows                            |
pub const AirmassFactorLut = struct {
    points: []AirmassFactorPoint,

    pub fn deinit(self: *AirmassFactorLut, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn nearest(
        self: AirmassFactorLut,
        solar_zenith_deg: f64,
        view_zenith_deg: f64,
        relative_azimuth_deg: f64,
    ) f64 {
        // AirmassFactorLut.nearest ---------------------------------------------------------------------------|
        // Resolve the nearest angular support row for one scene geometry.                                     |
        //                                                                                                     |
        // hot path                                                                                            |
        //   repeated : once while absorber preparation resolves the spectroscopy-state airmass support        |
        //   work     : linear scan over LUT points                                                            |
        //   memory   : reads each compact 32-byte point once                                                  |
        // ----------------------------------------------------------------------------------------------------|

        if (self.points.len == 0) return 1.0;

        var best_distance = std.math.inf(f64);
        var best_value = self.points[0].airmass_factor;
        for (self.points) |point| {
            const delta_sza = point.solar_zenith_deg - solar_zenith_deg;
            const delta_vza = point.view_zenith_deg - view_zenith_deg;
            const delta_raa = point.relative_azimuth_deg - relative_azimuth_deg;
            const distance = delta_sza * delta_sza + delta_vza * delta_vza + delta_raa * delta_raa;
            if (distance < best_distance) {
                best_distance = distance;
                best_value = point.airmass_factor;
            }
        }
        return best_value;
    }

    pub fn providesSupportOnly(_: AirmassFactorLut) bool {
        // AirmassFactorLut.providesSupportOnly ---------------------------------------------------------------|
        // Identify this LUT as support metadata. It selects preparation context but does not directly sample  |
        // a wavelength-dependent absorption cross section.                                                    |
        // ----------------------------------------------------------------------------------------------------|

        return true;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn spectralProfileFromOpticalDepth(
    allocator: Allocator,
    wavelengths_nm: []const f64,
    mean_airmass_factor: f64,
    optical_depth_proxy: []const f64,
) ![]f64 {
    // spectralProfileFromOpticalDepth ------------------------------------------------------------------------|
    // Build an airmass-shaped spectral profile from optical-depth proxy samples.                              |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : when reference support materializes band profiles                                          |
    //   work     : normalize proxy samples, apply a weak wavelength tilt, then restore the requested mean     |
    //   memory   : writes one f64 profile sample per input wavelength                                         |
    // --------------------------------------------------------------------------------------------------------|

    if (wavelengths_nm.len != optical_depth_proxy.len) return error.ShapeMismatch;

    const profile = try allocator.alloc(f64, wavelengths_nm.len);
    errdefer allocator.free(profile);
    if (wavelengths_nm.len == 0) return profile;

    var proxy_sum: f64 = 0.0;
    for (optical_depth_proxy) |value| proxy_sum += @max(value, 0.0);
    const proxy_mean =
        proxy_sum / @max(@as(f64, @floatFromInt(optical_depth_proxy.len)), 1.0e-9);
    const safe_mean_airmass = if (std.math.isFinite(mean_airmass_factor) and mean_airmass_factor > 0.0)
        mean_airmass_factor
    else
        1.0;
    const midpoint_nm = 0.5 * (wavelengths_nm[0] + wavelengths_nm[wavelengths_nm.len - 1]);
    const half_span_nm = @max(0.5 * (wavelengths_nm[wavelengths_nm.len - 1] - wavelengths_nm[0]), 1.0e-9);

    for (profile, wavelengths_nm, optical_depth_proxy) |*slot, wavelength_nm, proxy| {
        const normalized_proxy = if (proxy_mean > 0.0) @max(proxy, 0.0) / proxy_mean else 1.0;
        const coordinate = (wavelength_nm - midpoint_nm) / half_span_nm;

        // Keep a weak wavelength tilt so the profile is not numerically flat before the mean is restored.
        const geometric_tilt = 1.0 + 0.05 * coordinate;
        slot.* = safe_mean_airmass * normalized_proxy * geometric_tilt;
    }

    var current_mean: f64 = 0.0;
    for (profile) |value| current_mean += value;
    current_mean /= @max(@as(f64, @floatFromInt(profile.len)), 1.0e-9);
    const renormalization = safe_mean_airmass / @max(current_mean, 1.0e-9);
    for (profile) |*value| value.* *= renormalization;
    return profile;
}
