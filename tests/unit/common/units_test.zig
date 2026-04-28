const std = @import("std");
const internal = @import("internal");

const units = internal.common.units;
const Error = units.Error;
const WavelengthRange = units.WavelengthRange;
const AltitudeRangeKm = units.AltitudeRangeKm;
const PressureRangeHpa = units.PressureRangeHpa;
const AngleDeg = units.AngleDeg;
const ZenithAngleDeg = units.ZenithAngleDeg;
const AzimuthAngleDeg = units.AzimuthAngleDeg;

test "wavelength range rejects inverted intervals" {
    try std.testing.expectError(Error.InvalidRange, (WavelengthRange{
        .start_nm = 465.0,
        .end_nm = 405.0,
    }).validate());
}

test "altitude and pressure ranges enforce physical ordering" {
    try (AltitudeRangeKm{ .bottom_km = 0.0, .top_km = 2.5 }).validate();
    try (PressureRangeHpa{ .top_hpa = 150.0, .bottom_hpa = 900.0 }).validate();
    try std.testing.expectError(Error.InvalidRange, (AltitudeRangeKm{
        .bottom_km = 3.0,
        .top_km = 2.0,
    }).validate());
    try std.testing.expectError(Error.InvalidRange, (PressureRangeHpa{
        .top_hpa = 900.0,
        .bottom_hpa = 150.0,
    }).validate());
}

test "angle validation rejects NaN" {
    try std.testing.expectError(Error.InvalidValue, (AngleDeg{
        .value = std.math.nan(f64),
    }).validate());
}

test "zenith and azimuth helpers enforce physical angle ranges" {
    try (ZenithAngleDeg{ .value = 95.0 }).validate();
    try (AzimuthAngleDeg{ .value = 270.0 }).validate();
    try std.testing.expectError(Error.InvalidRange, (ZenithAngleDeg{ .value = -1.0 }).validate());
    try std.testing.expectError(Error.InvalidRange, (AzimuthAngleDeg{ .value = 361.0 }).validate());
}
