const std = @import("std");
const errors = @import("../core/errors.zig");
const Allocator = std.mem.Allocator;

pub const LayoutRequirements = @import("LayoutRequirements.zig").LayoutRequirements;
pub const Atmosphere = @import("Atmosphere.zig").Atmosphere;
pub const Binding = @import("Binding.zig").Binding;
pub const BindingKind = @import("Binding.zig").BindingKind;
pub const Geometry = @import("Geometry.zig").Geometry;
pub const GeometryModel = @import("Geometry.zig").Model;
pub const SpectralGrid = @import("Spectrum.zig").SpectralGrid;
pub const SpectralWindow = @import("Bands.zig").SpectralWindow;
pub const SpectralBand = @import("Bands.zig").SpectralBand;
pub const SpectralBandSet = @import("Bands.zig").SpectralBandSet;
pub const Absorber = @import("Absorber.zig").Absorber;
pub const AbsorberSet = @import("Absorber.zig").AbsorberSet;
pub const Spectroscopy = @import("Absorber.zig").Spectroscopy;
pub const SpectroscopyMode = @import("Absorber.zig").SpectroscopyMode;
pub const Surface = @import("Surface.zig").Surface;
pub const SurfaceParameter = @import("Surface.zig").Parameter;
pub const Cloud = @import("Cloud.zig").Cloud;
pub const Aerosol = @import("Aerosol.zig").Aerosol;
pub const Instrument = @import("Instrument.zig").Instrument;
pub const ObservationModel = @import("ObservationModel.zig").ObservationModel;
pub const ObservationRegime = @import("ObservationModel.zig").ObservationRegime;
pub const StateVector = @import("StateVector.zig").StateVector;
pub const StateParameter = @import("StateVector.zig").Parameter;
pub const StateBounds = @import("StateVector.zig").Bounds;
pub const StatePrior = @import("StateVector.zig").Prior;
pub const StateTransform = @import("StateVector.zig").Transform;
pub const Measurement = @import("Measurement.zig").Measurement;
pub const MeasurementVector = @import("Measurement.zig").MeasurementVector;
pub const MeasurementMask = @import("Measurement.zig").SpectralMask;
pub const MeasurementErrorModel = @import("Measurement.zig").ErrorModel;
pub const InverseProblem = @import("InverseProblem.zig").InverseProblem;
pub const CovarianceBlock = @import("InverseProblem.zig").CovarianceBlock;
pub const FitControls = @import("InverseProblem.zig").FitControls;
pub const Convergence = @import("InverseProblem.zig").Convergence;
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
    bands: SpectralBandSet = .{},
    absorbers: AbsorberSet = .{},
    surface: Surface = .{},
    cloud: Cloud = .{},
    aerosol: Aerosol = .{},
    observation_model: ObservationModel = .{},

    pub fn validate(self: Scene) errors.Error!void {
        if (self.id.len == 0) {
            return errors.Error.MissingScene;
        }

        try self.atmosphere.validate();
        try self.geometry.validate();
        try self.spectral_grid.validate();
        try self.bands.validate();
        try self.absorbers.validate();
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

    pub fn deinitOwned(self: *Scene, allocator: Allocator) void {
        self.surface.deinitOwned(allocator);
        self.bands.deinitOwned(allocator);
        self.absorbers.deinitOwned(allocator);
        self.observation_model.deinitOwned(allocator);
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
            .parameters = &[_]StateParameter{
                .{ .name = "albedo", .target = "scene.surface.albedo" },
                .{ .name = "ozone", .target = "scene.absorbers.o3.scale" },
            },
        },
        .measurements = .{
            .product = "slant_column",
            .observable = "slant_column",
            .sample_count = 121,
        },
    }).validate();
}

test "scene accepts canonical bands absorbers and supporting observation metadata" {
    try (Scene{
        .id = "scene-o2a",
        .atmosphere = .{
            .layer_count = 48,
            .profile_source = .{ .kind = .asset, .name = "us_standard_profile" },
            .surface_pressure_hpa = 1013.0,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 31.7,
            .viewing_zenith_deg = 7.9,
            .relative_azimuth_deg = 143.4,
        },
        .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 121 },
        .bands = .{
            .items = &[_]SpectralBand{
                .{
                    .id = "o2a",
                    .start_nm = 758.0,
                    .end_nm = 771.0,
                    .step_nm = 0.01,
                },
            },
        },
        .absorbers = .{
            .items = &[_]Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .{ .kind = .atmosphere },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_list = .{ .kind = .asset, .name = "o2_hitran" },
                    },
                },
            },
        },
        .surface = .{
            .kind = "ross_li_brdf",
            .parameters = &[_]SurfaceParameter{
                .{ .name = "isotropic", .value = 0.028 },
                .{ .name = "volumetric", .value = 0.019 },
                .{ .name = "geometric", .value = 0.011 },
            },
        },
        .observation_model = .{
            .instrument = "tropomi",
            .solar_spectrum_source = .{ .kind = .bundle_default },
            .weighted_reference_grid_source = .{ .kind = .ingest, .name = "refspec_demo.operational_refspec_grid" },
        },
    }).validate();
}
