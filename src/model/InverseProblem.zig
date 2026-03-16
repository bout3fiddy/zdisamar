const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");
const MeasurementVector = @import("Measurement.zig").MeasurementVector;
const StateParameter = @import("StateVector.zig").Parameter;
const StateVector = @import("StateVector.zig").StateVector;

pub const DerivativeMode = enum {
    none,
    semi_analytical,
    analytical_plugin,
    numerical,
};

pub const CovarianceBlock = struct {
    member_names: []const []const u8 = &[_][]const u8{},
    correlation: f64 = 0.0,

    pub fn validate(self: CovarianceBlock) errors.Error!void {
        if (self.member_names.len == 0 or !std.math.isFinite(self.correlation) or self.correlation < -1.0 or self.correlation > 1.0) {
            return errors.Error.InvalidRequest;
        }
        for (self.member_names) |name| {
            if (name.len == 0) return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *CovarianceBlock, allocator: Allocator) void {
        if (self.member_names.len != 0) allocator.free(self.member_names);
        self.* = .{};
    }
};

pub const FitControls = struct {
    max_iterations: u32 = 0,
    trust_region: []const u8 = "",

    pub fn validate(self: FitControls) errors.Error!void {
        if (self.max_iterations == 0 and self.trust_region.len != 0) {
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
        for (self.covariance_blocks) |block| {
            try block.validate();
        }
        try self.fit_controls.validate();
        try self.convergence.validate();
    }

    pub fn deinitOwned(self: *InverseProblem, allocator: Allocator) void {
        self.state_vector.deinitOwned(allocator);
        self.measurements.deinitOwned(allocator);
        for (self.covariance_blocks) |block| {
            if (block.member_names.len != 0) allocator.free(block.member_names);
        }
        if (self.covariance_blocks.len != 0) allocator.free(self.covariance_blocks);
        self.* = .{};
    }
};

test "inverse problem validates canonical covariance and convergence controls" {
    try (InverseProblem{
        .id = "inverse-1",
        .state_vector = .{
            .parameters = &[_]StateParameter{
                .{
                    .name = "surface_albedo",
                    .target = "scene.surface.albedo",
                    .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                },
            },
        },
        .measurements = .{
            .product = "radiance",
            .observable = "radiance",
            .sample_count = 121,
            .source = .{ .kind = .stage_product, .name = "truth_radiance" },
        },
        .covariance_blocks = &[_]CovarianceBlock{
            .{
                .member_names = &[_][]const u8{ "surface_albedo", "aerosol_tau" },
                .correlation = 0.3,
            },
        },
        .fit_controls = .{ .max_iterations = 8, .trust_region = "lm" },
        .convergence = .{ .cost_relative = 1.0e-3, .state_relative = 1.0e-3 },
    }).validate();
}
