const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Provenance = @import("provenance.zig").Provenance;
const std = @import("std");
const MeasurementSpaceSummary = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const MeasurementSpaceProduct = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceProduct;
const RetrievalOutcome = @import("../retrieval/common/contracts.zig").SolverOutcome;

const Allocator = std.mem.Allocator;

pub const Result = struct {
    pub const RetrievalStateVectorProduct = struct {
        parameter_names: []const []const u8 = &[_][]const u8{},
        values: []const f64 = &[_]f64{},

        pub fn deinit(self: *RetrievalStateVectorProduct, allocator: Allocator) void {
            if (self.parameter_names.len != 0) {
                for (self.parameter_names) |name| allocator.free(name);
                allocator.free(self.parameter_names);
            }
            if (self.values.len != 0) allocator.free(self.values);
            self.* = .{};
        }
    };

    pub const RetrievalMatrixProduct = struct {
        row_count: u32 = 0,
        column_count: u32 = 0,
        parameter_names: []const []const u8 = &[_][]const u8{},
        values: []const f64 = &[_]f64{},

        pub fn deinit(self: *RetrievalMatrixProduct, allocator: Allocator) void {
            if (self.parameter_names.len != 0) {
                for (self.parameter_names) |name| allocator.free(name);
                allocator.free(self.parameter_names);
            }
            if (self.values.len != 0) allocator.free(self.values);
            self.* = .{};
        }
    };

    pub const RetrievalProducts = struct {
        state_vector: ?RetrievalStateVectorProduct = null,
        fitted_measurement: ?MeasurementSpaceProduct = null,
        averaging_kernel: ?RetrievalMatrixProduct = null,
        jacobian: ?RetrievalMatrixProduct = null,

        pub fn deinit(self: *RetrievalProducts, allocator: Allocator) void {
            if (self.state_vector) |*state_vector| {
                state_vector.deinit(allocator);
                self.state_vector = null;
            }
            if (self.fitted_measurement) |*product| {
                product.deinit(allocator);
                self.fitted_measurement = null;
            }
            if (self.averaging_kernel) |*kernel| {
                kernel.deinit(allocator);
                self.averaging_kernel = null;
            }
            if (self.jacobian) |*jacobian| {
                jacobian.deinit(allocator);
                self.jacobian = null;
            }
        }
    };

    pub const Status = enum {
        success,
        invalid_request,
        internal_error,
    };

    status: Status = .success,
    plan_id: u64,
    workspace_label: []const u8,
    scene_id: []const u8,
    provenance: Provenance = .{},
    diagnostics: Diagnostics = .{},
    measurement_space: ?MeasurementSpaceSummary = null,
    measurement_space_product: ?MeasurementSpaceProduct = null,
    retrieval: ?RetrievalOutcome = null,
    retrieval_products: RetrievalProducts = .{},

    pub fn init(
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        provenance: Provenance,
    ) Result {
        return .{
            .plan_id = plan_id,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .provenance = provenance,
            .diagnostics = Diagnostics.fromSpec(.{ .provenance = true }, "Prepared transport routing and provenance are wired; full transport and retrieval numerics remain scaffold-only."),
        };
    }

    pub fn attachMeasurementSpaceProduct(self: *Result, product: MeasurementSpaceProduct) void {
        self.measurement_space = product.summary;
        self.measurement_space_product = product;
    }

    pub fn attachRetrievalOutcome(self: *Result, outcome: RetrievalOutcome) void {
        self.retrieval = outcome;
    }

    pub fn attachRetrievalProducts(self: *Result, products: RetrievalProducts) void {
        self.retrieval_products = products;
    }

    pub fn deinit(self: *Result, allocator: Allocator) void {
        if (self.measurement_space_product) |*product| {
            product.deinit(allocator);
            self.measurement_space_product = null;
        }
        self.retrieval_products.deinit(allocator);
        if (self.retrieval) |*outcome| {
            outcome.deinit(allocator);
            self.retrieval = null;
        }
        self.provenance.deinit(allocator);
    }
};

test "result can carry summary-only measurement-space output" {
    var result = Result.init(7, "unit", "scene-summary", .{});
    defer result.deinit(std.testing.allocator);

    result.measurement_space = .{
        .sample_count = 4,
        .wavelength_start_nm = 300.0,
        .wavelength_end_nm = 310.0,
        .mean_radiance = 1.0,
        .mean_irradiance = 2.0,
        .mean_reflectance = 0.5,
        .mean_noise_sigma = 0.01,
    };

    try std.testing.expect(result.measurement_space != null);
    try std.testing.expectEqual(@as(?MeasurementSpaceProduct, null), result.measurement_space_product);
    try std.testing.expectEqual(@as(u32, 4), result.measurement_space.?.sample_count);
}
