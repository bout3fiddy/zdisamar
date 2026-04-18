const std = @import("std");
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const ReferenceDataModel = @import("../../model/ReferenceData.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const providers = @import("../providers/root.zig");
const runtime = @import("vendor_parity_runtime.zig");
const Route = @import("../../kernels/transport/common.zig").Route;

pub const ReferenceData = ReferenceDataModel;
pub const ReferenceSample = runtime.ReferenceSample;
pub const ResolvedVendorO2ACase = runtime.ResolvedVendorO2ACase;
pub const LineGasSpec = runtime.LineGasSpec;

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
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,

    pub fn deinit(self: *VendorO2AReflectanceCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
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
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *VendorO2ATracePreparation, allocator: std.mem.Allocator) void {
        self.prepared.deinit(allocator);
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
            self.route,
            &self.prepared,
            providers.exact(),
            forward_profile,
        );
        errdefer product.deinit(allocator);

        const prepared = self.prepared;
        const route = self.route;
        const scene = self.scene;
        const reference = self.reference;
        self.* = undefined;

        return .{
            .reference = reference,
            .scene = scene,
            .route = route,
            .prepared = prepared,
            .product = product,
        };
    }
};
