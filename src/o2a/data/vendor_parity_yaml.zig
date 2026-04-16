//! Purpose:
//!   Provide a narrow internal API for running the committed executable O2A
//!   parity YAML case from product helpers and validation tests.
//!
//! Physics:
//!   The loaded document expresses the retained DISAMAR-inspired O2 A-band
//!   parity scene: geometry, pressure-interval placement, aerosol placement,
//!   line-by-line O2 controls, optional O2-O2 CIA, and scalar RTM controls.
//!
//! Vendor:
//!   `readConfigFileModule::GENERAL/INSTRUMENT/ATMOSPHERIC_INTERVALS/AEROSOL/O2/O2-O2`
//!   and `verifyConfigFileModule::fit-interval and interval-grid checks`
//!
//! Design:
//!   This module keeps the YAML adapter at the edge. Callers load the committed
//!   parity YAML, optionally apply a small typed override bundle, and then run
//!   the shared parity support helpers against that resolved case.
//!
//! Invariants:
//!   The executable YAML remains the source of truth for the retained parity
//!   case, while overrides stay small and local to tests or profiling helpers.
//!
//! Validation:
//!   `tests/validation/o2a_yaml_parity_runtime_test.zig`,
//!   `tests/validation/o2a_forward_shape_test.zig`,
//!   `tests/validation/o2a_vendor_reflectance_assessment_test.zig`,
//!   and `tests/validation/o2a_vendor_reflectance_profile_smoke_test.zig`.

const std = @import("std");
const parity_config = @import("../../adapters/o2a_parity_config.zig");
const parity_support = @import("vendor_parity_support.zig");
const SpectralGrid = @import("../../model/Spectrum.zig").SpectralGrid;

pub const default_yaml_path = "data/examples/vendor_o2a_parity.yaml";

pub const LoadedResolvedCase = parity_config.LoadedResolvedCase;
pub const RunSummary = parity_config.RunSummary;
pub const ReferenceData = parity_support.ReferenceData;
pub const ResolvedVendorO2ACase = parity_support.ResolvedVendorO2ACase;
pub const VendorO2AReflectanceCase = parity_support.VendorO2AReflectanceCase;
pub const VendorO2AProfileCase = parity_support.VendorO2AProfileCase;
pub const VendorO2ATracePreparation = parity_support.VendorO2ATracePreparation;
pub const VendorO2APreparationProfile = parity_support.VendorO2APreparationProfile;
pub const ComparisonMetrics = parity_support.ComparisonMetrics;
pub const TrendTolerances = parity_support.TrendTolerances;
pub const TrendState = parity_support.TrendState;
pub const AssessmentVerdict = parity_support.AssessmentVerdict;
pub const AssessmentOutcome = parity_support.AssessmentOutcome;
pub const RangeExtremum = parity_support.RangeExtremum;

pub const ExecutionOverrides = struct {
    spectral_grid: ?SpectralGrid = null,
    line_mixing_factor: ?f64 = null,
    isotopes_sim: ?[]const u8 = null,
    threshold_line_sim: ?f64 = null,
    cutoff_sim_cm1: ?f64 = null,
    adaptive_points_per_fwhm: ?u16 = null,
    adaptive_strong_line_min_divisions: ?u16 = null,
    adaptive_strong_line_max_divisions: ?u16 = null,
};

pub fn loadResolvedCaseFromFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) !LoadedResolvedCase {
    return parity_config.loadResolvedCaseFromFile(allocator, path);
}

pub fn loadDefaultResolvedCase(
    allocator: std.mem.Allocator,
) !LoadedResolvedCase {
    return loadResolvedCaseFromFile(allocator, default_yaml_path);
}

pub fn applyExecutionOverrides(
    resolved: *ResolvedVendorO2ACase,
    overrides: ExecutionOverrides,
) void {
    if (overrides.spectral_grid) |value| resolved.spectral_grid = value;
    if (overrides.line_mixing_factor) |value| resolved.o2.line_mixing_factor = value;
    if (overrides.isotopes_sim) |value| resolved.o2.isotopes_sim = value;
    if (overrides.threshold_line_sim) |value| resolved.o2.threshold_line_sim = value;
    if (overrides.cutoff_sim_cm1) |value| resolved.o2.cutoff_sim_cm1 = value;
    if (overrides.adaptive_points_per_fwhm) |value| {
        resolved.observation.adaptive_reference_grid.points_per_fwhm = value;
    }
    if (overrides.adaptive_strong_line_min_divisions) |value| {
        resolved.observation.adaptive_reference_grid.strong_line_min_divisions = value;
    }
    if (overrides.adaptive_strong_line_max_divisions) |value| {
        resolved.observation.adaptive_reference_grid.strong_line_max_divisions = value;
    }
}

pub fn renderResolvedJson(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) ![]u8 {
    return parity_config.renderResolvedJson(allocator, resolved);
}

pub fn runResolvedCaseAndWriteOutputs(
    allocator: std.mem.Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !RunSummary {
    return parity_config.runResolvedCaseAndWriteOutputs(allocator, resolved);
}

pub const runResolvedVendorO2AReflectanceCase = parity_support.runResolvedVendorO2AReflectanceCase;
pub const runResolvedVendorO2AProfileCase = parity_support.runResolvedVendorO2AProfileCase;
pub const prepareResolvedVendorO2ATraceCase = parity_support.prepareResolvedVendorO2ATraceCase;

pub fn runDefaultReflectanceCase(
    allocator: std.mem.Allocator,
    overrides: ExecutionOverrides,
) !VendorO2AReflectanceCase {
    var loaded = try loadDefaultResolvedCase(allocator);
    defer loaded.deinit();
    applyExecutionOverrides(&loaded.resolved, overrides);
    return parity_support.runResolvedVendorO2AReflectanceCase(allocator, &loaded.resolved);
}

pub fn runDefaultProfileCase(
    allocator: std.mem.Allocator,
    overrides: ExecutionOverrides,
) !VendorO2AProfileCase {
    var loaded = try loadDefaultResolvedCase(allocator);
    defer loaded.deinit();
    applyExecutionOverrides(&loaded.resolved, overrides);
    return parity_support.runResolvedVendorO2AProfileCase(allocator, &loaded.resolved);
}

pub fn prepareDefaultTraceCase(
    allocator: std.mem.Allocator,
    overrides: ExecutionOverrides,
) !VendorO2ATracePreparation {
    var loaded = try loadDefaultResolvedCase(allocator);
    defer loaded.deinit();
    applyExecutionOverrides(&loaded.resolved, overrides);
    return parity_support.prepareResolvedVendorO2ATraceCase(allocator, &loaded.resolved);
}

pub fn prepareTraceCase(
    allocator: std.mem.Allocator,
) !VendorO2ATracePreparation {
    return prepareDefaultTraceCase(allocator, .{});
}

pub fn loadVendorParityO2ASpectroscopyLineList(
    allocator: std.mem.Allocator,
) !ReferenceData.SpectroscopyLineList {
    var loaded = try loadDefaultResolvedCase(allocator);
    defer loaded.deinit();
    return parity_support.loadResolvedO2ASpectroscopyLineList(allocator, loaded.resolved.o2);
}

pub const meanVectorInRange = parity_support.meanVectorInRange;
pub const minVectorInRange = parity_support.minVectorInRange;
pub const computeComparisonMetrics = parity_support.computeComparisonMetrics;
pub const assessAgainstBaseline = parity_support.assessAgainstBaseline;
