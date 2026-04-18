const std = @import("std");
const internal = @import("internal");

const AbsorberModel = internal.absorber;
const ReferenceData = internal.reference_data;
const OperationalCrossSectionLut = internal.instrument.OperationalCrossSectionLut;

const AbsorberSet = AbsorberModel.AbsorberSet;
const Absorber = AbsorberModel.Absorber;
const Spectroscopy = AbsorberModel.Spectroscopy;
const AbsorberSpecies = AbsorberModel.AbsorberSpecies;
const AbsorptionRepresentation = AbsorberModel.AbsorptionRepresentation;
const LineGasControls = AbsorberModel.LineGasControls;
const resolvedAbsorberSpecies = AbsorberModel.resolvedAbsorberSpecies;
const validateVolumeMixingRatioProfile = AbsorberModel.validateVolumeMixingRatioProfile;

test "absorber set validates explicit spectroscopy bindings" {
    const valid: AbsorberSet = .{
        .items = &[_]Absorber{
            .{
                .id = "o2",
                .species = "o2",
                .profile_source = .atmosphere,
                .spectroscopy = .{
                    .mode = .line_by_line,
                    .provider = "builtin.cross_sections",
                    .line_list = .{ .asset = .{ .name = "o2_hitran" } },
                },
            },
            .{
                .id = "o2o2",
                .species = "o2o2",
                .profile_source = .atmosphere,
                .spectroscopy = .{
                    .mode = .cia,
                    .cia_table = .{ .asset = .{ .name = "o2o2_cia" } },
                },
            },
            .{
                .id = "no2",
                .species = "no2",
                .profile_source = .atmosphere,
                .spectroscopy = .{
                    .mode = .cross_sections,
                    .cross_section_table = .{ .asset = .{ .name = "no2_demo" } },
                },
            },
        },
    };
    try valid.validate();

    try std.testing.expectError(
        error.InvalidRequest,
        (AbsorberSet{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .spectroscopy = .{
                        .mode = .none,
                        .line_list = .{ .asset = .{ .name = "unexpected" } },
                    },
                },
            },
        }).validate(),
    );

    try std.testing.expectError(
        error.InvalidRequest,
        (AbsorberSet{
            .items = &[_]Absorber{
                .{
                    .id = "o3",
                    .species = "o3",
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .cross_sections,
                        .cross_section_table = .{ .asset = .{ .name = "o3_table" } },
                        .operational_lut = .{ .ingest = .{
                            .full_name = "demo.o3_operational_lut",
                            .ingest_name = "demo",
                            .output_name = "o3_operational_lut",
                        } },
                    },
                },
            },
        }).validate(),
    );
}

test "resolvedAbsorberSpecies normalizes legacy O2-O2 aliases" {
    try std.testing.expectEqual(
        AbsorberSpecies.o2_o2,
        resolvedAbsorberSpecies(.{ .id = "o2_o2", .species = "o2_o2" }).?,
    );
    try std.testing.expectEqual(
        AbsorberSpecies.o2_o2,
        resolvedAbsorberSpecies(.{ .id = "o2o2", .species = "o2o2" }).?,
    );
    try std.testing.expectEqual(
        AbsorberSpecies.o2_o2,
        resolvedAbsorberSpecies(.{ .id = "o2-o2", .species = "o2-o2" }).?,
    );
}

test "spectroscopy resolves explicit absorption representation tags" {
    const line_list = ReferenceData.SpectroscopyLineList{
        .lines = &.{},
    };
    const cross_section_table = ReferenceData.CrossSectionTable{
        .points = &.{},
    };
    const lut: OperationalCrossSectionLut = .{
        .wavelengths_nm = &.{ 405.0, 406.0 },
        .coefficients = &.{ 1.0, 0.0, 1.1, 0.0 },
        .temperature_coefficient_count = 1,
        .pressure_coefficient_count = 2,
        .min_temperature_k = 200.0,
        .max_temperature_k = 320.0,
        .min_pressure_hpa = 100.0,
        .max_pressure_hpa = 1100.0,
    };

    var line_spectroscopy = Spectroscopy{ .resolved_line_list = line_list };
    try std.testing.expectEqual(
        AbsorptionRepresentation{ .line_abs = &line_spectroscopy.resolved_line_list.? },
        line_spectroscopy.resolvedAbsorptionRepresentation(),
    );

    var cross_section_spectroscopy = Spectroscopy{
        .mode = .cross_sections,
        .resolved_cross_section_table = cross_section_table,
    };
    try std.testing.expectEqual(
        AbsorptionRepresentation{ .xsec_table = &cross_section_spectroscopy.resolved_cross_section_table.? },
        cross_section_spectroscopy.resolvedAbsorptionRepresentation(),
    );

    var operational_lut_spectroscopy = Spectroscopy{
        .mode = .line_by_line,
        .operational_lut = .{ .ingest = .{
            .full_name = "demo.o2_operational_lut",
            .ingest_name = "demo",
            .output_name = "o2_operational_lut",
        } },
        .resolved_cross_section_lut = lut,
    };
    try std.testing.expectEqual(
        AbsorptionRepresentation{ .xsec_lut = &operational_lut_spectroscopy.resolved_cross_section_lut.? },
        operational_lut_spectroscopy.resolvedAbsorptionRepresentation(),
    );
}

test "line-gas controls validate stage-specific isotope and cutoff selections" {
    try (LineGasControls{
        .factor_lm_sim = 1.0,
        .isotopes_sim = &.{ 1, 2 },
        .threshold_line_sim = 0.05,
        .cutoff_sim_cm1 = 12.0,
        .active_stage = .simulation,
    }).validate();

    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        (LineGasControls{ .factor_lm_sim = 1.0, .active_stage = .simulation }).activeLineMixingFactor(),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        (LineGasControls{ .active_stage = .simulation }).activeLineMixingFactor(),
        1.0e-12,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2 },
        (LineGasControls{ .isotopes_retr = &.{ 1, 2 }, .active_stage = .retrieval }).activeIsotopes(),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 2, 4 },
        (LineGasControls{ .isotopes_sim = &.{ 2, 4 } }).activeIsotopes(),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.05),
        (LineGasControls{ .threshold_line_sim = 0.05 }).activeThresholdLine(),
    );
    try std.testing.expectEqual(
        @as(?f64, 12.0),
        (LineGasControls{ .cutoff_sim_cm1 = 12.0 }).activeCutoffCm1(),
    );

    try std.testing.expectError(
        error.InvalidRequest,
        (LineGasControls{ .isotopes_sim = &.{ 1, 1 } }).validate(),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        (LineGasControls{ .cutoff_retr_cm1 = 0.0 }).validate(),
    );
}

test "volume mixing ratio profiles must be strictly monotonic in pressure" {
    try validateVolumeMixingRatioProfile(&.{
        .{ 1000.0, 400.0 },
        .{ 700.0, 250.0 },
        .{ 430.0, 200.0 },
    });
    try validateVolumeMixingRatioProfile(&.{
        .{ 430.0, 200.0 },
        .{ 700.0, 250.0 },
        .{ 1000.0, 400.0 },
    });

    try std.testing.expectError(
        error.InvalidRequest,
        validateVolumeMixingRatioProfile(&.{
            .{ 1000.0, 400.0 },
            .{ 430.0, 200.0 },
            .{ 700.0, 250.0 },
        }),
    );
    try std.testing.expectError(
        error.InvalidRequest,
        validateVolumeMixingRatioProfile(&.{
            .{ 1000.0, 400.0 },
            .{ 1000.0, 350.0 },
        }),
    );
}
