const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../common/errors.zig");
const MeasurementVector = @import("Measurement.zig").MeasurementVector;
const MeasurementQuantity = @import("Measurement.zig").Quantity;
const StateParameter = @import("StateVector.zig").Parameter;
const StateVector = @import("StateVector.zig").StateVector;

pub const DerivativeMode = enum {
    none,
    semi_analytical,
    numerical,
};

pub const CovarianceBlock = struct {
    parameter_indices: []const u32 = &[_]u32{},
    correlation: f64 = 0.0,

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

pub const FitControls = struct {
    pub const TrustRegion = enum {
        none,
        lm,

        pub fn enabled(self: TrustRegion) bool {
            return self != .none;
        }
    };

    max_iterations: u32 = 0,
    trust_region: TrustRegion = .none,

    pub fn validate(self: FitControls) errors.Error!void {
        if (self.max_iterations == 0 and self.trust_region.enabled()) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const Convergence = struct {
    cost_relative: f64 = 0.0,
    state_relative: f64 = 0.0,

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

pub const InverseProblem = struct {
    id: []const u8 = "inverse-0",
    state_vector: StateVector = .{},
    measurements: MeasurementVector = .{},
    covariance_blocks: []const CovarianceBlock = &[_]CovarianceBlock{},
    fit_controls: FitControls = .{},
    convergence: Convergence = .{},

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

    pub fn validateForOptimalEstimation(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();

        for (self.state_vector.parameters) |parameter| {
            if (!parameter.prior.enabled) return errors.Error.InvalidRequest;
        }

        if (self.fit_controls.trust_region != .none and self.fit_controls.trust_region != .lm) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn validateForDoas(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();

        if (!measurementAllows(self.measurements, .radiance) and
            !measurementAllows(self.measurements, .reflectance))
        {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn validateForDismas(self: InverseProblem) errors.Error!void {
        try self.validateForSpectralRetrieval();
        if (!measurementAllows(self.measurements, .radiance)) {
            return errors.Error.InvalidRequest;
        }
    }

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

    pub fn deinitOwned(self: *InverseProblem, allocator: Allocator) void {
        self.state_vector.deinitOwned(allocator);
        self.measurements.deinitOwned(allocator);
        for (self.covariance_blocks) |block| {
            if (block.parameter_indices.len != 0) allocator.free(block.parameter_indices);
        }
        if (self.covariance_blocks.len != 0) allocator.free(self.covariance_blocks);
        self.* = .{};
    }

    pub fn parameterIndex(self: InverseProblem, name: []const u8) ?usize {
        return self.state_vector.parameterIndex(name);
    }
};
