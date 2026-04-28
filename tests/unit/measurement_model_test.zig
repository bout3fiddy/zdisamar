const std = @import("std");
const internal = @import("internal");

const measurement_model = internal.measurement;
const Measurement = measurement_model.Measurement;
const SpectralWindow = internal.bands.SpectralWindow;

test "measurement validates source masks and error model" {
    try (Measurement{
        .product_name = "radiance",
        .observable = .radiance,
        .sample_count = 121,
        .source = .{ .stage_product = .{ .name = "truth_radiance" } },
        .mask = .{
            .band = "o2a",
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 759.35, .end_nm = 759.55 },
                .{ .start_nm = 770.50, .end_nm = 770.80 },
            },
        },
        .error_model = .{ .from_source_noise = true, .floor = 1.0e-4 },
    }).validate();
}

test "measurement sample selection honors excluded spectral windows" {
    const value: Measurement = .{
        .product_name = "radiance",
        .observable = .radiance,
        .sample_count = 3,
        .source = .{ .stage_product = .{ .name = "truth_radiance" } },
        .mask = .{
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 760.0, .end_nm = 761.0 },
            },
        },
    };
    const wavelengths = [_]f64{ 759.5, 760.5, 761.5, 762.0 };

    try std.testing.expect(value.includesWavelength(759.5));
    try std.testing.expect(!value.includesWavelength(760.5));
    try std.testing.expectEqual(@as(u32, 3), value.selectedSampleCount(&wavelengths));
}
