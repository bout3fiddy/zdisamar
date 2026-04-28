const std = @import("std");
const gauss_legendre = @import("../../kernels/quadrature/gauss_legendre.zig");
const spline = @import("../../kernels/interpolation/spline.zig");
const Allocator = std.mem.Allocator;

const max_spline_profile_rows: usize = 256;

pub const ClimatologyPoint = struct {
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    air_number_density_cm3: f64,
};

pub const ClimatologyProfile = struct {
    rows: []ClimatologyPoint,

    pub fn deinit(self: *ClimatologyProfile, allocator: Allocator) void {
        allocator.free(self.rows);
        self.* = undefined;
    }

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

        var gauss_nodes_01: [2]f64 = undefined;
        var gauss_weights_01: [2]f64 = undefined;
        try gauss_legendre.fillDisamarDivPoints01(2, gauss_nodes_01[0..], gauss_weights_01[0..]);
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

    pub fn meanNumberDensity(self: ClimatologyProfile) f64 {
        var total: f64 = 0.0;
        for (self.rows) |row| total += row.air_number_density_cm3;
        return if (self.rows.len == 0) 0.0 else total / @as(f64, @floatFromInt(self.rows.len));
    }

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

    pub fn maxAltitude(self: ClimatologyProfile) f64 {
        return if (self.rows.len == 0) 0.0 else self.rows[self.rows.len - 1].altitude_km;
    }
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
    const geodetic_flattening_term: f64 = @floatCast(@as(f32, 0.993306));
    const geodetic_latitude_rad = std.math.atan(std.math.tan(latitude_deg * std.math.pi / 180.0) /
        (geodetic_flattening_term + 1.049583e-6 * altitude_km));
    const sin_latitude = std.math.sin(geodetic_latitude_rad);
    const gravity_at_mean_sea_level = 9.78031 + 0.05186 * sin_latitude * sin_latitude;
    return gravity_at_mean_sea_level - 3.086e-3 * altitude_km;
}
