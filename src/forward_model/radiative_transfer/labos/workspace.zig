const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");
const attenuation_mod = @import("attenuation.zig");
const orders_mod = @import("orders.zig");

const Allocator = std.mem.Allocator;
const layer_phase_signature_seed: u64 = 0x9e37_79b9_7f4a_7c15;
const layer_phase_signature_hash_mask: u64 = 0x00ff_ffff_ffff_ffff;
const layer_phase_signature_index_shift: u6 = 56;

// workspace.zig ---------------------------------------------------------------------------------------------|
// Caller-owned LABOS scratch memory. This file owns buffers and cache validity; it does not own physics.     |
//                                                                                                            |
// used by                                                                                                    |
//   execute.zig passes one Workspace across high-resolution wavelength samples when the caller provides it.  |
//                                                                                                            |
// main cache paths                                                                                           |
//   attenuation data       -> reused by dynamic and runtime attenuation builders                             |
//   RT layers              -> reused by layer matrix builders                                                |
//   order fields           -> reused by orders.zig scattering transport                                      |
//   Plm basis              -> reused by Fourier term when geometry and phase range still match               |
//   layer phase signatures -> reused for telemetry about possible phase-kernel reuse                         |
//                                                                                                            |
// resizing rule                                                                                              |
//   ensureCapacity allocates a replacement buffer and does not copy old values. Callers rebuild any values   |
//   that matter after a resize. This keeps the workspace simple and avoids preserving scratch data.          |
// -----------------------------------------------------------------------------------------------------------|

// Workspace -------------------------------------------------------------------------------------------------|
// Scratch buffers and small caches reused across LABOS calls.                                                |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 3168 B (3.094 KiB), align: 8 B                                                                       |
//                                                                                                            |
// memory inside the struct                                                                                   |
// allocator                                  : 16 B                                                          |
// 13 slice descriptors                       : 208 B                                                         |
// orders cache                               : 104 B                                                         |
// cached_geometry                            : 2832 B                                                        |
// cached_geometry_valid + padding            : 8 B                                                           |
//                                                                                                            |
// pointed-to buffers are separate heap storage and are not included in the 3168 B struct size.               |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 50 cache line(s) at 64 B per line                                                              |
// footprint: per instance = 3168 B (3.094 KiB); total also includes referenced heap buffers                  |
pub const Workspace = struct {
    allocator: Allocator,
    attenuation_data: []f64 = &.{},
    attenuation_layer_transmittance: []f64 = &.{},
    attenuation_top_to_level: []f64 = &.{},
    rt_layers: []basis.LayerRT = &.{},
    layer_phase_max_indices: []usize = &.{},
    layer_effective_scattering_suffix: []f64 = &.{},
    source_phase_max_indices: []usize = &.{},
    orders: ?orders_mod.OrdersWorkspace = null,
    layer_phase_rows: []basis.PhaseKernelRow = &.{},
    layer_phase_row_valid: []bool = &.{},
    plm_basis_cache: []basis.FourierPlmBasis = &.{},
    plm_basis_cache_valid: []bool = &.{},
    previous_layer_phase_signatures: []u64 = &.{},
    previous_layer_phase_signature_valid: []bool = &.{},
    cached_geometry: basis.Geometry = undefined,
    cached_geometry_valid: bool = false,

    pub fn init(allocator: Allocator) Workspace {
        // Workspace.init ------------------------------------------------------------------------------------|
        // Start an empty workspace. Buffers are allocated lazily by the first rtm_config that needs them.    |
        // ---------------------------------------------------------------------------------------------------|

        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Workspace) void {
        // Workspace.deinit ----------------------------------------------------------------------------------|
        // Release every owned heap buffer and invalidate the workspace.                                      |
        // ---------------------------------------------------------------------------------------------------|

        if (self.orders) |*orders| orders.deinit();

        self.allocator.free(self.attenuation_data);
        self.allocator.free(self.attenuation_layer_transmittance);
        self.allocator.free(self.attenuation_top_to_level);
        self.allocator.free(self.rt_layers);
        self.allocator.free(self.layer_phase_max_indices);
        self.allocator.free(self.layer_effective_scattering_suffix);
        self.allocator.free(self.source_phase_max_indices);
        self.allocator.free(self.layer_phase_rows);
        self.allocator.free(self.layer_phase_row_valid);
        self.allocator.free(self.plm_basis_cache);
        self.allocator.free(self.plm_basis_cache_valid);
        self.allocator.free(self.previous_layer_phase_signatures);
        self.allocator.free(self.previous_layer_phase_signature_valid);

        self.* = undefined;
    }

    pub fn attenuation(
        self: *Workspace,
        layers: []const common.LayerInput,
        pseudo_spherical_grid: common.PseudoSphericalGrid,
        geo: *const basis.Geometry,
        use_spherical_correction: bool,
    ) !attenuation_mod.DynamicAttenArray {
        // Workspace.attenuation -----------------------------------------------------------------------------|
        // Reserve the full level-to-level attenuation table and the layer transmittance cache.               |
        //                                                                                                    |
        // used by                                                                                            |
        //   layer-resolved LABOS when later code wants arbitrary attenuation(from_level, to_level).          |
        //                                                                                                    |
        // memory                                                                                             |
        //   attenuation_data holds nmutot * nlevel * nlevel survival values.                                 |
        //   attenuation_layer_transmittance holds nmutot * nlayer one-layer survival values.                 |
        // ---------------------------------------------------------------------------------------------------|

        const nlevel = layers.len + 1;
        const attenuation_len = geo.nmutot * nlevel * nlevel;
        const layer_transmittance_len = geo.nmutot * layers.len;

        try ensureCapacity(f64, self.allocator, &self.attenuation_data, attenuation_len);
        try ensureCapacity(
            f64,
            self.allocator,
            &self.attenuation_layer_transmittance,
            layer_transmittance_len,
        );

        return attenuation_mod.fillAttenuationDynamicWithGridInBufferAndLayerCache(
            self.allocator,
            self.attenuation_data,
            self.attenuation_layer_transmittance,
            layers,
            pseudo_spherical_grid,
            geo,
            use_spherical_correction,
        );
    }

    pub fn runtimeAttenuation(
        self: *Workspace,
        layers: []const common.LayerInput,
        pseudo_spherical_grid: common.PseudoSphericalGrid,
        geo: *const basis.Geometry,
        use_spherical_correction: bool,
    ) !attenuation_mod.RuntimeAttenArray {
        // Workspace.runtimeAttenuation ----------------------------------------------------------------------|
        // Reserve the compact runtime attenuation representation.                                            |
        //                                                                                                    |
        // used by                                                                                            |
        //   integrated-source Jacobian routes that only need top-to-level attenuation and layer survival.    |
        //                                                                                                    |
        // memory                                                                                             |
        //   attenuation_layer_transmittance holds one-layer survival values.                                 |
        //   attenuation_top_to_level holds top-to-each-level survival values.                                |
        // ---------------------------------------------------------------------------------------------------|

        const nlevel = layers.len + 1;
        const layer_transmittance_len = geo.nmutot * layers.len;
        const top_to_level_len = geo.nmutot * nlevel;

        try ensureCapacity(
            f64,
            self.allocator,
            &self.attenuation_layer_transmittance,
            layer_transmittance_len,
        );
        try ensureCapacity(f64, self.allocator, &self.attenuation_top_to_level, top_to_level_len);

        return attenuation_mod.fillRuntimeAttenuationWithGridInBuffers(
            self.attenuation_layer_transmittance,
            self.attenuation_top_to_level,
            layers,
            pseudo_spherical_grid,
            geo,
            use_spherical_correction,
        );
    }

    pub fn geometry(
        self: *Workspace,
        n_gauss: usize,
        mu0: f64,
        muv: f64,
    ) *const basis.Geometry {
        // Workspace.geometry --------------------------------------------------------------------------------|
        // Return the cached geometry when it still matches, otherwise rebuild it.                            |
        // ---------------------------------------------------------------------------------------------------|

        return self.geometryWithStatus(n_gauss, mu0, muv).geometry;
    }

    // GeometryCacheStatus -----------------------------------------------------------------------------------|
    // Geometry pointer plus whether the workspace cache was reused.                                          |
    //                                                                                                        |
    // layout(64-bit)                                                                                         |
    // size: 16 B (0.016 KiB), align: 8 B                                                                     |
    //                                                                                                        |
    // memory                                                                                                 |
    // [ 0.. 7] geometry : *const Geometry                                                                    |
    // [ 8.. 8] hit      : bool                                                                               |
    // [ 9..15] padding  : 7 B                                                                                |
    //                                                                                                        |
    // unused bits: 56 padding + 7 bool-storage slack = 63 bits                                               |
    // footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                 |
    pub const GeometryCacheStatus = struct {
        geometry: *const basis.Geometry,
        hit: bool,
    };
    // -------------------------------------------------------------------------------------------------------|

    pub fn geometryWithStatus(
        self: *Workspace,
        n_gauss: usize,
        mu0: f64,
        muv: f64,
    ) GeometryCacheStatus {
        // Workspace.geometryWithStatus ----------------------------------------------------------------------|
        // Return geometry and report whether it came from the cache.                                         |
        //                                                                                                    |
        // cache key                                                                                          |
        //   n_gauss, solar direction cosine mu0, and viewing direction cosine muv.                           |
        //                                                                                                    |
        // cache miss                                                                                         |
        //   rebuilding geometry changes direction indexes and direction-pair factors, so dependent Plm and   |
        //   layer phase caches are marked invalid.                                                           |
        // ---------------------------------------------------------------------------------------------------|

        const hit = self.cached_geometry_valid and
            self.cached_geometry.n_gauss == n_gauss and
            self.cached_geometry.mu0 == mu0 and
            self.cached_geometry.muv == muv;

        if (!hit) {
            self.cached_geometry = basis.Geometry.init(n_gauss, mu0, muv);
            self.cached_geometry_valid = true;

            @memset(self.plm_basis_cache_valid, false);
            @memset(self.previous_layer_phase_signature_valid, false);
        }

        return .{ .geometry = &self.cached_geometry, .hit = hit };
    }

    pub fn layerRt(self: *Workspace, nlevel: usize) ![]basis.LayerRT {
        // Workspace.layerRt ---------------------------------------------------------------------------------|
        // Return scratch storage for one RT matrix pair per level/interface slot.                            |
        // ---------------------------------------------------------------------------------------------------|

        try ensureCapacity(basis.LayerRT, self.allocator, &self.rt_layers, nlevel);
        return self.rt_layers[0..nlevel];
    }

    pub fn layerPhaseMaxIndices(self: *Workspace, nlayer: usize) ![]usize {
        // Workspace.layerPhaseMaxIndices --------------------------------------------------------------------|
        // Return per-layer maximum phase coefficient indexes for this solve.                                 |
        // ---------------------------------------------------------------------------------------------------|

        try ensureCapacity(usize, self.allocator, &self.layer_phase_max_indices, nlayer);
        return self.layer_phase_max_indices[0..nlayer];
    }

    pub fn layerEffectiveScatteringSuffix(
        self: *Workspace,
        nlayer: usize,
        phase_stride: usize,
    ) ![]f64 {
        // Workspace.layerEffectiveScatteringSuffix ----------------------------------------------------------|
        // Return per-layer suffix sums used by the layer-doubling decision.                                  |
        //                                                                                                    |
        // shape                                                                                              |
        //   nlayer * phase_stride, where each layer owns one contiguous phase-coefficient row.               |
        // ---------------------------------------------------------------------------------------------------|

        const required_len = nlayer * phase_stride;

        try ensureCapacity(
            f64,
            self.allocator,
            &self.layer_effective_scattering_suffix,
            required_len,
        );

        return self.layer_effective_scattering_suffix[0..required_len];
    }

    pub fn sourcePhaseMaxIndices(self: *Workspace, nlevel: usize) ![]usize {
        // Workspace.sourcePhaseMaxIndices -------------------------------------------------------------------|
        // Return per-interface maximum phase coefficient indexes for integrated-source weighting.            |
        // ---------------------------------------------------------------------------------------------------|

        try ensureCapacity(usize, self.allocator, &self.source_phase_max_indices, nlevel);
        return self.source_phase_max_indices[0..nlevel];
    }

    pub fn ordersWorkspace(
        self: *Workspace,
        nlevel: usize,
        needs_local_sum: bool,
    ) !*orders_mod.OrdersWorkspace {
        // Workspace.ordersWorkspace -------------------------------------------------------------------------|
        // Return scattering-order workspace with enough level storage for the requested rtm_config.          |
        //                                                                                                    |
        // cache hit                                                                                          |
        //   existing order fields are reused when the level count still fits.                                |
        //                                                                                                    |
        // cache miss                                                                                         |
        //   smaller order workspaces are dropped and rebuilt because their nested buffers are owned by       |
        //   orders.zig and must be resized together.                                                         |
        // ---------------------------------------------------------------------------------------------------|

        if (self.orders) |*orders| {
            const cached_orders_fit = orders.ud.len >= nlevel;

            if (cached_orders_fit) {
                if (needs_local_sum) try orders.ensureLocalSumCapacity(nlevel);
                return orders;
            }

            orders.deinit();
            self.orders = null;
        }

        self.orders = try orders_mod.OrdersWorkspace.initWithLocalSumStorage(
            self.allocator,
            nlevel,
            needs_local_sum,
        );

        return &(self.orders.?);
    }

    pub fn phaseRowCache(self: *Workspace, nlevel: usize) ![]basis.PhaseKernelRow {
        // Workspace.phaseRowCache ---------------------------------------------------------------------------|
        // Return one cached phase-kernel row per level/interface slot.                                       |
        // ---------------------------------------------------------------------------------------------------|

        try ensureCapacity(basis.PhaseKernelRow, self.allocator, &self.layer_phase_rows, nlevel);
        return self.layer_phase_rows[0..nlevel];
    }

    pub fn phaseRowValid(self: *Workspace, nlevel: usize) ![]bool {
        // Workspace.phaseRowValid ---------------------------------------------------------------------------|
        // Return validity flags paired with the phase-row cache.                                             |
        // ---------------------------------------------------------------------------------------------------|

        try ensureCapacity(bool, self.allocator, &self.layer_phase_row_valid, nlevel);
        return self.layer_phase_row_valid[0..nlevel];
    }

    pub fn fourierPlmBasis(
        self: *Workspace,
        i_fourier: usize,
        max_phase_index: usize,
        cache_max_index: usize,
        geo: *const basis.Geometry,
    ) !*const basis.FourierPlmBasis {
        // Workspace.fourierPlmBasis -------------------------------------------------------------------------|
        // Return the Plm basis pointer and discard cache-status details.                                     |
        // ---------------------------------------------------------------------------------------------------|

        return (try self.fourierPlmBasisWithStatus(
            i_fourier,
            max_phase_index,
            cache_max_index,
            geo,
        )).plm_basis;
    }

    // PlmBasisCacheStatus -----------------------------------------------------------------------------------|
    // Plm basis pointer plus cache-hit details used by telemetry.                                            |
    //                                                                                                        |
    // layout(64-bit)                                                                                         |
    // size: 16 B (0.016 KiB), align: 8 B                                                                     |
    //                                                                                                        |
    // memory                                                                                                 |
    // [ 0.. 7] plm_basis : *const FourierPlmBasis                                                            |
    // [ 8.. 8] hit       : bool                                                                              |
    // [ 9.. 9] extended  : bool                                                                              |
    // [10..15] padding   : 6 B                                                                               |
    //                                                                                                        |
    // unused bits: 48 padding + 14 bool-storage slack = 62 bits                                              |
    // footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count                 |
    pub const PlmBasisCacheStatus = struct {
        plm_basis: *const basis.FourierPlmBasis,
        hit: bool,
        extended: bool,
    };
    // -------------------------------------------------------------------------------------------------------|

    pub fn fourierPlmBasisWithStatus(
        self: *Workspace,
        i_fourier: usize,
        max_phase_index: usize,
        cache_max_index: usize,
        geo: *const basis.Geometry,
    ) !PlmBasisCacheStatus {
        // Workspace.fourierPlmBasisWithStatus ---------------------------------------------------------------|
        // Return a Fourier Plm basis and report whether it was reused.                                       |
        //                                                                                                    |
        // cache key                                                                                          |
        //   Fourier index, requested maximum phase index, and the current cached geometry.                   |
        //                                                                                                    |
        // resize rule                                                                                        |
        //   ensureCapacity does not copy old basis values. If the cache grows, all validity flags are reset  |
        //   and this call rebuilds the requested Fourier basis.                                              |
        // ---------------------------------------------------------------------------------------------------|

        std.debug.assert(i_fourier < basis.max_phase_coef);
        std.debug.assert(max_phase_index < basis.max_phase_coef);
        std.debug.assert(cache_max_index < basis.max_phase_coef);

        const required_len = @max(i_fourier + 1, cache_max_index + 1);
        const previous_cache_len = self.plm_basis_cache.len;
        const previous_valid_len = self.plm_basis_cache_valid.len;

        try ensureCapacity(basis.FourierPlmBasis, self.allocator, &self.plm_basis_cache, required_len);
        try ensureCapacity(bool, self.allocator, &self.plm_basis_cache_valid, required_len);

        const cache_grew = previous_cache_len < required_len or previous_valid_len < required_len;
        if (cache_grew) {
            @memset(self.plm_basis_cache_valid, false);
        }

        const was_valid = self.plm_basis_cache_valid[i_fourier];
        const needs_extend = was_valid and self.plm_basis_cache[i_fourier].max_phase_index < max_phase_index;

        if (!was_valid or needs_extend) {
            self.plm_basis_cache[i_fourier] = basis.FourierPlmBasis.init(i_fourier, max_phase_index, geo);
            self.plm_basis_cache_valid[i_fourier] = true;
        }

        return .{
            .plm_basis = &self.plm_basis_cache[i_fourier],
            .hit = was_valid and !needs_extend,
            .extended = needs_extend,
        };
    }

    // LayerPhaseSignatureProbe ------------------------------------------------------------------------------|
    // Counts how much layer phase data matched the previous geometry/sample.                                 |
    //                                                                                                        |
    // layout(64-bit)                                                                                         |
    // size: 40 B (0.039 KiB), align: 8 B                                                                     |
    //                                                                                                        |
    // memory                                                                                                 |
    // [ 0.. 7] layer_count                       : usize                                                     |
    // [ 8..15] max_index_matches                 : usize                                                     |
    // [16..23] signature_matches                 : usize                                                     |
    // [24..31] reusable_fourier_layer_templates  : usize                                                     |
    // [32..39] possible_fourier_layer_templates  : usize                                                     |
    //                                                                                                        |
    // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                 |
    // footprint: per instance = 40 B (0.039 KiB); total = per instance * live instance count                 |
    pub const LayerPhaseSignatureProbe = struct {
        layer_count: usize = 0,
        max_index_matches: usize = 0,
        signature_matches: usize = 0,
        reusable_fourier_layer_templates: usize = 0,
        possible_fourier_layer_templates: usize = 0,
    };
    // -------------------------------------------------------------------------------------------------------|

    pub fn probeLayerPhaseSignatures(
        self: *Workspace,
        layers: []const common.LayerInput,
        layer_phase_max_indices: []const usize,
        fourier_max: usize,
    ) !LayerPhaseSignatureProbe {
        // Workspace.probeLayerPhaseSignatures ---------------------------------------------------------------|
        // Compare each layer phase row with the previous cached row and return reuse counters.               |
        //                                                                                                    |
        // used by                                                                                            |
        //   telemetry that tells whether phase-kernel rows could be reused across nearby samples.            |
        //                                                                                                    |
        // storage                                                                                            |
        //   previous_layer_phase_signatures stores one packed u64 per layer:                                 |
        //                                                                                                    |
        //       bits 63..56 : max_phase_index                                                                |
        //       bits 55.. 0 : hash(max_phase_index, phase coefficients 0..max_phase_index)                   |
        //                                                                                                    |
        //   Same top byte means the active phase range matched. Same whole u64 means the active phase row    |
        //   probably matched exactly, so telemetry counts those Fourier layer templates as reusable.         |
        // ---------------------------------------------------------------------------------------------------|

        std.debug.assert(layer_phase_max_indices.len >= layers.len);

        try ensureCapacity(u64, self.allocator, &self.previous_layer_phase_signatures, layers.len);

        const previous_valid_len = self.previous_layer_phase_signature_valid.len;
        try ensureCapacity(bool, self.allocator, &self.previous_layer_phase_signature_valid, layers.len);

        if (previous_valid_len < layers.len) {
            @memset(self.previous_layer_phase_signature_valid, false);
        }

        var probe = LayerPhaseSignatureProbe{ .layer_count = layers.len };

        for (layers, layer_phase_max_indices[0..layers.len], 0..) |*layer, max_index, layer_idx| {
            const signature = layerPhaseSignature(layer.phase, max_index);
            const possible_templates = @min(max_index, fourier_max) + 1;

            probe.possible_fourier_layer_templates += possible_templates;

            if (self.previous_layer_phase_signature_valid[layer_idx]) {
                const previous_signature = self.previous_layer_phase_signatures[layer_idx];

                if (signatureMaxIndex(previous_signature) == max_index) probe.max_index_matches += 1;

                if (previous_signature == signature) {
                    probe.signature_matches += 1;
                    probe.reusable_fourier_layer_templates += possible_templates;
                }
            }

            self.previous_layer_phase_signatures[layer_idx] = signature;
            self.previous_layer_phase_signature_valid[layer_idx] = true;
        }

        return probe;
    }
};
// -----------------------------------------------------------------------------------------------------------|

fn layerPhaseSignature(phase: common.LayerPhase, max_index: usize) u64 {
    // layerPhaseSignature -----------------------------------------------------------------------------------|
    // Build one packed fingerprint for a layer phase row.                                                    |
    //                                                                                                        |
    // signature layout                                                                                       |
    //                                                                                                        |
    //   63        56 55                                                                    0                 |
    //   | max_index | coefficient fingerprint                                              |                 |
    //                                                                                                        |
    // comparison                                                                                             |
    //   signatureMaxIndex(signature) == max_index : same active phase range                                  |
    //   signature == previous_signature        : same active range and same coefficient bits                 |
    //                                                                                                        |
    // steps                                                                                                  |
    //   1. hash max_index so rows with the same prefix but different active length do not look identical     |
    //   2. hash the exact f64 bit pattern for each active phase coefficient                                  |
    //   3. keep the low 56 hash bits                                                                         |
    //   4. store max_index in the top byte so the caller can count range matches cheaply                     |
    //                                                                                                        |
    // bit notes                                                                                              |
    //   max_phase_index is currently 0..150, so one byte has enough room.                                    |
    //   @bitCast does not round the coefficient; it feeds the exact f64 storage bits into the hash.          |
    // -------------------------------------------------------------------------------------------------------|

    var hasher = std.hash.Wyhash.init(layer_phase_signature_seed);
    hasher.update(std.mem.asBytes(&max_index));

    for (0..max_index + 1) |index| {
        const coefficient = phase.coefficient(index);
        const coefficient_bits = @as(u64, @bitCast(coefficient));

        hasher.update(std.mem.asBytes(&coefficient_bits));
    }

    const max_index_header = @as(u64, @intCast(max_index)) << layer_phase_signature_index_shift;
    const coefficient_fingerprint = hasher.final() & layer_phase_signature_hash_mask;

    return max_index_header | coefficient_fingerprint;
}

fn signatureMaxIndex(signature: u64) usize {
    // signatureMaxIndex -------------------------------------------------------------------------------------|
    // Recover the max_phase_index field from bits 63..56 of a layer phase signature.                         |
    //                                                                                                        |
    // The low 56 bits are only the coefficient fingerprint, so shifting right by 56 leaves the packed        |
    // max_phase_index value by itself.                                                                       |
    // -------------------------------------------------------------------------------------------------------|

    return @intCast(signature >> layer_phase_signature_index_shift);
}

fn ensureCapacity(
    comptime T: type,
    allocator: Allocator,
    buffer: *[]T,
    required_len: usize,
) !void {
    // ensureCapacity ----------------------------------------------------------------------------------------|
    // Grow a scratch buffer when required_len no longer fits.                                                |
    //                                                                                                        |
    // This helper does not copy old values. It is only used for workspace buffers where callers rebuild      |
    // live data after a resize or reset the matching validity flags.                                         |
    // -------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= required_len) return;

    const replacement = try allocator.alloc(T, required_len);
    allocator.free(buffer.*);
    buffer.* = replacement;
}
