const std = @import("std");
const Allocator = std.mem.Allocator;

// airmass_phase.zig ------------------------------------------------------------------------------------------|
// Reference support rows for geometry-dependent airmass factors and phase-support markers. These are setup    |
// helpers for O2 A preparation: they shape inputs before optical-state rows are built, but they do not sample |
// absorption cross sections or run RTM transport.                                                             |
//                                                                                                             |
// route                                                                                                       |
//   bundled/assets.zig loads the bundled AirmassFactorLut. o2a_reference/run.zig can load the same shape from |
//   an explicit fixed asset, with fixed_asset_cache owning cache reuse.                                       |
//   bundled/load.zig carries the LUT beside spectroscopy and CIA assets before buildOptics prepares the scene.|
//   optical-property preparation resolves one nearest airmass factor for the scene geometry, then stores the  |
//   resulting scalar/profile data in prepared state.                                                          |
//   finalize.zig chooses PhaseSupportKind.analytic_hg only when aerosol is enabled; LABOS later uses prepared |
//   phase coefficients and max phase indexes, not this public tag directly.                                   |
//                                                                                                             |
// data shapes                                                                                                 |
//   AirmassFactorPoint : one angular support row, 32 B, scanned by nearest                                    |
//   AirmassFactorLut   : owned slice of support rows from the reference-data loader                           |
//   PhaseSupportKind   : tag copied into prepared state to describe the aerosol phase-support family          |
//                                                                                                             |
// profile builder                                                                                             |
//   spectralProfileFromOpticalDepth converts wavelength-aligned optical-depth proxy samples into an airmass   |
//   profile with the requested mean. It clips negative proxy values to zero, adds a weak wavelength tilt so   |
//   the profile is not flat, then renormalizes the final profile back to mean_airmass_factor.                 |
//                                                                                                             |
// hot path boundary                                                                                           |
//   nearest is setup work: it runs once for the scene geometry and linearly scans the support rows.           |
//   spectralProfileFromOpticalDepth writes one f64 per wavelength when support assets are materialized.       |
//   Repeated wavelength execution consumes prepared optical rows and never calls back into this file.         |
//                                                                                                             |
// ownership                                                                                                   |
//   AirmassFactorLut owns the row storage returned by the reference-data loader and releases it in deinit.    |
//   spectralProfileFromOpticalDepth returns an owned f64 profile slice; the caller releases it.               |
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
};
// ------------------------------------------------------------------------------------------------------------|

pub fn spectralProfileFromOpticalDepth(
    allocator: Allocator,
    wavelengths_nm: []const f64,
    mean_airmass_factor: f64,
    optical_depth_proxy: []const f64,
) ![]f64 {
    // spectralProfileFromOpticalDepth ------------------------------------------------------------------------|
    // Build a wavelength-aligned airmass profile from optical-depth proxy samples.                            |
    //                                                                                                         |
    // call shape                                                                                              |
    //   Reference support loaders pass matching wavelength and proxy slices. The returned profile is owned by |
    //   the caller and has the same length/order as wavelengths_nm.                                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : when reference support materializes band profiles                                          |
    //   work     : one pass for proxy mean, one pass to write the profile, one pass to renormalize            |
    //   memory   : writes one f64 profile sample per input wavelength                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   proxy_mean = mean(max(proxy_i, 0))                                                                    |
    //   normalized_proxy_i = max(proxy_i, 0) / proxy_mean, or 1 when proxy_mean is zero                       |
    //   coordinate_i = (wavelength_i - midpoint_nm) / half_span_nm                                            |
    //   profile_i = safe_mean_airmass * normalized_proxy_i * (1 + 0.05 * coordinate_i)                        |
    //   final profile is scaled so mean(profile) = safe_mean_airmass                                          |
    //                                                                                                         |
    // fallback                                                                                                |
    //   Non-finite or non-positive mean_airmass_factor becomes 1.0. Empty inputs return an empty owned slice. |
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
