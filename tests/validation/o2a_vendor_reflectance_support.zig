const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.prepare;
const MeasurementSpace = internal.kernels.transport.measurement_space;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

pub const ReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    reflectance: f64,
};

pub const RangeExtremum = struct {
    wavelength_nm: f64,
    value: f64,
};

pub const ComparisonMetrics = struct {
    sample_count: usize,
    nonzero_sample_count: usize,
    exact_match_within_zero_tolerance: bool,
    mean_signed_difference: f64,
    mean_abs_difference: f64,
    root_mean_square_difference: f64,
    max_abs_difference: f64,
    max_abs_difference_wavelength_nm: f64,
    correlation: f64,
    blue_wing_mean_difference: f64,
    trough_wavelength_difference_nm: f64,
    trough_value_difference: f64,
    rebound_peak_difference: f64,
    mid_band_mean_difference: f64,
    red_wing_mean_difference: f64,
};

pub const TrendTolerances = struct {
    mean_abs_difference_abs: f64,
    root_mean_square_difference_abs: f64,
    max_abs_difference_abs: f64,
    correlation_abs: f64,
    blue_wing_mean_difference_abs: f64 = 1.0e-6,
    trough_wavelength_difference_nm_abs: f64 = 1.0e-6,
    trough_value_difference_abs: f64 = 1.0e-6,
    rebound_peak_difference_abs: f64 = 1.0e-6,
    mid_band_mean_difference_abs: f64 = 1.0e-6,
    red_wing_mean_difference_abs: f64 = 1.0e-6,
};

pub const TrendState = enum {
    improved,
    flat,
    regressed,
};

pub const AssessmentVerdict = enum {
    exact_zero_pass,
    baseline_pass,
    regression_fail,
    nonzero_fail,
};

pub const AssessmentTrend = struct {
    mean_abs_difference: TrendState,
    root_mean_square_difference: TrendState,
    max_abs_difference: TrendState,
    correlation: TrendState,
    blue_wing_mean_difference: TrendState,
    trough_wavelength_difference_nm: TrendState,
    trough_value_difference: TrendState,
    rebound_peak_difference: TrendState,
    mid_band_mean_difference: TrendState,
    red_wing_mean_difference: TrendState,
};

pub const AssessmentOutcome = struct {
    verdict: AssessmentVerdict,
    trend: AssessmentTrend,
};

pub const VendorO2AReflectanceCase = struct {
    reference: []ReferenceSample,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,

    pub fn deinit(self: *VendorO2AReflectanceCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }
};

pub const VendorO2AExecutionConfig = struct {
    spectral_grid: zdisamar.SpectralGrid = .{
        .start_nm = 755.0,
        .end_nm = 776.0,
        .sample_count = 701,
    },
    layer_count: u32 = 48,
    sublayer_divisions: u8 = 4,
    line_mixing_factor: ?f64 = 1.0,
    isotopes_sim: []const u8 = &.{},
    threshold_line_sim: ?f64 = null,
    cutoff_sim_cm1: ?f64 = null,
    adaptive_points_per_fwhm: u16 = 0,
    adaptive_strong_line_min_divisions: u16 = 0,
    adaptive_strong_line_max_divisions: u16 = 0,
    include_cia: bool = true,
};

pub fn zeroContinuumTable(
    allocator: std.mem.Allocator,
    start_nm: f64,
    end_nm: f64,
) !ReferenceData.CrossSectionTable {
    const midpoint_nm = (start_nm + end_nm) * 0.5;
    return .{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = start_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = end_nm, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
}

pub fn meanOpticalDepthInRange(
    prepared: *const OpticsPrepare.PreparedOpticalState,
    start_nm: f64,
    end_nm: f64,
    step_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    var wavelength_nm = start_nm;
    while (wavelength_nm <= end_nm + (step_nm * 0.5)) : (wavelength_nm += step_nm) {
        sum += prepared.totalOpticalDepthAtWavelength(wavelength_nm);
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn meanVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        sum += value;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn minVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) RangeExtremum {
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) {
            best = value;
            best_wavelength = wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

pub fn maxVectorInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = -std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value > best) best = value;
    }
    return best;
}

pub fn loadReferenceSamples(allocator: std.mem.Allocator, path: []const u8) ![]ReferenceSample {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(ReferenceSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;
        _ = columns.next() orelse return error.InvalidData;
        const reflectance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
            .reflectance = try std.fmt.parseFloat(f64, std.mem.trim(u8, reflectance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

pub fn meanReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var sum: f64 = 0.0;
    var count: usize = 0;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        sum += sample.reflectance;
        count += 1;
    }
    return if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count));
}

pub fn minReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) RangeExtremum {
    var best = std.math.inf(f64);
    var best_wavelength = start_nm;
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance < best) {
            best = sample.reflectance;
            best_wavelength = sample.wavelength_nm;
        }
    }
    return .{ .wavelength_nm = best_wavelength, .value = best };
}

pub fn maxReferenceInRange(
    reference: []const ReferenceSample,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = -std.math.inf(f64);
    for (reference) |sample| {
        if (sample.wavelength_nm < start_nm or sample.wavelength_nm > end_nm) continue;
        if (sample.reflectance > best) best = sample.reflectance;
    }
    return best;
}

pub fn interpolateVector(
    wavelengths_nm: []const f64,
    values: []const f64,
    target_wavelength_nm: f64,
) f64 {
    if (wavelengths_nm.len == 0 or values.len == 0) return 0.0;
    if (target_wavelength_nm <= wavelengths_nm[0]) return values[0];
    if (target_wavelength_nm >= wavelengths_nm[wavelengths_nm.len - 1]) return values[values.len - 1];

    var lower_index: usize = 0;
    while (lower_index + 1 < wavelengths_nm.len and wavelengths_nm[lower_index + 1] < target_wavelength_nm) : (lower_index += 1) {}

    const upper_index = lower_index + 1;
    const lower_wavelength = wavelengths_nm[lower_index];
    const upper_wavelength = wavelengths_nm[upper_index];
    const lower_value = values[lower_index];
    const upper_value = values[upper_index];
    const blend = (target_wavelength_nm - lower_wavelength) / (upper_wavelength - lower_wavelength);
    return lower_value + (upper_value - lower_value) * blend;
}

pub fn meanAbsoluteDifference(values_a: []const f64, values_b: []const f64) f64 {
    var sum: f64 = 0.0;
    for (values_a, values_b) |value_a, value_b| {
        sum += @abs(value_a - value_b);
    }
    return sum / @as(f64, @floatFromInt(values_a.len));
}

pub fn compareLowerIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    if (current < baseline - tolerance) return .improved;
    if (current > baseline + tolerance) return .regressed;
    return .flat;
}

pub fn compareHigherIsBetter(current: f64, baseline: f64, tolerance: f64) TrendState {
    if (current > baseline + tolerance) return .improved;
    if (current < baseline - tolerance) return .regressed;
    return .flat;
}

pub fn compareAbsoluteCeiling(current: f64, ceiling: f64) TrendState {
    if (current > ceiling) return .regressed;
    return .flat;
}

pub fn assessAgainstBaseline(
    current: ComparisonMetrics,
    baseline: ComparisonMetrics,
    tolerances: TrendTolerances,
    allowed_to_fail: bool,
) AssessmentOutcome {
    const trend: AssessmentTrend = .{
        .mean_abs_difference = compareLowerIsBetter(
            current.mean_abs_difference,
            baseline.mean_abs_difference,
            tolerances.mean_abs_difference_abs,
        ),
        .root_mean_square_difference = compareLowerIsBetter(
            current.root_mean_square_difference,
            baseline.root_mean_square_difference,
            tolerances.root_mean_square_difference_abs,
        ),
        .max_abs_difference = compareLowerIsBetter(
            current.max_abs_difference,
            baseline.max_abs_difference,
            tolerances.max_abs_difference_abs,
        ),
        .correlation = compareHigherIsBetter(
            current.correlation,
            baseline.correlation,
            tolerances.correlation_abs,
        ),
        // Keep morphology trends sensitive to any baseline improvement while
        // enforcing the broader absolute ceilings separately below.
        .blue_wing_mean_difference = compareLowerIsBetter(
            @abs(current.blue_wing_mean_difference),
            @abs(baseline.blue_wing_mean_difference),
            0.0,
        ),
        .trough_wavelength_difference_nm = compareLowerIsBetter(
            @abs(current.trough_wavelength_difference_nm),
            @abs(baseline.trough_wavelength_difference_nm),
            0.0,
        ),
        .trough_value_difference = compareLowerIsBetter(
            @abs(current.trough_value_difference),
            @abs(baseline.trough_value_difference),
            0.0,
        ),
        .rebound_peak_difference = compareLowerIsBetter(
            @abs(current.rebound_peak_difference),
            @abs(baseline.rebound_peak_difference),
            0.0,
        ),
        .mid_band_mean_difference = compareLowerIsBetter(
            @abs(current.mid_band_mean_difference),
            @abs(baseline.mid_band_mean_difference),
            0.0,
        ),
        .red_wing_mean_difference = compareLowerIsBetter(
            @abs(current.red_wing_mean_difference),
            @abs(baseline.red_wing_mean_difference),
            0.0,
        ),
    };

    const morphology_ceiling_regressed =
        compareAbsoluteCeiling(@abs(current.blue_wing_mean_difference), tolerances.blue_wing_mean_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.trough_wavelength_difference_nm), tolerances.trough_wavelength_difference_nm_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.trough_value_difference), tolerances.trough_value_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.rebound_peak_difference), tolerances.rebound_peak_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.mid_band_mean_difference), tolerances.mid_band_mean_difference_abs) == .regressed or
        compareAbsoluteCeiling(@abs(current.red_wing_mean_difference), tolerances.red_wing_mean_difference_abs) == .regressed;

    if (current.exact_match_within_zero_tolerance) {
        return .{
            .verdict = .exact_zero_pass,
            .trend = trend,
        };
    }

    if (!allowed_to_fail) {
        return .{
            .verdict = .nonzero_fail,
            .trend = trend,
        };
    }

    if (trend.mean_abs_difference == .regressed or
        trend.root_mean_square_difference == .regressed or
        trend.max_abs_difference == .regressed or
        trend.correlation == .regressed or
        morphology_ceiling_regressed)
    {
        return .{
            .verdict = .regression_fail,
            .trend = trend,
        };
    }

    return .{
        .verdict = .baseline_pass,
        .trend = trend,
    };
}

pub fn expectBoundedO2AMorphology(
    wavelengths_nm: []const f64,
    reflectance: []const f64,
) !void {
    const blue_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 755.0, 758.5);
    const trough = minVectorInRange(wavelengths_nm, reflectance, 760.2, 761.1);
    const rebound_peak = maxVectorInRange(wavelengths_nm, reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(wavelengths_nm, reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(wavelengths_nm, reflectance, 769.5, 771.0);
    const trough_ratio = trough.value / @max(blue_wing_mean, 1.0e-12);

    try std.testing.expect(blue_wing_mean > 0.0);
    try std.testing.expect(trough.value > 0.0);
    try std.testing.expect(rebound_peak > trough.value);
    try std.testing.expect(mid_band_mean > trough.value);
    try std.testing.expect(red_wing_mean > trough.value);
    try std.testing.expect(trough_ratio > 0.01);
    try std.testing.expect(trough_ratio < 0.18);
}

pub fn computeComparisonMetrics(
    product: *const MeasurementSpace.MeasurementSpaceProduct,
    reference: []const ReferenceSample,
    zero_tolerance_abs: f64,
) ComparisonMetrics {
    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 755.0, 758.5);
    const trough = minVectorInRange(product.wavelengths, product.reflectance, 760.2, 761.1);
    const rebound_peak = maxVectorInRange(product.wavelengths, product.reflectance, 761.8, 762.4);
    const mid_band_mean = meanVectorInRange(product.wavelengths, product.reflectance, 763.8, 765.5);
    const red_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 769.5, 771.0);

    const reference_blue_wing_mean = meanReferenceInRange(reference, 755.0, 758.5);
    const reference_trough = minReferenceInRange(reference, 760.2, 761.1);
    const reference_rebound_peak = maxReferenceInRange(reference, 761.8, 762.4);
    const reference_mid_band_mean = meanReferenceInRange(reference, 763.8, 765.5);
    const reference_red_wing_mean = meanReferenceInRange(reference, 769.5, 771.0);

    var sum_signed: f64 = 0.0;
    var sum_abs: f64 = 0.0;
    var sum_sq: f64 = 0.0;
    var generated_mean: f64 = 0.0;
    var reference_mean: f64 = 0.0;
    var max_abs_difference: f64 = 0.0;
    var max_abs_difference_wavelength_nm = if (reference.len == 0) 0.0 else reference[0].wavelength_nm;
    var nonzero_sample_count: usize = 0;

    for (reference) |sample| {
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
        const delta = generated - sample.reflectance;
        const abs_delta = @abs(delta);

        sum_signed += delta;
        sum_abs += abs_delta;
        sum_sq += delta * delta;
        generated_mean += generated;
        reference_mean += sample.reflectance;
        if (abs_delta > zero_tolerance_abs) nonzero_sample_count += 1;
        if (abs_delta > max_abs_difference) {
            max_abs_difference = abs_delta;
            max_abs_difference_wavelength_nm = sample.wavelength_nm;
        }
    }

    const sample_count = @as(f64, @floatFromInt(reference.len));
    if (reference.len != 0) {
        generated_mean /= sample_count;
        reference_mean /= sample_count;
    }

    var covariance: f64 = 0.0;
    var generated_variance: f64 = 0.0;
    var reference_variance: f64 = 0.0;
    for (reference) |sample| {
        const generated = interpolateVector(product.wavelengths, product.reflectance, sample.wavelength_nm);
        covariance += (generated - generated_mean) * (sample.reflectance - reference_mean);
        generated_variance += std.math.pow(f64, generated - generated_mean, 2.0);
        reference_variance += std.math.pow(f64, sample.reflectance - reference_mean, 2.0);
    }

    const correlation = if (generated_variance == 0.0 or reference_variance == 0.0)
        0.0
    else
        covariance / @sqrt(generated_variance * reference_variance);

    return .{
        .sample_count = reference.len,
        .nonzero_sample_count = nonzero_sample_count,
        .exact_match_within_zero_tolerance = nonzero_sample_count == 0,
        .mean_signed_difference = if (reference.len == 0) 0.0 else sum_signed / sample_count,
        .mean_abs_difference = if (reference.len == 0) 0.0 else sum_abs / sample_count,
        .root_mean_square_difference = if (reference.len == 0) 0.0 else @sqrt(sum_sq / sample_count),
        .max_abs_difference = max_abs_difference,
        .max_abs_difference_wavelength_nm = max_abs_difference_wavelength_nm,
        .correlation = correlation,
        .blue_wing_mean_difference = blue_wing_mean - reference_blue_wing_mean,
        .trough_wavelength_difference_nm = trough.wavelength_nm - reference_trough.wavelength_nm,
        .trough_value_difference = trough.value - reference_trough.value,
        .rebound_peak_difference = rebound_peak - reference_rebound_peak,
        .mid_band_mean_difference = mid_band_mean - reference_mid_band_mean,
        .red_wing_mean_difference = red_wing_mean - reference_red_wing_mean,
    };
}

pub fn runVendorO2AReflectanceCase(allocator: std.mem.Allocator) !VendorO2AReflectanceCase {
    return runConfiguredVendorO2AReflectanceCase(allocator, .{});
}

pub fn runConfiguredVendorO2AReflectanceCase(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
) !VendorO2AReflectanceCase {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(allocator);

    var line_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "o2a_hitran_07_hit08_tropomi",
    );
    defer line_asset.deinit(allocator);
    var strong_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf",
    );
    defer strong_asset.deinit(allocator);
    var rmf_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf",
    );
    defer rmf_asset.deinit(allocator);
    var cia_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .collision_induced_absorption_table,
        "data/cross_sections/bundle_manifest.json",
        "o2o2_bira_o2a",
    );
    defer cia_asset.deinit(allocator);
    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(allocator);

    var profile = try climatology_asset.toClimatologyProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try zeroContinuumTable(allocator, 758.0, 771.0);
    defer cross_sections.deinit(allocator);
    var line_list = try line_asset.toSpectroscopyLineList(allocator);
    defer line_list.deinit(allocator);
    var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
    defer strong_lines.deinit(allocator);
    var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(allocator);
    defer relaxation_matrix.deinit(allocator);
    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    var cia_table: ?ReferenceData.CollisionInducedAbsorptionTable = null;
    defer if (cia_table) |*table| table.deinit(allocator);
    if (config.include_cia) {
        cia_table = try cia_asset.toCollisionInducedAbsorptionTable(allocator);
    }
    var lut = try lut_asset.toAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    const reference = try loadReferenceSamples(
        allocator,
        "validation/reference/o2a_with_cia_disamar_reference.csv",
    );
    errdefer allocator.free(reference);

    const reference_wavelengths = try allocator.alloc(f64, reference.len);
    defer allocator.free(reference_wavelengths);
    const reference_irradiance = try allocator.alloc(f64, reference.len);
    defer allocator.free(reference_irradiance);

    for (reference, 0..) |sample, index| {
        reference_wavelengths[index] = sample.wavelength_nm;
        reference_irradiance[index] = sample.irradiance;
    }

    var scene: zdisamar.Scene = .{
        .id = "o2a-forward-validation",
        .surface = .{
            .albedo = 0.20,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.30,
            .single_scatter_albedo = 1.0,
            .asymmetry_factor = 0.70,
            .angstrom_exponent = 0.0,
            .reference_wavelength_nm = 760.0,
            .layer_center_km = 5.4,
            .layer_width_km = 0.4,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .atmosphere = .{
            .layer_count = config.layer_count,
            .sublayer_divisions = config.sublayer_divisions,
            .has_aerosols = true,
        },
        .spectral_grid = config.spectral_grid,
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "o2",
                    .species = "o2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "o2").?,
                    .profile_source = .atmosphere,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .factor_lm_sim = config.line_mixing_factor,
                            .isotopes_sim = config.isotopes_sim,
                            .threshold_line_sim = config.threshold_line_sim,
                            .cutoff_sim_cm1 = config.cutoff_sim_cm1,
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "disamar-o2a-compare" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
            .adaptive_reference_grid = .{
                .points_per_fwhm = config.adaptive_points_per_fwhm,
                .strong_line_min_divisions = config.adaptive_strong_line_min_divisions,
                .strong_line_max_divisions = config.adaptive_strong_line_max_divisions,
            },
        },
    };
    scene.observation_model.operational_solar_spectrum = .{
        .wavelengths_nm = reference_wavelengths,
        .irradiance = reference_irradiance,
    };

    var prepared = try OpticsPrepare.prepareWithSpectroscopyAndCollisionInducedAbsorption(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        if (cia_table) |*table| table else null,
        &line_list,
        &lut,
    );
    errdefer prepared.deinit(allocator);

    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();
    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.layer_count,
            .measurement_count_hint = scene.spectral_grid.sample_count,
        },
        .rtm_controls = .{
            .n_streams = 6,
            .num_orders_max = 20,
        },
    });
    defer plan.deinit();

    var product = try MeasurementSpace.simulateProduct(
        allocator,
        &scene,
        plan.transport_route,
        &prepared,
        .{
            .transport = plan.providers.transport,
            .surface = plan.providers.surface,
            .instrument = plan.providers.instrument,
            .noise = plan.providers.noise,
        },
    );
    errdefer product.deinit(allocator);

    return .{
        .reference = reference,
        .prepared = prepared,
        .product = product,
    };
}
