const std = @import("std");
const internal = @import("internal");

const ReferenceData = internal.reference_data;
const ClimatologyPoint = ReferenceData.ClimatologyPoint;
const ClimatologyProfile = ReferenceData.ClimatologyProfile;
const CrossSectionPoint = ReferenceData.CrossSectionPoint;
const CrossSectionTable = ReferenceData.CrossSectionTable;
const CollisionInducedAbsorptionPoint = ReferenceData.CollisionInducedAbsorptionPoint;
const CollisionInducedAbsorptionTable = ReferenceData.CollisionInducedAbsorptionTable;
const AirmassFactorPoint = ReferenceData.AirmassFactorPoint;
const AirmassFactorLut = ReferenceData.AirmassFactorLut;
const MiePhasePoint = ReferenceData.MiePhasePoint;
const MiePhaseTable = ReferenceData.MiePhaseTable;
const SpectroscopyLine = ReferenceData.SpectroscopyLine;
const SpectroscopyLineList = ReferenceData.SpectroscopyLineList;
const SpectroscopyStrongLine = ReferenceData.SpectroscopyStrongLine;
const SpectroscopyStrongLineSet = ReferenceData.SpectroscopyStrongLineSet;
const RelaxationMatrix = ReferenceData.RelaxationMatrix;
const SpectroscopyTraceContributionKind = ReferenceData.SpectroscopyTraceContributionKind;

test "spectroscopy constants preserve vendor weak and strong temperature scaling" {
    try std.testing.expectEqual(
        @as(f64, 1.4387770),
        ReferenceData.spectroscopy.Types.hitran_hc_over_kb_cm_k,
    );
    try std.testing.expectEqual(
        @as(f64, 1.43877696),
        ReferenceData.spectroscopy.Types.hitran_o2_line_mixing_hc_over_kb_cm_k,
    );
}

fn makeLineList(lines: []const SpectroscopyLine) !SpectroscopyLineList {
    return .{ .lines = try std.testing.allocator.dupe(SpectroscopyLine, lines) };
}

fn makeStrongLineSet(lines: []const SpectroscopyStrongLine) !SpectroscopyStrongLineSet {
    return .{ .lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, lines) };
}

fn makeRelaxationMatrix(line_count: usize, wt0: []const f64, bw: []const f64) !RelaxationMatrix {
    return .{
        .line_count = line_count,
        .wt0 = try std.testing.allocator.dupe(f64, wt0),
        .bw = try std.testing.allocator.dupe(f64, bw),
    };
}

fn countRows(trace: ReferenceData.SpectroscopyTrace, kind: SpectroscopyTraceContributionKind) usize {
    var count: usize = 0;
    for (trace.rows) |row| {
        if (row.contribution_kind == kind) count += 1;
    }
    return count;
}

fn applyRuntimeControlsRetryWithAllocator(allocator: std.mem.Allocator) !void {
    var lines = SpectroscopyLineList{
        .lines = try allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 4.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 7, .isotope_number = 2, .center_wavelength_nm = 760.1, .line_strength_cm2_per_molecule = 3.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
        }),
    };
    defer lines.deinit(allocator);

    try lines.applyRuntimeControls(allocator, 7, &.{1}, 0.02, 8.0, 0.4);
    try lines.applyRuntimeControls(allocator, 7, &.{2}, 0.02, 8.0, 0.4);
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

test "collision-induced absorption tables preserve pair-absorption units and interpolate coefficients" {
    var table = CollisionInducedAbsorptionTable{
        .scale_factor_cm5_per_molecule2 = 1.0e-46,
        .points = try std.testing.allocator.dupe(CollisionInducedAbsorptionPoint, &.{
            .{ .wavelength_nm = 760.0, .a0 = 4.0, .a1 = 1.0e-2, .a2 = 0.0 },
            .{ .wavelength_nm = 770.0, .a0 = 8.0, .a1 = 2.0e-2, .a2 = 0.0 },
        }),
    };
    defer table.deinit(std.testing.allocator);

    try std.testing.expect(table.sigmaAt(765.0, 293.15) > table.sigmaAt(760.0, 293.15));
    try std.testing.expectApproxEqAbs(@as(f64, 1.5e-48), table.dSigmaDTemperatureAt(765.0, 293.15), 1e-60);
    try std.testing.expect(table.meanSigmaInRange(760.0, 770.0, 293.15) > 0.0);
}

test "spectroscopy line list evaluates bounded temperature and pressure dependent sigma" {
    var lines = try makeLineList(&.{
        .{ .gas_index = 0, .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.041, .temperature_exponent = 0.69, .lower_state_energy_cm1 = 140.0, .pressure_shift_nm = 0.003, .line_mixing_coefficient = 0.07 },
        .{ .gas_index = 0, .center_wavelength_nm = 441.2, .line_strength_cm2_per_molecule = 9.7e-21, .air_half_width_nm = 0.038, .temperature_exponent = 0.74, .lower_state_energy_cm1 = 165.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.05 },
    });
    defer lines.deinit(std.testing.allocator);

    const near_line = lines.evaluateAt(434.6, 250.0, 750.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 750.0);
    const cold_dense = lines.evaluateAt(434.6, 220.0, 900.0);

    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(cold_dense.total_sigma_cm2_per_molecule != near_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(@abs(near_line.d_sigma_d_temperature_cm2_per_molecule_per_k) > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), near_line.line_mixing_sigma_cm2_per_molecule);
}

test "weak-line sigma treats abundance fraction as metadata for HITRAN strengths" {
    var reference = try makeLineList(&.{
        .{
            .gas_index = 7,
            .isotope_number = 1,
            .abundance_fraction = 0.995262,
            .center_wavelength_nm = 771.3015,
            .line_strength_cm2_per_molecule = 1.20e-20,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .lower_state_energy_cm1 = 1804.8773,
            .pressure_shift_nm = 0.00053,
            .line_mixing_coefficient = 0.03,
        },
    });
    defer reference.deinit(std.testing.allocator);

    var metadata_only = try makeLineList(&.{
        .{
            .gas_index = 7,
            .isotope_number = 1,
            .abundance_fraction = 0.0039914,
            .center_wavelength_nm = 771.3015,
            .line_strength_cm2_per_molecule = 1.20e-20,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .lower_state_energy_cm1 = 1804.8773,
            .pressure_shift_nm = 0.00053,
            .line_mixing_coefficient = 0.03,
        },
    });
    defer metadata_only.deinit(std.testing.allocator);

    const reference_eval = reference.evaluateAt(771.3015, 255.0, 820.0);
    const metadata_only_eval = metadata_only.evaluateAt(771.3015, 255.0, 820.0);

    try std.testing.expect(reference_eval.total_sigma_cm2_per_molecule > 0.0);
    try std.testing.expectApproxEqAbs(
        reference_eval.total_sigma_cm2_per_molecule,
        metadata_only_eval.total_sigma_cm2_per_molecule,
        1.0e-18,
    );
}

test "o2 spectroscopy uses vendor-tabulated partition ratios" {
    var lines = try makeLineList(&.{
        .{
            .gas_index = 7,
            .isotope_number = 1,
            .abundance_fraction = 0.995262,
            .center_wavelength_nm = 771.3015,
            .line_strength_cm2_per_molecule = 1.20e-20,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .lower_state_energy_cm1 = 1804.8773,
            .pressure_shift_nm = 0.00053,
            .line_mixing_coefficient = 0.03,
        },
    });
    defer lines.deinit(std.testing.allocator);

    const warm = lines.evaluateAt(771.3015, 296.0, 820.0);
    const cold = lines.evaluateAt(771.3015, 260.0, 820.0);
    try std.testing.expect(cold.total_sigma_cm2_per_molecule > warm.total_sigma_cm2_per_molecule);
}

test "vendor-covered gas and isotope mappings reach partition tables beyond o2" {
    const representative_lines = [_]SpectroscopyLine{
        .{ .gas_index = 1, .isotope_number = 1, .center_wavelength_nm = 720.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 2, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 5, .isotope_number = 1, .center_wavelength_nm = 4800.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 6, .isotope_number = 1, .center_wavelength_nm = 2300.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        .{ .gas_index = 11, .isotope_number = 1, .center_wavelength_nm = 640.0, .line_strength_cm2_per_molecule = 1.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
    };

    for (representative_lines) |line| {
        var line_list = try makeLineList(&.{line});
        defer line_list.deinit(std.testing.allocator);

        const warm = line_list.evaluateAt(line.center_wavelength_nm, 296.0, 820.0);
        const cold = line_list.evaluateAt(line.center_wavelength_nm, 260.0, 820.0);
        try std.testing.expect(cold.total_sigma_cm2_per_molecule > warm.total_sigma_cm2_per_molecule);
    }
}

test "weak-line evaluation narrows heavier isotopologues through vendor molecular weights" {
    const common = SpectroscopyLine{
        .gas_index = 7,
        .abundance_fraction = 1.0,
        .center_wavelength_nm = 771.3015,
        .line_strength_cm2_per_molecule = 1.20e-20,
        .air_half_width_nm = 0.00164,
        .temperature_exponent = 0.63,
        .lower_state_energy_cm1 = 1804.8773,
        .pressure_shift_nm = 0.00053,
        .line_mixing_coefficient = 0.03,
    };

    var lighter = try makeLineList(&.{
        common,
    });
    defer lighter.deinit(std.testing.allocator);
    lighter.lines[0].isotope_number = 1;

    var heavier = try makeLineList(&.{
        common,
    });
    defer heavier.deinit(std.testing.allocator);
    heavier.lines[0].isotope_number = 2;

    const lighter_eval = lighter.evaluateAt(common.center_wavelength_nm, 255.0, 820.0);
    const heavier_eval = heavier.evaluateAt(common.center_wavelength_nm, 255.0, 820.0);

    try std.testing.expect(heavier_eval.total_sigma_cm2_per_molecule > lighter_eval.total_sigma_cm2_per_molecule);
}

test "runtime controls filter gas and isotope selections and disable O2-only sidecars" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 4.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 7, .isotope_number = 2, .center_wavelength_nm = 760.1, .line_strength_cm2_per_molecule = 3.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.05 },
            .{ .gas_index = 2, .isotope_number = 1, .center_wavelength_nm = 760.2, .line_strength_cm2_per_molecule = 2.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 100.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
        }),
        .strong_lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 1.0e7 / 760.0,
                .center_wavelength_nm = 760.0,
                .population_t0 = 1.0,
                .dipole_ratio = 1.0,
                .dipole_t0 = 1.0,
                .lower_state_energy_cm1 = 100.0,
                .air_half_width_cm1 = 0.01,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.7,
                .pressure_shift_cm1 = 0.0,
                .pressure_shift_nm = 0.0,
                .rotational_index_m1 = 0,
            },
        }),
        .relaxation_matrix = .{
            .line_count = 1,
            .wt0 = try std.testing.allocator.dupe(f64, &.{1.0}),
            .bw = try std.testing.allocator.dupe(f64, &.{1.0}),
        },
    };
    defer lines.deinit(std.testing.allocator);

    try lines.applyRuntimeControls(std.testing.allocator, 7, &.{2}, 0.02, 8.0, 0.4);
    try std.testing.expectEqual(@as(usize, 1), lines.lines.len);
    try std.testing.expectEqual(@as(u8, 2), lines.lines[0].isotope_number);
    try std.testing.expect(lines.strong_lines == null);
    try std.testing.expect(lines.relaxation_matrix == null);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0e-23), lines.runtime_controls.thresholdStrength(lines.lines).?, 1.0e-30);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), lines.runtime_controls.cutoff_cm1.?, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), lines.runtime_controls.line_mixing_factor, 1.0e-12);
}

test "runtime controls preserve prior isotope storage across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        applyRuntimeControlsRetryWithAllocator,
        .{},
    );
}

test "spectroscopy line list partitions strong and weak lanes when sidecars are attached" {
    var lines = try makeLineList(&.{
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.2004, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1803.1765, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 769.9000, .line_strength_cm2_per_molecule = 2.50e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00, .branch_ic1 = 4, .branch_ic2 = 1, .rotational_nf = 40 },
    });
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
        .{
            .center_wavenumber_cm1 = 12966.8087,
            .center_wavelength_nm = 771.2004,
            .population_t0 = 4.99e-05,
            .dipole_ratio = -0.702,
            .dipole_t0 = -5.78e-04,
            .lower_state_energy_cm1 = 1803.1765,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -34,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(
        2,
        &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        },
        &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        },
    );
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const trace = try lines.traceAt(std.testing.allocator, 771.25, 255.0, 820.0, null);
    defer trace.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), countRows(trace, .strong_sidecar));
    try std.testing.expectEqual(@as(usize, 2), trace.rows[trace.rows.len - 1].strong_index.?);
    try std.testing.expect(trace.evaluation.weak_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(trace.evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(trace.evaluation.line_mixing_sigma_cm2_per_molecule) > 0.0);
}

test "strong-line sidecars choose one anchor line per strong feature" {
    var lines = try makeLineList(&.{
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594000, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594150, .line_strength_cm2_per_molecule = 2.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594260, .line_strength_cm2_per_molecule = 3.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 33, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.594500, .line_strength_cm2_per_molecule = 1.5e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 32, .vendor_filter_metadata_from_source = true },
    });
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 13165.0,
            .center_wavelength_nm = 759.594260,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(
        1,
        &.{0.02764486},
        &.{0.629999646133},
    );
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const trace = try lines.traceAt(std.testing.allocator, 759.594260, 255.0, 820.0, null);
    defer trace.deinit(std.testing.allocator);

    var strong_rows: usize = 0;
    var vendor_excluded_rows: usize = 0;
    for (trace.rows) |row| {
        switch (row.contribution_kind) {
            .strong_sidecar => {
                strong_rows += 1;
                try std.testing.expectEqual(@as(?usize, 2), row.global_line_index);
                try std.testing.expectEqual(@as(?usize, 0), row.strong_index);
            },
            .weak_excluded_vendor_partition => vendor_excluded_rows += 1,
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), strong_rows);
    try std.testing.expectEqual(@as(usize, 4), vendor_excluded_rows);
}

test "cutoff-based prewindow keeps far-wing O2A lines beyond one nanometer" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03 },
        }),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer lines.deinit(std.testing.allocator);

    const far_wing = lines.evaluateAt(775.0, 255.0, 820.0);
    try std.testing.expect(far_wing.total_sigma_cm2_per_molecule > 0.0);
}

test "O2A cutoff matches vendor nearest-grid weak-line boundary" {
    const boundary_line = SpectroscopyLine{
        .gas_index = 7,
        .isotope_number = 2,
        .center_wavelength_nm = 761.1959797053734,
        .line_strength_cm2_per_molecule = 1.385e-26,
        .air_half_width_nm = 0.0029955978819164518,
        .temperature_exponent = 0.74,
        .lower_state_energy_cm1 = 26.9889,
        .pressure_shift_nm = 0.00041138771685893244,
        .line_mixing_coefficient = 0.13733075435203096,
    };
    const excluded_boundary_line = SpectroscopyLine{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 761.002145522267,
        .line_strength_cm2_per_molecule = 7.311e-24,
        .air_half_width_nm = 0.002843500143553414,
        .temperature_exponent = 0.74,
        .lower_state_energy_cm1 = 81.5805,
        .pressure_shift_nm = 0.0003561614232760386,
        .line_mixing_coefficient = 0.12525458248472507,
    };
    const second_included_boundary_line = SpectroscopyLine{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 761.138995010687,
        .line_strength_cm2_per_molecule = 7.984e-24,
        .air_half_width_nm = 0.0029372161285102037,
        .temperature_exponent = 0.73,
        .lower_state_energy_cm1 = 42.224,
        .pressure_shift_nm = 0.00041132612450537367,
        .line_mixing_coefficient = 0.14003944773175542,
    };
    const grid_excluded_boundary_line = SpectroscopyLine{
        .gas_index = 7,
        .isotope_number = 1,
        .center_wavelength_nm = 760.885417768841,
        .line_strength_cm2_per_molecule = 8.762e-24,
        .air_half_width_nm = 0.0028426278991587244,
        .temperature_exponent = 0.74,
        .lower_state_energy_cm1 = 79.5646,
        .pressure_shift_nm = 0.00042263103185048246,
        .line_mixing_coefficient = 0.14867617107942974,
    };
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{boundary_line}),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer lines.deinit(std.testing.allocator);

    const vendor_boundary_sample_nm = 772.969173559943;
    const trace = try lines.traceAt(
        std.testing.allocator,
        vendor_boundary_sample_nm,
        294.2,
        1013.0,
        null,
    );
    defer trace.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), trace.rows.len);
    try std.testing.expectEqual(.weak_included, trace.rows[0].contribution_kind);
    try std.testing.expect(trace.evaluation.total_sigma_cm2_per_molecule > 0.0);

    var second_included_lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{second_included_boundary_line}),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer second_included_lines.deinit(std.testing.allocator);

    const second_included_sample_nm = 772.9113261319951;
    const second_included = second_included_lines.evaluateAt(
        second_included_sample_nm,
        294.2,
        1013.0,
    );
    try std.testing.expect(second_included.total_sigma_cm2_per_molecule > 0.0);

    var excluded_lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{excluded_boundary_line}),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    defer excluded_lines.deinit(std.testing.allocator);

    const excluded_boundary_sample_nm = 772.771013862351;
    const excluded = excluded_lines.evaluateAt(
        excluded_boundary_sample_nm,
        294.2,
        1013.0,
    );
    try std.testing.expectEqual(@as(f64, 0.0), excluded.total_sigma_cm2_per_molecule);

    const vendor_cutoff_grid_nm = [_]f64{
        1.0e7 / 13342.6,
        1.0e7 / 12942.64,
        772.6493541560737,
        1.0e7 / 12938.35,
        772.9113261319951,
    };

    var grid_excluded_lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{grid_excluded_boundary_line}),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    errdefer grid_excluded_lines.deinit(std.testing.allocator);
    grid_excluded_lines.runtime_controls.cutoff_grid_wavelengths_nm =
        try std.testing.allocator.dupe(f64, vendor_cutoff_grid_nm[0..]);
    defer grid_excluded_lines.deinit(std.testing.allocator);

    const grid_excluded = grid_excluded_lines.evaluateAt(
        772.6493541560737,
        294.2,
        1013.0,
    );
    try std.testing.expectEqual(@as(f64, 0.0), grid_excluded.total_sigma_cm2_per_molecule);

    var grid_included_lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{second_included_boundary_line}),
        .lines_sorted_ascending = true,
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
    };
    errdefer grid_included_lines.deinit(std.testing.allocator);
    grid_included_lines.runtime_controls.cutoff_grid_wavelengths_nm =
        try std.testing.allocator.dupe(f64, vendor_cutoff_grid_nm[0..]);
    defer grid_included_lines.deinit(std.testing.allocator);

    const grid_included = grid_included_lines.evaluateAt(
        772.9113261319951,
        294.2,
        1013.0,
    );
    try std.testing.expect(grid_included.total_sigma_cm2_per_molecule > 0.0);
}

test "vendor O2A partition removes every assigned strong candidate from the weak-line sum" {
    const strong_candidate_a = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true };
    const strong_candidate_b = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.2004, .line_strength_cm2_per_molecule = 1.15e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1803.1765, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34, .vendor_filter_metadata_from_source = true };
    const weak_candidate = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.0500, .line_strength_cm2_per_molecule = 1.10e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00, .branch_ic1 = 4, .branch_ic2 = 1, .rotational_nf = 40 };

    var lines = try makeLineList(&.{ strong_candidate_a, strong_candidate_b, weak_candidate });
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);

    const evaluation = lines.evaluateAt(771.25, 255.0, 820.0);
    var weak_only_view = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{weak_candidate}),
        .runtime_controls = lines.runtime_controls,
    };
    defer weak_only_view.deinit(std.testing.allocator);
    const weak_only = weak_only_view.evaluateAt(771.25, 255.0, 820.0);

    try std.testing.expectApproxEqRel(
        weak_only.line_sigma_cm2_per_molecule,
        evaluation.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );
    try std.testing.expect(evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
}

test "fallback strong-line anchors can preserve weak contributions when requested" {
    const anchor_proxy = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03 };
    const weak_neighbor = SpectroscopyLine{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.0500, .line_strength_cm2_per_molecule = 1.10e-21, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00 };

    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{ anchor_proxy, weak_neighbor }),
        .runtime_controls = .{ .cutoff_cm1 = 200.0 },
        .preserve_anchor_weak_lines = true,
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try lines.buildStrongLineMatchIndex(std.testing.allocator);

    const preserved = lines.evaluateAt(771.25, 255.0, 820.0);
    const weak_only_view = SpectroscopyLineList{
        .lines = lines.lines,
        .lines_sorted_ascending = lines.lines_sorted_ascending,
        .runtime_controls = lines.runtime_controls,
    };
    const weak_only = weak_only_view.evaluateAt(771.25, 255.0, 820.0);

    try std.testing.expectApproxEqRel(
        weak_only.weak_line_sigma_cm2_per_molecule,
        preserved.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );
    try std.testing.expect(preserved.strong_line_sigma_cm2_per_molecule > 0.0);
}

test "vendor strong-line partitions ignore nearby O2 lines without vendor metadata" {
    var lines = try makeLineList(&.{
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3019, .line_strength_cm2_per_molecule = 8.50e-22, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00 },
    });
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try lines.buildStrongLineMatchIndex(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lines.strong_lines.?.len);
    try std.testing.expectEqual(@as(usize, 2), lines.strong_line_match_by_line.?.len);
    try std.testing.expectEqual(@as(?u16, 0), lines.strong_line_match_by_line.?[0]);
    try std.testing.expectEqual(@as(?u16, null), lines.strong_line_match_by_line.?[1]);
}

test "vendor O2A partition keeps matched fallback metadata rows in the weak lane" {
    var lines = try makeLineList(&.{
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.20e-20, .air_half_width_nm = 0.00164, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1804.8773, .pressure_shift_nm = 0.00053, .line_mixing_coefficient = 0.03, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3018, .line_strength_cm2_per_molecule = 8.50e-22, .air_half_width_nm = 0.00110, .temperature_exponent = 0.58, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.00020, .line_mixing_coefficient = 0.00, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34, .vendor_filter_metadata_from_source = false },
    });
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try lines.buildStrongLineMatchIndex(std.testing.allocator);

    try std.testing.expectEqual(@as(?u16, 0), lines.strong_line_match_by_line.?[0]);
    try std.testing.expectEqual(@as(?u16, null), lines.strong_line_match_by_line.?[1]);

    const trace = try lines.traceAt(std.testing.allocator, 771.3016, 255.0, 820.0, null);
    defer trace.deinit(std.testing.allocator);

    var saw_fallback_weak = false;
    for (trace.rows) |row| {
        if (row.global_line_index != 1) continue;
        try std.testing.expectEqual(SpectroscopyTraceContributionKind.weak_included, row.contribution_kind);
        saw_fallback_weak = true;
    }
    try std.testing.expect(saw_fallback_weak);
}

test "vendor O2A strong candidates fail fast when they cannot be matched to a sidecar" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.0, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnmatchedStrongLineCandidate,
        lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix),
    );
}

test "vendor O2A sidecars remain active even when some vendor sidecars have no weak-line anchor" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
        .{
            .center_wavenumber_cm1 = 12966.8087,
            .center_wavelength_nm = 771.2004,
            .population_t0 = 4.99e-05,
            .dipole_ratio = -0.702,
            .dipole_t0 = -5.78e-04,
            .lower_state_energy_cm1 = 1803.1765,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -34,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(
        2,
        &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        },
        &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        },
    );
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try std.testing.expectEqual(@as(usize, 2), lines.strong_lines.?.len);

    var prepared_state = (try lines.prepareStrongLineState(std.testing.allocator, 255.0, 820.0)).?;
    defer prepared_state.deinit(std.testing.allocator);

    const evaluation = lines.evaluateAtPrepared(771.25, 255.0, 820.0, &prepared_state);
    try std.testing.expect(evaluation.strong_line_sigma_cm2_per_molecule > 0.0);
    try std.testing.expect(@abs(evaluation.line_mixing_sigma_cm2_per_molecule) > 0.0);
}

test "vendor O2A partition keeps unmatched vendor strong candidates in the weak lane" {
    var lines = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 771.3015, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.0015, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1800.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 35, .vendor_filter_metadata_from_source = true },
            .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 764.4800, .line_strength_cm2_per_molecule = 8.0e-21, .air_half_width_nm = 0.0012, .temperature_exponent = 0.63, .lower_state_energy_cm1 = 1790.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0, .branch_ic1 = 5, .branch_ic2 = 1, .rotational_nf = 34, .vendor_filter_metadata_from_source = false },
        }),
    };
    defer lines.deinit(std.testing.allocator);

    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var relaxation_matrix = try makeRelaxationMatrix(1, &.{0.02764486}, &.{0.629999646133});
    defer relaxation_matrix.deinit(std.testing.allocator);

    try lines.attachStrongLineSidecars(std.testing.allocator, strong_lines, relaxation_matrix);
    try lines.buildStrongLineMatchIndex(std.testing.allocator);

    try std.testing.expectEqual(@as(?u16, 0), lines.strong_line_match_by_line.?[0]);
    try std.testing.expectEqual(@as(?u16, null), lines.strong_line_match_by_line.?[1]);

    const evaluation = lines.evaluateAt(764.48, 255.0, 820.0);
    try std.testing.expect(evaluation.weak_line_sigma_cm2_per_molecule > 0.0);
}

test "strong-line convtp state applies detailed-balance and pressure-scaled line mixing" {
    var line_list = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{}),
        .strong_lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
        .relaxation_matrix = try makeRelaxationMatrix(
            2,
            &.{
                0.02764486,
                0.0004338554,
                0.0004338554,
                0.02655312,
            },
            &.{
                0.629999646133,
                1.169364903905,
                1.169364903905,
                0.629999646133,
            },
        ),
    };
    defer line_list.deinit(std.testing.allocator);

    const low_pressure = (try line_list.prepareStrongLineState(std.testing.allocator, 255.0, 0.5)).?;
    defer low_pressure.deinit(std.testing.allocator);
    const high_pressure = (try line_list.prepareStrongLineState(std.testing.allocator, 255.0, 1.0)).?;
    defer high_pressure.deinit(std.testing.allocator);

    try std.testing.expect(low_pressure.population_t[0] > 0.0);
    try std.testing.expect(@abs(low_pressure.relaxation_weights[1] - low_pressure.relaxation_weights[2]) > 1.0e-10);
    try std.testing.expect(@abs(high_pressure.line_mixing_coefficients[0]) > @abs(low_pressure.line_mixing_coefficients[0]));
    try std.testing.expect(high_pressure.half_width_cm1_at_t[0] > line_list.relaxation_matrix.?.weightAt(0, 0));
}

test "prepared strong-line state preserves upper-atmosphere pressure scaling" {
    var line_list = SpectroscopyLineList{
        .lines = try std.testing.allocator.dupe(SpectroscopyLine, &.{}),
        .strong_lines = try std.testing.allocator.dupe(SpectroscopyStrongLine, &.{
            .{
                .center_wavenumber_cm1 = 12965.1079,
                .center_wavelength_nm = 771.3015,
                .population_t0 = 5.10e-05,
                .dipole_ratio = 0.712,
                .dipole_t0 = 5.80e-04,
                .lower_state_energy_cm1 = 1804.8773,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -35,
            },
            .{
                .center_wavenumber_cm1 = 12966.8087,
                .center_wavelength_nm = 771.2004,
                .population_t0 = 4.99e-05,
                .dipole_ratio = -0.702,
                .dipole_t0 = -5.78e-04,
                .lower_state_energy_cm1 = 1803.1765,
                .air_half_width_cm1 = 0.0276,
                .air_half_width_nm = 0.00164,
                .temperature_exponent = 0.63,
                .pressure_shift_cm1 = -0.009,
                .pressure_shift_nm = 0.00053,
                .rotational_index_m1 = -34,
            },
        }),
        .relaxation_matrix = try makeRelaxationMatrix(
            2,
            &.{
                0.02764486,
                0.0004338554,
                0.0004338554,
                0.02655312,
            },
            &.{
                0.629999646133,
                1.169364903905,
                1.169364903905,
                0.629999646133,
            },
        ),
    };
    defer line_list.deinit(std.testing.allocator);

    var prepared_state = (try line_list.prepareStrongLineState(std.testing.allocator, 190.5, 0.000258)).?;
    defer prepared_state.deinit(std.testing.allocator);

    const pressure_atm = 0.000258 / 1013.25;
    const strong_lines = line_list.strong_lines.?;
    try std.testing.expectApproxEqAbs(
        strong_lines[0].center_wavenumber_cm1 + pressure_atm * strong_lines[0].pressure_shift_cm1,
        prepared_state.mod_sig_cm1[0],
        1.0e-12,
    );
    try std.testing.expect(prepared_state.half_width_cm1_at_t[0] > 0.0);

    const prepared_trace = try line_list.traceAt(std.testing.allocator, 771.25, 190.5, 0.000258, &prepared_state);
    defer prepared_trace.deinit(std.testing.allocator);
    const unprepared_trace = try line_list.traceAt(std.testing.allocator, 771.25, 190.5, 0.000258, null);
    defer unprepared_trace.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(
        unprepared_trace.evaluation.total_sigma_cm2_per_molecule,
        prepared_trace.evaluation.total_sigma_cm2_per_molecule,
        1.0e-18,
    );
}

test "demo reference assets are allocatable and physically ordered" {
    var profile = try ReferenceData.buildDemoClimatology(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try ReferenceData.buildDemoCrossSections(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try ReferenceData.buildDemoSpectroscopyLines(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try ReferenceData.buildDemoAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    try std.testing.expect(profile.rows.len >= 4);
    try std.testing.expect(cross_sections.points[0].wavelength_nm < cross_sections.points[cross_sections.points.len - 1].wavelength_nm);
    try std.testing.expect(spectroscopy.lines.len >= 4);
    try std.testing.expect(lut.points.len >= 3);
}

test "mie phase tables interpolate extinction, SSA, and coefficients deterministically" {
    var table = MiePhaseTable{
        .points = try std.testing.allocator.dupe(MiePhasePoint, &.{
            .{ .wavelength_nm = 400.0, .extinction_scale = 0.96, .single_scatter_albedo = 0.85, .phase_coefficients = .{ 1.0, 2.38, 3.47, 4.32 } },
            .{ .wavelength_nm = 500.0, .extinction_scale = 0.99, .single_scatter_albedo = 0.92, .phase_coefficients = .{ 1.0, 2.26, 3.25, 3.96 } },
        }),
    };
    defer table.deinit(std.testing.allocator);

    const interpolated = table.interpolate(450.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.975), interpolated.extinction_scale, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 2.32), interpolated.phase_coefficients[1], 1e-9);
    try std.testing.expectEqual(@as(f64, 1.0), interpolated.phase_coefficients[0]);
    try std.testing.expect(interpolated.single_scatter_albedo > 0.85);
}

test "strong-line sidecars and relaxation matrices stay typed and square" {
    var strong_lines = try makeStrongLineSet(&.{
        .{
            .center_wavenumber_cm1 = 12965.1079,
            .center_wavelength_nm = 771.3015,
            .population_t0 = 5.10e-05,
            .dipole_ratio = 0.712,
            .dipole_t0 = 5.80e-04,
            .lower_state_energy_cm1 = 1804.8773,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -35,
        },
        .{
            .center_wavenumber_cm1 = 12966.8087,
            .center_wavelength_nm = 771.2004,
            .population_t0 = 4.99e-05,
            .dipole_ratio = -0.702,
            .dipole_t0 = -5.78e-04,
            .lower_state_energy_cm1 = 1803.1765,
            .air_half_width_cm1 = 0.0276,
            .air_half_width_nm = 0.00164,
            .temperature_exponent = 0.63,
            .pressure_shift_cm1 = -0.009,
            .pressure_shift_nm = 0.00053,
            .rotational_index_m1 = -34,
        },
    });
    defer strong_lines.deinit(std.testing.allocator);

    var matrix = try makeRelaxationMatrix(
        2,
        &.{
            0.02764486,
            0.0004338554,
            0.0004338554,
            0.02655312,
        },
        &.{
            0.629999646133,
            1.169364903905,
            1.169364903905,
            0.629999646133,
        },
    );
    defer matrix.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), strong_lines.lines.len);
    try std.testing.expectEqual(@as(usize, 2), matrix.line_count);
    try std.testing.expect(matrix.weightAt(0, 0) > matrix.weightAt(0, 1));
    try std.testing.expect(matrix.temperatureExponentAt(0, 1) > 0.0);
}
