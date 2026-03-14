const std = @import("std");
const errors = @import("../core/errors.zig");

pub const LayoutRequirements = struct {
    spectral_start_nm: f64 = 270.0,
    spectral_end_nm: f64 = 2400.0,
    spectral_sample_count: u32 = 0,
    layer_count: u32 = 0,
    state_parameter_count: u32 = 0,
    measurement_count: u32 = 0,
};

pub const SpectralGrid = struct {
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,
    sample_count: u32 = 0,
};

pub const Atmosphere = struct {
    layer_count: u32 = 0,
    has_clouds: bool = false,
    has_aerosols: bool = false,
};

pub const Geometry = struct {
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,
};

pub const ObservationModel = struct {
    instrument: []const u8 = "generic",
    regime: ObservationRegime = .nadir,
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",
};

pub const ObservationRegime = enum {
    nadir,
    limb,
    occultation,
};

pub const DerivativeMode = enum {
    none,
    semi_analytical,
    analytical_plugin,
    numerical,
};

pub const StateVector = struct {
    parameter_names: []const []const u8 = &[_][]const u8{},
    value_count: u32 = 0,
};

pub const MeasurementVector = struct {
    product: []const u8 = "radiance",
    sample_count: u32 = 0,

    pub fn validate(self: MeasurementVector) errors.Error!void {
        if (self.product.len == 0) return errors.Error.InvalidRequest;
        if (self.sample_count == 0) return errors.Error.InvalidRequest;
    }
};

pub const InverseProblem = struct {
    id: []const u8 = "inverse-0",
    state_vector: StateVector = .{},
    measurements: MeasurementVector = .{},

    pub fn validate(self: InverseProblem) errors.Error!void {
        if (self.id.len == 0) return errors.Error.InvalidRequest;
        if (self.state_vector.value_count == 0) return errors.Error.InvalidRequest;
        try self.measurements.validate();
    }
};

pub const Blueprint = struct {
    id: []const u8 = "scene-template",
    spectral_grid: SpectralGrid = .{},
    observation_regime: ObservationRegime = .nadir,
    derivative_mode: DerivativeMode = .none,
    layer_count_hint: u32 = 0,
    state_parameter_count_hint: u32 = 0,
    measurement_count_hint: u32 = 0,

    pub fn layoutRequirements(self: Blueprint) LayoutRequirements {
        return .{
            .spectral_start_nm = self.spectral_grid.start_nm,
            .spectral_end_nm = self.spectral_grid.end_nm,
            .spectral_sample_count = self.spectral_grid.sample_count,
            .layer_count = self.layer_count_hint,
            .state_parameter_count = self.state_parameter_count_hint,
            .measurement_count = self.measurement_count_hint,
        };
    }
};

pub const Scene = struct {
    id: []const u8 = "scene-0",
    atmosphere: Atmosphere = .{},
    geometry: Geometry = .{},
    spectral_grid: SpectralGrid = .{},
    observation_model: ObservationModel = .{},

    pub fn validate(self: Scene) errors.Error!void {
        if (self.id.len == 0) {
            return errors.Error.MissingScene;
        }

        if (self.spectral_grid.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }

        if (self.observation_model.instrument.len == 0) {
            return errors.Error.MissingObservationInstrument;
        }
    }

    pub fn layoutRequirements(self: Scene) LayoutRequirements {
        return .{
            .spectral_start_nm = self.spectral_grid.start_nm,
            .spectral_end_nm = self.spectral_grid.end_nm,
            .spectral_sample_count = self.spectral_grid.sample_count,
            .layer_count = self.atmosphere.layer_count,
        };
    }
};

test "scene validation rejects missing instrument and accepts valid scene" {
    var scene: Scene = .{ .id = "scene-ok", .spectral_grid = .{ .sample_count = 16 } };
    try scene.validate();

    scene.observation_model.instrument = "";
    try std.testing.expectError(errors.Error.MissingObservationInstrument, scene.validate());
}

test "blueprint and inverse problem expose canonical layout and validation contracts" {
    const blueprint_requirements = (Blueprint{
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
        .layer_count_hint = 48,
        .state_parameter_count_hint = 3,
        .measurement_count_hint = 121,
    }).layoutRequirements();

    try std.testing.expectEqual(@as(u32, 48), blueprint_requirements.layer_count);
    try std.testing.expectEqual(@as(u32, 3), blueprint_requirements.state_parameter_count);
    try std.testing.expectEqual(@as(u32, 121), blueprint_requirements.measurement_count);

    try (InverseProblem{
        .id = "retrieval-1",
        .state_vector = .{
            .parameter_names = &[_][]const u8{ "albedo", "ozone" },
            .value_count = 2,
        },
        .measurements = .{
            .product = "slant_column",
            .sample_count = 121,
        },
    }).validate();
}
