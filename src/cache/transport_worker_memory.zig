const std = @import("std");

const memory = @import("../common/memory.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const source_levels = @import("../optics/source_levels.zig");
const attenuation = @import("../rtm/attenuation.zig");
const gauss_angles = @import("../rtm/gauss_angles.zig");
const phase_basis = @import("../rtm/phase_basis.zig");
const phase_table = @import("../setup/phase_table.zig");
const rows = @import("../rtm/rows.zig");
const scattering_orders = @import("../rtm/scattering_orders.zig");
const solve = @import("../rtm/solve.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
} || gauss_angles.Error;

// transport_worker_memory.zig ------------------------------------------------------------------------------  |
// Reusable optics and LABOS transport buffers for one forward worker.                                         |
//                                                                                                             |
//   named O2 A memory block. The borrowed row types come from the new `rtm/*` modules.                        |
//                                                                                                             |
// ownership boundary                                                                                          |
//   This owner stores arrays, geometry reuse state, and validity flags only. Optical-property values, phase   |
//   coefficients, RTM controls, source-level rows, and angles stay visible in worker function signatures.     |
//   geometry is valid until n_gauss, solar_mu, or view_mu changes, and the solve layer invalidates dependent  |
//   PLM rows only on that miss.                                                                               |
//                                                                                                             |
// hot path contract                                                                                           |
//   Call `ensureOpticsCapacity` and `ensureCapacity` before per-wavelength solves. Accessors below borrow     |
//   active prefixes and do not allocate.                                                                      |
// ------------------------------------------------------------------------------------------------------------|

// TransportWorkerMemory ------------------------------------------------------------------------------------- |
// Allocation owner for one worker-local optics and LABOS solve path.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 3272 B (3.195 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] attenuation_data                         : []f64                                               |
// [  16..  31] attenuation_tangent_data                 : []f64                                               |
// [  32..  47] attenuation_layer_transmittance          : []f64                                               |
// [  48..  63] attenuation_top_to_level                 : []f64                                               |
// [  64..  79] rt_layers                                : []LayerRT                                           |
// [  80..  95] rt_layers_tangent                        : []LayerRT                                           |
// [  96.. 111] layer_phase_max_indices                  : []usize                                             |
// [ 112.. 127] layer_effective_scattering_suffixes      : []f64                                               |
// [ 128.. 143] source_phase_max_indices                 : []usize                                             |
// [ 144.. 159] order_ud                                 : []UDField                                           |
// [ 160.. 175] order_ud_sum_local                       : []UDLocal                                           |
// [ 176.. 191] order_ud_orde                            : []UDLocal                                           |
// [ 192.. 207] order_ud_local                           : []UDLocal                                           |
// [ 208.. 223] order_ud_tangent_orde                    : []UDLocal                                           |
// [ 224.. 239] order_ud_tangent_local                   : []UDLocal                                           |
// [ 240.. 255] rt_active                                : []bool                                              |
// [ 256.. 271] layer_phase_rows                         : []PhaseKernelRow                                    |
// [ 272.. 287] layer_phase_row_valid                    : []bool                                              |
// [ 288.. 303] plm_basis_cache                          : []FourierPlmBasis                                   |
// [ 304.. 319] plm_basis_cache_valid                    : []bool                                              |
// [ 320.. 335] line_sigma_cm2_per_molecule       : []f64                                                      |
// [ 336.. 351] support_optics                    : []SupportOptics                                            |
// [ 352.. 367] layer_optics                      : []LayerOptics                                              |
// [ 368.. 383] source_level_rows                 : []SourceLevel                                              |
// [ 384.. 399] curved_samples                    : []CurvedSunPathSample                                      |
// [ 400.. 415] curved_level_starts               : []usize                                                    |
// [ 416.. 431] curved_level_altitudes_km         : []f64                                                      |
// [ 432..3263] cached_geometry                   : GaussGeometry                                              |
// [3264..3264] cached_geometry_valid             : bool                                                       |
// [3265..3271] trailing padding                  : 7 B                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   Every slice owns heap storage and is released by deinit. Optics rows are borrowed by spectrum prefetch;   |
//   active LABOS prefixes are borrowed by transport code.                                                     |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
pub const TransportWorkerMemory = struct {
    attenuation_data: []f64 = &.{},
    attenuation_tangent_data: []f64 = &.{},
    attenuation_layer_transmittance: []f64 = &.{},
    attenuation_top_to_level: []f64 = &.{},
    rt_layers: []rows.LayerRT = &.{},
    rt_layers_tangent: []rows.LayerRT = &.{},
    layer_phase_max_indices: []usize = &.{},
    layer_effective_scattering_suffixes: []f64 = &.{},
    source_phase_max_indices: []usize = &.{},
    order_ud: []rows.UDField = &.{},
    order_ud_sum_local: []rows.UDLocal = &.{},
    order_ud_orde: []rows.UDLocal = &.{},
    order_ud_local: []rows.UDLocal = &.{},
    order_ud_tangent_orde: []rows.UDLocal = &.{},
    order_ud_tangent_local: []rows.UDLocal = &.{},
    rt_active: []bool = &.{},
    layer_phase_rows: []phase_basis.PhaseKernelRow = &.{},
    layer_phase_row_valid: []bool = &.{},
    plm_basis_cache: []phase_basis.FourierPlmBasis = &.{},
    plm_basis_cache_valid: []bool = &.{},
    line_sigma_cm2_per_molecule: []f64 = &.{},
    support_optics: []layer_depths.SupportOptics = &.{},
    layer_optics: []layer_depths.LayerOptics = &.{},
    source_level_rows: []source_levels.SourceLevel = &.{},
    curved_samples: []curved_sun_path.CurvedSunPathSample = &.{},
    curved_level_starts: []usize = &.{},
    curved_level_altitudes_km: []f64 = &.{},
    cached_geometry: gauss_angles.GaussGeometry = undefined,
    cached_geometry_valid: bool = false,

    pub fn deinit(self: *TransportWorkerMemory, allocator: Allocator) void {
        // TransportWorkerMemory.deinit ---------------------------------------------------------------------- |
        // Release every worker-local transport buffer and invalidate cached geometry state.                   |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.attenuation_data);
        allocator.free(self.attenuation_tangent_data);
        allocator.free(self.attenuation_layer_transmittance);
        allocator.free(self.attenuation_top_to_level);
        allocator.free(self.rt_layers);
        allocator.free(self.rt_layers_tangent);
        allocator.free(self.layer_phase_max_indices);
        allocator.free(self.layer_effective_scattering_suffixes);
        allocator.free(self.source_phase_max_indices);
        allocator.free(self.order_ud);
        allocator.free(self.order_ud_sum_local);
        allocator.free(self.order_ud_orde);
        allocator.free(self.order_ud_local);
        allocator.free(self.order_ud_tangent_orde);
        allocator.free(self.order_ud_tangent_local);
        allocator.free(self.rt_active);
        allocator.free(self.layer_phase_rows);
        allocator.free(self.layer_phase_row_valid);
        allocator.free(self.plm_basis_cache);
        allocator.free(self.plm_basis_cache_valid);
        allocator.free(self.line_sigma_cm2_per_molecule);
        allocator.free(self.support_optics);
        allocator.free(self.layer_optics);
        allocator.free(self.source_level_rows);
        allocator.free(self.curved_samples);
        allocator.free(self.curved_level_starts);
        allocator.free(self.curved_level_altitudes_km);
        self.* = .{};
    }

    pub fn ensureOpticsCapacity(
        self: *TransportWorkerMemory,
        allocator: Allocator,
        support_count: usize,
        layer_count: usize,
    ) Allocator.Error!void {
        // TransportWorkerMemory.ensureOpticsCapacity ---------------------------------------------------------|
        // Reserve per-wavelength optics rows before a worker enters dense radiance prefetch.                  |
        //                                                                                                     |
        // shape                                                                                               |
        //   support_count : layer-grid support rows, one line-sigma and support-optics row each               |
        //   layer_count   : reduced transport layers                                                          |
        //   level_count   : layer_count + 1 source/curved boundary rows                                       |
        //                                                                                                     |
        // memory                                                                                              |
        //   The active route fills these slices repeatedly for different wavelengths. Retaining them here     |
        //   removes root-level per-run allocation and gives later multi-worker prefetch one private row set   |
        //   per worker.                                                                                       |
        // ----------------------------------------------------------------------------------------------------|
        const level_count = layer_count + 1;
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.line_sigma_cm2_per_molecule, support_count);
        _ = try memory.ensureSliceCapacity(
            layer_depths.SupportOptics,
            allocator,
            &self.support_optics,
            support_count,
        );
        _ = try memory.ensureSliceCapacity(layer_depths.LayerOptics, allocator, &self.layer_optics, layer_count);
        _ = try memory.ensureSliceCapacity(source_levels.SourceLevel, allocator, &self.source_level_rows, level_count);
        _ = try memory.ensureSliceCapacity(
            curved_sun_path.CurvedSunPathSample,
            allocator,
            &self.curved_samples,
            support_count,
        );
        _ = try memory.ensureSliceCapacity(usize, allocator, &self.curved_level_starts, level_count);
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.curved_level_altitudes_km, level_count);
    }

    pub fn ensureCapacity(
        self: *TransportWorkerMemory,
        allocator: Allocator,
        level_count: usize,
        stream_count: usize,
        phase_stride: usize,
        fourier_basis_count: usize,
        needs_local_sum: bool,
    ) Allocator.Error!void {
        // ensureCapacity -----------------------------------------------------------------------------------  |
        // Reserve all arrays a worker needs before transport enters a per-wavelength solve.                   |
        //                                                                                                     |
        // shape                                                                                               |
        //   level_count         : layer_count + 1                                                             |
        //   phase_stride        : active suffix rows per layer, capped by phase coefficient count             |
        //   fourier_basis_count : retained PLM basis rows for Fourier-index reuse                             |
        // ----------------------------------------------------------------------------------------------------|
        const layer_count = if (level_count == 0) 0 else level_count - 1;
        const phase_row_count = layer_count * phase_stride;
        const dynamic_attenuation_count = attenuation.dynamicRequiredLength(stream_count, layer_count);
        const layer_transmittance_count = attenuation.layerTransmittanceRequiredLength(stream_count, layer_count);
        const top_to_level_count = attenuation.topToLevelRequiredLength(stream_count, layer_count);

        _ = try memory.ensureSliceCapacity(f64, allocator, &self.attenuation_data, dynamic_attenuation_count);
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.attenuation_tangent_data, dynamic_attenuation_count);
        _ = try memory.ensureSliceCapacity(
            f64,
            allocator,
            &self.attenuation_layer_transmittance,
            layer_transmittance_count,
        );
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.attenuation_top_to_level, top_to_level_count);
        _ = try memory.ensureSliceCapacity(rows.LayerRT, allocator, &self.rt_layers, level_count);
        _ = try memory.ensureSliceCapacity(rows.LayerRT, allocator, &self.rt_layers_tangent, level_count);
        _ = try memory.ensureSliceCapacity(usize, allocator, &self.layer_phase_max_indices, layer_count);
        _ = try memory.ensureSliceCapacity(f64, allocator, &self.layer_effective_scattering_suffixes, phase_row_count);
        _ = try memory.ensureSliceCapacity(usize, allocator, &self.source_phase_max_indices, level_count);
        _ = try memory.ensureSliceCapacity(rows.UDField, allocator, &self.order_ud, level_count);
        if (needs_local_sum) {
            _ = try memory.ensureSliceCapacity(rows.UDLocal, allocator, &self.order_ud_sum_local, level_count);
        }
        _ = try memory.ensureSliceCapacity(rows.UDLocal, allocator, &self.order_ud_orde, level_count);
        _ = try memory.ensureSliceCapacity(rows.UDLocal, allocator, &self.order_ud_local, level_count);
        _ = try memory.ensureSliceCapacity(rows.UDLocal, allocator, &self.order_ud_tangent_orde, level_count);
        _ = try memory.ensureSliceCapacity(rows.UDLocal, allocator, &self.order_ud_tangent_local, level_count);
        _ = try memory.ensureSliceCapacity(bool, allocator, &self.rt_active, level_count);
        _ = try memory.ensureSliceCapacity(phase_basis.PhaseKernelRow, allocator, &self.layer_phase_rows, level_count);
        _ = try memory.ensureSliceCapacity(bool, allocator, &self.layer_phase_row_valid, level_count);

        const plm_replaced = try memory.ensureSliceCapacity(
            phase_basis.FourierPlmBasis,
            allocator,
            &self.plm_basis_cache,
            fourier_basis_count,
        );
        const plm_valid_replaced = try memory.ensureSliceCapacity(
            bool,
            allocator,
            &self.plm_basis_cache_valid,
            fourier_basis_count,
        );
        if (plm_replaced or plm_valid_replaced) @memset(self.plm_basis_cache_valid, false);
    }

    pub fn solveWorkArrays(
        self: *TransportWorkerMemory,
        layer_count: usize,
        stream_count: usize,
        needs_local_sum: bool,
    ) Error!solve.TransportWorkArrays {
        // solveWorkArrays ---------------------------------------------------------------------------------   |
        // Borrow the active per-worker arrays consumed by `rtm/solve.zig`.                                    |
        //                                                                                                     |
        // boundary                                                                                            |
        //   The owner provides storage and cached geometry only. Solve inputs remain explicit at the call     |
        //   site: angles, layers, phase rows, controls, source rows, and curved-path samples.                 |
        // ----------------------------------------------------------------------------------------------------|
        const level_count = layer_count + 1;
        const dynamic_count = attenuation.dynamicRequiredLength(stream_count, layer_count);
        const layer_transmittance_count = attenuation.layerTransmittanceRequiredLength(stream_count, layer_count);
        const top_to_level_count = attenuation.topToLevelRequiredLength(stream_count, layer_count);
        const needs_order_sum = needs_local_sum and level_count > self.order_ud_sum_local.len;
        const prefix_too_short =
            dynamic_count > self.attenuation_data.len or
            dynamic_count > self.attenuation_tangent_data.len or
            layer_transmittance_count > self.attenuation_layer_transmittance.len or
            top_to_level_count > self.attenuation_top_to_level.len or
            level_count > self.rt_layers.len or
            level_count > self.rt_layers_tangent.len or
            layer_count > self.layer_phase_max_indices.len or
            level_count > self.source_phase_max_indices.len or
            level_count > self.layer_phase_rows.len or
            level_count > self.layer_phase_row_valid.len or
            level_count > self.order_ud.len or
            level_count > self.order_ud_orde.len or
            level_count > self.order_ud_local.len or
            level_count > self.order_ud_tangent_orde.len or
            level_count > self.order_ud_tangent_local.len or
            level_count > self.rt_active.len or
            needs_order_sum;
        if (prefix_too_short) return error.ShapeMismatch;

        const ud_sum_local = if (needs_local_sum)
            self.order_ud_sum_local[0..level_count]
        else
            self.order_ud_sum_local[0..0];

        return .{
            .geometry = &self.cached_geometry,
            .dynamic_attenuation_data = self.attenuation_data[0..dynamic_count],
            .dynamic_attenuation_tangent_data = self.attenuation_tangent_data[0..dynamic_count],
            .layer_transmittance = self.attenuation_layer_transmittance[0..layer_transmittance_count],
            .top_to_level_attenuation = self.attenuation_top_to_level[0..top_to_level_count],
            .rt_layers = self.rt_layers[0..level_count],
            .rt_layers_tangent = self.rt_layers_tangent[0..level_count],
            .layer_phase_max_indices = self.layer_phase_max_indices[0..layer_count],
            .effective_scattering_suffixes = self.layer_effective_scattering_suffixes,
            .source_phase_max_indices = self.source_phase_max_indices[0..level_count],
            .phase_row_cache = self.layer_phase_rows[0..level_count],
            .phase_row_valid = self.layer_phase_row_valid[0..level_count],
            .curved_level_starts = &.{},
            .curved_level_altitudes_km = &.{},
            .orders = .{
                .ud = self.order_ud[0..level_count],
                .ud_sum_local = ud_sum_local,
                .ud_orde = self.order_ud_orde[0..level_count],
                .ud_local = self.order_ud_local[0..level_count],
                .ud_tangent_orde = self.order_ud_tangent_orde[0..level_count],
                .ud_tangent_local = self.order_ud_tangent_local[0..level_count],
                .rt_active = self.rt_active[0..level_count],
            },
            .plm_basis_cache = self.plm_basis_cache,
            .plm_basis_cache_valid = self.plm_basis_cache_valid,
            .geometry_valid = &self.cached_geometry_valid,
        };
    }
};
// ------------------------------------------------------------------------------------------------------------|

// TransportWorkerMemoryCollection ----------------------------------------------------------------------------|
// Retained worker-indexed memory array for the session prefetch worker set.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] workers : []TransportWorkerMemory                                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   workers owns one TransportWorkerMemory per possible worker index. Child heap buffers move with the value  |
//   when the worker slice grows; only the outer slice is reallocated.                                         |
pub const TransportWorkerMemoryCollection = struct {
    workers: []TransportWorkerMemory = &.{},

    pub fn deinit(self: *TransportWorkerMemoryCollection, allocator: Allocator) void {
        // TransportWorkerMemoryCollection.deinit -------------------------------------------------------------|
        // Release every worker-local owner, then release the outer worker slice.                              |
        // ----------------------------------------------------------------------------------------------------|
        for (self.workers) |*worker_memory| worker_memory.deinit(allocator);
        allocator.free(self.workers);
        self.* = .{};
    }

    pub fn ensureWorkerCount(
        self: *TransportWorkerMemoryCollection,
        allocator: Allocator,
        worker_count: usize,
    ) Allocator.Error!void {
        // TransportWorkerMemoryCollection.ensureWorkerCount --------------------------------------------------|
        // Grow the worker array while preserving each worker's retained child buffers.                        |
        //                                                                                                     |
        // memory                                                                                              |
        //   TransportWorkerMemory is moved by value. Its slices still point at owned child allocations, so    |
        //   the outer slice is freed without deinitializing the moved workers.                                |
        // ----------------------------------------------------------------------------------------------------|
        if (self.workers.len >= worker_count) return;

        const old_workers = self.workers;
        const new_workers = try allocator.alloc(TransportWorkerMemory, worker_count);
        for (new_workers) |*worker_memory| worker_memory.* = .{};
        @memcpy(new_workers[0..old_workers.len], old_workers);
        allocator.free(old_workers);
        self.workers = new_workers;
    }

    pub fn worker(self: *TransportWorkerMemoryCollection, worker_index: usize) *TransportWorkerMemory {
        // TransportWorkerMemoryCollection.worker -------------------------------------------------------------|
        // Borrow the stable memory owner paired with one worker index.                                        |
        // ----------------------------------------------------------------------------------------------------|
        std.debug.assert(worker_index < self.workers.len);
        return &self.workers[worker_index];
    }
};
// ------------------------------------------------------------------------------------------------------------|

comptime {
    std.debug.assert(@sizeOf(TransportWorkerMemory) == 3272);
    std.debug.assert(@sizeOf(TransportWorkerMemoryCollection) == 16);
}
