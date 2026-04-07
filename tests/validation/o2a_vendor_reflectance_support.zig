const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.preparation;
const MeasurementSpace = internal.kernels.transport.measurement;
const bundled_optics = internal.runtime.reference.bundled_optics_assets;
const reference_assets = zdisamar.ingest.reference_assets;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;
const RtmControls = @TypeOf(@as(zdisamar.PlanTemplate, .{}).rtm_controls);
const VerticalInterval = @typeInfo(@TypeOf(@as(zdisamar.Scene, .{}).atmosphere.interval_grid.intervals)).pointer.child;

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
    scene: zdisamar.Scene,
    plan: zdisamar.PreparedPlan,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,

    pub fn deinit(self: *VendorO2AReflectanceCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        self.plan.deinit();
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }
};

pub const VendorO2APreparationProfile = struct {
    input_loading_ns: u64 = 0,
    scene_assembly_ns: u64 = 0,
    optics_preparation_ns: u64 = 0,
    plan_preparation_ns: u64 = 0,

    pub fn reset(self: *VendorO2APreparationProfile) void {
        self.* = .{};
    }

    pub fn totalNs(self: VendorO2APreparationProfile) u64 {
        return self.input_loading_ns +
            self.scene_assembly_ns +
            self.optics_preparation_ns +
            self.plan_preparation_ns;
    }
};

pub const VendorO2AProfileCase = struct {
    reflectance_case: VendorO2AReflectanceCase,
    preparation_profile: VendorO2APreparationProfile,
    forward_profile: MeasurementSpace.ForwardProfile,

    pub fn deinit(self: *VendorO2AProfileCase, allocator: std.mem.Allocator) void {
        self.reflectance_case.deinit(allocator);
        self.* = undefined;
    }
};

pub const VendorO2ATracePreparation = struct {
    reference: []ReferenceSample,
    scene: zdisamar.Scene,
    plan: zdisamar.PreparedPlan,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *VendorO2ATracePreparation, allocator: std.mem.Allocator) void {
        self.prepared.deinit(allocator);
        self.plan.deinit();
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }

    pub fn intoReflectanceCase(
        self: *VendorO2ATracePreparation,
        allocator: std.mem.Allocator,
    ) !VendorO2AReflectanceCase {
        return intoReflectanceCaseWithProfile(self, allocator, null);
    }

    pub fn intoProfiledReflectanceCase(
        self: *VendorO2ATracePreparation,
        allocator: std.mem.Allocator,
        forward_profile: *MeasurementSpace.ForwardProfile,
    ) !VendorO2AReflectanceCase {
        return intoReflectanceCaseWithProfile(self, allocator, forward_profile);
    }

    fn intoReflectanceCaseWithProfile(
        self: *VendorO2ATracePreparation,
        allocator: std.mem.Allocator,
        forward_profile: ?*MeasurementSpace.ForwardProfile,
    ) !VendorO2AReflectanceCase {
        var product = try MeasurementSpace.simulateProductWithProfile(
            allocator,
            &self.scene,
            self.plan.transport_route,
            &self.prepared,
            .{
                .transport = self.plan.providers.transport,
                .surface = self.plan.providers.surface,
                .instrument = self.plan.providers.instrument,
                .noise = self.plan.providers.noise,
            },
            forward_profile,
        );
        errdefer product.deinit(allocator);

        const prepared = self.prepared;
        const plan = self.plan;
        const scene = self.scene;
        const reference = self.reference;
        self.* = undefined;

        return .{
            .reference = reference,
            .scene = scene,
            .plan = plan,
            .prepared = prepared,
            .product = product,
        };
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
    use_vendor_parity_fixture: bool = false,
};

const vendor_surface_pressure_hpa = 1013.25;
const vendor_fit_interval_index_1based: u32 = 2;
const vendor_aerosol_interval_index_1based: u32 = 2;
const vendor_adaptive_points_per_fwhm: u16 = 20;
const vendor_adaptive_strong_line_min_divisions: u16 = 8;
const vendor_adaptive_strong_line_max_divisions: u16 = 40;
const vendor_stock_o2a_line_list_path = "vendor/disamar-fortran/RefSpec/07_HIT08_TROPOMI.par";

const vendor_interval_grid = [_]VerticalInterval{
    .{
        .index_1based = 1,
        .top_pressure_hpa = 0.3,
        .bottom_pressure_hpa = 500.0,
        .altitude_divisions = 28,
    },
    .{
        .index_1based = 2,
        .top_pressure_hpa = 500.0,
        .bottom_pressure_hpa = 520.0,
        .altitude_divisions = 6,
    },
    .{
        .index_1based = 3,
        .top_pressure_hpa = 520.0,
        .bottom_pressure_hpa = vendor_surface_pressure_hpa,
        .altitude_divisions = 8,
    },
};

const vendor_parity_rtm_controls: RtmControls = .{
    .scattering = .multiple,
    .n_streams = 20,
    .use_adding = false,
    .num_orders_max = 0,
    .fourier_floor_scalar = 2,
    .threshold_conv_first = 1.5e-7,
    .threshold_conv_mult = 1.5e-9,
    .threshold_doubl = 1.0e-6,
    .threshold_mul = 1.0e-8,
    .use_spherical_correction = true,
    .integrate_source_function = true,
    .renorm_phase_function = true,
    .stokes_dimension = 1,
};

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
    return runConfiguredVendorO2AReflectanceCase(allocator, .{
        .use_vendor_parity_fixture = true,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
}

pub fn runConfiguredVendorO2AReflectanceCase(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
) !VendorO2AReflectanceCase {
    var prepared_case = try prepareConfiguredVendorO2ATraceCase(allocator, config);
    errdefer prepared_case.deinit(allocator);
    return try prepared_case.intoReflectanceCase(allocator);
}

pub fn runVendorO2AProfileCase(allocator: std.mem.Allocator) !VendorO2AProfileCase {
    return runConfiguredVendorO2AProfileCase(allocator, .{
        .use_vendor_parity_fixture = true,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
}

pub fn runConfiguredVendorO2AProfileCase(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
) !VendorO2AProfileCase {
    var preparation_profile: VendorO2APreparationProfile = .{};
    var prepared_case = try prepareConfiguredVendorO2ATraceCaseWithProfile(
        allocator,
        config,
        &preparation_profile,
    );
    errdefer prepared_case.deinit(allocator);

    var forward_profile: MeasurementSpace.ForwardProfile = .{};
    const reflectance_case = try prepared_case.intoProfiledReflectanceCase(
        allocator,
        &forward_profile,
    );
    return .{
        .reflectance_case = reflectance_case,
        .preparation_profile = preparation_profile,
        .forward_profile = forward_profile,
    };
}

pub fn prepareVendorO2ATraceCase(allocator: std.mem.Allocator) !VendorO2ATracePreparation {
    return prepareConfiguredVendorO2ATraceCase(allocator, .{
        .use_vendor_parity_fixture = true,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
}

pub fn prepareConfiguredVendorO2ATraceCase(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
) !VendorO2ATracePreparation {
    return prepareConfiguredVendorO2ATraceCaseWithProfile(allocator, config, null);
}

fn recordPreparationLap(timer: ?*std.time.Timer, target: *u64) void {
    if (timer) |resolved_timer| target.* = resolved_timer.lap();
}

const LoadedVendorO2AInputs = struct {
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    line_list: ReferenceData.SpectroscopyLineList,
    cia_table: ?ReferenceData.CollisionInducedAbsorptionTable,
    lut: ReferenceData.AirmassFactorLut,
    reference: []ReferenceSample,

    fn deinit(self: *LoadedVendorO2AInputs, allocator: std.mem.Allocator) void {
        self.profile.deinit(allocator);
        self.cross_sections.deinit(allocator);
        self.line_list.deinit(allocator);
        if (self.cia_table) |*table| table.deinit(allocator);
        self.lut.deinit(allocator);
        if (self.reference.len != 0) allocator.free(self.reference);
        self.* = undefined;
    }
};

const ResolvedAdaptiveReferenceGrid = struct {
    points_per_fwhm: u16,
    strong_line_min_divisions: u16,
    strong_line_max_divisions: u16,
};

fn prepareConfiguredVendorO2ATraceCaseWithProfile(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
    preparation_profile: ?*VendorO2APreparationProfile,
) !VendorO2ATracePreparation {
    if (preparation_profile) |profile| profile.reset();
    var phase_timer = if (preparation_profile != null)
        std.time.Timer.start() catch unreachable
    else
        null;

    var inputs = try loadConfiguredVendorO2AInputs(allocator, config);
    defer inputs.deinit(allocator);
    if (preparation_profile) |profile| recordPreparationLap(
        if (phase_timer) |*timer| timer else null,
        &profile.input_loading_ns,
    );

    var scene = try buildConfiguredVendorO2AScene(allocator, config, inputs.reference);
    errdefer scene.deinitOwned(allocator);
    if (preparation_profile) |profile| recordPreparationLap(
        if (phase_timer) |*timer| timer else null,
        &profile.scene_assembly_ns,
    );

    const reference = inputs.reference;
    inputs.reference = inputs.reference[0..0];
    errdefer allocator.free(reference);

    var prepared = try OpticsPrepare.prepare(allocator, &scene, .{
        .profile = &inputs.profile,
        .cross_sections = &inputs.cross_sections,
        .collision_induced_absorption = if (inputs.cia_table) |*table| table else null,
        .spectroscopy_lines = &inputs.line_list,
        .lut = &inputs.lut,
    });
    errdefer prepared.deinit(allocator);
    if (preparation_profile) |profile| recordPreparationLap(
        if (phase_timer) |*timer| timer else null,
        &profile.optics_preparation_ns,
    );

    var plan = try prepareConfiguredVendorO2APlan(allocator, &scene, configuredVendorO2ARtmControls(config));
    errdefer plan.deinit();
    if (preparation_profile) |profile| recordPreparationLap(
        if (phase_timer) |*timer| timer else null,
        &profile.plan_preparation_ns,
    );

    return .{
        .reference = reference,
        .scene = scene,
        .plan = plan,
        .prepared = prepared,
    };
}

fn loadConfiguredVendorO2AInputs(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
) !LoadedVendorO2AInputs {
    var profile = try bundled_optics.loadStandardClimatologyProfile(allocator);
    errdefer profile.deinit(allocator);
    var cross_sections = try bundled_optics.zeroContinuumTable(allocator, 758.0, 771.0);
    errdefer cross_sections.deinit(allocator);
    var line_list = if (config.use_vendor_parity_fixture)
        try loadVendorParityO2ASpectroscopyLineList(allocator)
    else
        try bundled_optics.loadO2aSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    var cia_table: ?ReferenceData.CollisionInducedAbsorptionTable = null;
    errdefer if (cia_table) |*table| table.deinit(allocator);
    if (config.include_cia) {
        cia_table = try bundled_optics.loadO2ACollisionInducedAbsorptionTable(allocator);
    }

    var lut = try bundled_optics.loadAirmassFactorLut(allocator);
    errdefer lut.deinit(allocator);

    const reference = try loadReferenceSamples(
        allocator,
        "validation/reference/o2a_with_cia_disamar_reference.csv",
    );
    errdefer allocator.free(reference);

    return .{
        .profile = profile,
        .cross_sections = cross_sections,
        .line_list = line_list,
        .cia_table = cia_table,
        .lut = lut,
        .reference = reference,
    };
}

fn buildConfiguredVendorO2AScene(
    allocator: std.mem.Allocator,
    config: VendorO2AExecutionConfig,
    reference: []const ReferenceSample,
) !zdisamar.Scene {
    const adaptive_grid = resolveAdaptiveReferenceGrid(config);
    const reference_wavelengths = try allocator.alloc(f64, reference.len);
    errdefer allocator.free(reference_wavelengths);
    const reference_irradiance = try allocator.alloc(f64, reference.len);
    errdefer allocator.free(reference_irradiance);

    for (reference, 0..) |sample, index| {
        reference_wavelengths[index] = sample.wavelength_nm;
        reference_irradiance[index] = sample.irradiance;
    }

    const absorber_items = try allocator.alloc(zdisamar.Absorber, 1);
    errdefer allocator.free(absorber_items);
    const absorber_id = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_id);
    const absorber_species = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_species);
    const isotopes_sim = if (config.isotopes_sim.len != 0)
        try allocator.dupe(u8, config.isotopes_sim)
    else
        &.{};
    errdefer if (isotopes_sim.len != 0) allocator.free(isotopes_sim);
    absorber_items[0] = .{
        .id = absorber_id,
        .species = absorber_species,
        .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "o2").?,
        .profile_source = .atmosphere,
        .spectroscopy = .{
            .mode = .line_by_line,
            .line_gas_controls = .{
                .factor_lm_sim = config.line_mixing_factor,
                .isotopes_sim = isotopes_sim,
                .threshold_line_sim = config.threshold_line_sim,
                .cutoff_sim_cm1 = config.cutoff_sim_cm1,
                .active_stage = .simulation,
            },
        },
    };

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
            .items = absorber_items,
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
                .points_per_fwhm = adaptive_grid.points_per_fwhm,
                .strong_line_min_divisions = adaptive_grid.strong_line_min_divisions,
                .strong_line_max_divisions = adaptive_grid.strong_line_max_divisions,
            },
            .operational_solar_spectrum = .{
                .wavelengths_nm = reference_wavelengths,
                .irradiance = reference_irradiance,
            },
        },
    };
    errdefer scene.deinitOwned(allocator);

    if (config.use_vendor_parity_fixture) {
        scene.id = "o2a-vendor-parity";
        scene.surface.pressure_hpa = vendor_surface_pressure_hpa;
        scene.atmosphere.surface_pressure_hpa = vendor_surface_pressure_hpa;
        scene.atmosphere.layer_count = vendor_interval_grid.len;
        scene.atmosphere.interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = vendor_fit_interval_index_1based,
            .intervals = vendor_interval_grid[0..],
        };
        scene.aerosol.reference_wavelength_nm = 550.0;
        scene.aerosol.placement = .{
            .semantics = .explicit_interval_bounds,
            .interval_index_1based = vendor_aerosol_interval_index_1based,
            .top_pressure_hpa = vendor_interval_grid[vendor_aerosol_interval_index_1based - 1].top_pressure_hpa,
            .bottom_pressure_hpa = vendor_interval_grid[vendor_aerosol_interval_index_1based - 1].bottom_pressure_hpa,
        };
    }

    return scene;
}

fn resolveAdaptiveReferenceGrid(
    config: VendorO2AExecutionConfig,
) ResolvedAdaptiveReferenceGrid {
    return .{
        .points_per_fwhm = if (config.use_vendor_parity_fixture and
            config.adaptive_points_per_fwhm == 0 and
            config.adaptive_strong_line_min_divisions == 0 and
            config.adaptive_strong_line_max_divisions == 0)
            vendor_adaptive_points_per_fwhm
        else
            config.adaptive_points_per_fwhm,
        .strong_line_min_divisions = if (config.use_vendor_parity_fixture and
            config.adaptive_points_per_fwhm == 0 and
            config.adaptive_strong_line_min_divisions == 0 and
            config.adaptive_strong_line_max_divisions == 0)
            vendor_adaptive_strong_line_min_divisions
        else
            config.adaptive_strong_line_min_divisions,
        .strong_line_max_divisions = if (config.use_vendor_parity_fixture and
            config.adaptive_points_per_fwhm == 0 and
            config.adaptive_strong_line_min_divisions == 0 and
            config.adaptive_strong_line_max_divisions == 0)
            vendor_adaptive_strong_line_max_divisions
        else
            config.adaptive_strong_line_max_divisions,
    };
}

fn configuredVendorO2ARtmControls(config: VendorO2AExecutionConfig) RtmControls {
    if (config.use_vendor_parity_fixture) return vendor_parity_rtm_controls;
    return .{
        .n_streams = 6,
        .num_orders_max = 20,
    };
}

fn prepareConfiguredVendorO2APlan(
    allocator: std.mem.Allocator,
    scene: *const zdisamar.Scene,
    rtm_controls: RtmControls,
) !zdisamar.PreparedPlan {
    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();
    return engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.preparedLayerCount(),
            .measurement_count_hint = scene.spectral_grid.sample_count,
        },
        .rtm_controls = rtm_controls,
    });
}

pub fn loadVendorParityO2ASpectroscopyLineList(
    allocator: std.mem.Allocator,
) !ReferenceData.SpectroscopyLineList {
    var asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_line_list,
        "vendor_o2a_hitran_07_hit08_tropomi",
        vendor_stock_o2a_line_list_path,
        "hitran_par_o2a",
    );
    defer asset.deinit(allocator);

    var line_list = try asset.toSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    var strong_lines = try bundled_optics.loadO2AStrongLineSet(allocator);
    defer strong_lines.deinit(allocator);

    var relaxation_matrix = try bundled_optics.loadO2ARelaxationMatrix(allocator);
    defer relaxation_matrix.deinit(allocator);

    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    line_list.preserve_anchor_weak_lines = true;
    return line_list;
}
