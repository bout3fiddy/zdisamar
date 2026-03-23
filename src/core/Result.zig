//! Purpose:
//!   Define the owned result record returned by forward and retrieval execution.
//!
//! Physics:
//!   Carries provenance, diagnostics, forward measurement-space products, and optional
//!   retrieval-state/matrix products derived from the executed scene.
//!
//! Vendor:
//!   `result assembly and ownership`
//!
//! Design:
//!   Result storage is owned and allocator-backed so callers can keep identifiers, provenance,
//!   and optional forward/retrieval products without borrowing engine internals.
//!
//! Invariants:
//!   Identifier strings and owned products outlive the execution stack, but all owned storage
//!   must be released together by `deinit`.
//!
//! Validation:
//!   Result ownership and measurement-space tests in this file plus engine execution tests that
//!   attach forward and retrieval outputs.

const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Provenance = @import("provenance.zig").Provenance;
const std = @import("std");
const MeasurementSpaceSummary = @import("../kernels/transport/measurement.zig").MeasurementSpaceSummary;
const MeasurementSpaceProduct = @import("../kernels/transport/measurement.zig").MeasurementSpaceProduct;
const RetrievalOutcome = @import("../retrieval/common/contracts.zig").SolverOutcome;

const Allocator = std.mem.Allocator;

pub const Result = struct {
    /// Purpose:
    ///   Store a named retrieval state vector with owned parameter labels.
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

    /// Purpose:
    ///   Store a named retrieval matrix product with owned parameter labels and flattened values.
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

    /// Purpose:
    ///   Group the optional retrieval products materialized alongside the main solver outcome.
    pub const RetrievalProducts = struct {
        state_vector: ?RetrievalStateVectorProduct = null,
        fitted_measurement: ?MeasurementSpaceProduct = null,
        averaging_kernel: ?RetrievalMatrixProduct = null,
        jacobian: ?RetrievalMatrixProduct = null,
        posterior_covariance: ?RetrievalMatrixProduct = null,

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
            if (self.posterior_covariance) |*posterior_covariance| {
                posterior_covariance.deinit(allocator);
                self.posterior_covariance = null;
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

    /// Purpose:
    ///   Initialize an owned result record from the prepared plan metadata and provenance.
    pub fn initOwned(
        self: *Result,
        allocator: Allocator,
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        provenance: Provenance,
    ) !void {
        const owned_workspace_label = try allocator.dupe(u8, workspace_label);
        errdefer allocator.free(owned_workspace_label);
        const owned_scene_id = try allocator.dupe(u8, scene_id);
        errdefer allocator.free(owned_scene_id);

        self.* = .{
            .plan_id = plan_id,
            .workspace_label = owned_workspace_label,
            .scene_id = owned_scene_id,
            .provenance = provenance,
            .diagnostics = Diagnostics.fromSpec(.{ .provenance = true }, "Prepared transport routing and provenance are wired; see validation docs for the currently verified scientific coverage."),
        };
    }

    pub fn init(
        allocator: Allocator,
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        provenance: Provenance,
    ) !Result {
        var result: Result = undefined;
        try result.initOwned(allocator, plan_id, workspace_label, scene_id, provenance);
        return result;
    }

    /// Purpose:
    ///   Attach the fully sampled measurement-space product and expose its summary at top level.
    pub fn attachMeasurementSpaceProduct(self: *Result, product: MeasurementSpaceProduct) void {
        self.measurement_space = product.summary;
        self.measurement_space_product = product;
    }

    /// Purpose:
    ///   Attach the owned solver outcome while discarding any borrowed fitted-scene snapshot.
    pub fn attachRetrievalOutcome(self: *Result, outcome: RetrievalOutcome) void {
        var owned = outcome;
        // GOTCHA:
        //   Results keep fitted products and solver diagnostics, not a borrowed fitted scene
        //   graph. Clearing the snapshot here avoids handing out scene ownership implicitly.
        owned.fitted_scene = null;
        self.retrieval = owned;
    }

    pub fn attachRetrievalProducts(self: *Result, products: RetrievalProducts) void {
        self.retrieval_products = products;
    }

    /// Purpose:
    ///   Release all storage owned by the result and reset the record to an empty state.
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
        // INVARIANT:
        //   Identifier strings are duplicated into the result and must be released after any
        //   attached products that may still refer to their labels diagnostically.
        allocator.free(self.workspace_label);
        allocator.free(self.scene_id);
        self.workspace_label = "";
        self.scene_id = "";
    }
};

test "result can carry summary-only measurement-space output" {
    var result = try Result.init(std.testing.allocator, 7, "unit", "scene-summary", .{});
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

test "result owns identifier strings independently of caller buffers" {
    const workspace_label = try std.fmt.allocPrint(std.testing.allocator, "workspace-{d}", .{11});
    const scene_id = try std.fmt.allocPrint(std.testing.allocator, "scene-{d}", .{29});

    var result = try Result.init(std.testing.allocator, 11, workspace_label, scene_id, .{});
    defer result.deinit(std.testing.allocator);

    std.testing.allocator.free(workspace_label);
    std.testing.allocator.free(scene_id);

    try std.testing.expectEqualStrings("workspace-11", result.workspace_label);
    try std.testing.expectEqualStrings("scene-29", result.scene_id);
}
