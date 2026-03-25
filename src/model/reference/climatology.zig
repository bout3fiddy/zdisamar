//! Purpose:
//!   Store simple climatology profiles for altitude-dependent pressure, temperature, and density.
//!
//! Physics:
//!   Provides monotonic altitude samples for basic atmospheric property interpolation.
//!
//! Vendor:
//!   `climatology profile`
//!
//! Design:
//!   The profile is an owned slice so retrieval and preparation code can clone or free it explicitly.
//!
//! Invariants:
//!   Altitude rows are expected to be ordered monotonically from low to high altitude.
//!
//! Validation:
//!   Tests cover density and temperature interpolation over the demo profile data.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Purpose:
///   Store one climatology sample row.
pub const ClimatologyPoint = struct {
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    air_number_density_cm3: f64,
};

/// Purpose:
///   Own a climatology profile table.
pub const ClimatologyProfile = struct {
    rows: []ClimatologyPoint,

    /// Purpose:
    ///   Release the owned profile rows.
    pub fn deinit(self: *ClimatologyProfile, allocator: Allocator) void {
        allocator.free(self.rows);
        self.* = undefined;
    }

    /// Purpose:
    ///   Compute the mean air-number density across the profile.
    ///
    /// Physics:
    ///   Averages the stored number-density samples without regridding.
    pub fn meanNumberDensity(self: ClimatologyProfile) f64 {
        var total: f64 = 0.0;
        for (self.rows) |row| total += row.air_number_density_cm3;
        return if (self.rows.len == 0) 0.0 else total / @as(f64, @floatFromInt(self.rows.len));
    }

    /// Purpose:
    ///   Interpolate air-number density at the requested altitude.
    ///
    /// Physics:
    ///   Uses linear interpolation between monotonic altitude samples.
    pub fn interpolateDensity(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].air_number_density_cm3;

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km <= right.altitude_km) {
                const span = right.altitude_km - left.altitude_km;
                if (span == 0.0) return right.air_number_density_cm3;
                const weight = (altitude_km - left.altitude_km) / span;
                return left.air_number_density_cm3 + weight * (right.air_number_density_cm3 - left.air_number_density_cm3);
            }
        }
        return self.rows[self.rows.len - 1].air_number_density_cm3;
    }

    /// Purpose:
    ///   Interpolate temperature at the requested altitude.
    ///
    /// Physics:
    ///   Uses linear interpolation between monotonic altitude samples.
    pub fn interpolateTemperature(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].temperature_k;

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km <= right.altitude_km) {
                const span = right.altitude_km - left.altitude_km;
                if (span == 0.0) return right.temperature_k;
                const weight = (altitude_km - left.altitude_km) / span;
                return left.temperature_k + weight * (right.temperature_k - left.temperature_k);
            }
        }
        return self.rows[self.rows.len - 1].temperature_k;
    }

    /// Purpose:
    ///   Interpolate pressure at the requested altitude.
    ///
    /// Physics:
    ///   Uses linear interpolation between monotonic altitude samples.
    pub fn interpolatePressure(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].pressure_hpa;

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km <= right.altitude_km) {
                const span = right.altitude_km - left.altitude_km;
                if (span == 0.0) return right.pressure_hpa;
                const weight = (altitude_km - left.altitude_km) / span;
                return left.pressure_hpa + weight * (right.pressure_hpa - left.pressure_hpa);
            }
        }
        return self.rows[self.rows.len - 1].pressure_hpa;
    }

    /// Purpose:
    ///   Report the highest altitude in the profile.
    pub fn maxAltitude(self: ClimatologyProfile) f64 {
        return if (self.rows.len == 0) 0.0 else self.rows[self.rows.len - 1].altitude_km;
    }

    /// Purpose:
    ///   Report the lowest altitude in the profile.
    pub fn minAltitude(self: ClimatologyProfile) f64 {
        return if (self.rows.len == 0) 0.0 else self.rows[0].altitude_km;
    }

    /// Purpose:
    ///   Interpolate altitude at the requested pressure.
    ///
    /// Physics:
    ///   Uses log-pressure interpolation between monotonic climatology samples
    ///   so pressure-bounded atmospheric intervals can be mapped into altitude
    ///   bounds without reverting to uniform-layer approximations.
    pub fn interpolateAltitudeForPressure(self: ClimatologyProfile, pressure_hpa: f64) f64 {
        if (self.rows.len == 0) return 0.0;

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].altitude_km;
        }
        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].altitude_km;
        }

        const log_pressure = @log(@max(safe_pressure_hpa, 1.0e-9));
        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            const in_segment = if (descending)
                safe_pressure_hpa <= left.pressure_hpa and safe_pressure_hpa >= right.pressure_hpa
            else
                safe_pressure_hpa >= left.pressure_hpa and safe_pressure_hpa <= right.pressure_hpa;
            if (!in_segment) continue;

            const left_log = @log(@max(left.pressure_hpa, 1.0e-9));
            const right_log = @log(@max(right.pressure_hpa, 1.0e-9));
            const span = right_log - left_log;
            if (span == 0.0) return right.altitude_km;
            const weight = (log_pressure - left_log) / span;
            return left.altitude_km + weight * (right.altitude_km - left.altitude_km);
        }
        return self.rows[self.rows.len - 1].altitude_km;
    }
};

test "climatology interpolates altitude from pressure with log-pressure spacing" {
    const profile = ClimatologyProfile{
        .rows = &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 5.0,
                .pressure_hpa = 540.0,
                .temperature_k = 255.0,
                .air_number_density_cm3 = 1.4e19,
            },
            .{
                .altitude_km = 10.0,
                .pressure_hpa = 260.0,
                .temperature_k = 225.0,
                .air_number_density_cm3 = 7.0e18,
            },
        },
    };

    const altitude_km = profile.interpolateAltitudeForPressure(540.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), altitude_km, 1.0e-12);
    try std.testing.expect(profile.interpolateAltitudeForPressure(400.0) > 5.0);
    try std.testing.expect(profile.interpolateAltitudeForPressure(800.0) < 5.0);
}
