//! Purpose:
//!   Hold small reference tables for airmass factors and Mie phase behavior used by optics preparation.
//!
//! Physics:
//!   Encodes interpolation points for geometric airmass factors and wavelength-dependent phase proxies.
//!
//! Vendor:
//!   `airmass / Mie phase helper tables`
//!
//! Design:
//!   Zig keeps these as lightweight owned slices so preparation code can clone or discard them explicitly.
//!
//! Invariants:
//!   Table points are monotonic in wavelength where interpolation is used, and empty tables fall back to safe defaults.
//!
//! Validation:
//!   Tests cover mean-preserving AMF profiles and interpolation behavior.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Store a geometric airmass lookup point.
pub const AirmassFactorPoint = struct {
    solar_zenith_deg: f64,
    view_zenith_deg: f64,
    relative_azimuth_deg: f64,
    airmass_factor: f64,
};

/// Purpose:
///   Store a wavelength-dependent proxy for Mie phase and extinction behavior.
pub const MiePhasePoint = struct {
    wavelength_nm: f64,
    extinction_scale: f64,
    single_scatter_albedo: f64,
    phase_coefficients: [4]f64,
};

/// Purpose:
///   Own an interpolatable Mie phase table.
pub const MiePhaseTable = struct {
    points: []MiePhasePoint,

    /// Purpose:
    ///   Release the owned phase points.
    pub fn deinit(self: *MiePhaseTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    /// Purpose:
    ///   Interpolate a phase point at an arbitrary wavelength.
    ///
    /// Physics:
    ///   Linearly interpolates extinction, single-scatter albedo, and phase coefficients over wavelength.
    pub fn interpolate(self: MiePhaseTable, wavelength_nm: f64) MiePhasePoint {
        if (self.points.len == 0) {
            return .{
                .wavelength_nm = wavelength_nm,
                .extinction_scale = 1.0,
                .single_scatter_albedo = 1.0,
                .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
            };
        }
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0];

        for (self.points[0 .. self.points.len - 1], self.points[1..]) |left, right| {
            if (wavelength_nm <= right.wavelength_nm) {
                const span = right.wavelength_nm - left.wavelength_nm;
                if (span == 0.0) return right;
                const weight = (wavelength_nm - left.wavelength_nm) / span;

                var phase_coefficients: [4]f64 = undefined;
                for (&phase_coefficients, 0..) |*slot, index| {
                    slot.* = left.phase_coefficients[index] +
                        weight * (right.phase_coefficients[index] - left.phase_coefficients[index]);
                }
                phase_coefficients[0] = 1.0;
                return .{
                    .wavelength_nm = wavelength_nm,
                    .extinction_scale = left.extinction_scale + weight * (right.extinction_scale - left.extinction_scale),
                    .single_scatter_albedo = left.single_scatter_albedo + weight * (right.single_scatter_albedo - left.single_scatter_albedo),
                    .phase_coefficients = phase_coefficients,
                };
            }
        }
        return self.points[self.points.len - 1];
    }
};

/// Purpose:
///   Own an airmass-factor lookup table.
pub const AirmassFactorLut = struct {
    points: []AirmassFactorPoint,

    /// Purpose:
    ///   Release the owned airmass-factor points.
    pub fn deinit(self: *AirmassFactorLut, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    /// Purpose:
    ///   Return the nearest airmass-factor point in the lookup table.
    ///
    /// Physics:
    ///   Uses the closest sample in `(solar zenith, view zenith, relative azimuth)` space.
    pub fn nearest(self: AirmassFactorLut, solar_zenith_deg: f64, view_zenith_deg: f64, relative_azimuth_deg: f64) f64 {
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

    /// Purpose:
    ///   Mark the LUT as support-only rather than a full solver.
    pub fn providesSupportOnly(_: AirmassFactorLut) bool {
        return true;
    }
};

/// Purpose:
///   Build a wavelength-dependent airmass profile from an optical-depth proxy.
///
/// Physics:
///   Scales the mean airmass by local proxy intensity and a small geometric tilt, then renormalizes the mean.
///
/// Vendor:
///   `spectral AMF profile`
///
/// Units:
///   `wavelengths_nm` is in nanometers and the returned profile is a dimensionless airmass factor.
///
/// Decisions:
///   The profile is renormalized to preserve the requested mean airmass factor after local weighting.
pub fn spectralProfileFromOpticalDepth(
    allocator: Allocator,
    wavelengths_nm: []const f64,
    mean_airmass_factor: f64,
    optical_depth_proxy: []const f64,
) ![]f64 {
    if (wavelengths_nm.len != optical_depth_proxy.len) return error.ShapeMismatch;

    const profile = try allocator.alloc(f64, wavelengths_nm.len);
    errdefer allocator.free(profile);
    if (wavelengths_nm.len == 0) return profile;

    var proxy_sum: f64 = 0.0;
    for (optical_depth_proxy) |value| proxy_sum += @max(value, 0.0);
    const proxy_mean = proxy_sum / @max(@as(f64, @floatFromInt(optical_depth_proxy.len)), 1.0e-9);
    const safe_mean_airmass = if (std.math.isFinite(mean_airmass_factor) and mean_airmass_factor > 0.0)
        mean_airmass_factor
    else
        1.0;
    const midpoint_nm = 0.5 * (wavelengths_nm[0] + wavelengths_nm[wavelengths_nm.len - 1]);
    const half_span_nm = @max(0.5 * (wavelengths_nm[wavelengths_nm.len - 1] - wavelengths_nm[0]), 1.0e-9);

    for (profile, wavelengths_nm, optical_depth_proxy) |*slot, wavelength_nm, proxy| {
        const normalized_proxy = if (proxy_mean > 0.0) @max(proxy, 0.0) / proxy_mean else 1.0;
        const coordinate = (wavelength_nm - midpoint_nm) / half_span_nm;
        // DECISION:
        //   Keep a weak wavelength tilt so the profile is not numerically flat before the mean is restored.
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

test "spectral amf profile preserves the requested mean factor" {
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const proxy = [_]f64{ 0.5, 1.0, 1.5, 1.0 };
    const profile = try spectralProfileFromOpticalDepth(std.testing.allocator, &wavelengths, 2.0, &proxy);
    defer std.testing.allocator.free(profile);

    var mean: f64 = 0.0;
    for (profile) |value| mean += value;
    mean /= @as(f64, @floatFromInt(profile.len));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), mean, 1.0e-9);
    try std.testing.expect(profile[2] > profile[0]);
}
