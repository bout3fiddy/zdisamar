const std = @import("std");
const internal = @import("internal");

const bands = internal.bands;
const SpectralBand = bands.SpectralBand;
const SpectralBandSet = bands.SpectralBandSet;
const SpectralWindow = bands.SpectralWindow;
const errors = internal.core.errors;

test "spectral band set rejects duplicate ids and invalid exclusion windows" {
    const valid: SpectralBandSet = .{
        .items = &[_]SpectralBand{
            .{
                .id = "o2a",
                .start_nm = 758.0,
                .end_nm = 771.0,
                .step_nm = 0.01,
                .exclude = &[_]SpectralWindow{
                    .{ .start_nm = 759.35, .end_nm = 759.55 },
                    .{ .start_nm = 770.50, .end_nm = 770.80 },
                },
            },
        },
    };
    try valid.validate();

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (SpectralBandSet{
            .items = &[_]SpectralBand{
                .{ .id = "o2a", .start_nm = 758.0, .end_nm = 771.0, .step_nm = 0.01 },
                .{ .id = "o2a", .start_nm = 405.0, .end_nm = 465.0, .step_nm = 0.1 },
            },
        }).validate(),
    );

    try std.testing.expectError(
        errors.Error.InvalidRequest,
        (SpectralBand{
            .id = "o2a",
            .start_nm = 758.0,
            .end_nm = 771.0,
            .step_nm = 0.01,
            .exclude = &[_]SpectralWindow{
                .{ .start_nm = 759.8, .end_nm = 760.0 },
                .{ .start_nm = 759.9, .end_nm = 760.1 },
            },
        }).validate(),
    );
}
