//! Purpose:
//!   Define the canonical retrieval state-vector contract.
//!
//! Physics:
//!   Captures named retrievable parameters, their target quantities, transforms, priors, and
//!   bounds for inverse methods.
//!
//! Vendor:
//!   `state-vector contract`
//!
//! Design:
//!   Keep the retrieval parameter namespace typed and explicit while preserving room for
//!   parsed-but-not-yet-wired vendor targets.
//!
//! Invariants:
//!   Parameter names must be unique at the caller level, targets must be wired for the current
//!   engine, and transform-specific prior/bounds constraints must hold.
//!
//! Validation:
//!   State-vector validation tests in this file plus retrieval integration tests that materialize
//!   solver-space state from canonical parameters.

const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");

/// Purpose:
///   Select the solver-space transform applied to a physical retrieval parameter.
pub const Transform = enum {
    none,
    log,
    logit,
};

/// Purpose:
///   Identify which physical quantity a retrieval parameter controls.
pub const Target = enum {
    unset,
    surface_albedo,
    aerosol_optical_depth_550_nm,
    aerosol_layer_center_km,
    aerosol_layer_width_km,
    cloud_optical_thickness,
    wavelength_shift_nm,
    multiplicative_offset,
    stray_light,
    /// Vendor retrieval target: total or partial column amount of an absorber.
    absorber_column_amount,
    /// Vendor retrieval target: temperature profile shift (K).
    temperature_shift,
    /// Vendor retrieval target: cloud top pressure or altitude.
    cloud_top_pressure,

    /// Purpose:
    ///   Parse the stable public target label into the typed target enum.
    pub fn parse(text: []const u8) errors.Error!Target {
        if (std.mem.eql(u8, text, "scene.surface.albedo")) return .surface_albedo;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.optical_depth_550_nm")) return .aerosol_optical_depth_550_nm;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.layer_center_km")) return .aerosol_layer_center_km;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.layer_width_km")) return .aerosol_layer_width_km;
        if (std.mem.eql(u8, text, "scene.cloud.optical_thickness")) return .cloud_optical_thickness;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.wavelength_shift_nm")) return .wavelength_shift_nm;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.multiplicative_offset")) return .multiplicative_offset;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.stray_light")) return .stray_light;
        if (std.mem.eql(u8, text, "scene.absorbers.column_amount")) return .absorber_column_amount;
        if (std.mem.eql(u8, text, "scene.atmosphere.temperature_shift")) return .temperature_shift;
        if (std.mem.eql(u8, text, "scene.cloud.top_pressure")) return .cloud_top_pressure;
        return errors.Error.InvalidRequest;
    }

    /// Purpose:
    ///   Return the stable public label for this retrieval target.
    pub fn label(self: Target) []const u8 {
        return switch (self) {
            .unset => "",
            .surface_albedo => "scene.surface.albedo",
            .aerosol_optical_depth_550_nm => "scene.aerosols.plume.optical_depth_550_nm",
            .aerosol_layer_center_km => "scene.aerosols.plume.layer_center_km",
            .aerosol_layer_width_km => "scene.aerosols.plume.layer_width_km",
            .cloud_optical_thickness => "scene.cloud.optical_thickness",
            .wavelength_shift_nm => "scene.measurement_model.calibration.wavelength_shift_nm",
            .multiplicative_offset => "scene.measurement_model.calibration.multiplicative_offset",
            .stray_light => "scene.measurement_model.calibration.stray_light",
            .absorber_column_amount => "scene.absorbers.column_amount",
            .temperature_shift => "scene.atmosphere.temperature_shift",
            .cloud_top_pressure => "scene.cloud.top_pressure",
        };
    }
};

/// Purpose:
///   Define optional lower/upper bounds for one retrieval parameter.
pub const Bounds = struct {
    enabled: bool = false,
    min: f64 = 0.0,
    max: f64 = 0.0,

    /// Purpose:
    ///   Validate enabled bounds for finite ordered endpoints.
    pub fn validate(self: Bounds) errors.Error!void {
        if (!self.enabled) return;
        if (!std.math.isFinite(self.min) or !std.math.isFinite(self.max) or self.max < self.min) {
            return errors.Error.InvalidRequest;
        }
    }
};

/// Purpose:
///   Define an optional Gaussian prior for one retrieval parameter.
pub const Prior = struct {
    enabled: bool = false,
    mean: f64 = 0.0,
    sigma: f64 = 0.0,

    /// Purpose:
    ///   Validate an enabled prior for finite mean and positive sigma.
    pub fn validate(self: Prior) errors.Error!void {
        if (!self.enabled) return;
        if (!std.math.isFinite(self.mean) or !std.math.isFinite(self.sigma) or self.sigma <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};

/// Purpose:
///   Describe one retrievable parameter in the canonical state vector.
pub const Parameter = struct {
    name: []const u8 = "",
    target: Target = .unset,
    transform: Transform = .none,
    prior: Prior = .{},
    bounds: Bounds = .{},

    /// Purpose:
    ///   Validate the target, transform, prior, and bounds for one retrieval parameter.
    pub fn validate(self: Parameter) errors.Error!void {
        if (self.name.len == 0 or self.target == .unset) {
            return errors.Error.InvalidRequest;
        }
        switch (self.target) {
            .absorber_column_amount, .temperature_shift, .cloud_top_pressure => {
                // ISSUE:
                //   These vendor-recognized targets are parsed and labeled today, but the
                //   retrieval and scene-mapping layers do not yet implement them end-to-end.
                return errors.Error.InvalidRequest;
            },
            else => {},
        }
        try self.prior.validate();
        try self.bounds.validate();

        switch (self.transform) {
            .none => {},
            .log => {
                if (self.prior.enabled and self.prior.mean <= 0.0) return errors.Error.InvalidRequest;
                if (self.bounds.enabled and self.bounds.min <= 0.0) return errors.Error.InvalidRequest;
            },
            .logit => {
                if (self.prior.enabled and (self.prior.mean <= 0.0 or self.prior.mean >= 1.0)) {
                    return errors.Error.InvalidRequest;
                }
                if (self.bounds.enabled and
                    (self.bounds.min < 0.0 or self.bounds.max > 1.0 or self.bounds.min == self.bounds.max))
                {
                    return errors.Error.InvalidRequest;
                }
            },
        }
    }
};

/// Purpose:
///   Store the ordered retrieval parameters used by an inverse problem.
pub const StateVector = struct {
    value_count: u32 = 0,
    parameters: []const Parameter = &[_]Parameter{},

    /// Purpose:
    ///   Return the effective state length, preferring explicit parameter descriptors when
    ///   present.
    pub fn count(self: StateVector) u32 {
        if (self.parameters.len != 0) return @intCast(self.parameters.len);
        return self.value_count;
    }

    /// Purpose:
    ///   Find the index of a named retrieval parameter.
    pub fn parameterIndex(self: StateVector, name: []const u8) ?usize {
        for (self.parameters, 0..) |parameter, index| {
            if (std.mem.eql(u8, parameter.name, name)) return index;
        }
        return null;
    }

    /// Purpose:
    ///   Validate the state-vector contract and any explicit parameter descriptors.
    pub fn validate(self: StateVector) errors.Error!void {
        if (self.parameters.len == 0) {
            if (self.value_count == 0) return errors.Error.InvalidRequest;
            return;
        }

        for (self.parameters) |parameter| {
            try parameter.validate();
        }

        if (self.value_count != 0 and self.value_count != self.parameters.len) {
            return errors.Error.InvalidRequest;
        }
    }

    /// Purpose:
    ///   Release any owned parameter array attached to the state vector.
    pub fn deinitOwned(self: *StateVector, allocator: Allocator) void {
        if (self.parameters.len != 0) allocator.free(self.parameters);
        self.* = .{};
    }
};

test "state vector accepts canonical parameter descriptors" {
    const vector: StateVector = .{
        .parameters = &[_]Parameter{
            .{
                .name = "surface_albedo",
                .target = .surface_albedo,
                .transform = .logit,
                .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 },
            },
            .{
                .name = "aerosol_tau",
                .target = .aerosol_optical_depth_550_nm,
                .transform = .log,
                .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.10 },
                .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 5.0 },
            },
        },
    };

    try vector.validate();
    try std.testing.expectEqual(@as(u32, 2), vector.count());
}

test "state targets parse canonical labels and reject unknown labels" {
    try std.testing.expectEqual(Target.surface_albedo, try Target.parse("scene.surface.albedo"));
    try std.testing.expectEqualStrings(
        "scene.aerosols.plume.layer_center_km",
        Target.aerosol_layer_center_km.label(),
    );
    try std.testing.expectError(errors.Error.InvalidRequest, Target.parse("scene.unknown.target"));
}

test "state vector rejects parsed-but-unwired retrieval targets" {
    const unsupported_targets = [_]Target{
        .absorber_column_amount,
        .temperature_shift,
        .cloud_top_pressure,
    };
    for (unsupported_targets) |target| {
        const vector: StateVector = .{
            .parameters = &[_]Parameter{
                .{
                    .name = "unsupported_target",
                    .target = target,
                    .prior = .{ .enabled = true, .mean = 1.0, .sigma = 0.1 },
                },
            },
        };

        try std.testing.expectError(errors.Error.InvalidRequest, vector.validate());
    }
}
