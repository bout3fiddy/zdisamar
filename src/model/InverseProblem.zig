//! Purpose:
//!   Define the canonical inverse-problem contract used by retrieval execution.
//!
//! Physics:
//!   Couples the retrieval state vector, measurement definition, covariance structure, fit
//!   controls, and convergence thresholds for OE, DOAS, and DISMAS-style inversions.
//!
//! Vendor:
//!   `inverse-problem and retrieval validation contract`
//!
//! Design:
//!   Share one typed inverse-problem surface across retrieval methods while method-specific
//!   validation gates remain explicit helper entrypoints.
//!
//! Invariants:
//!   State-vector and measurement contracts must validate first. Method-specific validation adds
//!   extra observable, prior, and covariance requirements without mutating the base problem.
//!
//! Validation:
//!   Inverse-problem tests in this file plus the retrieval solver integration and parity tests.

const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const MeasurementVector = @import("Measurement.zig").MeasurementVector;
const MeasurementQuantity = @import("Measurement.zig").Quantity;
const StateParameter = @import("StateVector.zig").Parameter;
const StateVector = @import("StateVector.zig").StateVector;

/// Purpose:
///   Select how transport and retrieval derivatives are expected to be produced.
pub const DerivativeMode = enum {
    none,
    semi_analytical,
    analytical_plugin,
    numerical,
};

/// Purpose:
///   Describe a correlated block in the state-vector prior covariance model.
pub const CovarianceBlock = struct {
    parameter_indices: []const u32 = &[_]u32{},
    correlation: f64 = 0.0,

    /// Purpose:
    ///   Validate the block indices and correlation against the state-vector size.
    pub fn validate(self: CovarianceBlock, parameter_count: u32) errors.Error!void {
        if (self.parameter_indices.len == 0 or !std.math.isFinite(self.correlation) or self.correlation < -1.0 or self.correlation > 1.0) {
            return errors.Error.InvalidRequest;
        }
        for (self.parameter_indices) |parameter_index| {
            if (parameter_index >= parameter_count) return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *CovarianceBlock, allocator: Allocator) void {
        if (self.parameter_indices.len != 0) allocator.free(self.parameter_indices);
        self.* = .{};
    }
};

/// Purpose:
///   Configure retrieval iteration limits and trust-region policy.
pub const FitControls = struct {
    pub const TrustRegion = enum {
        none,
        lm,

        /// Purpose:
        ///   Report whether the trust-region policy implies an active damping scheme.
        pub fn enabled(self: TrustRegion) bool {
            return self != .none;
        }
    };

    max_iterations: u32 = 0,
    trust_region: TrustRegion = .none,

    /// Purpose:
    ///   Validate the fit-control configuration.
    pub fn validate(self: FitControls) errors.Error!void {
        if (self.max_iterations == 0 and self.trust_region.enabled()) {
            return errors.Error.InvalidRequest;
        }
    }
};

/// Purpose:
///   Define relative convergence tolerances for retrieval cost and state updates.
pub const Convergence = struct {
    cost_relative: f64 = 0.0,
    state_relative: f64 = 0.0,

    /// Purpose:
    ///   Validate convergence tolerances for finiteness and non-negativity.
    pub fn validate(self: Convergence) errors.Error!void {
        if (!std.math.isFinite(self.cost_relative) or
            !std.math.isFinite(self.state_relative) or
            self.cost_relative < 0.0 or
            self.state_relative < 0.0)
        {
            return errors.Error.InvalidRequest;
        }
    }
};

/// Purpose:
///   Hold the fully typed inverse-problem definition executed by a retrieval provider.
pub const InverseProblem = struct {
    id: []const u8 = "inverse-0",
    state_vector: StateVector = .{},
    measurements: MeasurementVector = .{},
    covariance_blocks: []const CovarianceBlock = &[_]CovarianceBlock{},
    fit_controls: FitControls = .{},
    convergence: Convergence = .{},

    /// Purpose:
    ///   Validate the base inverse-problem contract shared by all retrieval methods.
    pub fn validate(self: InverseProblem) errors.Error!void {
        if (self.id.len == 0) return errors.Error.InvalidRequest;
        try self.state_vector.validate();
        try self.measurements.validate();
        const parameter_count = self.state_vector.count();
        for (self.covariance_blocks) |block| {
            try block.validate(parameter_count);
        }
        try self.fit_controls.validate();
        try self.convergence.validate();
    }

    /// Purpose:
    ///   Validate the extra prior and fit-control constraints required by optimal estimation.
    pub fn validateForOptimalEstimation(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();

        for (self.state_vector.parameters) |parameter| {
            if (!parameter.prior.enabled) return errors.Error.InvalidRequest;
        }

        if (self.fit_controls.trust_region != .none and self.fit_controls.trust_region != .lm) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Validate the observable contract required by DOAS-style spectral retrieval.
    pub fn validateForDoas(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();

        if (!measurementAllows(self.measurements, .radiance) and
            !measurementAllows(self.measurements, .reflectance))
        {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Validate the observable contract required by DISMAS-style spectral retrieval.
    pub fn validateForDismas(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();
        if (!measurementAllows(self.measurements, .radiance)) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Validate the shared requirements for spectral retrieval methods.
    fn validateForSpectralRetrieval(self: InverseProblem) errors.Error!void {
        try self.validate();

        if (self.state_vector.parameters.len == 0) return errors.Error.InvalidRequest;
        // DECISION:
        //   Real spectral retrieval currently requires an explicit state-vector description and an
        //   error model that defines covariance; implicit/default retrieval wiring is rejected.
        if (!self.measurements.error_model.definesCovariance()) return errors.Error.InvalidRequest;

        for (self.state_vector.parameters) |parameter| {
            if (!parameter.prior.enabled) return errors.Error.InvalidRequest;
        }
    }

    fn measurementAllows(measurements: MeasurementVector, expected: MeasurementQuantity) bool {
        return measurements.observable == expected;
    }

    /// Purpose:
    ///   Release the owned state vector, measurements, and covariance blocks.
    pub fn deinitOwned(self: *InverseProblem, allocator: Allocator) void {
        self.state_vector.deinitOwned(allocator);
        self.measurements.deinitOwned(allocator);
        for (self.covariance_blocks) |block| {
            if (block.parameter_indices.len != 0) allocator.free(block.parameter_indices);
        }
        if (self.covariance_blocks.len != 0) allocator.free(self.covariance_blocks);
        self.* = .{};
    }

    /// Purpose:
    ///   Look up a state-parameter index by name through the owned state vector.
    pub fn parameterIndex(self: InverseProblem, name: []const u8) ?usize {
        return self.state_vector.parameterIndex(name);
    }
};

test "inverse problem validates canonical covariance and convergence controls" {
    try (InverseProblem{
        .id = "inverse-1",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{
                    .name = "surface_albedo",
                    .target = .surface_albedo,
                    .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 121,
            .source = .{ .stage_product = .{ .name = "truth_radiance" } },
        },
        .covariance_blocks = &[_]CovarianceBlock{
            .{
                .parameter_indices = &[_]u32{ 0, 1 },
                .correlation = 0.3,
            },
        },
        .fit_controls = .{ .max_iterations = 8, .trust_region = .lm },
        .convergence = .{ .cost_relative = 1.0e-3, .state_relative = 1.0e-3 },
    }).validate();
}

test "inverse problem requires priors and a typed observable for real OE" {
    try (InverseProblem{
        .id = "inverse-oe",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{
                    .name = "surface_albedo",
                    .target = .surface_albedo,
                    .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 32,
            .source = .{ .stage_product = .{ .name = "truth_radiance" } },
            .error_model = .{ .floor = 1.0e-4 },
        },
    }).validateForOptimalEstimation();
}

test "inverse problem validates DOAS and DISMAS observable contracts separately from OE" {
    const base: InverseProblem = .{
        .id = "inverse-spectral",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{
                    .name = "surface_albedo",
                    .target = .surface_albedo,
                    .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                },
            },
        },
        .measurements = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = 32,
            .source = .{ .stage_product = .{ .name = "truth_radiance" } },
            .error_model = .{ .floor = 1.0e-4 },
        },
    };

    try base.validateForDoas();
    try base.validateForDismas();

    const doas_reflectance = InverseProblem{
        .id = base.id,
        .state_vector = base.state_vector,
        .measurements = .{
            .product_name = "reflectance",
            .observable = .reflectance,
            .sample_count = 32,
            .source = .{ .stage_product = .{ .name = "truth_reflectance" } },
            .error_model = .{ .floor = 1.0e-4 },
        },
    };
    try doas_reflectance.validateForDoas();
    try std.testing.expectError(errors.Error.InvalidRequest, doas_reflectance.validateForDismas());
}
