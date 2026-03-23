const std = @import("std");
const core_errors = @import("../../../core/errors.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const NoiseProviders = @import("../../../plugins/providers/noise.zig");
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const grid = @import("../../spectra/grid.zig");
const convolution = @import("../../spectra/convolution.zig");
const Types = @import("types.zig");

const Allocator = std.mem.Allocator;

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    NoiseProviders.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    jacobian: ?[]f64 = null,
    noise_sigma: ?[]f64 = null,
};

pub const SummaryWorkspace = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    layer_inputs: []common.LayerInput = &.{},
    pseudo_spherical_layers: []common.LayerInput = &.{},
    source_interfaces: []common.SourceInterfaceInput = &.{},
    rtm_quadrature_levels: []common.RtmQuadratureLevel = &.{},
    pseudo_spherical_samples: []common.PseudoSphericalSample = &.{},
    pseudo_spherical_level_starts: []usize = &.{},
    pseudo_spherical_level_altitudes: []f64 = &.{},
    jacobian: []f64 = &.{},
    noise_sigma: []f64 = &.{},

    pub fn deinit(self: *SummaryWorkspace, allocator: Allocator) void {
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeLayerBuffer(allocator, self.layer_inputs);
        freeLayerBuffer(allocator, self.pseudo_spherical_layers);
        freeSourceInterfaceBuffer(allocator, self.source_interfaces);
        freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
        freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
        freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
        freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
        freeBuffer(allocator, self.jacobian);
        freeBuffer(allocator, self.noise_sigma);
        self.* = .{};
    }

    pub fn buffers(
        self: *SummaryWorkspace,
        allocator: Allocator,
        scene: *const Scene,
        route: common.Route,
        providers: Types.ProviderBindings,
    ) Error!Buffers {
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, route);
        const pseudo_spherical_sample_count = pseudoSphericalSampleCountHint(scene, route);
        const wants_jacobian = route.derivative_mode != .none;
        const wants_noise = providers.noise.materializesSigma(scene);

        try ensureBufferCapacity(allocator, &self.wavelengths, sample_count);
        try ensureBufferCapacity(allocator, &self.radiance, sample_count);
        try ensureBufferCapacity(allocator, &self.irradiance, sample_count);
        try ensureBufferCapacity(allocator, &self.reflectance, sample_count);
        try ensureBufferCapacity(allocator, &self.scratch, sample_count);
        try ensureLayerBufferCapacity(allocator, &self.layer_inputs, layer_count);
        try ensureLayerBufferCapacity(allocator, &self.pseudo_spherical_layers, pseudo_spherical_sample_count);
        try ensureSourceInterfaceBufferCapacity(allocator, &self.source_interfaces, layer_count + 1);
        try ensureRtmQuadratureBufferCapacity(allocator, &self.rtm_quadrature_levels, layer_count + 1);
        try ensurePseudoSphericalSampleBufferCapacity(allocator, &self.pseudo_spherical_samples, pseudo_spherical_sample_count);
        try ensureIndexBufferCapacity(allocator, &self.pseudo_spherical_level_starts, layer_count + 1);
        try ensureBufferCapacity(allocator, &self.pseudo_spherical_level_altitudes, layer_count + 1);
        if (wants_jacobian) {
            try ensureBufferCapacity(allocator, &self.jacobian, sample_count);
        }
        if (wants_noise) {
            try ensureBufferCapacity(allocator, &self.noise_sigma, sample_count);
        }

        return .{
            .wavelengths = self.wavelengths[0..sample_count],
            .radiance = self.radiance[0..sample_count],
            .irradiance = self.irradiance[0..sample_count],
            .reflectance = self.reflectance[0..sample_count],
            .scratch = self.scratch[0..sample_count],
            .layer_inputs = self.layer_inputs[0..layer_count],
            .pseudo_spherical_layers = self.pseudo_spherical_layers[0..pseudo_spherical_sample_count],
            .source_interfaces = self.source_interfaces[0 .. layer_count + 1],
            .rtm_quadrature_levels = self.rtm_quadrature_levels[0 .. layer_count + 1],
            .pseudo_spherical_samples = self.pseudo_spherical_samples[0..pseudo_spherical_sample_count],
            .pseudo_spherical_level_starts = self.pseudo_spherical_level_starts[0 .. layer_count + 1],
            .pseudo_spherical_level_altitudes = self.pseudo_spherical_level_altitudes[0 .. layer_count + 1],
            .jacobian = if (wants_jacobian) self.jacobian[0..sample_count] else null,
            .noise_sigma = if (wants_noise) self.noise_sigma[0..sample_count] else null,
        };
    }
};

pub fn transportLayerCountHint(scene: *const Scene, route: common.Route) usize {
    _ = route;
    const layer_count = @max(@as(usize, @intCast(scene.atmosphere.layer_count)), 1);
    return layer_count * @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn pseudoSphericalSampleCountHint(scene: *const Scene, route: common.Route) usize {
    const layer_count = transportLayerCountHint(scene, route);
    return layer_count * pseudoSphericalSubgridDivisions(scene);
}

pub fn resolvedTransportLayerCount(route: common.Route, prepared: *const OpticsPreparation.PreparedOpticalState) usize {
    _ = route;
    return prepared.transportLayerCount();
}

pub fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    return resolvedTransportLayerCount(route, prepared) * pseudoSphericalSubgridDivisions(scene);
}

fn pseudoSphericalSubgridDivisions(scene: *const Scene) usize {
    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn validateBuffers(sample_count: usize, buffers: Buffers) Error!void {
    if (sample_count == 0 or
        buffers.wavelengths.len != sample_count or
        buffers.radiance.len != sample_count or
        buffers.irradiance.len != sample_count or
        buffers.reflectance.len != sample_count or
        buffers.scratch.len != sample_count or
        buffers.layer_inputs.len == 0 or
        buffers.pseudo_spherical_layers.len == 0 or
        buffers.source_interfaces.len != buffers.layer_inputs.len + 1 or
        buffers.rtm_quadrature_levels.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.pseudo_spherical_samples.len != buffers.pseudo_spherical_layers.len or
        buffers.pseudo_spherical_level_starts.len != buffers.layer_inputs.len + 1 or
        buffers.pseudo_spherical_level_altitudes.len != buffers.layer_inputs.len + 1)
    {
        return error.ShapeMismatch;
    }
    if (buffers.jacobian) |jacobian| {
        if (jacobian.len != sample_count) return error.ShapeMismatch;
    }
    if (buffers.noise_sigma) |noise_sigma| {
        if (noise_sigma.len != sample_count) return error.ShapeMismatch;
    }
}

pub fn ensureBufferCapacity(allocator: Allocator, buffer: *[]f64, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(f64, capacity);
    freeBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureLayerBufferCapacity(allocator: Allocator, buffer: *[]common.LayerInput, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.LayerInput, capacity);
    freeLayerBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureSourceInterfaceBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.SourceInterfaceInput,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.SourceInterfaceInput, capacity);
    freeSourceInterfaceBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureRtmQuadratureBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.RtmQuadratureLevel,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.RtmQuadratureLevel, capacity);
    freeRtmQuadratureBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensurePseudoSphericalSampleBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.PseudoSphericalSample,
    capacity: usize,
) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.PseudoSphericalSample, capacity);
    freePseudoSphericalSampleBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureIndexBufferCapacity(allocator: Allocator, buffer: *[]usize, capacity: usize) Error!void {
    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(usize, capacity);
    freeIndexBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn freeBuffer(allocator: Allocator, buffer: []f64) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeLayerBuffer(allocator: Allocator, buffer: []common.LayerInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeSourceInterfaceBuffer(allocator: Allocator, buffer: []common.SourceInterfaceInput) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeRtmQuadratureBuffer(allocator: Allocator, buffer: []common.RtmQuadratureLevel) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freePseudoSphericalSampleBuffer(allocator: Allocator, buffer: []common.PseudoSphericalSample) void {
    if (buffer.len != 0) allocator.free(buffer);
}

fn freeIndexBuffer(allocator: Allocator, buffer: []usize) void {
    if (buffer.len != 0) allocator.free(buffer);
}
