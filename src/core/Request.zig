//! Purpose:
//!   Define the typed execution request submitted against a prepared plan.
//!
//! Physics:
//!   Binds a canonical scene, optional inverse problem, optional measurement source binding, and
//!   requested output products into one validated execution record.
//!
//! Vendor:
//!   `request validation and measurement binding`
//!
//! Design:
//!   Requests stay independent from plan preparation while `validateForPlan` enforces the parts
//!   of the contract that depend on the prepared transport route and measurement-source wiring.
//!
//! Invariants:
//!   Scene and inverse-problem validation must succeed before execution. Measurement bindings and
//!   derivative expectations must match the prepared plan when they are present.
//!
//! Validation:
//!   Request validation is exercised through engine execution tests and retrieval/measurement
//!   integration tests.

const SceneModel = @import("../model/Scene.zig");
const PreparedPlan = @import("Plan.zig").PreparedPlan;
const DiagnosticsSpec = @import("diagnostics.zig").DiagnosticsSpec;
const errors = @import("errors.zig");
const MeasurementSpaceProduct = @import("../kernels/transport/measurement.zig").MeasurementSpaceProduct;
const MeasurementQuantity = @import("../model/Measurement.zig").Quantity;
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Request = struct {
    pub const RequestedProductKind = enum {
        measurement_space,
        state_vector,
        fitted_measurement,
        averaging_kernel,
        jacobian,
        posterior_covariance,
        result,
        diagnostics,
    };

    /// Purpose:
    ///   Identify a named product that should be materialized from forward or retrieval
    ///   execution.
    pub const RequestedProduct = struct {
        kind: RequestedProductKind,
        name: []const u8,
        observable: ?MeasurementQuantity = null,

        pub fn named(
            name: []const u8,
            kind: RequestedProductKind,
            observable: ?MeasurementQuantity,
        ) RequestedProduct {
            return .{
                .kind = kind,
                .name = name,
                .observable = observable,
            };
        }

        /// Purpose:
        ///   Build a typed requested-product record from a public-facing product name.
        pub fn fromName(name: []const u8) RequestedProduct {
            const observable = inferObservable(name);
            return RequestedProduct.named(name, inferKind(name, observable), observable);
        }

        fn inferObservable(name: []const u8) ?MeasurementQuantity {
            if (MeasurementQuantity.parse(name)) |observable| return observable else |_| {}

            inline for ([_]MeasurementQuantity{ .radiance, .irradiance, .reflectance, .slant_column }) |observable| {
                const prefix = observable.label();
                if (std.mem.startsWith(u8, name, prefix) and
                    name.len > prefix.len and
                    name[prefix.len] == '.')
                {
                    return observable;
                }
            }
            return null;
        }

        fn inferKind(name: []const u8, observable: ?MeasurementQuantity) RequestedProductKind {
            if (observable) |resolved| {
                return switch (resolved) {
                    .radiance, .irradiance, .reflectance => .measurement_space,
                    .slant_column => .result,
                };
            }
            if (std.mem.eql(u8, name, "state_vector")) return .state_vector;
            if (std.mem.eql(u8, name, "fitted_measurement")) return .fitted_measurement;
            if (std.mem.eql(u8, name, "averaging_kernel")) return .averaging_kernel;
            if (std.mem.eql(u8, name, "jacobian")) return .jacobian;
            if (std.mem.eql(u8, name, "posterior_covariance")) return .posterior_covariance;
            if (std.mem.eql(u8, name, "diagnostics")) return .diagnostics;
            return .result;
        }
    };

    /// Purpose:
    ///   Borrow a measurement-space product that already lives outside the request lifecycle.
    pub const BorrowedMeasurementProduct = struct {
        product: *const MeasurementSpaceProduct,

        pub fn init(product: *const MeasurementSpaceProduct) BorrowedMeasurementProduct {
            return .{ .product = product };
        }

        /// Purpose:
        ///   Reject borrowed products that do not describe a usable measurement-space sample set.
        pub fn validate(self: BorrowedMeasurementProduct) errors.Error!void {
            if (self.product.summary.sample_count == 0) return errors.Error.InvalidRequest;
        }

        pub fn wavelengths(self: BorrowedMeasurementProduct) []const f64 {
            return self.product.wavelengths;
        }
    };

    /// Purpose:
    ///   Tie an inverse-problem measurement source binding to a concrete borrowed
    ///   measurement-space product.
    pub const MeasurementBinding = struct {
        source: SceneModel.Binding = .none,
        borrowed_product: BorrowedMeasurementProduct,
        owns_source: bool = false,

        /// Purpose:
        ///   Validate that the named source binding and borrowed product can be used together.
        pub fn validate(self: MeasurementBinding) errors.Error!void {
            if (!self.source.enabled()) return errors.Error.InvalidRequest;
            try self.source.validate();
            try self.borrowed_product.validate();
        }

        pub fn deinitOwned(self: *MeasurementBinding, allocator: Allocator) void {
            if (self.owns_source) self.source.deinitOwned(allocator);
            self.* = undefined;
        }
    };

    scene: SceneModel.Scene,
    inverse_problem: ?SceneModel.InverseProblem = null,
    measurement_binding: ?MeasurementBinding = null,
    requested_products: []const RequestedProduct = &[_]RequestedProduct{},
    expected_derivative_mode: ?SceneModel.DerivativeMode = null,
    diagnostics: DiagnosticsSpec = .{},

    pub fn init(scene: SceneModel.Scene) Request {
        return .{ .scene = scene };
    }

    /// Purpose:
    ///   Validate the request independently of any prepared plan.
    pub fn validate(self: *const Request) errors.Error!void {
        try self.scene.validate();
        if (self.inverse_problem) |inverse_problem| {
            try inverse_problem.validate();
        }
        if (self.measurement_binding) |binding| {
            try binding.validate();
        }
    }

    /// Purpose:
    ///   Validate the parts of the request that depend on the prepared plan contract.
    ///
    /// Assumptions:
    ///   Measurement bindings and derivative expectations are checked only after the request's
    ///   scene and inverse problem have already passed standalone validation.
    pub fn validateForPlan(self: *const Request, plan: *const PreparedPlan) errors.Error!void {
        try self.validate();

        if (self.inverse_problem) |inverse_problem| {
            switch (inverse_problem.measurements.source.kind()) {
                .stage_product, .external_observation, .ingest => {
                    const binding = self.measurement_binding orelse return errors.Error.InvalidRequest;
                    // GOTCHA:
                    //   Retrieval measurement bindings are validated against both the source kind
                    //   and the named source so that imported/borrowed products cannot silently
                    //   drift away from the inverse-problem declaration.
                    if (binding.source.kind() != inverse_problem.measurements.source.kind())
                        return errors.Error.InvalidRequest;
                    const expected_name = inverse_problem.measurements.source.name();
                    if (expected_name.len != 0 and
                        !std.mem.eql(u8, expected_name, binding.source.name()))
                    {
                        return errors.Error.InvalidRequest;
                    }
                    if (inverse_problem.measurements.selectedSampleCount(binding.borrowed_product.wavelengths()) !=
                        inverse_problem.measurements.sample_count)
                    {
                        return errors.Error.InvalidRequest;
                    }
                },
                else => {},
            }
        }

        if (self.expected_derivative_mode) |mode| {
            if (mode != plan.transport_route.derivative_mode) {
                return errors.Error.DerivativeModeMismatch;
            }
        }
    }

    /// Purpose:
    ///   Release any scene, inverse-problem, and measurement-binding storage owned by the
    ///   request.
    pub fn deinitOwned(self: *Request, allocator: Allocator) void {
        self.scene.deinitOwned(allocator);
        if (self.inverse_problem) |*inverse_problem| {
            inverse_problem.deinitOwned(allocator);
        }
        if (self.measurement_binding) |*binding| {
            binding.deinitOwned(allocator);
        }
        self.* = undefined;
    }
};
