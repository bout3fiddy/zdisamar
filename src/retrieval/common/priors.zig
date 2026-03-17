const std = @import("std");
const dense = @import("../../kernels/linalg/small_dense.zig");
const cholesky = @import("../../kernels/linalg/cholesky.zig");
const common = @import("contracts.zig");
const transforms = @import("transforms.zig");

pub const Assembly = struct {
    mean_solver: []f64,
    covariance: []f64,
    inverse_covariance: []f64,

    pub fn deinit(self: *Assembly, allocator: std.mem.Allocator) void {
        if (self.mean_solver.len != 0) allocator.free(self.mean_solver);
        if (self.covariance.len != 0) allocator.free(self.covariance);
        if (self.inverse_covariance.len != 0) allocator.free(self.inverse_covariance);
        self.* = undefined;
    }
};

pub fn assemble(allocator: std.mem.Allocator, problem: common.RetrievalProblem) common.Error!Assembly {
    const parameters = problem.inverse_problem.state_vector.parameters;
    if (parameters.len == 0) return common.Error.InvalidRequest;

    const dimension = parameters.len;
    const mean_solver = try allocator.alloc(f64, dimension);
    errdefer allocator.free(mean_solver);
    const covariance = try allocator.alloc(f64, dimension * dimension);
    errdefer allocator.free(covariance);
    const inverse_covariance = try allocator.alloc(f64, dimension * dimension);
    errdefer allocator.free(inverse_covariance);

    @memset(covariance, 0.0);
    for (parameters, 0..) |parameter, index| {
        mean_solver[index] = transforms.toSolverSpace(parameter.transform, parameter.prior.mean) catch {
            return common.Error.InvalidRequest;
        };
        covariance[dense.index(index, index, dimension)] = parameter.prior.sigma * parameter.prior.sigma;
    }

    for (problem.inverse_problem.covariance_blocks) |block| {
        for (block.parameter_indices, 0..) |lhs_index, lhs_offset| {
            const lhs: usize = @intCast(lhs_index);
            const lhs_sigma = parameters[lhs].prior.sigma;
            for (block.parameter_indices[lhs_offset + 1 ..]) |rhs_index| {
                const rhs: usize = @intCast(rhs_index);
                const rhs_sigma = parameters[rhs].prior.sigma;
                const covariance_value = block.correlation * lhs_sigma * rhs_sigma;
                covariance[dense.index(lhs, rhs, dimension)] = covariance_value;
                covariance[dense.index(rhs, lhs, dimension)] = covariance_value;
            }
        }
    }

    const factor = try allocator.dupe(f64, covariance);
    defer allocator.free(factor);
    cholesky.factorInPlace(factor, dimension) catch {
        return common.Error.SingularMatrix;
    };
    const workspace = try allocator.alloc(f64, 2 * dimension);
    defer allocator.free(workspace);
    cholesky.invertFromFactor(factor, dimension, inverse_covariance, workspace) catch {
        return common.Error.SingularMatrix;
    };

    return .{
        .mean_solver = mean_solver,
        .covariance = covariance,
        .inverse_covariance = inverse_covariance,
    };
}

test "prior assembly builds correlated covariance and inverse" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "scene-priors",
            .spectral_grid = .{ .sample_count = 4 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "inverse-priors",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{
                        .name = "albedo",
                        .target = .surface_albedo,
                        .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 },
                    },
                    .{
                        .name = "aerosol_tau",
                        .target = .aerosol_optical_depth_550_nm,
                        .transform = .log,
                        .prior = .{ .enabled = true, .mean = 0.2, .sigma = 0.1 },
                    },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 4,
            },
            .covariance_blocks = &[_]@import("../../model/Scene.zig").CovarianceBlock{
                .{
                    .parameter_indices = &[_]u32{ 0, 1 },
                    .correlation = 0.25,
                },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    var assembly = try assemble(std.testing.allocator, problem);
    defer assembly.deinit(std.testing.allocator);

    try std.testing.expect(assembly.mean_solver[1] < 0.0);
    try std.testing.expect(assembly.covariance[dense.index(0, 1, 2)] > 0.0);
    try std.testing.expect(assembly.inverse_covariance[dense.index(0, 0, 2)] > 0.0);
}
