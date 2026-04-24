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
const spline = @import("../../kernels/interpolation/spline.zig");
const Allocator = std.mem.Allocator;

const max_spline_profile_rows: usize = 256;

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
    ///   Expand sparse vendor PT nodes onto the dense pressure grid used by the
    ///   DISAMAR parity path.
    ///
    /// Physics:
    ///   DISAMAR first inserts additional log-pressure levels between the
    ///   configured PT nodes, then realizes altitude hydrostatically on that
    ///   dense pressure grid before interval/support sampling.
    pub fn densifyVendorPressureGrid(
        self: ClimatologyProfile,
        allocator: Allocator,
        surface_pressure_hpa: f64,
    ) !ClimatologyProfile {
        if (self.rows.len < 2) {
            return .{ .rows = try allocator.dupe(ClimatologyPoint, self.rows) };
        }

        const scale_height_guess_km = 8.0;
        var dense_row_count: usize = 1;
        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |lower, upper| {
            const safe_lower_pressure = @max(lower.pressure_hpa, 1.0e-9);
            const safe_upper_pressure = @max(upper.pressure_hpa, 1.0e-9);
            const delta_z_guess = scale_height_guess_km * @log(safe_lower_pressure / safe_upper_pressure);
            const additional_levels: usize = @intFromFloat(@floor(@max(delta_z_guess, 0.0)));
            dense_row_count += additional_levels + 1;
        }

        const dense_pressures_hpa = try allocator.alloc(f64, dense_row_count);
        defer allocator.free(dense_pressures_hpa);
        const dense_temperatures_k = try allocator.alloc(f64, dense_row_count);
        defer allocator.free(dense_temperatures_k);
        const dense_altitudes_km = try allocator.alloc(f64, dense_row_count);
        defer allocator.free(dense_altitudes_km);
        const dense_altitudes_gp_km = try allocator.alloc(f64, (dense_row_count - 1) * 2);
        defer allocator.free(dense_altitudes_gp_km);

        var dense_index: usize = 0;
        dense_pressures_hpa[dense_index] = self.rows[0].pressure_hpa;
        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |lower, upper| {
            const safe_lower_pressure = @max(lower.pressure_hpa, 1.0e-9);
            const safe_upper_pressure = @max(upper.pressure_hpa, 1.0e-9);
            const delta_z_guess = scale_height_guess_km * @log(safe_lower_pressure / safe_upper_pressure);
            const additional_levels: usize = @intFromFloat(@floor(@max(delta_z_guess, 0.0)));
            if (additional_levels > 0) {
                const delta_nodes_lnp = @log(safe_lower_pressure / safe_upper_pressure);
                const delta_lnp = delta_nodes_lnp / @as(f64, @floatFromInt(additional_levels + 1));
                for (0..additional_levels) |_| {
                    dense_index += 1;
                    dense_pressures_hpa[dense_index] = dense_pressures_hpa[dense_index - 1] * @exp(-delta_lnp);
                }
            }
            dense_index += 1;
            dense_pressures_hpa[dense_index] = upper.pressure_hpa;
        }
        std.debug.assert(dense_index + 1 == dense_row_count);

        for (dense_pressures_hpa, 0..) |pressure_hpa, index| {
            dense_temperatures_k[index] = self.interpolateTemperatureForPressureSpline(pressure_hpa);
        }

        const gauss_nodes_01 = [_]f64{ 0.21132486540518713, 0.7886751345948129 };
        const gauss_weights_01 = [_]f64{ 0.5, 0.5 };
        const universal_gas_constant = 8.3144621;
        const mean_molecular_weight_air = 28.964e-3;
        const safe_surface_pressure_hpa = @max(surface_pressure_hpa, 1.0e-9);

        var dense_log_pressures = try allocator.alloc(f64, dense_row_count);
        defer allocator.free(dense_log_pressures);
        for (dense_pressures_hpa, 0..) |pressure_hpa, index| {
            dense_log_pressures[index] = @log(@max(pressure_hpa, 1.0e-9));
            dense_altitudes_km[index] = scale_height_guess_km *
                (@log(safe_surface_pressure_hpa) - dense_log_pressures[index]);
        }

        for (0..dense_row_count - 1) |interval_index| {
            const dlnp = dense_log_pressures[interval_index] - dense_log_pressures[interval_index + 1];
            for (0..2) |gauss_index| {
                const gp_index = interval_index * 2 + gauss_index;
                dense_altitudes_gp_km[gp_index] = scale_height_guess_km *
                    (@log(safe_surface_pressure_hpa) -
                        (dense_log_pressures[interval_index + 1] + dlnp * gauss_nodes_01[gauss_index]));
            }
        }

        const previous_altitudes_km = try allocator.dupe(f64, dense_altitudes_km);
        defer allocator.free(previous_altitudes_km);
        var iteration: usize = 0;
        while (iteration < 6) : (iteration += 1) {
            dense_altitudes_km[0] = 0.0;
            for (1..dense_row_count) |pressure_index| {
                const gp_start = (pressure_index - 1) * 2;
                const dlnp = dense_log_pressures[pressure_index - 1] - dense_log_pressures[pressure_index];
                var interval_altitude_increment_km: f64 = 0.0;
                for (0..2) |gauss_index| {
                    const gp_index = gp_start + gauss_index;
                    const pressure_gp_hpa = @exp(dense_log_pressures[pressure_index] + dlnp * gauss_nodes_01[gauss_index]);
                    const temperature_gp_k = self.interpolateTemperatureForPressureSpline(pressure_gp_hpa);
                    const gravity = gravitationalAccelerationMetersPerSecondSquared(45.0, dense_altitudes_gp_km[gp_index]);
                    const scale_height_km = 1.0e-3 * universal_gas_constant * temperature_gp_k /
                        mean_molecular_weight_air / gravity;
                    interval_altitude_increment_km += gauss_weights_01[gauss_index] * dlnp * scale_height_km;
                }
                dense_altitudes_km[pressure_index] = dense_altitudes_km[pressure_index - 1] + interval_altitude_increment_km;
            }

            var chi2: f64 = 0.0;
            for (dense_altitudes_km, previous_altitudes_km) |altitude_km, previous_altitude_km| {
                const delta = altitude_km - previous_altitude_km;
                chi2 += delta * delta;
            }
            if (chi2 < 1.0e-6) break;
            @memcpy(previous_altitudes_km, dense_altitudes_km);
        }

        const surface_altitude_shift_km = linearSampleDescending(
            dense_pressures_hpa,
            dense_altitudes_km,
            safe_surface_pressure_hpa,
        );

        const dense_rows = try allocator.alloc(ClimatologyPoint, dense_row_count);
        errdefer allocator.free(dense_rows);
        for (0..dense_row_count) |index| {
            const pressure_hpa = dense_pressures_hpa[index];
            const temperature_k = dense_temperatures_k[index];
            dense_rows[index] = .{
                .altitude_km = dense_altitudes_km[index] - surface_altitude_shift_km,
                .pressure_hpa = pressure_hpa,
                .temperature_k = temperature_k,
                .air_number_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / 1.380658e-19,
            };
        }

        return .{ .rows = dense_rows };
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
    ///   Interpolate temperature with the spline contract used by the vendor
    ///   parity path.
    pub fn interpolateTemperatureSpline(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateTemperature(altitude_km);
        }
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].temperature_k;
        if (altitude_km >= self.rows[self.rows.len - 1].altitude_km) return self.rows[self.rows.len - 1].temperature_k;

        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        var temperatures_k: [max_spline_profile_rows]f64 = undefined;
        for (self.rows, 0..) |row, index| {
            altitudes_km[index] = row.altitude_km;
            temperatures_k[index] = row.temperature_k;
        }
        return spline.sampleEndpointSecant(
            altitudes_km[0..self.rows.len],
            temperatures_k[0..self.rows.len],
            altitude_km,
        ) catch self.interpolateTemperature(altitude_km);
    }

    /// Purpose:
    ///   Interpolate temperature at the requested pressure in log-pressure
    ///   space.
    ///
    /// Physics:
    ///   DISAMAR realizes PT state on the dense pressure grid first, then
    ///   samples temperature as `T(ln p)` on derived interval/support rows.
    pub fn interpolateTemperatureForPressureLogLinear(self: ClimatologyProfile, pressure_hpa: f64) f64 {
        if (self.rows.len == 0) return 0.0;

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].temperature_k;
        }
        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].temperature_k;
        }

        const log_pressure = @log(safe_pressure_hpa);
        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            const in_segment = if (descending)
                safe_pressure_hpa <= left.pressure_hpa and safe_pressure_hpa >= right.pressure_hpa
            else
                safe_pressure_hpa >= left.pressure_hpa and safe_pressure_hpa <= right.pressure_hpa;
            if (!in_segment) continue;

            const left_log = @log(@max(left.pressure_hpa, 1.0e-9));
            const right_log = @log(@max(right.pressure_hpa, 1.0e-9));
            const span = right_log - left_log;
            if (span == 0.0) return right.temperature_k;
            const weight = (log_pressure - left_log) / span;
            return left.temperature_k + weight * (right.temperature_k - left.temperature_k);
        }
        return self.rows[self.rows.len - 1].temperature_k;
    }

    /// Purpose:
    ///   Interpolate temperature from a natural spline in `ln(p)`.
    ///
    /// Physics:
    ///   Mirrors DISAMAR's `T(ln p)` realization on the vendor-style
    ///   high-resolution pressure grid.
    pub fn interpolateTemperatureForPressureSpline(self: ClimatologyProfile, pressure_hpa: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateTemperatureForPressureLogLinear(pressure_hpa);
        }

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].temperature_k;
        }
        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].temperature_k;
        }

        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        var temperatures_k: [max_spline_profile_rows]f64 = undefined;
        if (descending) {
            for (self.rows, 0..) |_, index| {
                const reversed_index = self.rows.len - 1 - index;
                log_pressures[index] = @log(@max(self.rows[reversed_index].pressure_hpa, 1.0e-9));
                temperatures_k[index] = self.rows[reversed_index].temperature_k;
            }
        } else {
            for (self.rows, 0..) |row, index| {
                log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
                temperatures_k[index] = row.temperature_k;
            }
        }
        return spline.sampleEndpointSecant(
            log_pressures[0..self.rows.len],
            temperatures_k[0..self.rows.len],
            @log(safe_pressure_hpa),
        ) catch self.interpolateTemperatureForPressureLogLinear(safe_pressure_hpa);
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
    ///   Interpolate pressure at the requested altitude in log-pressure space.
    ///
    /// Physics:
    ///   DISAMAR prepares pressure on the RTM support grid from a spline in
    ///   `ln(p)`. This helper keeps the parity path closer to that contract
    ///   than the default linear-in-pressure interpolation used elsewhere.
    pub fn interpolatePressureLogLinear(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].pressure_hpa;

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km <= right.altitude_km) {
                const span = right.altitude_km - left.altitude_km;
                if (span == 0.0) return right.pressure_hpa;
                const weight = (altitude_km - left.altitude_km) / span;
                const left_log = @log(@max(left.pressure_hpa, 1.0e-9));
                const right_log = @log(@max(right.pressure_hpa, 1.0e-9));
                return @exp(left_log + weight * (right_log - left_log));
            }
        }
        return self.rows[self.rows.len - 1].pressure_hpa;
    }

    /// Purpose:
    ///   Interpolate pressure from a natural spline in `ln(p)`.
    ///
    /// Physics:
    ///   DISAMAR realizes the RTM support grid from a spline in log-pressure.
    pub fn interpolatePressureLogSpline(self: ClimatologyProfile, altitude_km: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolatePressureLogLinear(altitude_km);
        }
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].pressure_hpa;
        if (altitude_km >= self.rows[self.rows.len - 1].altitude_km) return self.rows[self.rows.len - 1].pressure_hpa;

        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        for (self.rows, 0..) |row, index| {
            altitudes_km[index] = row.altitude_km;
            log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
        }
        const log_pressure = spline.sampleEndpointSecant(
            altitudes_km[0..self.rows.len],
            log_pressures[0..self.rows.len],
            altitude_km,
        ) catch return self.interpolatePressureLogLinear(altitude_km);
        return @exp(log_pressure);
    }

    /// Purpose:
    ///   Report the highest altitude in the profile.
    pub fn maxAltitude(self: ClimatologyProfile) f64 {
        return if (self.rows.len == 0) 0.0 else self.rows[self.rows.len - 1].altitude_km;
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

    /// Purpose:
    ///   Invert the spline-based pressure realization used by the parity path.
    pub fn interpolateAltitudeForPressureSpline(self: ClimatologyProfile, pressure_hpa: f64) f64 {
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateAltitudeForPressure(pressure_hpa);
        }

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

        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        if (descending) {
            for (self.rows, 0..) |_, index| {
                const reversed_index = self.rows.len - 1 - index;
                log_pressures[index] = @log(@max(self.rows[reversed_index].pressure_hpa, 1.0e-9));
                altitudes_km[index] = self.rows[reversed_index].altitude_km;
            }
        } else {
            for (self.rows, 0..) |row, index| {
                log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
                altitudes_km[index] = row.altitude_km;
            }
        }
        return spline.sampleEndpointSecant(
            log_pressures[0..self.rows.len],
            altitudes_km[0..self.rows.len],
            @log(safe_pressure_hpa),
        ) catch self.interpolateAltitudeForPressure(safe_pressure_hpa);
    }
};

fn linearSampleDescending(x_desc: []const f64, y: []const f64, target_x: f64) f64 {
    std.debug.assert(x_desc.len == y.len);
    std.debug.assert(x_desc.len != 0);
    if (target_x >= x_desc[0]) return y[0];
    if (target_x <= x_desc[x_desc.len - 1]) return y[x_desc.len - 1];

    for (x_desc[0 .. x_desc.len - 1], x_desc[1..], y[0 .. y.len - 1], y[1..]) |left_x, right_x, left_y, right_y| {
        if (target_x > left_x or target_x < right_x) continue;
        const span = right_x - left_x;
        if (span == 0.0) return right_y;
        const weight = (target_x - left_x) / span;
        return left_y + weight * (right_y - left_y);
    }
    return y[y.len - 1];
}

fn gravitationalAccelerationMetersPerSecondSquared(latitude_deg: f64, altitude_km: f64) f64 {
    const geodetic_latitude_rad = std.math.atan(std.math.tan(latitude_deg * std.math.pi / 180.0) /
        (0.993306 + 1.049583e-6 * altitude_km));
    const sin_latitude = std.math.sin(geodetic_latitude_rad);
    const gravity_at_mean_sea_level = 9.78031 + 0.05186 * sin_latitude * sin_latitude;
    return gravity_at_mean_sea_level - 3.086e-3 * altitude_km;
}

test "climatology interpolates altitude from pressure with log-pressure spacing" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
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
        })),
    };

    const altitude_km = profile.interpolateAltitudeForPressure(540.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), altitude_km, 1.0e-12);
    try std.testing.expect(profile.interpolateAltitudeForPressure(400.0) > 5.0);
    try std.testing.expect(profile.interpolateAltitudeForPressure(800.0) < 5.0);
}

test "climatology interpolates pressure in log-pressure space" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 10.0,
                .pressure_hpa = 100.0,
                .temperature_k = 220.0,
                .air_number_density_cm3 = 5.0e18,
            },
        })),
    };

    try std.testing.expectApproxEqAbs(
        @as(f64, 316.22776601683796),
        profile.interpolatePressureLogLinear(5.0),
        1.0e-9,
    );
}

test "climatology temperature spline follows curved samples" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 1.0,
                .pressure_hpa = 900.0,
                .temperature_k = 280.0,
                .air_number_density_cm3 = 2.2e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 700.0,
                .temperature_k = 250.0,
                .air_number_density_cm3 = 1.6e19,
            },
            .{
                .altitude_km = 3.0,
                .pressure_hpa = 500.0,
                .temperature_k = 230.0,
                .air_number_density_cm3 = 1.1e19,
            },
        })),
    };

    try std.testing.expectApproxEqAbs(@as(f64, 263.75), profile.interpolateTemperatureSpline(1.5), 1.0e-6);
}

test "climatology pressure-based spline helpers follow linear log-pressure profiles" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 300.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 1.0,
                .pressure_hpa = 367.87944117144235,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.1e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 135.3352832366127,
                .temperature_k = 280.0,
                .air_number_density_cm3 = 1.5e19,
            },
            .{
                .altitude_km = 3.0,
                .pressure_hpa = 49.787068367863945,
                .temperature_k = 270.0,
                .air_number_density_cm3 = 1.0e19,
            },
        })),
    };

    const target_pressure_hpa = 223.1301601484298;
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), profile.interpolateAltitudeForPressureSpline(target_pressure_hpa), 1.0e-6);
    try std.testing.expectApproxEqAbs(@as(f64, 285.0), profile.interpolateTemperatureForPressureSpline(target_pressure_hpa), 1.0e-6);
}

test "vendor pressure-grid densification inserts additional levels and anchors the surface" {
    const profile = ClimatologyProfile{
        .rows = @constCast(@as([]const ClimatologyPoint, &.{
            .{
                .altitude_km = 0.0,
                .pressure_hpa = 1000.0,
                .temperature_k = 290.0,
                .air_number_density_cm3 = 2.5e19,
            },
            .{
                .altitude_km = 2.0,
                .pressure_hpa = 700.0,
                .temperature_k = 270.0,
                .air_number_density_cm3 = 1.7e19,
            },
            .{
                .altitude_km = 4.5,
                .pressure_hpa = 400.0,
                .temperature_k = 250.0,
                .air_number_density_cm3 = 1.0e19,
            },
        })),
    };

    var dense = try profile.densifyVendorPressureGrid(std.testing.allocator, 1000.0);
    defer dense.deinit(std.testing.allocator);

    try std.testing.expect(dense.rows.len > profile.rows.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), dense.rows[0].altitude_km, 1.0e-9);
    try std.testing.expect(dense.rows[1].pressure_hpa < dense.rows[0].pressure_hpa);
    try std.testing.expect(dense.rows[dense.rows.len - 1].altitude_km > dense.rows[0].altitude_km);
}
