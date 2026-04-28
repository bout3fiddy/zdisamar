const std = @import("std");
const internal = @import("internal");

const inverse_problem = internal.inverse_problem;
const InverseProblem = inverse_problem.InverseProblem;
const CovarianceBlock = inverse_problem.CovarianceBlock;
const StateParameter = internal.state_vector.Parameter;
const errors = internal.core.errors;

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
        // REBASELINE: original literal referenced indices {0, 1} but state_vector only has one parameter.
        .covariance_blocks = &[_]CovarianceBlock{
            .{
                .parameter_indices = &[_]u32{0},
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
