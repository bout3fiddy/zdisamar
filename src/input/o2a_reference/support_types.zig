const std = @import("std");
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const implementations = @import("../../forward_model/implementations/root.zig");
const runtime = @import("run.zig");
const Route = @import("../../forward_model/radiative_transfer/root.zig").Route;

pub const ReferenceData = ReferenceDataModel;
pub const ReferenceSample = runtime.ReferenceSample;
pub const ResolvedVendorO2ACase = runtime.ResolvedVendorO2ACase;
pub const LineGasSpec = runtime.LineGasSpec;

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: wavelength_nm=8 B, value=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const RangeExtremum = struct {
    wavelength_nm: f64,
    value: f64,
};

// layout(64-bit):
//   size: 120 B, align: 8 B
//   field storage: 113 B across 15 fields; largest: sample_count=8 B, nonzero_sample_count=8 B, mean_signed_difference=8 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 120 B (0.117 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage: 80 B across 10 fields; largest: mean_abs_difference_abs=8 B, root_mean_square_difference_abs=8 B, max_abs_difference_abs=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 10 B, align: 1 B
//   field storage: 10 B across 10 fields; largest: mean_abs_difference=1 B, root_mean_square_difference=1 B, max_abs_difference=1 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 10 B (0.010 KiB); total = per instance * live instance count
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

// layout(64-bit):
//   size: 11 B, align: 1 B
//   field storage: verdict=1 B, trend=10 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 11 B (0.011 KiB); total = per instance * live instance count
pub const AssessmentOutcome = struct {
    verdict: AssessmentVerdict,
    trend: AssessmentTrend,
};

// layout(64-bit):
//   size: 4144 B, align: 8 B
//   field storage: 4144 B across 5 fields; largest: scene=2680 B, prepared=1056 B, product=320 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: reference carry references/descriptors; referenced storage is not included in size
//   cache span: 65 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 4144 B (4.047 KiB); total also includes referenced storage above
pub const VendorO2AReflectanceCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: InstrumentGrid.InstrumentGridProduct,

    pub fn deinit(self: *VendorO2AReflectanceCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }
};

// layout(64-bit):
//   size: 3824 B, align: 8 B
//   field storage: reference=16 B, scene=2680 B, route=72 B, prepared=1056 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: reference carry references/descriptors; referenced storage is not included in size
//   cache span: 60 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 3824 B (3.734 KiB); total also includes referenced storage above
pub const VendorO2APreparedCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    route: Route,
    prepared: OpticsPrepare.PreparedOpticalState,

    pub fn deinit(self: *VendorO2APreparedCase, allocator: std.mem.Allocator) void {
        self.prepared.deinit(allocator);
        self.scene.deinitOwned(allocator);
        allocator.free(self.reference);
        self.* = undefined;
    }

    pub fn intoReflectanceCase(
        self: *VendorO2APreparedCase,
        allocator: std.mem.Allocator,
    ) !VendorO2AReflectanceCase {
        return intoReflectanceCaseInternal(self, allocator);
    }

    fn intoReflectanceCaseInternal(
        self: *VendorO2APreparedCase,
        allocator: std.mem.Allocator,
    ) !VendorO2AReflectanceCase {
        var product = try InstrumentGrid.simulateProduct(
            allocator,
            &self.scene,
            self.route,
            &self.prepared,
            implementations.exact(),
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
