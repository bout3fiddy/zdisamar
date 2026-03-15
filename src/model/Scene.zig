const std = @import("std");
const errors = @import("../core/errors.zig");

pub const LayoutRequirements = @import("LayoutRequirements.zig").LayoutRequirements;
pub const Atmosphere = @import("Atmosphere.zig").Atmosphere;
pub const Geometry = @import("Geometry.zig").Geometry;
pub const SpectralGrid = @import("Spectrum.zig").SpectralGrid;
pub const Surface = @import("Surface.zig").Surface;
pub const Cloud = @import("Cloud.zig").Cloud;
pub const Aerosol = @import("Aerosol.zig").Aerosol;
pub const Instrument = @import("Instrument.zig").Instrument;
pub const ObservationModel = @import("ObservationModel.zig").ObservationModel;
pub const ObservationRegime = @import("ObservationModel.zig").ObservationRegime;
pub const StateVector = @import("StateVector.zig").StateVector;
pub const Measurement = @import("Measurement.zig").Measurement;
pub const MeasurementVector = @import("Measurement.zig").MeasurementVector;
pub const InverseProblem = @import("InverseProblem.zig").InverseProblem;
pub const DerivativeMode = @import("InverseProblem.zig").DerivativeMode;

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
    surface: Surface = .{},
    cloud: Cloud = .{},
    aerosol: Aerosol = .{},
    observation_model: ObservationModel = .{},

    pub fn validate(self: Scene) errors.Error!void {
        if (self.id.len == 0) {
            return errors.Error.MissingScene;
        }

        try self.geometry.validate();
        try self.spectral_grid.validate();
        try self.surface.validate();
        try self.cloud.validate();
        try self.aerosol.validate();
        try self.observation_model.validate();
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
