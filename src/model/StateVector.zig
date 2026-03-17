const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("../core/errors.zig");

pub const Transform = enum {
    none,
    log,
    logit,
};

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

    pub fn parse(text: []const u8) errors.Error!Target {
        if (std.mem.eql(u8, text, "scene.surface.albedo")) return .surface_albedo;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.optical_depth_550_nm")) return .aerosol_optical_depth_550_nm;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.layer_center_km")) return .aerosol_layer_center_km;
        if (std.mem.eql(u8, text, "scene.aerosols.plume.layer_width_km")) return .aerosol_layer_width_km;
        if (std.mem.eql(u8, text, "scene.cloud.optical_thickness")) return .cloud_optical_thickness;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.wavelength_shift_nm")) return .wavelength_shift_nm;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.multiplicative_offset")) return .multiplicative_offset;
        if (std.mem.eql(u8, text, "scene.measurement_model.calibration.stray_light")) return .stray_light;
        return errors.Error.InvalidRequest;
    }

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
        };
    }
};

pub const Bounds = struct {
    enabled: bool = false,
    min: f64 = 0.0,
    max: f64 = 0.0,

    pub fn validate(self: Bounds) errors.Error!void {
        if (!self.enabled) return;
        if (!std.math.isFinite(self.min) or !std.math.isFinite(self.max) or self.max < self.min) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const Prior = struct {
    enabled: bool = false,
    mean: f64 = 0.0,
    sigma: f64 = 0.0,

    pub fn validate(self: Prior) errors.Error!void {
        if (!self.enabled) return;
        if (!std.math.isFinite(self.mean) or !std.math.isFinite(self.sigma) or self.sigma <= 0.0) {
            return errors.Error.InvalidRequest;
        }
    }
};

pub const Parameter = struct {
    name: []const u8 = "",
    target: Target = .unset,
    transform: Transform = .none,
    prior: Prior = .{},
    bounds: Bounds = .{},

    pub fn validate(self: Parameter) errors.Error!void {
        if (self.name.len == 0 or self.target == .unset) {
            return errors.Error.InvalidRequest;
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

pub const StateVector = struct {
    parameter_names: []const []const u8 = &[_][]const u8{},
    value_count: u32 = 0,
    parameters: []const Parameter = &[_]Parameter{},

    pub fn count(self: StateVector) u32 {
        if (self.parameters.len != 0) return @intCast(self.parameters.len);
        return self.value_count;
    }

    pub fn parameterIndex(self: StateVector, name: []const u8) ?usize {
        if (self.parameter_names.len != 0) {
            for (self.parameter_names, 0..) |parameter_name, index| {
                if (std.mem.eql(u8, parameter_name, name)) return index;
            }
        }
        for (self.parameters, 0..) |parameter, index| {
            if (std.mem.eql(u8, parameter.name, name)) return index;
        }
        return null;
    }

    pub fn validate(self: StateVector) errors.Error!void {
        if (self.parameters.len == 0) {
            if (self.value_count == 0) return errors.Error.InvalidRequest;
            if (self.parameter_names.len != 0 and self.parameter_names.len != self.value_count) {
                return errors.Error.InvalidRequest;
            }
            return;
        }

        if (self.parameter_names.len != 0 and self.parameter_names.len != self.parameters.len) {
            return errors.Error.InvalidRequest;
        }

        for (self.parameters, 0..) |parameter, index| {
            try parameter.validate();
            if (self.parameter_names.len != 0 and
                (!std.mem.eql(u8, self.parameter_names[index], parameter.name)))
            {
                return errors.Error.InvalidRequest;
            }
        }

        if (self.value_count != 0 and self.value_count != self.parameters.len) {
            return errors.Error.InvalidRequest;
        }
    }

    pub fn deinitOwned(self: *StateVector, allocator: Allocator) void {
        if (self.parameters.len != 0) allocator.free(self.parameters);
        self.* = .{};
    }
};

test "state vector accepts canonical parameter descriptors" {
    const vector: StateVector = .{
        .parameter_names = &[_][]const u8{ "surface_albedo", "aerosol_tau" },
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
