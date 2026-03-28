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
const ExecutionMode = @import("execution_mode.zig").ExecutionMode;
const errors = @import("errors.zig");
const MeasurementSpaceProduct = @import("../kernels/transport/measurement.zig").MeasurementSpaceProduct;
const MeasurementSpaceSummary = @import("../kernels/transport/measurement.zig").MeasurementSpaceSummary;
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
    ///   Carry a typed borrowed view of a measurement-space product without
    ///   retaining a raw external pointer.
    pub const BorrowedMeasurementProduct = struct {
        product_view: MeasurementSpaceProduct,

        pub fn init(product: *const MeasurementSpaceProduct) BorrowedMeasurementProduct {
            return .{
                .product_view = product.*,
            };
        }

        /// Purpose:
        ///   Reject borrowed products that do not describe a usable measurement-space sample set.
        pub fn validate(self: BorrowedMeasurementProduct) errors.Error!void {
            if (self.product_view.summary.sample_count == 0) return errors.Error.InvalidRequest;
            if (self.product_view.wavelengths.len == 0) return errors.Error.InvalidRequest;
        }

        pub fn wavelengths(self: BorrowedMeasurementProduct) []const f64 {
            return self.product_view.wavelengths;
        }

        pub fn view(self: *const BorrowedMeasurementProduct) *const MeasurementSpaceProduct {
            return &self.product_view;
        }

        pub fn summary(self: BorrowedMeasurementProduct) MeasurementSpaceSummary {
            return self.product_view.summary;
        }
    };

    /// Purpose:
    ///   Store one measured operational spectrum with explicit ownership and
    ///   per-sample sigma values.
    pub const MeasuredSpectrum = struct {
        observable: MeasurementQuantity = .radiance,
        wavelengths_nm: []const f64 = &[_]f64{},
        values: []const f64 = &[_]f64{},
        noise_sigma: []const f64 = &[_]f64{},
        owns_memory: bool = false,

        pub fn validate(self: MeasuredSpectrum) errors.Error!void {
            if (self.wavelengths_nm.len == 0 or self.values.len == 0) {
                return errors.Error.InvalidRequest;
            }
            if (self.wavelengths_nm.len != self.values.len) {
                return errors.Error.InvalidRequest;
            }
            if (self.noise_sigma.len != 0 and self.noise_sigma.len != self.values.len) {
                return errors.Error.InvalidRequest;
            }
            var previous_wavelength: ?f64 = null;
            for (self.wavelengths_nm, self.values, 0..) |wavelength_nm, value, index| {
                if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(value)) {
                    return errors.Error.InvalidRequest;
                }
                if (previous_wavelength) |previous| {
                    if (wavelength_nm <= previous) return errors.Error.InvalidRequest;
                }
                previous_wavelength = wavelength_nm;
                if (index < self.noise_sigma.len) {
                    const sigma = self.noise_sigma[index];
                    if (!std.math.isFinite(sigma) or sigma <= 0.0) return errors.Error.InvalidRequest;
                }
            }
        }

        pub fn deinitOwned(self: *MeasuredSpectrum, allocator: Allocator) void {
            if (self.owns_memory) {
                if (self.wavelengths_nm.len != 0) allocator.free(@constCast(self.wavelengths_nm));
                if (self.values.len != 0) allocator.free(@constCast(self.values));
                if (self.noise_sigma.len != 0) allocator.free(@constCast(self.noise_sigma));
            }
            self.* = .{};
        }
    };

    /// Purpose:
    ///   Group the measured radiance and irradiance carried by an operational
    ///   request.
    pub const MeasuredInput = struct {
        source_name: []const u8 = "",
        owns_source_name: bool = false,
        radiance: MeasuredSpectrum = .{ .observable = .radiance },
        irradiance: ?MeasuredSpectrum = null,

        pub fn validate(self: *const MeasuredInput) errors.Error!void {
            if (self.source_name.len == 0) return errors.Error.InvalidRequest;
            try self.radiance.validate();
            if (self.radiance.observable != .radiance) return errors.Error.InvalidRequest;
            if (self.irradiance) |irradiance| {
                try irradiance.validate();
                if (irradiance.observable != .irradiance) return errors.Error.InvalidRequest;
            }
        }

        pub fn deinitOwned(self: *MeasuredInput, allocator: Allocator) void {
            if (self.owns_source_name and self.source_name.len != 0) allocator.free(self.source_name);
            self.radiance.deinitOwned(allocator);
            if (self.irradiance) |*irradiance| {
                irradiance.deinitOwned(allocator);
                self.irradiance = null;
            }
            self.* = .{};
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
    execution_mode: ExecutionMode = .synthetic,
    measured_input: ?MeasuredInput = null,
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
        switch (self.execution_mode) {
            .synthetic => {
                if (self.measured_input != null) return errors.Error.InvalidRequest;
            },
            .operational_measured_input => {
                const measured_input = self.measured_input orelse return errors.Error.InvalidRequest;
                try measured_input.validate();
                const observation_model = self.scene.observation_model;
                if (observation_model.operationalBandCount() == 0) {
                    return errors.Error.InvalidRequest;
                }
                if ((observation_model.measured_wavelengths_nm.len != 0 and
                    !floatSlicesEqual(observation_model.measured_wavelengths_nm, measured_input.radiance.wavelengths_nm)) or
                    !floatSlicesEqual(observation_model.reference_radiance, measured_input.radiance.values) or
                    !floatSlicesEqual(observation_model.ingested_noise_sigma, measured_input.radiance.noise_sigma))
                {
                    return errors.Error.InvalidRequest;
                }
                const radiance_noise = observation_model.resolvedChannelControls(.radiance).noise;
                if ((radiance_noise.reference_signal.len != 0 and
                    !floatSlicesEqual(radiance_noise.reference_signal, measured_input.radiance.values)) or
                    (radiance_noise.reference_sigma.len != 0 and
                        !floatSlicesEqual(radiance_noise.reference_sigma, measured_input.radiance.noise_sigma)))
                {
                    return errors.Error.InvalidRequest;
                }
            },
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
        if (self.execution_mode != plan.execution_mode) {
            return errors.Error.InvalidRequest;
        }
        if (self.execution_mode == .operational_measured_input and
            plan.operational_band_count != @as(u32, @intCast(self.scene.observation_model.operationalBandCount())))
        {
            return errors.Error.InvalidRequest;
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
        if (self.measured_input) |*measured_input| {
            measured_input.deinitOwned(allocator);
            self.measured_input = null;
        }
        if (self.measurement_binding) |*binding| {
            binding.deinitOwned(allocator);
        }
        self.* = undefined;
    }
};

fn floatSlicesEqual(lhs: []const f64, rhs: []const f64) bool {
    return std.mem.eql(u8, std.mem.sliceAsBytes(lhs), std.mem.sliceAsBytes(rhs));
}
