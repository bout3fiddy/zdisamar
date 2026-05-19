const std = @import("std");
const InstrumentGrid = @import("../forward_model/instrument_grid/root.zig");
const implementations = @import("../forward_model/implementations/root.zig");
const jacobian = @import("../forward_model/jacobian/root.zig");
const o2a_runtime = @import("../input/o2a_reference/run.zig");
const o2a_types = @import("../input/o2a_reference/types.zig");
const Trace = @import("../forward_model/performance_trace.zig");
const algebra = @import("algebra.zig");

const Allocator = std.mem.Allocator;
const Matrix = algebra.Matrix;
const Vector = algebra.Vector;

pub const max_state_count = algebra.max_state_count;
pub const max_iteration_count: usize = 1000;
pub const no_lower_bound = -std.math.inf(f64);
pub const no_upper_bound = std.math.inf(f64);

pub const Error = error{
    EmptyMeasurement,
    InvalidMeasurement,
    InvalidStateCount,
    InvalidStateSpec,
    InvalidPressureProfile,
    WavelengthGridMismatch,
    MissingJacobian,
    UnsupportedState,
    OutOfMemory,
    SingularMatrix,
    InvalidPriorCovariance,
};

// Scalar retrieval variable description passed from Python into native OE.
// layout(64-bit):
//   size: 104 B, align: 8 B
//   field storage: 101 B across 9 fields; largest: pressure_altitude_profile=48 B; padding: 3 B (24 bits)
//   unused bits: 24 padding + 0 bool-storage slack = 24 bits
//   encoded fields: bounds use infinities for absence; an empty pressure profile means no pressure-state metadata
//   cache span: 2 cache line(s) at 64 B per line
//   count: retrieval state count, currently 1..3
//   footprint: per instance = 104 B (0.102 KiB); total = per instance * state count
pub const StateSpec = struct {
    state: jacobian.State,
    initial: f64,
    prior: f64,
    variance: f64,
    lower_bound: f64 = no_lower_bound,
    upper_bound: f64 = no_upper_bound,
    thickness_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    pressure_altitude_profile: PressureAltitudeProfile = .{},
};

// Pressure-altitude table used to convert native altitude tangents to hPa tangents.
// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: altitude_km=16 B, pressure_hpa=16 B, second=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: all fields are borrowed or workspace-owned slices; referenced storage is not included in size
//   cache span: 1 cache line(s) at 64 B per line
//   count: at most one profile per pressure-placement state
//   footprint: per instance = 48 B (0.047 KiB); total also includes second-derivative storage
pub const PressureAltitudeProfile = struct {
    altitude_km: []const f64 = &.{},
    pressure_hpa: []const f64 = &.{},
    second: []const f64 = &.{},

    pub fn hasSamples(self: PressureAltitudeProfile) bool {
        return self.altitude_km.len != 0 or self.pressure_hpa.len != 0 or self.second.len != 0;
    }

    pub fn altitudeDerivativeAtPressure(self: PressureAltitudeProfile, pressure_hpa: f64) !f64 {
        if (self.altitude_km.len < 2 or self.altitude_km.len != self.pressure_hpa.len or self.second.len != self.altitude_km.len) {
            return error.InvalidPressureProfile;
        }
        const step_hpa = @max(@abs(pressure_hpa) * 1.0e-4, 1.0e-3);
        const lower_pressure = @max(self.pressure_hpa[self.pressure_hpa.len - 1], pressure_hpa - step_hpa);
        const upper_pressure = @min(self.pressure_hpa[0], pressure_hpa + step_hpa);
        if (upper_pressure <= lower_pressure) return error.InvalidPressureProfile;
        const altitude_span =
            try self.altitudeAtPressure(upper_pressure) -
            try self.altitudeAtPressure(lower_pressure);
        return altitude_span / (upper_pressure - lower_pressure);
    }

    fn altitudeAtPressure(self: PressureAltitudeProfile, pressure_hpa: f64) !f64 {
        if (!std.math.isFinite(pressure_hpa)) return error.InvalidPressureProfile;
        const lower_pressure = self.pressure_hpa[self.pressure_hpa.len - 1];
        const upper_pressure = self.pressure_hpa[0];
        if (pressure_hpa < lower_pressure or pressure_hpa > upper_pressure) return error.InvalidPressureProfile;

        var lower_altitude = self.altitude_km[0];
        var upper_altitude = self.altitude_km[self.altitude_km.len - 1];
        for (0..80) |_| {
            const mid_altitude = 0.5 * (lower_altitude + upper_altitude);
            const mid_pressure = try self.pressureAtAltitude(mid_altitude);
            if (mid_pressure > pressure_hpa) {
                lower_altitude = mid_altitude;
            } else {
                upper_altitude = mid_altitude;
            }
        }
        return 0.5 * (lower_altitude + upper_altitude);
    }

    fn pressureAtAltitude(self: PressureAltitudeProfile, altitude_km: f64) !f64 {
        const log_pressure = try cubicSplineSample(
            self.altitude_km,
            self.pressure_hpa,
            self.second,
            altitude_km,
        );
        return @exp(log_pressure);
    }
};

// Long-lived measurement buffers for one retrieval.
// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: four slice descriptors at 16 B each; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: spectral arrays are dense f64 SoA buffers owned by this workspace
//   cache span: 1 cache line(s) at 64 B per line
//   count: one per retrieval
//   footprint: per instance = 64 B (0.062 KiB); total also includes 4 * sample_count * 8 B
pub const MeasurementWorkspace = struct {
    wavelength_nm: []f64 = &.{},
    reflectance: []f64 = &.{},
    variance: []f64 = &.{},
    inv_variance: []f64 = &.{},

    pub fn init(
        allocator: Allocator,
        wavelength_nm: []const f64,
        reflectance: []const f64,
        variance: []const f64,
    ) !MeasurementWorkspace {
        if (wavelength_nm.len == 0) return error.EmptyMeasurement;
        if (wavelength_nm.len != reflectance.len or wavelength_nm.len != variance.len) return error.InvalidMeasurement;
        var workspace: MeasurementWorkspace = .{};
        errdefer workspace.deinit(allocator);
        workspace.wavelength_nm = try allocator.dupe(f64, wavelength_nm);
        workspace.reflectance = try allocator.dupe(f64, reflectance);
        workspace.variance = try allocator.dupe(f64, variance);
        workspace.inv_variance = try allocator.alloc(f64, variance.len);
        for (workspace.wavelength_nm, workspace.reflectance, workspace.variance, workspace.inv_variance, 0..) |wavelength, y, var_value, *inv, index| {
            if (!std.math.isFinite(wavelength) or !std.math.isFinite(y) or !std.math.isFinite(var_value) or var_value <= 0.0) {
                return error.InvalidMeasurement;
            }
            if (index != 0 and wavelength <= workspace.wavelength_nm[index - 1]) return error.InvalidMeasurement;
            inv.* = 1.0 / var_value;
        }
        return workspace;
    }

    pub fn deinit(self: *MeasurementWorkspace, allocator: Allocator) void {
        allocator.free(self.wavelength_nm);
        allocator.free(self.reflectance);
        allocator.free(self.variance);
        allocator.free(self.inv_variance);
        self.* = .{};
    }
};

// Reused fixed-size state-space scratch. The spectral dimension is never stored here.
// layout(64-bit):
//   size: 560 B, align: 8 B
//   field storage: vectors=128 B across 8 x [3]f64, matrices=432 B across 6 x 3x3 f64; padding: 0 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 9 cache line(s) at 64 B per line
//   count: one stack value per active retrieval
//   footprint: per instance = 560 B (0.547 KiB)
pub const IterationWorkspace = struct {
    sqrt_sa: Vector = algebra.zeroVector(),
    sqrt_inv_sa: Vector = algebra.zeroVector(),
    dx_white: Vector = algebra.zeroVector(),
    b: Vector = algebra.zeroVector(),
    dx_trans: Vector = algebra.zeroVector(),
    rhs_trans: Vector = algebra.zeroVector(),
    dx_trans_new: Vector = algebra.zeroVector(),
    dx_physical: Vector = algebra.zeroVector(),
    g: Matrix = algebra.zeroMatrix(),
    jt_invse_j: Matrix = algebra.zeroMatrix(),
    eigenvectors: Matrix = algebra.zeroMatrix(),
    posterior_precision: Matrix = algebra.zeroMatrix(),
    posterior_covariance: Matrix = algebra.zeroMatrix(),
    averaging_kernel: Matrix = algebra.zeroMatrix(),
};

// Native result storage retained behind the C result handle.
// layout(64-bit):
//   size: 184 B, align: 8 B
//   field storage: counters/status=4 B, slice descriptors=176 B across 11 fields; padding: 4 B
//   unused bits: 32 padding + 7 bool-storage slack = 39 bits
//   out-of-line: state, posterior, and history arrays are owned contiguous f64/u8 buffers
//   cache span: 3 cache line(s) at 64 B per line
//   count: one per completed retrieval result handle
//   footprint: per instance = 184 B (0.180 KiB); total also includes referenced result buffers
pub const Result = struct {
    state_count: u8 = 0,
    iteration_count: u16 = 0,
    converged: bool = false,
    state_ids: []jacobian.State = &.{},
    state: []f64 = &.{},
    initial_state: []f64 = &.{},
    posterior_covariance: []f64 = &.{},
    averaging_kernel: []f64 = &.{},
    history_state: []f64 = &.{},
    history_chi2: []f64 = &.{},
    history_chi2_reflectance: []f64 = &.{},
    history_chi2_state_vector: []f64 = &.{},
    history_state_vector_convergence: []f64 = &.{},
    history_snr_normal: []u8 = &.{},

    pub fn init(allocator: Allocator, state_count: usize, max_iterations: usize) !Result {
        if (state_count > max_state_count) return error.InvalidStateCount;
        if (max_iterations > max_iteration_count) return error.InvalidStateSpec;
        var result: Result = .{ .state_count = @intCast(state_count) };
        errdefer result.deinit(allocator);
        result.state_ids = try allocator.alloc(jacobian.State, state_count);
        result.state = try allocator.alloc(f64, state_count);
        result.initial_state = try allocator.alloc(f64, state_count);
        result.posterior_covariance = try allocator.alloc(f64, state_count * state_count);
        result.averaging_kernel = try allocator.alloc(f64, state_count * state_count);
        result.history_state = try allocator.alloc(f64, max_iterations * state_count);
        result.history_chi2 = try allocator.alloc(f64, max_iterations);
        result.history_chi2_reflectance = try allocator.alloc(f64, max_iterations);
        result.history_chi2_state_vector = try allocator.alloc(f64, max_iterations);
        result.history_state_vector_convergence = try allocator.alloc(f64, max_iterations);
        result.history_snr_normal = try allocator.alloc(u8, max_iterations);
        return result;
    }

    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.state_ids);
        allocator.free(self.state);
        allocator.free(self.initial_state);
        allocator.free(self.posterior_covariance);
        allocator.free(self.averaging_kernel);
        allocator.free(self.history_state);
        allocator.free(self.history_chi2);
        allocator.free(self.history_chi2_reflectance);
        allocator.free(self.history_chi2_state_vector);
        allocator.free(self.history_state_vector_convergence);
        allocator.free(self.history_snr_normal);
        self.* = .{};
    }
};

pub const Controls = struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};

pub fn runO2A(
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const StateSpec,
    forward_storage: *InstrumentGrid.ProductStorage,
    controls: Controls,
) !Result {
    const retrieval_zone = Trace.staticZone(@src(), "optimal_estimation.run");
    defer retrieval_zone.end();

    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;
    if (controls.max_iterations == 0 or controls.max_iterations > max_iteration_count) return error.InvalidStateSpec;
    Trace.plotU("optimal_estimation_state_count", @intCast(state_specs.len));
    Trace.plotU("optimal_estimation_max_iterations", @intCast(controls.max_iterations));

    var measurement = try MeasurementWorkspace.init(
        allocator,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
    );
    defer measurement.deinit(allocator);

    var loaded_inputs = try o2a_runtime.loadResolvedVendorO2AInputs(allocator, base_input);
    defer loaded_inputs.deinit(allocator);

    const mutable_intervals = try allocator.alloc(@import("../input/Atmosphere.zig").VerticalInterval, base_input.intervals.len);
    defer allocator.free(mutable_intervals);

    var result = try Result.init(allocator, state_specs.len, controls.max_iterations);
    errdefer result.deinit(allocator);

    var state = algebra.zeroVector();
    var prior = algebra.zeroVector();
    var variance = algebra.zeroVector();
    var lower = algebra.zeroVector();
    var upper = algebra.zeroVector();
    var derivative_state_mask: jacobian.StateMask = 0;

    for (state_specs, 0..) |spec, index| {
        try validateStateSpec(spec);
        result.state_ids[index] = spec.state;
        state[index] = spec.initial;
        prior[index] = spec.prior;
        variance[index] = spec.variance;
        result.initial_state[index] = spec.initial;
        derivative_state_mask |= jacobian.stateMask(spec.state);
        lower[index] = spec.lower_bound;
        upper[index] = spec.upper_bound;
    }

    var scratch: IterationWorkspace = .{};
    try algebra.choleskyLowerDiagonal(variance[0..state_specs.len], &scratch.sqrt_sa, &scratch.sqrt_inv_sa);

    var final_posterior_precision = algebra.zeroMatrix();
    for (0..state_specs.len) |index| {
        final_posterior_precision[index][index] = 1.0 / variance[index];
        scratch.posterior_covariance[index][index] = variance[index];
        scratch.averaging_kernel[index][index] = 1.0;
    }

    var converged = false;
    var iteration_count: usize = 0;
    for (0..controls.max_iterations) |iteration_offset| {
        const iteration_zone = Trace.staticZone(@src(), "optimal_estimation.iteration");
        defer iteration_zone.end();
        iteration_zone.value(@intCast(iteration_offset + 1));

        const previous = state;
        var evaluation = evaluation: {
            const zone = Trace.staticZone(@src(), "optimal_estimation.rtm_jacobian");
            defer zone.end();
            break :evaluation try evaluateO2AState(
                allocator,
                &loaded_inputs,
                base_input,
                mutable_intervals,
                forward_storage,
                state_specs,
                previous,
                derivative_state_mask,
            );
        };
        defer evaluation.runtime_case.deinit(allocator);

        const accumulation = accumulation: {
            const zone = Trace.staticZone(@src(), "optimal_estimation.normal_system");
            defer zone.end();
            break :accumulation try accumulateNormalSystem(
                measurement,
                evaluation.view,
                state_specs,
                previous,
                prior,
                scratch.sqrt_sa,
                evaluation.solar_mu0,
                &scratch,
            );
        };

        const step = step: {
            const zone = Trace.staticZone(@src(), "optimal_estimation.solver_update");
            defer zone.end();
            break :step try solveStep(
                state_specs.len,
                scratch.g,
                scratch.b,
                prior,
                scratch.sqrt_sa,
                scratch.sqrt_inv_sa,
                controls.max_change_transformed_state,
                &scratch,
            );
        };
        state = step.state;
        for (0..state_specs.len) |index| {
            state[index] = @min(upper[index], @max(lower[index], state[index]));
        }

        var dx_iter = algebra.zeroVector();
        for (0..state_specs.len) |index| dx_iter[index] = state[index] - previous[index];
        var chi2_state: f64 = 0.0;
        for (0..state_specs.len) |index| chi2_state += dx_iter[index] * dx_iter[index] / variance[index];
        const state_conv = quadraticForm(step.posterior_precision, dx_iter, state_specs.len) /
            @as(f64, @floatFromInt(state_specs.len));
        converged = state_conv < controls.state_vector_convergence_threshold and step.snr_normal;

        const history_offset = iteration_offset * state_specs.len;
        for (0..state_specs.len) |index| result.history_state[history_offset + index] = state[index];
        result.history_chi2[iteration_offset] = accumulation.chi2_reflectance + chi2_state;
        result.history_chi2_reflectance[iteration_offset] = accumulation.chi2_reflectance;
        result.history_chi2_state_vector[iteration_offset] = chi2_state;
        result.history_state_vector_convergence[iteration_offset] = state_conv;
        result.history_snr_normal[iteration_offset] = if (step.snr_normal) 1 else 0;

        final_posterior_precision = step.posterior_precision;
        scratch.jt_invse_j = accumulation.jt_invse_j;
        iteration_count = iteration_offset + 1;
        if (converged) break;
    }

    const posterior_covariance = try algebra.invertSymmetric(final_posterior_precision, state_specs.len);
    const averaging_kernel = algebra.multiply(posterior_covariance, scratch.jt_invse_j, state_specs.len);
    result.iteration_count = @intCast(iteration_count);
    result.converged = converged;
    for (0..state_specs.len) |row| {
        result.state[row] = state[row];
        for (0..state_specs.len) |col| {
            result.posterior_covariance[row * state_specs.len + col] = posterior_covariance[row][col];
            result.averaging_kernel[row * state_specs.len + col] = averaging_kernel[row][col];
        }
    }
    return result;
}

fn validateStateSpec(spec: StateSpec) !void {
    if (!std.math.isFinite(spec.initial) or
        !std.math.isFinite(spec.prior) or
        !std.math.isFinite(spec.variance) or
        spec.variance <= 0.0)
    {
        return error.InvalidStateSpec;
    }
    if (std.math.isNan(spec.lower_bound) or std.math.isNan(spec.upper_bound)) return error.InvalidStateSpec;
    if (spec.lower_bound != no_lower_bound and !std.math.isFinite(spec.lower_bound)) return error.InvalidStateSpec;
    if (spec.upper_bound != no_upper_bound and !std.math.isFinite(spec.upper_bound)) return error.InvalidStateSpec;
    if (spec.lower_bound > spec.upper_bound) return error.InvalidStateSpec;
    if (spec.state == .aerosol_layer_mid_pressure_hpa) {
        if (spec.thickness_hpa <= 0.0 or spec.interval_index_1based == 0 or !spec.pressure_altitude_profile.hasSamples()) {
            return error.InvalidStateSpec;
        }
    } else if (spec.thickness_hpa != 0.0 or spec.interval_index_1based != 0 or spec.pressure_altitude_profile.hasSamples()) {
        return error.InvalidStateSpec;
    }
}

// Borrowed forward evaluation consumed immediately by the OE accumulation loop.
// layout(64-bit):
//   size: 4128 B, align: 8 B
//   field storage: runtime_case=3808 B, view=320 B; padding: 0 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: runtime_case owns scene/prepared arrays; view borrows ProductStorage arrays
//   cache span: 65 cache line(s) at 64 B per line
//   count: one live value inside an iteration
//   footprint: per instance = 4128 B (4.031 KiB); borrowed product buffers live in ProductStorage
const ForwardEvaluation = struct {
    runtime_case: o2a_runtime.PreparedRuntimeEvaluation,
    view: InstrumentGrid.InstrumentGridProductView,
    solar_mu0: f64,
};

fn evaluateO2AState(
    allocator: Allocator,
    inputs: *const o2a_types.LoadedVendorO2AInputs,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    mutable_intervals: []@import("../input/Atmosphere.zig").VerticalInterval,
    forward_storage: *InstrumentGrid.ProductStorage,
    state_specs: []const StateSpec,
    state: Vector,
    derivative_state_mask: jacobian.StateMask,
) !ForwardEvaluation {
    var working_input = base_input.*;
    @memcpy(mutable_intervals, base_input.intervals);
    working_input.intervals = mutable_intervals;
    try writeStateToInput(&working_input, mutable_intervals, state_specs, state);

    var runtime_case = try o2a_runtime.prepareResolvedVendorO2AEvaluationWithInputs(
        allocator,
        &working_input,
        inputs,
    );
    errdefer runtime_case.deinit(allocator);
    runtime_case.route.derivative_mode = .semi_analytical;
    runtime_case.route.derivative_state_mask = derivative_state_mask;
    const view = try InstrumentGrid.simulateProductWithWorkspace(
        allocator,
        forward_storage,
        &runtime_case.scene,
        runtime_case.route,
        &runtime_case.prepared,
        implementations.exact(),
    );
    return .{
        .runtime_case = runtime_case,
        .view = view,
        .solar_mu0 = runtime_case.scene.geometry.solarCosineAtAltitude(0.0),
    };
}

fn writeStateToInput(
    input: *o2a_types.ResolvedVendorO2ACase,
    intervals: []@import("../input/Atmosphere.zig").VerticalInterval,
    state_specs: []const StateSpec,
    state: Vector,
) !void {
    for (state_specs, 0..) |spec, index| {
        const value = state[index];
        switch (spec.state) {
            .surface_albedo => input.surface_albedo = value,
            .aerosol_optical_depth => input.aerosol.optical_depth = value,
            .aerosol_layer_mid_pressure_hpa => {
                const fit_interval_index = @as(u64, spec.interval_index_1based);
                const half_thickness = 0.5 * spec.thickness_hpa;
                const top_pressure = value - half_thickness;
                const bottom_pressure = value + half_thickness;
                input.aerosol.placement.top_pressure_hpa = top_pressure;
                input.aerosol.placement.bottom_pressure_hpa = bottom_pressure;
                var updated = false;
                for (intervals) |*interval| {
                    const interval_index = @as(u64, interval.index_1based);
                    if (interval_index == fit_interval_index) {
                        interval.top_pressure_hpa = top_pressure;
                        interval.bottom_pressure_hpa = bottom_pressure;
                        updated = true;
                    } else if (interval_index + 1 == fit_interval_index) {
                        interval.bottom_pressure_hpa = top_pressure;
                    } else if (interval_index == fit_interval_index + 1) {
                        interval.top_pressure_hpa = bottom_pressure;
                    }
                }
                if (!updated) return error.InvalidStateSpec;
            },
        }
    }
}

const Accumulation = struct {
    chi2_reflectance: f64,
    jt_invse_j: Matrix,
};

// Per-iteration projection from native RTM Jacobian columns into the OE state vector.
// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: source_index=24 B, state_scale=24 B; padding: 0 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: one stack value per OE iteration
//   footprint: per instance = 48 B (0.047 KiB)
const JacobianProjection = struct {
    source_index: [max_state_count]usize = [_]usize{0} ** max_state_count,
    state_scale: Vector = algebra.zeroVector(),
};

fn accumulateNormalSystem(
    measurement: MeasurementWorkspace,
    view: InstrumentGrid.InstrumentGridProductView,
    state_specs: []const StateSpec,
    previous: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    solar_mu0: f64,
    scratch: *IterationWorkspace,
) !Accumulation {
    if (view.wavelengths.len != measurement.wavelength_nm.len) return error.WavelengthGridMismatch;
    const raw_jacobian = view.jacobian orelse return error.MissingJacobian;
    scratch.b = algebra.zeroVector();
    scratch.g = algebra.zeroMatrix();
    scratch.jt_invse_j = algebra.zeroMatrix();
    var projection: JacobianProjection = .{};
    for (0..state_specs.len) |index| {
        scratch.dx_white[index] = (previous[index] - prior[index]) / sqrt_sa[index];
        const spec = state_specs[index];
        projection.source_index[index] = jacobian.stateIndex(spec.state);
        projection.state_scale[index] = if (spec.state == .aerosol_layer_mid_pressure_hpa)
            try spec.pressure_altitude_profile.altitudeDerivativeAtPressure(previous[index])
        else
            1.0;
    }

    var chi2_reflectance: f64 = 0.0;
    var column_values = algebra.zeroVector();
    for (measurement.wavelength_nm, 0..) |wavelength_nm, sample_index| {
        if (view.wavelengths[sample_index] != wavelength_nm) return error.WavelengthGridMismatch;
        const residual = measurement.reflectance[sample_index] - view.reflectance[sample_index];
        const inv_variance = measurement.inv_variance[sample_index];
        chi2_reflectance += residual * residual * inv_variance;
        const reflectance_scale = std.math.pi / (solar_mu0 * @max(view.irradiance[sample_index], 1.0e-300));
        for (0..state_specs.len) |state_index| {
            const source_index = sample_index * jacobian.state_count + projection.source_index[state_index];
            column_values[state_index] =
                raw_jacobian[source_index] * reflectance_scale * projection.state_scale[state_index];
        }
        for (0..state_specs.len) |row| {
            const weighted_row = column_values[row] * inv_variance;
            scratch.b[row] += sqrt_sa[row] * weighted_row * residual;
            for (0..state_specs.len) |col| {
                const normal = weighted_row * column_values[col];
                scratch.jt_invse_j[row][col] += normal;
                scratch.g[row][col] += sqrt_sa[row] * normal * sqrt_sa[col];
            }
        }
    }
    return .{
        .chi2_reflectance = chi2_reflectance,
        .jt_invse_j = scratch.jt_invse_j,
    };
}

const Step = struct {
    state: Vector,
    posterior_precision: Matrix,
    snr_normal: bool,
};

fn solveStep(
    state_count: usize,
    g: Matrix,
    b: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    sqrt_inv_sa: Vector,
    max_change_transformed_state: f64,
    scratch: *IterationWorkspace,
) !Step {
    const eig = algebra.jacobiEigenSymmetric(g, state_count);
    scratch.eigenvectors = eig.vectors;
    scratch.dx_trans = algebra.transposeMatrixVector(eig.vectors, scratch.dx_white, state_count);
    scratch.rhs_trans = algebra.transposeMatrixVector(eig.vectors, b, state_count);

    var max_dx_trans: f64 = 0.0;
    for (0..state_count) |index| max_dx_trans = @max(max_dx_trans, @abs(scratch.dx_trans[index]));
    const max_change = @max(max_change_transformed_state, max_dx_trans);
    var lambda_scale: f64 = 1.0;
    var snr_normal = true;
    computeTransformedUpdate(eig.values, scratch.rhs_trans, scratch.dx_trans, state_count, lambda_scale, &scratch.dx_trans_new);
    var change = transformedChange(scratch.dx_trans_new, scratch.dx_trans, state_count);
    if (change > 1.01 * max_change) {
        snr_normal = false;
        var factor_total: f64 = 1.0;
        for (0..10) |_| {
            factor_total *= 0.75;
            const scale2 = factor_total * factor_total;
            computeTransformedUpdate(eig.values, scratch.rhs_trans, scratch.dx_trans, state_count, scale2, &scratch.dx_trans_new);
            change = transformedChange(scratch.dx_trans_new, scratch.dx_trans, state_count);
            if (change < max_change) {
                lambda_scale = scale2;
                break;
            }
        }
    }

    const rotated = algebra.matrixVector(eig.vectors, scratch.dx_trans_new, state_count);
    var state = algebra.zeroVector();
    for (0..state_count) |index| {
        scratch.dx_physical[index] = sqrt_sa[index] * rotated[index];
        state[index] = prior[index] + scratch.dx_physical[index];
    }

    var posterior_white = algebra.identityMatrix(state_count);
    for (0..state_count) |row| {
        for (0..state_count) |col| {
            var value: f64 = 0.0;
            for (0..state_count) |k| {
                value += eig.vectors[row][k] * (lambda_scale * eig.values[k]) * eig.vectors[col][k];
            }
            posterior_white[row][col] += value;
        }
    }

    var posterior_precision = algebra.zeroMatrix();
    for (0..state_count) |row| {
        for (0..state_count) |col| {
            posterior_precision[row][col] = sqrt_inv_sa[row] * posterior_white[row][col] * sqrt_inv_sa[col];
        }
    }
    return .{
        .state = state,
        .posterior_precision = posterior_precision,
        .snr_normal = snr_normal,
    };
}

fn computeTransformedUpdate(
    eigenvalues: Vector,
    rhs_trans: Vector,
    dx_trans: Vector,
    state_count: usize,
    lambda_scale: f64,
    out: *Vector,
) void {
    for (0..state_count) |index| {
        const lambda = lambda_scale * eigenvalues[index];
        out[index] = (lambda_scale * rhs_trans[index] + lambda * dx_trans[index]) / (lambda + 1.0);
    }
}

fn transformedChange(next: Vector, previous: Vector, state_count: usize) f64 {
    var change: f64 = 0.0;
    for (0..state_count) |index| change = @max(change, @abs(next[index] - previous[index]));
    return change;
}

fn quadraticForm(matrix: Matrix, vector: Vector, state_count: usize) f64 {
    var value: f64 = 0.0;
    for (0..state_count) |row| {
        var row_value: f64 = 0.0;
        for (0..state_count) |col| row_value += matrix[row][col] * vector[col];
        value += vector[row] * row_value;
    }
    return value;
}

pub fn buildPressureProfile(
    allocator: Allocator,
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) !PressureAltitudeProfile {
    if (altitude_km.len < 2 or altitude_km.len != pressure_hpa.len) return error.InvalidPressureProfile;
    const second = try allocator.alloc(f64, altitude_km.len);
    errdefer allocator.free(second);
    try endpointSplineSecondDerivatives(allocator, altitude_km, pressure_hpa, second);
    return .{
        .altitude_km = altitude_km,
        .pressure_hpa = pressure_hpa,
        .second = second,
    };
}

pub fn freePressureProfile(allocator: Allocator, profile: PressureAltitudeProfile) void {
    if (profile.second.len == 0) return;
    allocator.free(profile.second);
}

fn validatePressureProfileSamples(altitude_km: []const f64, pressure_hpa: []const f64) !void {
    if (altitude_km.len < 2 or altitude_km.len != pressure_hpa.len) return error.InvalidPressureProfile;
    for (0..altitude_km.len) |index| {
        if (!std.math.isFinite(altitude_km[index]) or !std.math.isFinite(pressure_hpa[index]) or pressure_hpa[index] <= 0.0) {
            return error.InvalidPressureProfile;
        }
        if (index != 0 and (altitude_km[index] <= altitude_km[index - 1] or pressure_hpa[index] >= pressure_hpa[index - 1])) {
            return error.InvalidPressureProfile;
        }
    }
}

fn endpointSplineSecondDerivatives(allocator: Allocator, x: []const f64, pressure_hpa: []const f64, second: []f64) !void {
    const count = x.len;
    if (count != pressure_hpa.len or count != second.len or count < 2) return error.InvalidPressureProfile;
    try validatePressureProfileSamples(x, pressure_hpa);
    if (count == 2) {
        second[0] = 0.0;
        second[1] = 0.0;
        return;
    }
    var matrix = algebra.zeroMatrix();
    if (count > max_state_count) {
        return endpointSplineSecondDerivativesDynamic(allocator, x, pressure_hpa, second);
    }
    var rhs = algebra.zeroVector();
    const width0 = x[1] - x[0];
    matrix[0][0] = 2.0 * width0;
    matrix[0][1] = width0;
    rhs[0] = 0.0;
    for (1..count - 1) |index| {
        const width_left = x[index] - x[index - 1];
        const width_right = x[index + 1] - x[index];
        const slope_left = (@log(pressure_hpa[index]) - @log(pressure_hpa[index - 1])) / width_left;
        const slope_right = (@log(pressure_hpa[index + 1]) - @log(pressure_hpa[index])) / width_right;
        matrix[index][index - 1] = width_left;
        matrix[index][index] = 2.0 * (width_left + width_right);
        matrix[index][index + 1] = width_right;
        rhs[index] = 6.0 * (slope_right - slope_left);
    }
    const last = count - 1;
    const width_last = x[last] - x[last - 1];
    matrix[last][last - 1] = width_last;
    matrix[last][last] = 2.0 * width_last;
    const inverse = try algebra.invertSymmetric(matrix, count);
    const solved = algebra.matrixVector(inverse, rhs, count);
    for (0..count) |index| second[index] = solved[index];
}

fn endpointSplineSecondDerivativesDynamic(allocator: Allocator, x: []const f64, pressure_hpa: []const f64, second: []f64) !void {
    const count = x.len;
    var lower = try allocator.alloc(f64, count);
    defer allocator.free(lower);
    var diag = try allocator.alloc(f64, count);
    defer allocator.free(diag);
    var upper = try allocator.alloc(f64, count);
    defer allocator.free(upper);
    var rhs = try allocator.alloc(f64, count);
    defer allocator.free(rhs);
    @memset(lower, 0.0);
    @memset(diag, 0.0);
    @memset(upper, 0.0);
    @memset(rhs, 0.0);
    const width0 = x[1] - x[0];
    diag[0] = 2.0 * width0;
    upper[0] = width0;
    for (1..count - 1) |index| {
        const width_left = x[index] - x[index - 1];
        const width_right = x[index + 1] - x[index];
        const slope_left = (@log(pressure_hpa[index]) - @log(pressure_hpa[index - 1])) / width_left;
        const slope_right = (@log(pressure_hpa[index + 1]) - @log(pressure_hpa[index])) / width_right;
        lower[index] = width_left;
        diag[index] = 2.0 * (width_left + width_right);
        upper[index] = width_right;
        rhs[index] = 6.0 * (slope_right - slope_left);
    }
    const last = count - 1;
    const width_last = x[last] - x[last - 1];
    lower[last] = width_last;
    diag[last] = 2.0 * width_last;
    for (1..count) |index| {
        const factor = lower[index] / diag[index - 1];
        diag[index] -= factor * upper[index - 1];
        rhs[index] -= factor * rhs[index - 1];
    }
    second[last] = rhs[last] / diag[last];
    var reverse_index = last;
    while (reverse_index > 0) {
        reverse_index -= 1;
        second[reverse_index] = (rhs[reverse_index] - upper[reverse_index] * second[reverse_index + 1]) / diag[reverse_index];
    }
}

fn cubicSplineSample(x: []const f64, pressure_hpa: []const f64, second: []const f64, value: f64) !f64 {
    var lower_index: usize = 0;
    while (lower_index + 1 < x.len and x[lower_index + 1] < value) : (lower_index += 1) {}
    lower_index = @min(lower_index, x.len - 2);
    const upper_index = lower_index + 1;
    const width = x[upper_index] - x[lower_index];
    if (width <= 0.0) return error.InvalidPressureProfile;
    const upper_weight = (x[upper_index] - value) / width;
    const lower_weight = (value - x[lower_index]) / width;
    const y0 = @log(pressure_hpa[lower_index]);
    const y1 = @log(pressure_hpa[upper_index]);
    var interpolated = upper_weight * y0 + lower_weight * y1;
    interpolated += ((upper_weight * upper_weight * upper_weight - upper_weight) * second[lower_index] +
        (lower_weight * lower_weight * lower_weight - lower_weight) * second[upper_index]) * width * width / 6.0;
    return interpolated;
}
