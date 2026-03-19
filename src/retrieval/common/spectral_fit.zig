const std = @import("std");
const common = @import("contracts.zig");
const diagnostics = @import("diagnostics.zig");
const forward_model = @import("forward_model.zig");
const priors = @import("priors.zig");
const state_access = @import("state_access.zig");
const transforms = @import("transforms.zig");
const cholesky = @import("../../kernels/linalg/cholesky.zig");
const dense = @import("../../kernels/linalg/small_dense.zig");
const svd_fallback = @import("../../kernels/linalg/svd_fallback.zig");
const vector_ops = @import("../../kernels/linalg/vector_ops.zig");
const airmass_phase = @import("../../model/reference/airmass_phase.zig");
const cross_sections = @import("../../model/reference/cross_sections.zig");
const Allocator = std.mem.Allocator;
const StateParameter = @import("../../model/Scene.zig").StateParameter;

const SelectionStrategy = enum {
    all_samples,
    differential_zero_crossings,
};

const Policy = struct {
    selection_strategy: SelectionStrategy,
    fit_space: common.FitSpace,
    polynomial_order: u32,
    max_iterations_default: u32,
    damping: f64,
    selection_budget: usize,
};

const SelectionResult = struct {
    indices: []usize,
    zero_crossing_count: u32 = 0,

    fn deinit(self: *SelectionResult, allocator: Allocator) void {
        allocator.free(self.indices);
        self.* = undefined;
    }
};

const TransformedMeasurement = struct {
    wavelengths_nm: []f64,
    values: []f64,
    sigma: []f64,
    optical_depth_proxy: []f64,
    amf_profile: []f64,

    fn deinit(self: *TransformedMeasurement, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.values);
        allocator.free(self.sigma);
        allocator.free(self.optical_depth_proxy);
        allocator.free(self.amf_profile);
        self.* = undefined;
    }
};

const Linearization = struct {
    measurement: forward_model.SpectralMeasurement,
    transformed: TransformedMeasurement,
    residual: []f64,
    jacobian: []f64,
    measurement_normal: []f64,
    hessian: []f64,
    gradient: []f64,
    physical_state: []f64,
    scene: ?@import("../../model/Scene.zig").Scene = null,
    measurement_cost: f64,
    prior_cost: f64,
    fit_diagnostics: common.SolverOutcome.FitDiagnostics,

    fn deinit(self: *Linearization, allocator: Allocator) void {
        self.measurement.deinit(allocator);
        self.transformed.deinit(allocator);
        if (self.residual.len != 0) allocator.free(self.residual);
        if (self.jacobian.len != 0) allocator.free(self.jacobian);
        if (self.measurement_normal.len != 0) allocator.free(self.measurement_normal);
        if (self.hessian.len != 0) allocator.free(self.hessian);
        if (self.gradient.len != 0) allocator.free(self.gradient);
        if (self.physical_state.len != 0) allocator.free(self.physical_state);
        self.* = undefined;
    }
};

pub fn solveMethod(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    method: common.Method,
) common.Error!common.SolverOutcome {
    try problem.validateForMethod(method);
    const policy = policyForMethod(method);
    const layout = try state_access.resolveStateLayout(problem);
    const state_count = problem.inverse_problem.state_vector.parameters.len;

    var observed_measurement = try forward_model.observedMeasurement(allocator, problem);
    defer observed_measurement.deinit(allocator);
    var selection = try buildSelectionIndices(allocator, observed_measurement, policy);
    defer selection.deinit(allocator);

    var observed_transformed = try transformMeasurement(allocator, observed_measurement, policy, selection.indices);
    defer observed_transformed.deinit(allocator);

    var prior = try priors.assemble(allocator, problem);
    defer prior.deinit(allocator);

    const solver_state = try allocator.alloc(f64, state_count);
    defer allocator.free(solver_state);
    try seedSolverState(allocator, problem, layout, prior.mean_solver, solver_state);

    const max_iterations: u32 = if (problem.inverse_problem.fit_controls.max_iterations != 0)
        problem.inverse_problem.fit_controls.max_iterations
    else
        policy.max_iterations_default;

    var previous_total_cost: ?f64 = null;
    var iterations: u32 = 0;
    var converged = false;
    var last_step_norm: f64 = std.math.inf(f64);

    while (iterations < max_iterations) : (iterations += 1) {
        var linearization = try linearizeState(
            allocator,
            problem,
            evaluator,
            layout,
            solver_state,
            observed_transformed,
            selection,
            policy,
            prior,
        );
        defer linearization.deinit(allocator);

        const step = try allocator.alloc(f64, state_count);
        defer allocator.free(step);
        try solveSymmetricSystem(
            allocator,
            linearization.hessian,
            state_count,
            linearization.gradient,
            policy.damping,
            step,
        );

        const candidate_state = try allocator.dupe(f64, solver_state);
        defer allocator.free(candidate_state);
        var accepted_measurement_cost = linearization.measurement_cost;
        var accepted_prior_cost = linearization.prior_cost;
        var accepted_scale: f64 = 0.0;
        var accepted = false;
        var scale: f64 = 1.0;
        while (scale >= 1.0 / 64.0) : (scale *= 0.5) {
            try vector_ops.copy(solver_state, candidate_state);
            for (candidate_state, step) |*slot, value| {
                slot.* += scale * value;
            }

            accepted_measurement_cost = try candidateMeasurementCost(
                allocator,
                problem,
                evaluator,
                layout,
                candidate_state,
                observed_transformed,
                selection,
                policy,
            );
            accepted_prior_cost = priorCost(prior.inverse_covariance, candidate_state, prior.mean_solver);
            const current_total = linearization.measurement_cost + linearization.prior_cost;
            if (accepted_measurement_cost + accepted_prior_cost <= current_total) {
                accepted = true;
                accepted_scale = scale;
                break;
            }
        }

        if (!accepted) {
            last_step_norm = 0.0;
            previous_total_cost = linearization.measurement_cost + linearization.prior_cost;
            iterations += 1;
            break;
        }

        try vector_ops.copy(candidate_state, solver_state);
        const scaled_step = try allocator.alloc(f64, state_count);
        defer allocator.free(scaled_step);
        for (scaled_step, step) |*slot, value| slot.* = accepted_scale * value;

        const fit_summary = switch (method) {
            .doas => diagnostics.assessDifferential(
                previous_total_cost,
                accepted_measurement_cost,
                accepted_prior_cost,
                scaled_step,
                solver_state,
                problem.inverse_problem.convergence,
                @intCast(observed_transformed.values.len),
                0.0,
                policy.polynomial_order,
                linearization.fit_diagnostics.effective_air_mass_factor,
                linearization.fit_diagnostics.window_start_nm,
                linearization.fit_diagnostics.window_end_nm,
                linearization.fit_diagnostics.effective_cross_section_rms,
            ).common,
            .dismas => diagnostics.assessDirectIntensity(
                previous_total_cost,
                accepted_measurement_cost,
                accepted_prior_cost,
                scaled_step,
                solver_state,
                problem.inverse_problem.convergence,
                @intCast(observed_transformed.values.len),
                0.0,
                policy.polynomial_order,
                linearization.fit_diagnostics.effective_air_mass_factor,
                linearization.fit_diagnostics.window_start_nm,
                linearization.fit_diagnostics.window_end_nm,
                linearization.fit_diagnostics.selected_rtm_sample_count,
                linearization.fit_diagnostics.selection_zero_crossing_count,
            ).common,
            else => unreachable,
        };
        previous_total_cost = fit_summary.total_cost;
        last_step_norm = fit_summary.step_norm;
        converged = fit_summary.converged;
        if (converged) {
            iterations += 1;
            break;
        }
    }

    var final_context = try linearizeState(
        allocator,
        problem,
        evaluator,
        layout,
        solver_state,
        observed_transformed,
        selection,
        policy,
        prior,
    );
    errdefer final_context.deinit(allocator);

    const posterior_covariance = try invertHessian(
        allocator,
        final_context.hessian,
        state_count,
        policy.damping,
    );
    errdefer allocator.free(posterior_covariance);

    const averaging_kernel = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(averaging_kernel);
    try buildAveragingKernel(
        posterior_covariance,
        final_context.measurement_normal,
        state_count,
        averaging_kernel,
    );

    const dfs = try dense.trace(averaging_kernel, state_count);
    const final_values = try allocator.dupe(f64, final_context.physical_state);
    errdefer allocator.free(final_values);
    const parameter_names = try parameterNames(allocator, problem);
    defer allocator.free(parameter_names);
    const final_jacobian = final_context.jacobian;
    final_context.jacobian = &[_]f64{};

    const outcome = try common.outcome(
        allocator,
        problem,
        method,
        iterations,
        final_context.measurement_cost + final_context.prior_cost,
        converged,
        true,
        dfs,
        vector_ops.normL2(final_context.residual),
        last_step_norm,
        final_context.fit_diagnostics,
        .{
            .parameter_names = parameter_names,
            .values = final_values,
        },
        final_context.scene,
        final_context.measurement.summary,
        .{
            .row_count = @intCast(final_context.transformed.values.len),
            .column_count = @intCast(state_count),
            .values = final_jacobian,
        },
        .{
            .row_count = @intCast(state_count),
            .column_count = @intCast(state_count),
            .values = averaging_kernel,
        },
        .{
            .row_count = @intCast(state_count),
            .column_count = @intCast(state_count),
            .values = posterior_covariance,
        },
    );
    final_context.deinit(allocator);
    return outcome;
}

pub fn fitResidualCost(
    allocator: Allocator,
    method: common.Method,
    observed: forward_model.SpectralMeasurement,
    candidate: forward_model.SpectralMeasurement,
) common.Error!f64 {
    const policy = policyForMethod(method);
    var selection = try buildSelectionIndices(allocator, observed, policy);
    defer selection.deinit(allocator);

    var observed_transformed = try transformMeasurement(allocator, observed, policy, selection.indices);
    defer observed_transformed.deinit(allocator);
    var candidate_transformed = try transformMeasurement(allocator, candidate, policy, selection.indices);
    defer candidate_transformed.deinit(allocator);

    const weights = try inverseVarianceWeights(allocator, observed_transformed.sigma);
    defer allocator.free(weights);
    const residual = try residualInFitSpace(allocator, observed_transformed, candidate_transformed, policy, weights);
    defer allocator.free(residual);
    return weightedResidualCost(residual, observed_transformed.sigma);
}

fn policyForMethod(method: common.Method) Policy {
    return switch (method) {
        .doas => .{
            .selection_strategy = .all_samples,
            .fit_space = .differential_optical_depth,
            .polynomial_order = 3,
            .max_iterations_default = 8,
            .damping = 1.0e-5,
            .selection_budget = 0,
        },
        .dismas => .{
            .selection_strategy = .differential_zero_crossings,
            .fit_space = .radiance,
            .polynomial_order = 1,
            .max_iterations_default = 8,
            .damping = 1.0e-4,
            .selection_budget = 64,
        },
        else => unreachable,
    };
}

fn linearizeState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    solver_state: []f64,
    observed: TransformedMeasurement,
    selection: SelectionResult,
    policy: Policy,
    prior: priors.Assembly,
) common.Error!Linearization {
    const state_count = solver_state.len;
    const measurement_count = observed.values.len;

    const normalized_state = try allocator.dupe(f64, solver_state);
    errdefer allocator.free(normalized_state);
    const physical_state = try allocator.alloc(f64, state_count);
    errdefer allocator.free(physical_state);
    try normalizeSolverState(problem, normalized_state, physical_state);

    const scene = try state_access.sceneForStateWithLayout(problem, physical_state, layout);
    var measurement = try forward_model.evaluateMeasurement(allocator, problem, evaluator, scene);
    errdefer measurement.deinit(allocator);
    var transformed = try transformMeasurement(allocator, measurement, policy, selection.indices);
    errdefer transformed.deinit(allocator);

    const weights = try inverseVarianceWeights(allocator, observed.sigma);
    defer allocator.free(weights);
    const residual = try residualInFitSpace(allocator, observed, transformed, policy, weights);
    errdefer allocator.free(residual);

    const jacobian = try allocator.alloc(f64, measurement_count * state_count);
    errdefer allocator.free(jacobian);
    @memset(jacobian, 0.0);
    try buildNumericalJacobian(
        allocator,
        problem,
        evaluator,
        layout,
        normalized_state,
        physical_state,
        transformed,
        selection.indices,
        policy,
        weights,
        jacobian,
    );

    const measurement_normal = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(measurement_normal);
    const hessian = try allocator.alloc(f64, state_count * state_count);
    errdefer allocator.free(hessian);
    const gradient = try allocator.alloc(f64, state_count);
    errdefer allocator.free(gradient);
    try accumulateWeightedNormalEquation(jacobian, observed.sigma, measurement_count, state_count, measurement_normal, gradient, residual);
    @memcpy(hessian, measurement_normal);
    addMatrixInPlace(hessian, prior.inverse_covariance);
    subtractMatVec(gradient, prior.inverse_covariance, normalized_state, prior.mean_solver);

    const measurement_cost_value = weightedResidualCost(residual, observed.sigma);
    const prior_cost_value = priorCost(prior.inverse_covariance, normalized_state, prior.mean_solver);
    allocator.free(normalized_state);

    var fit_diagnostics = buildFitDiagnostics(allocator, policy, transformed, jacobian, state_count, selection);
    fit_diagnostics.weighted_residual_rms = std.math.sqrt(
        measurement_cost_value / @max(@as(f64, @floatFromInt(measurement_count)), 1.0),
    );

    return .{
        .measurement = measurement,
        .transformed = transformed,
        .residual = residual,
        .jacobian = jacobian,
        .measurement_normal = measurement_normal,
        .hessian = hessian,
        .gradient = gradient,
        .physical_state = physical_state,
        .scene = scene,
        .measurement_cost = measurement_cost_value,
        .prior_cost = prior_cost_value,
        .fit_diagnostics = fit_diagnostics,
    };
}

fn buildSelectionIndices(
    allocator: Allocator,
    measurement: forward_model.SpectralMeasurement,
    policy: Policy,
) !SelectionResult {
    const sample_count = measurement.values.len;
    const budget = if (policy.selection_budget == 0) sample_count else @min(policy.selection_budget, sample_count);
    const indices = try allocator.alloc(usize, budget);
    errdefer allocator.free(indices);
    if (budget == sample_count or policy.selection_strategy == .all_samples) {
        for (indices, 0..) |*slot, index| slot.* = index;
        return .{ .indices = indices };
    }

    const zero_crossings = try differentialZeroCrossingIndices(allocator, measurement, policy);
    defer allocator.free(zero_crossings);
    if (zero_crossings.len == 0) {
        for (indices, 0..) |*slot, index| {
            slot.* = if (budget <= 1)
                sample_count / 2
            else
                @min(sample_count - 1, (index * (sample_count - 1)) / (budget - 1));
        }
        return .{ .indices = indices };
    }

    const selected_count = @min(budget, zero_crossings.len);
    const selected = try allocator.alloc(usize, selected_count);
    errdefer allocator.free(selected);
    if (selected_count == 1) {
        selected[0] = zero_crossings[zero_crossings.len / 2];
    } else {
        for (selected, 0..) |*slot, output_index| {
            const scaled = output_index * (zero_crossings.len - 1);
            slot.* = zero_crossings[scaled / (selected_count - 1)];
        }
    }
    allocator.free(indices);
    std.sort.heap(usize, selected, {}, struct {
        fn lessThan(_: void, lhs: usize, rhs: usize) bool {
            return lhs < rhs;
        }
    }.lessThan);
    return .{
        .indices = selected,
        .zero_crossing_count = @intCast(zero_crossings.len),
    };
}

fn differentialZeroCrossingIndices(
    allocator: Allocator,
    measurement: forward_model.SpectralMeasurement,
    policy: Policy,
) ![]usize {
    const sample_count = measurement.values.len;
    if (sample_count < 3) return allocator.alloc(usize, 0);

    const optical_depth_proxy = try allocator.alloc(f64, sample_count);
    defer allocator.free(optical_depth_proxy);
    for (optical_depth_proxy, 0..) |*slot, index| {
        slot.* = opticalDepthProxyForIndex(measurement, index);
    }
    const weights = try inverseVarianceWeights(allocator, measurement.sigma);
    defer allocator.free(weights);
    const differential = cross_sections.differentialVector(
        allocator,
        measurement.wavelengths_nm,
        optical_depth_proxy,
        weights,
        policy.polynomial_order,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidRequest,
    };
    defer allocator.free(differential);

    var candidates = std.ArrayListUnmanaged(usize){};
    defer candidates.deinit(allocator);
    for (1..differential.len) |index| {
        const left = differential[index - 1];
        const right = differential[index];
        if ((left == 0.0 and right == 0.0) or left * right > 0.0) continue;
        const candidate = if (@abs(left) <= @abs(right)) index - 1 else index;
        if (candidates.items.len == 0 or candidates.items[candidates.items.len - 1] != candidate) {
            try candidates.append(allocator, candidate);
        }
    }
    return candidates.toOwnedSlice(allocator);
}

fn transformMeasurement(
    allocator: Allocator,
    measurement: forward_model.SpectralMeasurement,
    policy: Policy,
    selection_indices: []const usize,
) common.Error!TransformedMeasurement {
    const wavelengths = try allocator.alloc(f64, selection_indices.len);
    errdefer allocator.free(wavelengths);
    const values = try allocator.alloc(f64, selection_indices.len);
    errdefer allocator.free(values);
    const sigma = try allocator.alloc(f64, selection_indices.len);
    errdefer allocator.free(sigma);
    const optical_depth_proxy = try allocator.alloc(f64, selection_indices.len);
    errdefer allocator.free(optical_depth_proxy);

    for (selection_indices, 0..) |source_index, output_index| {
        wavelengths[output_index] = measurement.wavelengths_nm[source_index];
        optical_depth_proxy[output_index] = opticalDepthProxyForIndex(measurement, source_index);
    }
    const amf_profile = airmass_phase.spectralProfileFromOpticalDepth(
        allocator,
        wavelengths,
        measurement.metadata.effective_air_mass_factor,
        optical_depth_proxy,
    ) catch return common.Error.OutOfMemory;
    errdefer allocator.free(amf_profile);
    for (selection_indices, 0..) |source_index, output_index| {
        switch (policy.fit_space) {
            .differential_optical_depth => {
                values[output_index] = optical_depth_proxy[output_index];
                sigma[output_index] = measurement.sigma[source_index] /
                    @max(measurement.radiance[source_index], 1.0e-12);
            },
            .radiance => {
                values[output_index] = measurement.values[source_index];
                sigma[output_index] = measurement.sigma[source_index];
            },
        }
    }

    return .{
        .wavelengths_nm = wavelengths,
        .values = values,
        .sigma = sigma,
        .optical_depth_proxy = optical_depth_proxy,
        .amf_profile = amf_profile,
    };
}

fn opticalDepthProxyForIndex(measurement: forward_model.SpectralMeasurement, index: usize) f64 {
    const reflectance = if (measurement.reflectance.len != 0)
        measurement.reflectance[index]
    else
        (measurement.radiance[index] * std.math.pi) / @max(measurement.irradiance[index], 1.0e-12);
    return -std.math.log(f64, std.math.e, @max(reflectance, 1.0e-12));
}

fn inverseVarianceWeights(allocator: Allocator, sigma: []const f64) ![]f64 {
    const weights = try allocator.alloc(f64, sigma.len);
    for (weights, sigma) |*slot, value| {
        slot.* = 1.0 / @max(value * value, 1.0e-18);
    }
    return weights;
}

fn residualInFitSpace(
    allocator: Allocator,
    observed: TransformedMeasurement,
    predicted: TransformedMeasurement,
    policy: Policy,
    weights: []const f64,
) ![]f64 {
    const residual = try allocator.alloc(f64, observed.values.len);
    for (residual, observed.values, predicted.values) |*slot, lhs, rhs| {
        slot.* = lhs - rhs;
    }
    if (policy.fit_space == .radiance) {
        return residual;
    }
    const differential = cross_sections.differentialVector(
        allocator,
        observed.wavelengths_nm,
        residual,
        weights,
        policy.polynomial_order,
    ) catch |err| switch (err) {
        error.OutOfMemory => {
            allocator.free(residual);
            return error.OutOfMemory;
        },
        else => {
            allocator.free(residual);
            return error.InvalidRequest;
        },
    };
    allocator.free(residual);
    return differential;
}

fn buildNumericalJacobian(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    solver_state: []const f64,
    physical_state: []const f64,
    base_transformed: TransformedMeasurement,
    selection_indices: []const usize,
    policy: Policy,
    weights: []const f64,
    out: []f64,
) common.Error!void {
    const measurement_count = base_transformed.values.len;
    const state_count = physical_state.len;

    for (problem.inverse_problem.state_vector.parameters, 0..) |parameter, column| {
        const step_physical = finiteDifferenceStep(parameter, physical_state[column]);
        const perturbed_physical = try allocator.dupe(f64, physical_state);
        defer allocator.free(perturbed_physical);
        const perturbed_solver = try allocator.dupe(f64, solver_state);
        defer allocator.free(perturbed_solver);

        perturbed_physical[column] = clampPhysical(parameter, physical_state[column] + step_physical);
        perturbed_solver[column] = safeSolverValue(parameter, perturbed_physical[column]) catch return common.Error.InvalidRequest;
        const delta_solver = perturbed_solver[column] - solver_state[column];
        if (@abs(delta_solver) <= 1.0e-15) continue;

        const perturbed_scene = try state_access.sceneForStateWithLayout(problem, perturbed_physical, layout);
        var perturbed_measurement = try forward_model.evaluateMeasurement(allocator, problem, evaluator, perturbed_scene);
        defer perturbed_measurement.deinit(allocator);
        var perturbed_transformed = try transformMeasurement(allocator, perturbed_measurement, policy, selection_indices);
        defer perturbed_transformed.deinit(allocator);

        const raw_column = try allocator.alloc(f64, measurement_count);
        defer allocator.free(raw_column);
        for (raw_column, perturbed_transformed.values, base_transformed.values) |*slot, perturbed, base| {
            slot.* = (perturbed - base) / delta_solver;
        }
        if (policy.fit_space == .radiance) {
            for (raw_column, 0..) |value, row| {
                out[dense.index(row, column, state_count)] = value;
            }
        } else {
            const detrended = cross_sections.differentialVector(
                allocator,
                base_transformed.wavelengths_nm,
                raw_column,
                weights,
                policy.polynomial_order,
            ) catch |err| switch (err) {
                error.OutOfMemory => return common.Error.OutOfMemory,
                else => return common.Error.InvalidRequest,
            };
            defer allocator.free(detrended);
            for (detrended, 0..) |value, row| {
                out[dense.index(row, column, state_count)] = value;
            }
        }
    }
}

fn accumulateWeightedNormalEquation(
    jacobian: []const f64,
    sigma: []const f64,
    measurement_count: usize,
    state_count: usize,
    measurement_normal: []f64,
    gradient: []f64,
    residual: []const f64,
) !void {
    if (jacobian.len != measurement_count * state_count or
        sigma.len != measurement_count or
        measurement_normal.len != state_count * state_count or
        gradient.len != state_count or
        residual.len != measurement_count)
    {
        return error.ShapeMismatch;
    }

    @memset(measurement_normal, 0.0);
    @memset(gradient, 0.0);
    for (0..measurement_count) |row| {
        const weight = 1.0 / @max(sigma[row] * sigma[row], 1.0e-18);
        for (0..state_count) |column| {
            const j_col = jacobian[dense.index(row, column, state_count)];
            gradient[column] += j_col * residual[row] * weight;
            for (0..state_count) |other| {
                measurement_normal[dense.index(column, other, state_count)] +=
                    j_col * jacobian[dense.index(row, other, state_count)] * weight;
            }
        }
    }
}

fn candidateMeasurementCost(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    evaluator: forward_model.Evaluator,
    layout: state_access.ResolvedStateLayout,
    candidate_state: []f64,
    observed: TransformedMeasurement,
    selection: SelectionResult,
    policy: Policy,
) common.Error!f64 {
    const normalized_state = try allocator.dupe(f64, candidate_state);
    defer allocator.free(normalized_state);
    const physical_state = try allocator.alloc(f64, candidate_state.len);
    defer allocator.free(physical_state);
    try normalizeSolverState(problem, normalized_state, physical_state);

    const candidate_scene = try state_access.sceneForStateWithLayout(problem, physical_state, layout);
    var candidate_measurement = try forward_model.evaluateMeasurement(allocator, problem, evaluator, candidate_scene);
    defer candidate_measurement.deinit(allocator);
    var candidate_transformed = try transformMeasurement(allocator, candidate_measurement, policy, selection.indices);
    defer candidate_transformed.deinit(allocator);
    const weights = try inverseVarianceWeights(allocator, observed.sigma);
    defer allocator.free(weights);
    const residual = try residualInFitSpace(allocator, observed, candidate_transformed, policy, weights);
    defer allocator.free(residual);
    return weightedResidualCost(residual, observed.sigma);
}

fn buildFitDiagnostics(
    allocator: Allocator,
    policy: Policy,
    transformed: TransformedMeasurement,
    jacobian: []const f64,
    state_count: usize,
    selection: SelectionResult,
) common.SolverOutcome.FitDiagnostics {
    var effective_cross_section_rms: ?f64 = null;
    if (policy.fit_space == .differential_optical_depth and state_count != 0 and transformed.values.len != 0) {
        var total_rms: f64 = 0.0;
        var column_count: usize = 0;
        for (0..state_count) |column| {
            const column_values = allocator.alloc(f64, transformed.values.len) catch break;
            defer allocator.free(column_values);
            for (column_values, 0..) |*slot, row| {
                slot.* = jacobian[dense.index(row, column, state_count)];
            }
            const effective = cross_sections.effectiveCrossSectionFromSensitivity(
                allocator,
                transformed.wavelengths_nm,
                column_values,
                transformed.amf_profile,
                policy.polynomial_order,
            ) catch break;
            defer allocator.free(effective);
            var sum_sq: f64 = 0.0;
            for (effective) |value| sum_sq += value * value;
            total_rms += std.math.sqrt(sum_sq / @as(f64, @floatFromInt(effective.len)));
            column_count += 1;
        }
        if (column_count != 0) {
            effective_cross_section_rms = total_rms / @as(f64, @floatFromInt(column_count));
        }
    }
    var effective_air_mass_factor: f64 = 0.0;
    if (transformed.amf_profile.len != 0) {
        for (transformed.amf_profile) |value| effective_air_mass_factor += value;
        effective_air_mass_factor /= @as(f64, @floatFromInt(transformed.amf_profile.len));
    }

    return .{
        .fit_space = policy.fit_space,
        .polynomial_order = policy.polynomial_order,
        .fit_sample_count = @intCast(transformed.values.len),
        .selected_rtm_sample_count = @intCast(transformed.values.len),
        .selection_zero_crossing_count = selection.zero_crossing_count,
        .window_start_nm = if (transformed.wavelengths_nm.len != 0) transformed.wavelengths_nm[0] else 0.0,
        .window_end_nm = if (transformed.wavelengths_nm.len != 0) transformed.wavelengths_nm[transformed.wavelengths_nm.len - 1] else 0.0,
        .effective_air_mass_factor = effective_air_mass_factor,
        .weighted_residual_rms = 0.0,
        .effective_cross_section_rms = effective_cross_section_rms,
    };
}

fn weightedResidualCost(residual: []const f64, sigma: []const f64) f64 {
    var total: f64 = 0.0;
    for (residual, sigma) |value, sample_sigma| {
        const normalized = value / @max(sample_sigma, 1.0e-12);
        total += normalized * normalized;
    }
    return total;
}

fn buildAveragingKernel(
    posterior_covariance: []const f64,
    measurement_normal: []const f64,
    state_count: usize,
    out: []f64,
) !void {
    if (posterior_covariance.len != state_count * state_count or
        measurement_normal.len != state_count * state_count or
        out.len != state_count * state_count)
    {
        return error.ShapeMismatch;
    }

    @memset(out, 0.0);
    for (0..state_count) |row| {
        for (0..state_count) |column| {
            var total: f64 = 0.0;
            for (0..state_count) |inner| {
                total += posterior_covariance[dense.index(row, inner, state_count)] *
                    measurement_normal[dense.index(inner, column, state_count)];
            }
            out[dense.index(row, column, state_count)] = total;
        }
    }
}

fn solveSymmetricSystem(
    allocator: Allocator,
    hessian: []const f64,
    dimension: usize,
    gradient: []const f64,
    damping: f64,
    out: []f64,
) common.Error!void {
    const factor = try allocator.dupe(f64, hessian);
    defer allocator.free(factor);
    addDiagonal(factor, dimension, damping);

    cholesky.factorInPlace(factor, dimension) catch {
        const workspace = try allocator.alloc(f64, dimension * (dimension + 1));
        defer allocator.free(workspace);
        svd_fallback.dampedSolve(hessian, dimension, gradient, @max(damping, 1.0e-6), out, workspace[0 .. dimension * (dimension + 1)]) catch {
            return common.Error.SingularMatrix;
        };
        return;
    };
    try vector_ops.copy(gradient, out);
    cholesky.solveWithFactor(factor, dimension, gradient, out) catch return common.Error.SingularMatrix;
}

fn invertHessian(
    allocator: Allocator,
    hessian: []const f64,
    dimension: usize,
    damping: f64,
) common.Error![]f64 {
    const inverse = try allocator.alloc(f64, dimension * dimension);
    errdefer allocator.free(inverse);

    const factor = try allocator.dupe(f64, hessian);
    defer allocator.free(factor);
    addDiagonal(factor, dimension, damping);

    if (cholesky.factorInPlace(factor, dimension)) |_| {
        const workspace = try allocator.alloc(f64, 2 * dimension);
        defer allocator.free(workspace);
        cholesky.invertFromFactor(factor, dimension, inverse, workspace) catch return common.Error.SingularMatrix;
        return inverse;
    } else |_| {
        const solve_workspace = try allocator.alloc(f64, dimension * (dimension + 1));
        defer allocator.free(solve_workspace);
        const basis = try allocator.alloc(f64, dimension);
        defer allocator.free(basis);
        const solution = try allocator.alloc(f64, dimension);
        defer allocator.free(solution);

        for (0..dimension) |column| {
            @memset(basis, 0.0);
            basis[column] = 1.0;
            svd_fallback.dampedSolve(hessian, dimension, basis, @max(damping, 1.0e-6), solution, solve_workspace) catch {
                return common.Error.SingularMatrix;
            };
            for (0..dimension) |row| {
                inverse[dense.index(row, column, dimension)] = solution[row];
            }
        }
        return inverse;
    }
}

fn normalizeSolverState(problem: common.RetrievalProblem, solver_state: []f64, physical_state: []f64) common.Error!void {
    for (problem.inverse_problem.state_vector.parameters, solver_state, physical_state) |parameter, *solver_value, *physical_value| {
        const clamped = clampPhysical(parameter, transforms.toPhysicalSpace(parameter.transform, solver_value.*));
        physical_value.* = clamped;
        solver_value.* = safeSolverValue(parameter, clamped) catch return common.Error.InvalidRequest;
    }
}

fn seedSolverState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    layout: state_access.ResolvedStateLayout,
    prior_mean_solver: []const f64,
    out: []f64,
) common.Error!void {
    const seeded_physical = try state_access.seedStateWithLayout(allocator, problem, layout);
    defer allocator.free(seeded_physical);
    for (problem.inverse_problem.state_vector.parameters, seeded_physical, prior_mean_solver, out) |parameter, seeded_value, prior_solver, *slot| {
        slot.* = safeSolverValue(parameter, seeded_value) catch prior_solver;
    }
}

fn parameterNames(allocator: Allocator, problem: common.RetrievalProblem) ![]const []const u8 {
    const parameters = problem.inverse_problem.state_vector.parameters;
    const names = try allocator.alloc([]const u8, parameters.len);
    for (parameters, 0..) |parameter, index| {
        names[index] = parameter.name;
    }
    return names;
}

fn addMatrixInPlace(lhs: []f64, rhs: []const f64) void {
    for (lhs, rhs) |*left, right| left.* += right;
}

fn subtractMatVec(out: []f64, matrix: []const f64, lhs: []const f64, rhs: []const f64) void {
    const dimension = out.len;
    for (0..dimension) |row| {
        var total: f64 = 0.0;
        for (0..dimension) |column| {
            total += matrix[dense.index(row, column, dimension)] * (lhs[column] - rhs[column]);
        }
        out[row] -= total;
    }
}

fn addDiagonal(matrix: []f64, dimension: usize, value: f64) void {
    if (value == 0.0) return;
    for (0..dimension) |diag_index| {
        matrix[dense.index(diag_index, diag_index, dimension)] += value;
    }
}

fn priorCost(inverse_covariance: []const f64, solver_state: []const f64, prior_mean_solver: []const f64) f64 {
    const dimension = solver_state.len;
    var total: f64 = 0.0;
    for (0..dimension) |row| {
        var row_total: f64 = 0.0;
        for (0..dimension) |column| {
            row_total += inverse_covariance[dense.index(row, column, dimension)] *
                (solver_state[column] - prior_mean_solver[column]);
        }
        total += (solver_state[row] - prior_mean_solver[row]) * row_total;
    }
    return total;
}

fn clampPhysical(parameter: StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

fn safeSolverValue(parameter: StateParameter, physical_value: f64) !f64 {
    return switch (parameter.transform) {
        .none => physical_value,
        .log => transforms.toSolverSpace(.log, @max(physical_value, 1.0e-9)),
        .logit => transforms.toSolverSpace(.logit, std.math.clamp(physical_value, 1.0e-9, 1.0 - 1.0e-9)),
    };
}

fn finiteDifferenceStep(parameter: StateParameter, physical_value: f64) f64 {
    var step = @max(@abs(physical_value) * 1.0e-3, 1.0e-6);
    if (parameter.bounds.enabled) {
        step = @min(step, 0.25 * @max(parameter.bounds.max - parameter.bounds.min, 1.0e-6));
    }
    return step;
}

test "dismas selection prefers differential optical-depth zero crossings" {
    const optical_depth = [_]f64{ 0.20, 0.24, 0.18, 0.25, 0.17, 0.23, 0.19, 0.22, 0.18, 0.24 };
    var reflectance: [optical_depth.len]f64 = undefined;
    for (optical_depth, 0..) |value, index| {
        reflectance[index] = std.math.exp(-value);
    }

    const measurement: forward_model.SpectralMeasurement = .{
        .wavelengths_nm = @constCast(@as([]const f64, &[_]f64{ 405.0, 411.0, 417.0, 423.0, 429.0, 435.0, 441.0, 447.0, 453.0, 459.0 })),
        .values = @constCast(@as([]const f64, &[_]f64{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 })),
        .sigma = @constCast(@as([]const f64, &[_]f64{ 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01 })),
        .radiance = @constCast(@as([]const f64, &[_]f64{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 })),
        .irradiance = @constCast(@as([]const f64, &[_]f64{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 })),
        .reflectance = &reflectance,
        .summary = .{
            .sample_count = optical_depth.len,
            .wavelength_start_nm = 405.0,
            .wavelength_end_nm = 459.0,
            .mean_radiance = 1.0,
            .mean_irradiance = 1.0,
            .mean_reflectance = 0.8,
            .mean_noise_sigma = 0.01,
        },
        .metadata = .{ .effective_air_mass_factor = 2.0 },
    };

    const policy = policyForMethod(.dismas);
    const zero_crossings = try differentialZeroCrossingIndices(std.testing.allocator, measurement, policy);
    defer std.testing.allocator.free(zero_crossings);
    var selection = try buildSelectionIndices(std.testing.allocator, measurement, policy);
    defer selection.deinit(std.testing.allocator);

    try std.testing.expect(zero_crossings.len > 0);
    try std.testing.expectEqual(@as(u32, @intCast(zero_crossings.len)), selection.zero_crossing_count);
    try std.testing.expect(selection.indices.len <= policy.selection_budget);
    for (selection.indices) |selected_index| {
        try std.testing.expect(std.mem.indexOfScalar(usize, zero_crossings, selected_index) != null);
    }
}

test "radiance-space transform preserves selected measurement values" {
    const measurement: forward_model.SpectralMeasurement = .{
        .wavelengths_nm = @constCast(@as([]const f64, &[_]f64{ 405.0, 411.0, 417.0 })),
        .values = @constCast(@as([]const f64, &[_]f64{ 0.81, 0.78, 0.75 })),
        .sigma = @constCast(@as([]const f64, &[_]f64{ 0.01, 0.02, 0.03 })),
        .radiance = @constCast(@as([]const f64, &[_]f64{ 1.5, 1.4, 1.3 })),
        .irradiance = @constCast(@as([]const f64, &[_]f64{ 2.0, 2.0, 2.0 })),
        .reflectance = @constCast(@as([]const f64, &[_]f64{ 0.81, 0.78, 0.75 })),
        .summary = .{
            .sample_count = 3,
            .wavelength_start_nm = 405.0,
            .wavelength_end_nm = 417.0,
            .mean_radiance = 1.4,
            .mean_irradiance = 2.0,
            .mean_reflectance = 0.78,
            .mean_noise_sigma = 0.02,
        },
        .metadata = .{ .effective_air_mass_factor = 2.0 },
    };
    const policy: Policy = .{
        .selection_strategy = .all_samples,
        .fit_space = .radiance,
        .polynomial_order = 1,
        .max_iterations_default = 8,
        .damping = 1.0e-4,
        .selection_budget = 0,
    };
    const selection_indices = [_]usize{ 0, 2 };

    var transformed = try transformMeasurement(std.testing.allocator, measurement, policy, &selection_indices);
    defer transformed.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(f64, &.{ 0.81, 0.75 }, transformed.values);
    try std.testing.expectEqualSlices(f64, &.{ 0.01, 0.03 }, transformed.sigma);
}
