const std = @import("std");
const jacobian = @import("../../jacobian/root.zig");

const Allocator = std.mem.Allocator;

pub const reflectance_export_name = "reflectance";
pub const fitted_reflectance_export_name = "fitted_reflectance";

// types.zig -------------------------------------------------------------------------------------------------------------|
// Product data shapes for measurement-space spectra. Storage code fills borrowed views first; public API                 |
// paths clone those views into owned products when the caller needs independent lifetime.                                |
//                                                                                                                        |
// main paths                                                                                                             |
//   InstrumentGridProductView -> borrowed workspace-backed result                                                        |
//   InstrumentGridProduct     -> owned public result                                                                     |
//   clone*Jacobian            -> convert state-major workspace columns into public row-major arrays                      |
// -----------------------------------------------------------------------------------------------------------------------|

// InstrumentGridSummary -------------------------------------------------------------------------------------------------|
// Measurement-space summary statistics for one spectral sweep.                                                           |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 80 B (0.078 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] wavelength_start_nm : f64                                                                                     |
// [ 8..15] wavelength_end_nm   : f64                                                                                     |
// [16..23] mean_radiance       : f64                                                                                     |
// [24..31] mean_irradiance     : f64                                                                                     |
// [32..39] mean_reflectance    : f64                                                                                     |
// [40..71] mean_jacobian       : ?[3]f64                                                                                 |
// [72..75] sample_count        : u32                                                                                     |
// [76..79] padding             : 4 B                                                                                     |
//                                                                                                                        |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                               |
// cache span: 2 cache lines at 64 B per line                                                                             |
// footprint: per instance = 80 B (0.078 KiB); total = per instance * live instance count                                 |
pub const InstrumentGridSummary = struct {
    sample_count: u32,
    wavelength_start_nm: f64,
    wavelength_end_nm: f64,
    mean_radiance: f64,
    mean_irradiance: f64,
    mean_reflectance: f64,
    mean_jacobian: ?jacobian.Vector = null,
};
// -----------------------------------------------------------------------------------------------------------------------|

// ForwardIntegratedSample -----------------------------------------------------------------------------------------------|
// High-resolution forward result retained between LABOS prefetch and nominal-channel integration.                        |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] radiance : f64                                                                                                |
// [ 8..31] jacobian : [3]f64                                                                                             |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// count: one cell per unique forward-cache miss in the prefetch batch                                                    |
// footprint: per instance = 32 B (0.031 KiB); storage reuses one dense array across batches                              |
pub const ForwardIntegratedSample = struct {
    radiance: f64,
    jacobian: jacobian.Vector = jacobian.zero(),
};
// -----------------------------------------------------------------------------------------------------------------------|

// InstrumentGridProduct -------------------------------------------------------------------------------------------------|
// Owned product arrays plus the bulk optical-property scalars used for the run.                                          |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 240 B (0.234 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 79] summary                         : InstrumentGridSummary                                                     |
// [ 80.. 95] wavelengths                     : []f64                                                                     |
// [ 96..111] radiance                        : []f64                                                                     |
// [112..127] irradiance                      : []f64                                                                     |
// [128..143] reflectance                     : []f64                                                                     |
// [144..159] jacobian                        : ?[]f64                                                                    |
// [160..167] effective_air_mass_factor       : f64                                                                       |
// [168..175] effective_single_scatter_albedo : f64                                                                       |
// [176..183] effective_temperature_k         : f64                                                                       |
// [184..191] effective_pressure_hpa          : f64                                                                       |
// [192..199] gas_optical_depth               : f64                                                                       |
// [200..207] cia_optical_depth               : f64                                                                       |
// [208..215] aerosol_optical_depth           : f64                                                                       |
// [216..223] total_optical_depth             : f64                                                                       |
// [224..231] depolarization_factor           : f64                                                                       |
// [232..239] d_optical_depth_d_temperature   : f64                                                                       |
//                                                                                                                        |
// out-of-line storage                                                                                                    |
//   wavelengths, radiance, irradiance, reflectance, and optional jacobian each own heap slices.                          |
//   The optical-property scalar fields are copied from PreparedOpticalState for reporting.                               |
//                                                                                                                        |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 240 B (0.234 KiB); total also includes referenced storage above                              |
pub const InstrumentGridProduct = struct {
    summary: InstrumentGridSummary,
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    jacobian: ?[]f64 = null,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn deinit(self: *InstrumentGridProduct, allocator: Allocator) void {
        // InstrumentGridProduct.deinit ----------------------------------------------------------------------------------|
        // Release owned product arrays. The scalar fields live inside the struct and need no separate free.              |
        // ---------------------------------------------------------------------------------------------------------------|

        allocator.free(self.wavelengths);
        allocator.free(self.radiance);
        allocator.free(self.irradiance);
        allocator.free(self.reflectance);
        if (self.jacobian) |values| allocator.free(values);
        self.* = undefined;
    }
};
// -----------------------------------------------------------------------------------------------------------------------|

// InstrumentGridProductView ---------------------------------------------------------------------------------------------|
// Borrowed instrument-grid output backed by ProductStorage. Views are cheap to return but become invalid                 |
// after the workspace buffers are reused or freed.                                                                       |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 248 B (0.242 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 79] summary                         : InstrumentGridSummary                                                     |
// [ 80.. 95] wavelengths                     : []const f64                                                               |
// [ 96..111] radiance                        : []const f64                                                               |
// [112..127] irradiance                      : []const f64                                                               |
// [128..143] reflectance                     : []const f64                                                               |
// [144..159] jacobian                        : ?[]const f64                                                              |
// [160..167] effective_air_mass_factor       : f64                                                                       |
// [168..175] effective_single_scatter_albedo : f64                                                                       |
// [176..183] effective_temperature_k         : f64                                                                       |
// [184..191] effective_pressure_hpa          : f64                                                                       |
// [192..199] gas_optical_depth               : f64                                                                       |
// [200..207] cia_optical_depth               : f64                                                                       |
// [208..215] aerosol_optical_depth           : f64                                                                       |
// [216..223] total_optical_depth             : f64                                                                       |
// [224..231] depolarization_factor           : f64                                                                       |
// [232..239] d_optical_depth_d_temperature   : f64                                                                       |
// [240..240] jacobian_state_mask             : jacobian.StateMask                                                        |
// [241..247] padding                         : 7 B                                                                       |
//                                                                                                                        |
// out-of-line storage                                                                                                    |
//   wavelengths, radiance, irradiance, reflectance, and optional jacobian are borrowed slices.                           |
//   Workspace Jacobians are state-major and compacted to active states only.                                             |
//                                                                                                                        |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                               |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 248 B (0.242 KiB); total also includes referenced storage above                              |
pub const InstrumentGridProductView = struct {
    summary: InstrumentGridSummary,
    wavelengths: []const f64,
    radiance: []const f64,
    irradiance: []const f64,
    reflectance: []const f64,

    // Borrowed workspace Jacobians are state-major and contain only the active
    // derivative states. The default owned product keeps the public full-state
    // row-major shape; requested-state API paths clone compact row-major output
    // directly from the same workspace columns.
    jacobian: ?[]const f64 = null,
    jacobian_state_mask: jacobian.StateMask = 0,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    total_optical_depth: f64,
    depolarization_factor: f64,
    d_optical_depth_d_temperature: f64,

    pub fn toOwned(self: InstrumentGridProductView, allocator: Allocator) !InstrumentGridProduct {
        // InstrumentGridProductView.toOwned -----------------------------------------------------------------------------|
        // Clone the borrowed view into the default public product shape. Jacobians expand to all supported               |
        // states in row-major sample order.                                                                              |
        // ---------------------------------------------------------------------------------------------------------------|

        return self.toOwnedWithJacobianStates(allocator, @as([]const jacobian.State, &.{}));
    }

    pub fn toOwnedWithJacobianStates(
        self: InstrumentGridProductView,
        allocator: Allocator,
        output_states: []const jacobian.State,
    ) !InstrumentGridProduct {
        // InstrumentGridProductView.toOwnedWithJacobianStates -----------------------------------------------------------|
        // Clone workspace-backed arrays into owned storage and convert compact state-major Jacobian columns              |
        // to the requested public row-major shape.                                                                       |
        //                                                                                                                |
        // output                                                                                                         |
        //   output_states empty -> full [sample][all states] layout with inactive states filled as zero                  |
        //   output_states set   -> compact [sample][requested states] layout                                             |
        // ---------------------------------------------------------------------------------------------------------------|

        const wavelengths = try cloneF64Slice(allocator, self.wavelengths);

        errdefer allocator.free(wavelengths);
        const radiance = try cloneF64Slice(allocator, self.radiance);
        errdefer allocator.free(radiance);
        const irradiance = try cloneF64Slice(allocator, self.irradiance);
        errdefer allocator.free(irradiance);
        const reflectance = try cloneF64Slice(allocator, self.reflectance);

        errdefer allocator.free(reflectance);
        const jacobian_values = choose_jacobian_values: {
            const values = self.jacobian orelse break :choose_jacobian_values null;

            if (output_states.len == 0) {
                break :choose_jacobian_values try cloneExpandedJacobian(
                    allocator,
                    values,
                    self.jacobian_state_mask,
                    self.wavelengths.len,
                );
            }

            break :choose_jacobian_values try cloneSelectedRowMajorJacobian(
                allocator,
                values,
                self.jacobian_state_mask,
                self.wavelengths.len,
                output_states,
            );
        };
        errdefer if (jacobian_values) |values| allocator.free(values);

        return .{
            .summary = self.summary,
            .wavelengths = wavelengths,
            .radiance = radiance,
            .irradiance = irradiance,
            .reflectance = reflectance,
            .jacobian = jacobian_values,
            .effective_air_mass_factor = self.effective_air_mass_factor,
            .effective_single_scatter_albedo = self.effective_single_scatter_albedo,
            .effective_temperature_k = self.effective_temperature_k,
            .effective_pressure_hpa = self.effective_pressure_hpa,
            .gas_optical_depth = self.gas_optical_depth,
            .cia_optical_depth = self.cia_optical_depth,
            .aerosol_optical_depth = self.aerosol_optical_depth,
            .total_optical_depth = self.total_optical_depth,
            .depolarization_factor = self.depolarization_factor,
            .d_optical_depth_d_temperature = self.d_optical_depth_d_temperature,
        };
    }
};
// -----------------------------------------------------------------------------------------------------------------------|

fn cloneExpandedJacobian(
    allocator: Allocator,
    values: []const f64,
    active_mask: jacobian.StateMask,
    sample_count: usize,
) ![]f64 {
    // cloneExpandedJacobian ---------------------------------------------------------------------------------------------|
    // Convert compact workspace Jacobians into the legacy public full-state row-major layout. Inactive                   |
    // states are present as zero columns so older callers see stable column positions.                                   |
    // -------------------------------------------------------------------------------------------------------------------|

    const active_count = jacobian.activeStateCount(active_mask);
    if (active_count == 0 or values.len != active_count * sample_count) return error.ShapeMismatch;

    const expanded = try allocator.alloc(f64, sample_count * jacobian.state_count);
    @memset(expanded, 0.0);
    for (0..active_count) |active_index| {
        const state = jacobian.activeStateAt(active_mask, active_index) orelse return error.ShapeMismatch;
        const state_index = jacobian.stateIndex(state);
        const column = values[active_index * sample_count ..][0..sample_count];
        for (column, 0..) |value, sample_index| {
            expanded[sample_index * jacobian.state_count + state_index] = value;
        }
    }
    return expanded;
}

fn cloneSelectedRowMajorJacobian(
    allocator: Allocator,
    values: []const f64,
    active_mask: jacobian.StateMask,
    sample_count: usize,
    output_states: []const jacobian.State,
) ![]f64 {
    // cloneSelectedRowMajorJacobian -------------------------------------------------------------------------------------|
    // Convert compact workspace Jacobians into a caller-selected row-major layout. Every requested state must            |
    // be active in the workspace mask, otherwise returning a partial matrix would silently drop a derivative.            |
    // -------------------------------------------------------------------------------------------------------------------|

    const active_count = jacobian.activeStateCount(active_mask);
    if (output_states.len == 0 or active_count == 0 or values.len != active_count * sample_count) {
        return error.ShapeMismatch;
    }

    const selected = try allocator.alloc(f64, sample_count * output_states.len);
    errdefer allocator.free(selected);
    for (output_states, 0..) |state, output_index| {
        const active_index = jacobian.activeStateIndex(active_mask, state) orelse return error.ShapeMismatch;
        const column = values[active_index * sample_count ..][0..sample_count];
        for (column, 0..) |value, sample_index| {
            selected[sample_index * output_states.len + output_index] = value;
        }
    }
    return selected;
}

fn cloneF64Slice(allocator: Allocator, values: []const f64) ![]f64 {
    // cloneF64Slice -----------------------------------------------------------------------------------------------------|
    // Clone one product column while preserving the empty-slice ownership rule: callers still receive a                  |
    // heap allocation they can free through InstrumentGridProduct.deinit.                                                |
    // -------------------------------------------------------------------------------------------------------------------|

    if (values.len == 0) return try allocator.alloc(f64, 0);
    return try allocator.dupe(f64, values);
}
