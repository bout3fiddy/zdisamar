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
    threshold_conv_first: f64 = 1.0e-5,
    /// Convergence threshold for subsequent orders
    threshold_conv_mult: f64 = 1.0e-8,
    /// Doubling threshold: start doubling when aeff*b < this
    threshold_doubl: f64 = 1.0e-6,
    /// Matrix multiplication threshold: skip smul when traces small
    threshold_mul: f64 = 1.0e-10,
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
        .threshold_conv_first = 1.0e-5,
        .threshold_conv_mult = 1.0e-8,
        .threshold_doubl = 1.0e-6,
        .threshold_mul = 1.0e-10,
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
    layers: []const LayerInput = &.{},
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
};

pub const ExecuteError = PrepareError || error{
    SingularDoublingDenominator,
};

pub const Error = ExecuteError;

pub fn prepareRoute(request: DispatchRequest) PrepareError!Route {
    if (request.derivative_mode == .analytical_plugin) {
        return Error.UnsupportedDerivativeMode;
    }
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

    // Adding rejects polarized execution mode
    try std.testing.expectError(Error.UnsupportedExecutionMode, prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .polarized,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    }));
    try std.testing.expectError(Error.UnsupportedDerivativeMode, prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}
