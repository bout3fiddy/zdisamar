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
};
