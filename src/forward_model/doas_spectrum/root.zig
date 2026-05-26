const std = @import("std");
const cholesky = @import("../../common/math/linalg/cholesky.zig");
const dense = @import("../../common/math/linalg/small_dense.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    ShapeMismatch,
    InvalidPolynomialDegree,
    InvalidWavelengthGrid,
    InsufficientSamples,
    WorkspaceTooSmall,
    InvalidWeight,
    NonFiniteInput,
    NonPositiveReflectance,
    SingularSystem,
    OutputTooSmall,
    SupportWavelengthsTooClose,
} || Allocator.Error;

pub const Fit = struct {
    start_nm: f64,
    end_nm: f64,
    coefficients: []const f64,
};

pub const Workspace = struct {
    coefficients: []f64 = &.{},
    normal: []f64 = &.{},
    rhs: []f64 = &.{},
    factor: []f64 = &.{},
    basis: []f64 = &.{},
    sample_scratch: []f64 = &.{},
    max_terms: usize = 0,
    max_samples: usize = 0,

    pub fn init(allocator: Allocator, max_samples: usize, max_terms: usize) Error!Workspace {
        if (max_terms == 0) return error.InvalidPolynomialDegree;
        return .{
            .coefficients = try allocator.alloc(f64, max_terms),
            .normal = try allocator.alloc(f64, max_terms * max_terms),
            .rhs = try allocator.alloc(f64, max_terms),
            .factor = try allocator.alloc(f64, max_terms * max_terms),
            .basis = try allocator.alloc(f64, max_terms),
            .sample_scratch = try allocator.alloc(f64, max_samples),
            .max_terms = max_terms,
            .max_samples = max_samples,
        };
    }

    pub fn deinit(self: *Workspace, allocator: Allocator) void {
        allocator.free(self.coefficients);
        allocator.free(self.normal);
        allocator.free(self.rhs);
        allocator.free(self.factor);
        allocator.free(self.basis);
        allocator.free(self.sample_scratch);
        self.* = .{};
    }

    fn requireTerms(self: *Workspace, term_count: usize) Error!void {
        if (term_count == 0 or term_count > self.max_terms) return error.WorkspaceTooSmall;
    }

    fn requireSamples(self: *Workspace, sample_count: usize) Error!void {
        if (sample_count > self.max_samples) return error.WorkspaceTooSmall;
    }
};

pub const TraceGasAbsorption = struct {
    column: f64,
    air_mass_factor: []const f64,
    cross_section: []const f64,
};

pub const TraceGasDifferential = struct {
    column: f64,
    air_mass_factor: []const f64,
    differential_cross_section: []const f64,
};

pub fn termCountFromDegree(polynomial_degree: u32) Error!usize {
    if (polynomial_degree > 31) return error.InvalidPolynomialDegree;
    return @as(usize, @intCast(polynomial_degree)) + 1;
}

pub fn fitLegendre(
    wavelengths_nm: []const f64,
    values: []const f64,
    weights: ?[]const f64,
    polynomial_degree: u32,
    workspace: *Workspace,
) Error!Fit {
    try validatePairedGrid(wavelengths_nm, values);
    if (weights) |weight_values| {
        if (weight_values.len != wavelengths_nm.len) return error.ShapeMismatch;
    }
    const term_count = try termCountFromDegree(polynomial_degree);
    if (wavelengths_nm.len < term_count) return error.InsufficientSamples;
    try workspace.requireTerms(term_count);

    const coefficients = workspace.coefficients[0..term_count];
    const normal = workspace.normal[0 .. term_count * term_count];
    const rhs = workspace.rhs[0..term_count];
    const factor = workspace.factor[0 .. term_count * term_count];
    const basis = workspace.basis[0..term_count];
    @memset(normal, 0.0);
    @memset(rhs, 0.0);
    @memset(coefficients, 0.0);

    const start_nm = wavelengths_nm[0];
    const end_nm = wavelengths_nm[wavelengths_nm.len - 1];
    for (wavelengths_nm, values, 0..) |wavelength_nm, value, sample_index| {
        if (!std.math.isFinite(value)) return error.NonFiniteInput;
        const weight = if (weights) |weight_values| weight_values[sample_index] else 1.0;
        if (!std.math.isFinite(weight) or weight <= 0.0) return error.InvalidWeight;
        evaluateLegendreBasisInto(scaledCoordinate(start_nm, end_nm, wavelength_nm), basis);

        for (0..term_count) |row| {
            rhs[row] += weight * basis[row] * value;
            for (0..term_count) |column| {
                normal[dense.index(row, column, term_count)] += weight * basis[row] * basis[column];
            }
        }
    }

    @memcpy(factor, normal);
    cholesky.factorInPlace(factor, term_count) catch return error.SingularSystem;
    cholesky.solveWithFactor(factor, term_count, rhs, coefficients) catch return error.SingularSystem;

    return .{
        .start_nm = start_nm,
        .end_nm = end_nm,
        .coefficients = coefficients,
    };
}

pub fn evaluateLegendreFitInto(fit: Fit, wavelengths_nm: []const f64, out: []f64, workspace: *Workspace) Error!void {
    if (wavelengths_nm.len != out.len) return error.ShapeMismatch;
    try validateWavelengthGrid(wavelengths_nm);
    try workspace.requireTerms(fit.coefficients.len);
    const basis = workspace.basis[0..fit.coefficients.len];
    for (wavelengths_nm, out) |wavelength_nm, *slot| {
        evaluateLegendreBasisInto(scaledCoordinate(fit.start_nm, fit.end_nm, wavelength_nm), basis);
        var value: f64 = 0.0;
        for (fit.coefficients, basis) |coefficient, basis_value| value += coefficient * basis_value;
        slot.* = value;
    }
}

pub fn fitLegendreSmoothInto(
    wavelengths_nm: []const f64,
    values: []const f64,
    weights: ?[]const f64,
    polynomial_degree: u32,
    workspace: *Workspace,
    smooth_out: []f64,
) Error!void {
    if (smooth_out.len != wavelengths_nm.len) return error.ShapeMismatch;
    const fit = try fitLegendre(wavelengths_nm, values, weights, polynomial_degree, workspace);
    try evaluateLegendreFitInto(fit, wavelengths_nm, smooth_out, workspace);
}

pub fn splitSmoothDifferentialInto(
    wavelengths_nm: []const f64,
    values: []const f64,
    weights: ?[]const f64,
    polynomial_degree: u32,
    workspace: *Workspace,
    smooth_out: []f64,
    differential_out: []f64,
) Error!void {
    if (smooth_out.len != values.len or differential_out.len != values.len) return error.ShapeMismatch;
    try fitLegendreSmoothInto(wavelengths_nm, values, weights, polynomial_degree, workspace, smooth_out);
    for (values, smooth_out, differential_out) |value, smooth, *differential| {
        differential.* = value - smooth;
    }
}

pub fn fitLogSmoothReflectanceInto(
    support_wavelengths_nm: []const f64,
    support_reflectance: []const f64,
    output_wavelengths_nm: []const f64,
    polynomial_degree: u32,
    workspace: *Workspace,
    smooth_reflectance_out: []f64,
) Error!void {
    try validatePairedGrid(support_wavelengths_nm, support_reflectance);
    if (output_wavelengths_nm.len != smooth_reflectance_out.len) return error.ShapeMismatch;
    try validateWavelengthGrid(output_wavelengths_nm);
    try workspace.requireSamples(support_wavelengths_nm.len);

    const log_support = workspace.sample_scratch[0..support_wavelengths_nm.len];
    for (support_reflectance, log_support) |reflectance, *slot| {
        if (!std.math.isFinite(reflectance)) return error.NonFiniteInput;
        if (reflectance <= 0.0) return error.NonPositiveReflectance;
        slot.* = @log(reflectance);
    }

    const fit = try fitLegendre(
        support_wavelengths_nm,
        log_support,
        null,
        polynomial_degree,
        workspace,
    );
    try evaluateLegendreFitInto(fit, output_wavelengths_nm, smooth_reflectance_out, workspace);
    for (smooth_reflectance_out) |*value| value.* = @exp(value.*);
}

pub fn slantOpticalThicknessInto(traces: []const TraceGasAbsorption, out: []f64) Error!void {
    @memset(out, 0.0);
    for (traces) |trace| {
        if (!std.math.isFinite(trace.column)) return error.NonFiniteInput;
        if (trace.air_mass_factor.len != out.len or trace.cross_section.len != out.len) return error.ShapeMismatch;
        for (out, trace.air_mass_factor, trace.cross_section) |*slot, amf, sigma| {
            if (!std.math.isFinite(amf) or !std.math.isFinite(sigma)) return error.NonFiniteInput;
            slot.* += trace.column * amf * sigma;
        }
    }
}

pub fn differentialSlantOpticalThicknessInto(traces: []const TraceGasDifferential, out: []f64) Error!void {
    @memset(out, 0.0);
    for (traces) |trace| {
        if (!std.math.isFinite(trace.column)) return error.NonFiniteInput;
        if (trace.air_mass_factor.len != out.len or trace.differential_cross_section.len != out.len) {
            return error.ShapeMismatch;
        }
        for (out, trace.air_mass_factor, trace.differential_cross_section) |*slot, amf, sigma_diff| {
            if (!std.math.isFinite(amf) or !std.math.isFinite(sigma_diff)) return error.NonFiniteInput;
            slot.* += trace.column * amf * sigma_diff;
        }
    }
}

pub fn fitSlantDifferentialOpticalThicknessInto(
    wavelengths_nm: []const f64,
    traces: []const TraceGasAbsorption,
    polynomial_degree: u32,
    workspace: *Workspace,
    differential_out: []f64,
) Error!void {
    if (wavelengths_nm.len != differential_out.len) return error.ShapeMismatch;
    try validateWavelengthGrid(wavelengths_nm);
    try workspace.requireSamples(wavelengths_nm.len);

    const total_tau = workspace.sample_scratch[0..wavelengths_nm.len];
    try slantOpticalThicknessInto(traces, total_tau);
    try fitLegendreSmoothInto(wavelengths_nm, total_tau, null, polynomial_degree, workspace, differential_out);
    for (total_tau, differential_out) |total, *differential| {
        differential.* = total - differential.*;
    }
}

pub fn zeroCrossingSupportInto(
    wavelengths_nm: []const f64,
    differential_tau: []const f64,
    min_spacing_nm: f64,
    support_out: []f64,
) Error!usize {
    try validatePairedGrid(wavelengths_nm, differential_tau);
    if (!std.math.isFinite(min_spacing_nm) or min_spacing_nm < 0.0) return error.NonFiniteInput;
    if (wavelengths_nm.len < 2) return error.InsufficientSamples;

    var count: usize = 0;
    var previous_support: ?f64 = null;
    for (1..wavelengths_nm.len) |index| {
        const previous_tau = differential_tau[index - 1];
        const current_tau = differential_tau[index];
        if (!std.math.isFinite(previous_tau) or !std.math.isFinite(current_tau)) return error.NonFiniteInput;
        if (previous_tau * current_tau >= 0.0) continue;
        const left_wavelength = wavelengths_nm[index - 1];
        const right_wavelength = wavelengths_nm[index];
        const support_wavelength = left_wavelength -
            (right_wavelength - left_wavelength) * previous_tau / (current_tau - previous_tau);
        if (previous_support) |previous| {
            if (support_wavelength - previous < min_spacing_nm) return error.SupportWavelengthsTooClose;
        }
        if (count >= support_out.len) return error.OutputTooSmall;
        support_out[count] = support_wavelength;
        previous_support = support_wavelength;
        count += 1;
    }
    return count;
}

pub fn reconstructReflectanceInto(
    smooth_reflectance: []const f64,
    differential_tau: []const f64,
    reflectance_out: []f64,
) Error!void {
    if (smooth_reflectance.len != differential_tau.len or reflectance_out.len != smooth_reflectance.len) {
        return error.ShapeMismatch;
    }
    for (smooth_reflectance, differential_tau, reflectance_out) |smooth, tau, *reflectance| {
        if (!std.math.isFinite(smooth) or !std.math.isFinite(tau)) return error.NonFiniteInput;
        reflectance.* = smooth * @exp(-tau);
    }
}

pub fn fitSmoothReflectanceAndReconstructInto(
    support_wavelengths_nm: []const f64,
    support_reflectance: []const f64,
    output_wavelengths_nm: []const f64,
    differential_tau: []const f64,
    polynomial_degree: u32,
    workspace: *Workspace,
    reflectance_out: []f64,
) Error!void {
    if (output_wavelengths_nm.len != differential_tau.len or reflectance_out.len != differential_tau.len) {
        return error.ShapeMismatch;
    }
    try fitLogSmoothReflectanceInto(
        support_wavelengths_nm,
        support_reflectance,
        output_wavelengths_nm,
        polynomial_degree,
        workspace,
        reflectance_out,
    );
    try reconstructReflectanceInto(reflectance_out, differential_tau, reflectance_out);
}

fn validatePairedGrid(wavelengths_nm: []const f64, values: []const f64) Error!void {
    if (wavelengths_nm.len != values.len) return error.ShapeMismatch;
    try validateWavelengthGrid(wavelengths_nm);
}

fn validateWavelengthGrid(wavelengths_nm: []const f64) Error!void {
    if (wavelengths_nm.len == 0) return error.InvalidWavelengthGrid;
    var previous: ?f64 = null;
    for (wavelengths_nm) |wavelength_nm| {
        if (!std.math.isFinite(wavelength_nm)) return error.InvalidWavelengthGrid;
        if (previous) |previous_wavelength| {
            if (wavelength_nm <= previous_wavelength) return error.InvalidWavelengthGrid;
        }
        previous = wavelength_nm;
    }
}

fn scaledCoordinate(start_nm: f64, end_nm: f64, wavelength_nm: f64) f64 {
    return 2.0 * (wavelength_nm - start_nm) / (end_nm - start_nm) - 1.0;
}

fn evaluateLegendreBasisInto(coordinate: f64, basis: []f64) void {
    if (basis.len == 0) return;
    basis[0] = 1.0;
    if (basis.len == 1) return;
    basis[1] = coordinate;
    var order: usize = 2;
    while (order < basis.len) : (order += 1) {
        const n = @as(f64, @floatFromInt(order));
        basis[order] = ((2.0 * n - 1.0) * coordinate * basis[order - 1] -
            (n - 1.0) * basis[order - 2]) / n;
    }
}
