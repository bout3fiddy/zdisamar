const std = @import("std");

const Allocator = std.mem.Allocator;

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

    pub fn maxAltitude(self: ClimatologyProfile) f64 {
        return if (self.rows.len == 0) 0.0 else self.rows[self.rows.len - 1].altitude_km;
    }
};

pub const CrossSectionPoint = struct {
    wavelength_nm: f64,
    sigma_cm2_per_molecule: f64,
};

pub const CrossSectionTable = struct {
    points: []CrossSectionPoint,

    pub fn deinit(self: *CrossSectionTable, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

    pub fn meanSigmaInRange(self: CrossSectionTable, start_nm: f64, end_nm: f64) f64 {
        var total: f64 = 0.0;
        var count: usize = 0;
        for (self.points) |point| {
            if (point.wavelength_nm < start_nm or point.wavelength_nm > end_nm) continue;
            total += point.sigma_cm2_per_molecule;
            count += 1;
        }

        if (count > 0) return total / @as(f64, @floatFromInt(count));
        return self.interpolateSigma((start_nm + end_nm) * 0.5);
    }

    pub fn interpolateSigma(self: CrossSectionTable, wavelength_nm: f64) f64 {
        if (self.points.len == 0) return 0.0;
        if (wavelength_nm <= self.points[0].wavelength_nm) return self.points[0].sigma_cm2_per_molecule;

        for (self.points[0 .. self.points.len - 1], self.points[1..]) |left, right| {
            if (wavelength_nm <= right.wavelength_nm) {
                const span = right.wavelength_nm - left.wavelength_nm;
                if (span == 0.0) return right.sigma_cm2_per_molecule;
                const weight = (wavelength_nm - left.wavelength_nm) / span;
                return left.sigma_cm2_per_molecule + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule);
            }
        }
        return self.points[self.points.len - 1].sigma_cm2_per_molecule;
    }
};

pub const SpectroscopyLine = struct {
    center_wavelength_nm: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    lower_state_energy_cm1: f64,
    pressure_shift_nm: f64,
    line_mixing_coefficient: f64,
};

pub const SpectroscopyEvaluation = struct {
    line_sigma_cm2_per_molecule: f64,
    line_mixing_sigma_cm2_per_molecule: f64,
    total_sigma_cm2_per_molecule: f64,
    d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
};

pub const SpectroscopyLineList = struct {
    lines: []SpectroscopyLine,

    pub fn deinit(self: *SpectroscopyLineList, allocator: Allocator) void {
        allocator.free(self.lines);
        self.* = undefined;
    }

    pub fn sigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) f64 {
        return self.evaluateAt(wavelength_nm, temperature_k, pressure_hpa).total_sigma_cm2_per_molecule;
    }

    pub fn evaluateAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        const total = self.totalSigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        const delta_t = 0.5;
        const upper = self.totalSigmaAt(wavelength_nm, temperature_k + delta_t, pressure_hpa);
        const lower = self.totalSigmaAt(wavelength_nm, @max(temperature_k - delta_t, 150.0), pressure_hpa);
        return .{
            .line_sigma_cm2_per_molecule = total.line_sigma_cm2_per_molecule,
            .line_mixing_sigma_cm2_per_molecule = total.line_mixing_sigma_cm2_per_molecule,
            .total_sigma_cm2_per_molecule = total.total_sigma_cm2_per_molecule,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = (upper.total_sigma_cm2_per_molecule - lower.total_sigma_cm2_per_molecule) / (2.0 * delta_t),
        };
    }

    fn totalSigmaAt(self: SpectroscopyLineList, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) SpectroscopyEvaluation {
        if (self.lines.len == 0) {
            return .{
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        const reference_temperature_k = 296.0;
        const pressure_scale = @max(pressure_hpa / 1013.25, 0.05);
        const temperature_ratio = reference_temperature_k / @max(temperature_k, 150.0);

        var line_sigma: f64 = 0.0;
        var line_mixing_sigma: f64 = 0.0;
        for (self.lines) |line| {
            const shifted_center = line.center_wavelength_nm + line.pressure_shift_nm * pressure_scale;
            const exponent_scale = std.math.pow(f64, temperature_ratio, line.temperature_exponent);
            const boltzmann_scale = @exp(
                -1.438776877 * line.lower_state_energy_cm1 *
                    ((1.0 / @max(temperature_k, 150.0)) - (1.0 / reference_temperature_k)),
            );
            const amplitude = line.line_strength_cm2_per_molecule * exponent_scale * boltzmann_scale;

            const lorentz_width = @max(line.air_half_width_nm * pressure_scale * exponent_scale, 1e-5);
            const doppler_width = @max(
                shifted_center * 1.0e-6 * std.math.sqrt(@max(temperature_k, 150.0) / reference_temperature_k),
                1e-5,
            );
            const profile = pseudoVoigt(wavelength_nm, shifted_center, doppler_width, lorentz_width);
            line_sigma += amplitude * profile;
            line_mixing_sigma += amplitude *
                line.line_mixing_coefficient *
                lineMixingShape(wavelength_nm, shifted_center, lorentz_width) *
                pressure_scale;
        }
        const total_sigma = @max(line_sigma + line_mixing_sigma, 0.0);
        return .{
            .line_sigma_cm2_per_molecule = line_sigma,
            .line_mixing_sigma_cm2_per_molecule = line_mixing_sigma,
            .total_sigma_cm2_per_molecule = total_sigma,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }
};

pub const AirmassFactorPoint = struct {
    solar_zenith_deg: f64,
    view_zenith_deg: f64,
    relative_azimuth_deg: f64,
    airmass_factor: f64,
};

pub const AirmassFactorLut = struct {
    points: []AirmassFactorPoint,

    pub fn deinit(self: *AirmassFactorLut, allocator: Allocator) void {
        allocator.free(self.points);
        self.* = undefined;
    }

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
};

const demo_profile_rows = [_]ClimatologyPoint{
    .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
    .{ .altitude_km = 5.0, .pressure_hpa = 540.48, .temperature_k = 255.65, .air_number_density_cm3 = 1.149e19 },
    .{ .altitude_km = 10.0, .pressure_hpa = 264.36, .temperature_k = 223.15, .air_number_density_cm3 = 5.413e18 },
    .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
    .{ .altitude_km = 40.0, .pressure_hpa = 2.87, .temperature_k = 251.05, .air_number_density_cm3 = 8.24e16 },
};

const demo_cross_section_points = [_]CrossSectionPoint{
    .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
    .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 5.72e-19 },
    .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 5.13e-19 },
    .{ .wavelength_nm = 470.0, .sigma_cm2_per_molecule = 4.42e-19 },
    .{ .wavelength_nm = 490.0, .sigma_cm2_per_molecule = 3.98e-19 },
};

const demo_spectroscopy_lines = [_]SpectroscopyLine{
    .{ .center_wavelength_nm = 429.8, .line_strength_cm2_per_molecule = 8.2e-21, .air_half_width_nm = 0.035, .temperature_exponent = 0.72, .lower_state_energy_cm1 = 112.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.04 },
    .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
    .{ .center_wavelength_nm = 441.2, .line_strength_cm2_per_molecule = 9.7e-21, .air_half_width_nm = 0.038, .temperature_exponent = 0.74, .lower_state_energy_cm1 = 165.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.05 },
    .{ .center_wavelength_nm = 448.1, .line_strength_cm2_per_molecule = 7.6e-21, .air_half_width_nm = 0.034, .temperature_exponent = 0.77, .lower_state_energy_cm1 = 188.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.03 },
    .{ .center_wavelength_nm = 456.0, .line_strength_cm2_per_molecule = 5.4e-21, .air_half_width_nm = 0.030, .temperature_exponent = 0.81, .lower_state_energy_cm1 = 205.0, .pressure_shift_nm = 0.001, .line_mixing_coefficient = 0.02 },
};

const demo_airmass_factor_points = [_]AirmassFactorPoint{
    .{ .solar_zenith_deg = 20.0, .view_zenith_deg = 0.0, .relative_azimuth_deg = 0.0, .airmass_factor = 1.08 },
    .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
    .{ .solar_zenith_deg = 55.0, .view_zenith_deg = 20.0, .relative_azimuth_deg = 60.0, .airmass_factor = 1.58 },
    .{ .solar_zenith_deg = 70.0, .view_zenith_deg = 30.0, .relative_azimuth_deg = 90.0, .airmass_factor = 2.11 },
};

pub fn buildDemoClimatology(allocator: Allocator) !ClimatologyProfile {
    return .{
        .rows = try allocator.dupe(ClimatologyPoint, demo_profile_rows[0..]),
    };
}

pub fn buildDemoCrossSections(allocator: Allocator) !CrossSectionTable {
    return .{
        .points = try allocator.dupe(CrossSectionPoint, demo_cross_section_points[0..]),
    };
}

pub fn buildDemoSpectroscopyLines(allocator: Allocator) !SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(SpectroscopyLine, demo_spectroscopy_lines[0..]),
    };
}

pub fn buildDemoAirmassFactorLut(allocator: Allocator) !AirmassFactorLut {
    return .{
        .points = try allocator.dupe(AirmassFactorPoint, demo_airmass_factor_points[0..]),
    };
}

test "reference data helpers interpolate physical tables deterministically" {
    var profile = ClimatologyProfile{
        .rows = try std.testing.allocator.dupe(ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.5e19 },
            .{ .altitude_km = 10.0, .pressure_hpa = 260.0, .temperature_k = 223.0, .air_number_density_cm3 = 6.6e18 },
        }),
    };
    defer profile.deinit(std.testing.allocator);

    var cross_sections = CrossSectionTable{
        .points = try std.testing.allocator.dupe(CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.17e-19 },
        }),
    };
    defer cross_sections.deinit(std.testing.allocator);

    var lut = AirmassFactorLut{
        .points = try std.testing.allocator.dupe(AirmassFactorPoint, &.{
            .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
            .{ .solar_zenith_deg = 60.0, .view_zenith_deg = 20.0, .relative_azimuth_deg = 60.0, .airmass_factor = 1.756 },
        }),
    };
    defer lut.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 1.58e19), profile.interpolateDensity(5.0), 1e16);
    try std.testing.expectApproxEqAbs(@as(f64, 630.0), profile.interpolatePressure(5.0), 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.19e-19), cross_sections.meanSigmaInRange(405.0, 465.0), 1e-22);
    try std.testing.expectApproxEqAbs(@as(f64, 1.241), lut.nearest(42.0, 11.0, 35.0), 1e-9);
}

test "spectroscopy line list evaluates bounded temperature and pressure dependent sigma" {
    var lines = try buildDemoSpectroscopyLines(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    const near_line = lines.evaluateAt(434.6, 250.0, 750.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 750.0);
    const cold_dense = lines.evaluateAt(434.6, 220.0, 900.0);

    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(cold_dense.total_sigma_cm2_per_molecule != near_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(@abs(near_line.d_sigma_d_temperature_cm2_per_molecule_per_k) > 0.0);
    try std.testing.expect(@abs(near_line.line_mixing_sigma_cm2_per_molecule) > 0.0);
}

test "demo reference assets are allocatable and physically ordered" {
    var profile = try buildDemoClimatology(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try buildDemoCrossSections(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try buildDemoSpectroscopyLines(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    try std.testing.expect(profile.rows.len >= 4);
    try std.testing.expect(cross_sections.points[0].wavelength_nm < cross_sections.points[cross_sections.points.len - 1].wavelength_nm);
    try std.testing.expect(spectroscopy.lines.len >= 4);
    try std.testing.expect(lut.points.len >= 3);
}

fn pseudoVoigt(wavelength_nm: f64, center_nm: f64, gaussian_width_nm: f64, lorentz_width_nm: f64) f64 {
    const delta = wavelength_nm - center_nm;
    const sigma = @max(gaussian_width_nm / 2.354820045, 1e-6);
    const gaussian = @exp(-0.5 * (delta / sigma) * (delta / sigma)) / (sigma * std.math.sqrt(2.0 * std.math.pi));
    const lorentz = (lorentz_width_nm / std.math.pi) / (delta * delta + lorentz_width_nm * lorentz_width_nm);
    const ratio = lorentz_width_nm / @max(lorentz_width_nm + gaussian_width_nm, 1e-9);
    const eta = std.math.clamp(1.35 * ratio - 0.35 * ratio * ratio, 0.0, 1.0);
    return eta * lorentz + (1.0 - eta) * gaussian;
}

fn lineMixingShape(wavelength_nm: f64, center_nm: f64, lorentz_width_nm: f64) f64 {
    const delta = wavelength_nm - center_nm;
    const scaled = delta / @max(lorentz_width_nm, 1e-6);
    return (1.0 - 0.35 * scaled * scaled) * @exp(-0.5 * scaled * scaled) / @max(lorentz_width_nm, 1e-6);
}
