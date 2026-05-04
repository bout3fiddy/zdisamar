const std = @import("std");
const basis = @import("basis.zig");
const common = @import("../root.zig");
const attenuation_mod = @import("attenuation.zig");
const orders_mod = @import("orders.zig");

const Allocator = std.mem.Allocator;

pub const Workspace = struct {
    allocator: Allocator,
    attenuation_data: []f64 = &.{},
    attenuation_layer_transmittance: []f64 = &.{},
    rt_layers: []basis.LayerRT = &.{},
    layer_phase_max_indices: []usize = &.{},
    source_phase_max_indices: []usize = &.{},
    orders: ?orders_mod.OrdersWorkspace = null,
    layer_phase_kernels: []basis.PhaseKernel = &.{},
    layer_phase_kernel_valid: []bool = &.{},
    plm_basis_cache: []basis.FourierPlmBasis = &.{},
    plm_basis_cache_valid: []bool = &.{},
    cached_geometry: basis.Geometry = undefined,
    cached_geometry_valid: bool = false,

    pub fn init(allocator: Allocator) Workspace {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Workspace) void {
        if (self.orders) |*orders| orders.deinit();
        self.allocator.free(self.attenuation_data);
        self.allocator.free(self.attenuation_layer_transmittance);
        self.allocator.free(self.rt_layers);
        self.allocator.free(self.layer_phase_max_indices);
        self.allocator.free(self.source_phase_max_indices);
        self.allocator.free(self.layer_phase_kernels);
        self.allocator.free(self.layer_phase_kernel_valid);
        self.allocator.free(self.plm_basis_cache);
        self.allocator.free(self.plm_basis_cache_valid);
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

    pub fn geometry(
        self: *Workspace,
        n_gauss: usize,
        mu0: f64,
        muv: f64,
    ) *const basis.Geometry {
        if (!self.cached_geometry_valid or
            self.cached_geometry.n_gauss != n_gauss or
            self.cached_geometry.mu0 != mu0 or
            self.cached_geometry.muv != muv)
        {
            self.cached_geometry = basis.Geometry.init(n_gauss, mu0, muv);
            self.cached_geometry_valid = true;
            @memset(self.plm_basis_cache_valid, false);
        }
        return &self.cached_geometry;
    }

    pub fn layerRt(self: *Workspace, nlevel: usize) ![]basis.LayerRT {
        try ensureCapacity(basis.LayerRT, self.allocator, &self.rt_layers, nlevel);
        return self.rt_layers[0..nlevel];
    }

    pub fn layerPhaseMaxIndices(self: *Workspace, nlayer: usize) ![]usize {
        try ensureCapacity(usize, self.allocator, &self.layer_phase_max_indices, nlayer);
        return self.layer_phase_max_indices[0..nlayer];
    }

    pub fn sourcePhaseMaxIndices(self: *Workspace, nlevel: usize) ![]usize {
        try ensureCapacity(usize, self.allocator, &self.source_phase_max_indices, nlevel);
        return self.source_phase_max_indices[0..nlevel];
    }

    pub fn ordersWorkspace(self: *Workspace, nlevel: usize) !*orders_mod.OrdersWorkspace {
        if (self.orders) |*orders| {
            if (orders.ud.len >= nlevel) return orders;
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
        std.debug.assert(i_fourier < basis.max_phase_coef);
        const previous_cache_len = self.plm_basis_cache.len;
        const previous_valid_len = self.plm_basis_cache_valid.len;
        try ensureCapacity(basis.FourierPlmBasis, self.allocator, &self.plm_basis_cache, basis.max_phase_coef);
        try ensureCapacity(bool, self.allocator, &self.plm_basis_cache_valid, basis.max_phase_coef);
        if (previous_cache_len < basis.max_phase_coef or previous_valid_len < basis.max_phase_coef) {
            @memset(self.plm_basis_cache_valid, false);
        }
        if (!self.plm_basis_cache_valid[i_fourier] or
            self.plm_basis_cache[i_fourier].max_phase_index < max_phase_index)
        {
            self.plm_basis_cache[i_fourier] = basis.FourierPlmBasis.init(i_fourier, max_phase_index, geo);
            self.plm_basis_cache_valid[i_fourier] = true;
        }
        return &self.plm_basis_cache[i_fourier];
    }
};

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
