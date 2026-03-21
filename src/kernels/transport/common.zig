const std = @import("std");
const SceneModel = @import("../../model/Scene.zig");
const phase_coefficient_count = @import("../optics/prepare/phase_functions.zig").phase_coefficient_count;

/// Atmospheric scattering treatment.
/// Defined locally to avoid a reverse dependency from kernels -> adapters.
pub const ScatteringMode = enum(u2) {
    none = 0,
    single = 1,
    multiple = 2,
};

/// Resolved radiative transfer method controls, compiled from canonical YAML.
/// These drive real transport behavior — they are not cosmetic hints.
pub const RtmControls = struct {
    /// Atmospheric scattering treatment
    scattering: ScatteringMode = .multiple,
    /// Number of discrete ordinate streams (half-streams = n_streams / 2)
    n_streams: u16 = 16,
    /// Use adding method (true) vs orders of scattering (false)
    use_adding: bool = false,
    /// Maximum scattering orders (0 = auto: int(bsca + 15))
    num_orders_max: u16 = 0,
    /// Fourier floor for scalar treatment (above this m, use dimSV=1)
    fourier_floor_scalar: u16 = 2,
    /// Convergence threshold for first scattering order
    threshold_conv_first: f64 = 1.0e-6,
    /// Convergence threshold for subsequent orders
    threshold_conv_mult: f64 = 1.0e-4,
    /// Doubling threshold: start doubling when aeff*b < this
    threshold_doubl: f64 = 0.1,
    /// Matrix multiplication threshold: skip smul when traces small
    threshold_mul: f64 = 1.0e-12,
    /// Use pseudo-spherical correction for direct-beam attenuation
    use_spherical_correction: bool = false,
    /// Integrate source function for reflectance (vs direct field extraction)
    integrate_source_function: bool = true,
    /// Renormalize phase function for quadrature conservation
    renorm_phase_function: bool = true,
    /// Stokes vector dimension (1=scalar, 3=I/Q/U, 4=full)
    stokes_dimension: u8 = 1,

    pub fn nGauss(self: RtmControls) u16 {
        return self.n_streams / 2;
    }

    pub fn validate(self: RtmControls, execution_mode: ExecutionMode) PrepareError!void {
        if (self.n_streams < 4 or (self.n_streams % 2) != 0) {
            return error.UnsupportedRtmControls;
        }
        switch (self.nGauss()) {
            2, 3, 4, 8, 10 => {},
            else => return error.UnsupportedRtmControls,
        }
        if (self.use_adding and self.scattering == .single) {
            return error.UnsupportedRtmControls;
        }
        if (self.stokes_dimension != 1 and execution_mode == .scalar) {
            return error.UnsupportedRtmControls;
        }
        if (self.threshold_conv_first <= 0.0 or
            self.threshold_conv_mult <= 0.0 or
            self.threshold_doubl <= 0.0 or
            self.threshold_mul <= 0.0)
        {
            return error.UnsupportedRtmControls;
        }
    }

    pub fn resolvedNumOrdersMax(self: RtmControls, scattering_optical_depth: f64) u16 {
        if (self.num_orders_max != 0) return self.num_orders_max;
        const heuristic = @max(scattering_optical_depth, 0.0) + 15.0;
        return @intFromFloat(std.math.clamp(heuristic, 1.0, @as(f64, std.math.maxInt(u16))));
    }

    /// Total number of directions: Gauss points + viewing + solar
    pub fn nDirections(self: RtmControls) u16 {
        return self.nGauss() + 2;
    }

    /// Supermatrix dimension: nDirections * stokes_dimension
    pub fn supermatrixSize(self: RtmControls) u32 {
        return @as(u32, self.nDirections()) * @as(u32, self.stokes_dimension);
    }

    pub const default_vendor = RtmControls{
        .scattering = .multiple,
        .n_streams = 16,
        .use_adding = false,
        .num_orders_max = 0,
        .fourier_floor_scalar = 2,
        .threshold_conv_first = 1.0e-6,
        .threshold_conv_mult = 1.0e-4,
        .threshold_doubl = 0.1,
        .threshold_mul = 1.0e-12,
        .use_spherical_correction = false,
        .integrate_source_function = true,
        .renorm_phase_function = true,
        .stokes_dimension = 1,
    };
};

pub const TransportFamily = enum {
    adding,
    labos,

    pub fn classification(self: TransportFamily) ImplementationClass {
        return switch (self) {
            .adding => .baseline,
            .labos => .baseline,
        };
    }

    pub fn provenanceLabel(self: TransportFamily) []const u8 {
        return switch (self) {
            .adding => "baseline_adding",
            .labos => "baseline_labos",
        };
    }
};

pub const ImplementationClass = enum {
    baseline,
    surrogate,
};

pub const DerivativeSemantics = enum {
    none,
    proxy,
    analytical,
};

pub const Regime = SceneModel.ObservationRegime;

pub const ExecutionMode = enum {
    scalar,
    polarized,
};

pub const DerivativeMode = SceneModel.DerivativeMode;

pub const DispatchRequest = struct {
    regime: Regime = .nadir,
    execution_mode: ExecutionMode = .scalar,
    derivative_mode: DerivativeMode = .none,
    rtm_controls: RtmControls = .{},
};

pub const Route = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    rtm_controls: RtmControls = .{},

    pub fn derivativeSemantics(self: Route) DerivativeSemantics {
        if (self.derivative_mode == .none) return .none;
        return switch (self.family.classification()) {
            .surrogate => .proxy,
            .baseline => .analytical,
        };
    }
};

pub const LayerInput = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.0,
    scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
    phase_coefficients: [phase_coefficient_count]f64 = .{ 1.0, 0.0, 0.0, 0.0 },
};

/// Source-function metadata on the transport interface grid.
/// `source_weight` is the legacy coarse-grid analogue of vendor `RTMweight * ksca`.
/// `rtm_weight` and `ksca_above` carry the split vendor-shaped contract when available,
/// with `rtm_weight` representing a geometric RTM quadrature weight rather than path length.
pub const SourceInterfaceInput = struct {
    source_weight: f64 = 0.0,
    rtm_weight: f64 = 0.0,
    ksca_above: f64 = 0.0,
    phase_coefficients_above: [phase_coefficient_count]f64 = .{ 1.0, 0.0, 0.0, 0.0 },

    pub fn effectiveWeight(self: SourceInterfaceInput) f64 {
        if (self.rtm_weight > 0.0 and self.ksca_above > 0.0) {
            return self.rtm_weight * self.ksca_above;
        }
        return self.source_weight;
    }
};

/// Explicit RTM quadrature carrier for integrated source-function evaluation.
/// Levels align with the transport field grid (`layers.len + 1`), with zero-weight
/// physical or parent-layer boundaries and active interior quadrature nodes.
pub const RtmQuadratureLevel = struct {
    altitude_km: f64 = 0.0,
    weight: f64 = 0.0,
    ksca: f64 = 0.0,
    phase_coefficients: [phase_coefficient_count]f64 = .{ 1.0, 0.0, 0.0, 0.0 },

    pub fn weightedScattering(self: RtmQuadratureLevel) f64 {
        return self.weight * self.ksca;
    }
};

pub const RtmQuadratureGrid = struct {
    levels: []const RtmQuadratureLevel = &.{},

    pub fn isValidFor(self: RtmQuadratureGrid, layer_count: usize) bool {
        return self.levels.len == layer_count + 1;
    }
};

pub const PseudoSphericalSample = struct {
    altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    optical_depth: f64 = 0.0,
};

pub const PseudoSphericalGrid = struct {
    samples: []const PseudoSphericalSample = &.{},
    level_sample_starts: []const usize = &.{},
    level_altitudes_km: []const f64 = &.{},

    pub fn isValidFor(self: PseudoSphericalGrid, layer_count: usize) bool {
        if (self.samples.len == 0) return false;
        if (self.level_sample_starts.len != layer_count + 1) return false;
        if (self.level_altitudes_km.len != 0 and self.level_altitudes_km.len != layer_count + 1) return false;
        if (self.level_sample_starts[0] != 0) return false;
        if (self.level_sample_starts[self.level_sample_starts.len - 1] != self.samples.len) return false;
        for (1..self.level_sample_starts.len) |index| {
            if (self.level_sample_starts[index] < self.level_sample_starts[index - 1] or
                self.level_sample_starts[index] > self.samples.len)
            {
                return false;
            }
        }
        return true;
    }
};

pub const ForwardInput = struct {
    wavelength_nm: f64 = 440.0,
    spectral_weight: f64 = 1.0,
    air_mass_factor: f64 = 1.0,
    mu0: f64 = 1.0,
    muv: f64 = 1.0,
    surface_albedo: f64 = 0.05,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,
    optical_depth: f64 = 0.5,
    single_scatter_albedo: f64 = 0.95,
    relative_azimuth_rad: f64 = 0.0,
    layers: []const LayerInput = &.{},
    source_interfaces: []const SourceInterfaceInput = &.{},
    rtm_quadrature: RtmQuadratureGrid = .{},
    pseudo_spherical_grid: PseudoSphericalGrid = .{},
    rtm_controls: RtmControls = .{},
};

pub const ForwardResult = struct {
    family: TransportFamily,
    regime: Regime,
    execution_mode: ExecutionMode,
    derivative_mode: DerivativeMode,
    toa_reflectance_factor: f64,
    jacobian_column: ?f64,
};

pub const PrepareError = error{
    UnsupportedDerivativeMode,
    UnsupportedExecutionMode,
    UnsupportedRtmControls,
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
    OutOfMemory,
};

pub const Error = ExecuteError;

pub fn prepareRoute(request: DispatchRequest) PrepareError!Route {
    if (request.derivative_mode == .analytical_plugin) {
        return Error.UnsupportedDerivativeMode;
    }
    try request.rtm_controls.validate(request.execution_mode);
    const family = selectFamily(request);
    if (family == .adding and request.execution_mode != .scalar) {
        return Error.UnsupportedExecutionMode;
    }
    return .{
        .family = family,
        .regime = request.regime,
        .execution_mode = request.execution_mode,
        .derivative_mode = request.derivative_mode,
        .rtm_controls = request.rtm_controls,
    };
}

fn selectFamily(request: DispatchRequest) TransportFamily {
    // If RTM controls explicitly request adding, use it
    if (request.rtm_controls.use_adding) return .adding;
    // For non-nadir observation, use LABOS
    if (request.regime != .nadir) return .labos;
    // Default: LABOS (matches vendor default behavior)
    return .labos;
}

pub fn sourceInterfaceFromLayers(layers: []const LayerInput, ilevel: usize) SourceInterfaceInput {
    if (layers.len == 0) return .{};
    const above_index = @min(ilevel, layers.len - 1);
    const source_weight = if (ilevel < layers.len)
        @max(layers[ilevel].scattering_optical_depth, 0.0)
    else
        0.5 * @max(layers[above_index].scattering_optical_depth, 0.0);

    return .{
        .source_weight = source_weight,
        .phase_coefficients_above = layers[above_index].phase_coefficients,
    };
}

pub fn fillSourceInterfacesFromLayers(
    layers: []const LayerInput,
    source_interfaces: []SourceInterfaceInput,
) void {
    if (layers.len == 0 or source_interfaces.len != layers.len + 1) return;
    for (source_interfaces, 0..) |*source_interface, ilevel| {
        source_interface.* = sourceInterfaceFromLayers(layers, ilevel);
    }
}

test "prepare route resolves families and keeps derivative mode explicit" {
    // Nadir with use_adding=true selects the adding family
    const adding_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{ .use_adding = true },
    });
    try std.testing.expectEqual(TransportFamily.adding, adding_route.family);
    try std.testing.expectEqual(DerivativeMode.semi_analytical, adding_route.derivative_mode);
    try std.testing.expectEqual(DerivativeSemantics.analytical, adding_route.derivativeSemantics());
    try std.testing.expectEqual(ImplementationClass.baseline, adding_route.family.classification());
    try std.testing.expectEqualStrings("baseline_adding", adding_route.family.provenanceLabel());

    const adding_no_scattering_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .none,
        },
    });
    try std.testing.expectEqual(TransportFamily.adding, adding_no_scattering_route.family);
    try std.testing.expectEqual(ScatteringMode.none, adding_no_scattering_route.rtm_controls.scattering);

    // Nadir without use_adding defaults to LABOS
    const nadir_default_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(TransportFamily.labos, nadir_default_route.family);

    const labos_route = try prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(TransportFamily.labos, labos_route.family);
    try std.testing.expectEqual(DerivativeMode.semi_analytical, labos_route.derivative_mode);
    try std.testing.expectEqual(DerivativeSemantics.analytical, labos_route.derivativeSemantics());
    try std.testing.expectEqualStrings("baseline_labos", labos_route.family.provenanceLabel());

    const twenty_stream_route = try prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{ .n_streams = 20 },
    });
    try std.testing.expectEqual(@as(u16, 20), twenty_stream_route.rtm_controls.n_streams);

    // Adding rejects polarized execution mode
    try std.testing.expectError(Error.UnsupportedExecutionMode, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .polarized,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    }));
    try std.testing.expectError(Error.UnsupportedRtmControls, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .scattering = .single,
        },
    }));
    try std.testing.expectError(Error.UnsupportedDerivativeMode, prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}

test "source interface builder preserves the top boundary weight and halves the bottom boundary weight" {
    const layers = [_]LayerInput{
        .{
            .scattering_optical_depth = 0.20,
            .phase_coefficients = .{ 1.0, 0.10, 0.0, 0.0 },
        },
        .{
            .scattering_optical_depth = 0.40,
            .phase_coefficients = .{ 1.0, 0.30, 0.0, 0.0 },
        },
    };
    var source_interfaces: [3]SourceInterfaceInput = undefined;
    fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[0].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), source_interfaces[1].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[2].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[1].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[2].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), source_interfaces[0].phase_coefficients_above[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[1].phase_coefficients_above[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[2].phase_coefficients_above[1], 1.0e-12);
}
