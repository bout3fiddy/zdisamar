const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");
const attenuation_mod = @import("attenuation.zig");
const orders_mod = @import("orders.zig");

const Allocator = std.mem.Allocator;

// layout(64-bit):
//   size: 3168 B, align: 8 B
//   field storage: 3161 B across 17 fields; largest: cached_geometry=2832 B, orders=104 B, allocator=16 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   out-of-line: attenuation_data, attenuation_layer_transmittance, attenuation_top_to_level, rt_layers, layer_phase_max_indices, +8 more carry references/descriptors; referenced storage is not included in size
//   cache span: 50 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 3168 B (3.094 KiB); total also includes referenced storage above
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
    layer_phase_kernels: []basis.PhaseKernel = &.{},
    layer_phase_kernel_valid: []bool = &.{},
    plm_basis_cache: []basis.FourierPlmBasis = &.{},
    plm_basis_cache_valid: []bool = &.{},
    previous_layer_phase_signatures: []u64 = &.{},
    previous_layer_phase_signature_valid: []bool = &.{},
    cached_geometry: basis.Geometry = undefined,
    cached_geometry_valid: bool = false,

    pub fn init(allocator: Allocator) Workspace {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Workspace) void {
        if (self.orders) |*orders| orders.deinit();
        self.allocator.free(self.attenuation_data);
        self.allocator.free(self.attenuation_layer_transmittance);
        self.allocator.free(self.attenuation_top_to_level);
        self.allocator.free(self.rt_layers);
        self.allocator.free(self.layer_phase_max_indices);
        self.allocator.free(self.layer_effective_scattering_suffix);
        self.allocator.free(self.source_phase_max_indices);
        self.allocator.free(self.layer_phase_kernels);
        self.allocator.free(self.layer_phase_kernel_valid);
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
        const nlevel = layers.len + 1;
        const required_len = geo.nmutot * nlevel * nlevel;
        try ensureCapacity(f64, self.allocator, &self.attenuation_data, required_len);
        try ensureCapacity(f64, self.allocator, &self.attenuation_layer_transmittance, geo.nmutot * layers.len);
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
        const nlevel = layers.len + 1;
        try ensureCapacity(f64, self.allocator, &self.attenuation_layer_transmittance, geo.nmutot * layers.len);
        try ensureCapacity(f64, self.allocator, &self.attenuation_top_to_level, geo.nmutot * nlevel);
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
        return self.geometryWithStatus(n_gauss, mu0, muv).geometry;
    }

    // layout(64-bit):
    //   size: 16 B, align: 8 B
    //   field storage: geometry=8 B, hit=1 B; padding: 7 B (56 bits)
    //   unused bits: 56 padding + 7 bool-storage slack = 63 bits
    //   out-of-line: geometry carry references/descriptors; referenced storage is not included in size
    //   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
    //   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
    pub const GeometryCacheStatus = struct {
        geometry: *const basis.Geometry,
        hit: bool,
    };

    pub fn geometryWithStatus(
        self: *Workspace,
        n_gauss: usize,
        mu0: f64,
        muv: f64,
    ) GeometryCacheStatus {
        const hit = self.cached_geometry_valid and
            self.cached_geometry.n_gauss == n_gauss and
            self.cached_geometry.mu0 == mu0 and
            self.cached_geometry.muv == muv;
        if (!self.cached_geometry_valid or
            self.cached_geometry.n_gauss != n_gauss or
            self.cached_geometry.mu0 != mu0 or
            self.cached_geometry.muv != muv)
        {
            self.cached_geometry = basis.Geometry.init(n_gauss, mu0, muv);
            self.cached_geometry_valid = true;
            @memset(self.plm_basis_cache_valid, false);
            @memset(self.previous_layer_phase_signature_valid, false);
        }
        return .{ .geometry = &self.cached_geometry, .hit = hit };
    }

    pub fn layerRt(self: *Workspace, nlevel: usize) ![]basis.LayerRT {
        try ensureCapacity(basis.LayerRT, self.allocator, &self.rt_layers, nlevel);
        return self.rt_layers[0..nlevel];
    }

    pub fn layerPhaseMaxIndices(self: *Workspace, nlayer: usize) ![]usize {
        try ensureCapacity(usize, self.allocator, &self.layer_phase_max_indices, nlayer);
        return self.layer_phase_max_indices[0..nlayer];
    }

    pub fn layerEffectiveScatteringSuffix(self: *Workspace, nlayer: usize) ![]f64 {
        const required_len = nlayer * basis.max_phase_coef;
        try ensureCapacity(f64, self.allocator, &self.layer_effective_scattering_suffix, required_len);
        return self.layer_effective_scattering_suffix[0..required_len];
    }

    pub fn sourcePhaseMaxIndices(self: *Workspace, nlevel: usize) ![]usize {
        try ensureCapacity(usize, self.allocator, &self.source_phase_max_indices, nlevel);
        return self.source_phase_max_indices[0..nlevel];
    }

    pub fn ordersWorkspace(self: *Workspace, nlevel: usize) !*orders_mod.OrdersWorkspace {
        if (self.orders) |*orders| {
            if (orders.ud.len >= nlevel) {
                return orders;
            }
            orders.deinit();
            self.orders = null;
        }
        self.orders = try orders_mod.OrdersWorkspace.init(self.allocator, nlevel);
        return &(self.orders.?);
    }

    pub fn phaseKernelCache(self: *Workspace, nlevel: usize) ![]basis.PhaseKernel {
        try ensureCapacity(basis.PhaseKernel, self.allocator, &self.layer_phase_kernels, nlevel);
        return self.layer_phase_kernels[0..nlevel];
    }

    pub fn phaseKernelValid(self: *Workspace, nlevel: usize) ![]bool {
        try ensureCapacity(bool, self.allocator, &self.layer_phase_kernel_valid, nlevel);
        return self.layer_phase_kernel_valid[0..nlevel];
    }

    pub fn fourierPlmBasis(
        self: *Workspace,
        i_fourier: usize,
        max_phase_index: usize,
        geo: *const basis.Geometry,
    ) !*const basis.FourierPlmBasis {
        return (try self.fourierPlmBasisWithStatus(i_fourier, max_phase_index, geo)).plm_basis;
    }

    // layout(64-bit):
    //   size: 16 B, align: 8 B
    //   field storage: plm_basis=8 B, hit=1 B, extended=1 B; padding: 6 B (48 bits)
    //   unused bits: 48 padding + 14 bool-storage slack = 62 bits
    //   out-of-line: plm_basis carry references/descriptors; referenced storage is not included in size
    //   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
    //   footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above
    pub const PlmBasisCacheStatus = struct {
        plm_basis: *const basis.FourierPlmBasis,
        hit: bool,
        extended: bool,
    };

    pub fn fourierPlmBasisWithStatus(
        self: *Workspace,
        i_fourier: usize,
        max_phase_index: usize,
        geo: *const basis.Geometry,
    ) !PlmBasisCacheStatus {
        std.debug.assert(i_fourier < basis.max_phase_coef);
        const previous_cache_len = self.plm_basis_cache.len;
        const previous_valid_len = self.plm_basis_cache_valid.len;
        try ensureCapacity(basis.FourierPlmBasis, self.allocator, &self.plm_basis_cache, basis.max_phase_coef);
        try ensureCapacity(bool, self.allocator, &self.plm_basis_cache_valid, basis.max_phase_coef);
        if (previous_cache_len < basis.max_phase_coef or previous_valid_len < basis.max_phase_coef) {
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

    // layout(64-bit):
    //   size: 40 B, align: 8 B
    //   field storage: 40 B across 5 fields; largest: layer_count=8 B, max_index_matches=8 B, signature_matches=8 B; padding: 0 B (0 bits)
    //   unused bits: 0 padding + 0 bool-storage slack = 0 bits
    //   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
    //   footprint: per instance = 40 B (0.039 KiB); total = per instance * live instance count
    pub const LayerPhaseSignatureProbe = struct {
        layer_count: usize = 0,
        max_index_matches: usize = 0,
        signature_matches: usize = 0,
        reusable_fourier_layer_templates: usize = 0,
        possible_fourier_layer_templates: usize = 0,
    };

    pub fn probeLayerPhaseSignatures(
        self: *Workspace,
        layers: []const common.LayerInput,
        layer_phase_max_indices: []const usize,
        fourier_max: usize,
    ) !LayerPhaseSignatureProbe {
        std.debug.assert(layer_phase_max_indices.len >= layers.len);
        try ensureCapacity(u64, self.allocator, &self.previous_layer_phase_signatures, layers.len);
        const previous_valid_len = self.previous_layer_phase_signature_valid.len;
        try ensureCapacity(bool, self.allocator, &self.previous_layer_phase_signature_valid, layers.len);
        if (previous_valid_len < layers.len) {
            @memset(self.previous_layer_phase_signature_valid, false);
        }

        var probe = LayerPhaseSignatureProbe{ .layer_count = layers.len };
        for (layers, layer_phase_max_indices[0..layers.len], 0..) |layer, max_index, layer_idx| {
            const signature = layerPhaseSignature(layer.phase_coefficients, max_index);
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

fn layerPhaseSignature(phase_coefficients: [common.phase_coefficient_count]f64, max_index: usize) u64 {
    var hasher = std.hash.Wyhash.init(0x9e37_79b9_7f4a_7c15);
    hasher.update(std.mem.asBytes(&max_index));
    for (phase_coefficients[0 .. max_index + 1]) |coefficient| {
        const bits = @as(u64, @bitCast(coefficient));
        hasher.update(std.mem.asBytes(&bits));
    }
    return (@as(u64, @intCast(max_index)) << 56) ^ (hasher.final() & 0x00ff_ffff_ffff_ffff);
}

fn signatureMaxIndex(signature: u64) usize {
    return @intCast(signature >> 56);
}

fn ensureCapacity(
    comptime T: type,
    allocator: Allocator,
    buffer: *[]T,
    required_len: usize,
) !void {
    if (buffer.*.len >= required_len) return;
    const replacement = try allocator.alloc(T, required_len);
    allocator.free(buffer.*);
    buffer.* = replacement;
}
