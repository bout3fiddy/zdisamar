const PlanTemplate = @import("../../../core/Plan.zig").Template;
const Request = @import("../../../core/Request.zig").Request;
const Scene = @import("../../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../../model/Scene.zig").SpectralGrid;
const DerivativeMode = @import("../../../model/Scene.zig").DerivativeMode;
const Measurement = @import("../../../model/Measurement.zig").Measurement;
const ExportFormat = @import("../../exporters/format.zig").ExportFormat;
const ExportSpec = @import("../../exporters/spec.zig");
const SpectralAscii = @import("../../ingest/spectral_ascii.zig");

pub const Product = enum {
    no2_nadir,
    hcho_nadir,
};

pub const BuildOptions = struct {
    scene_id: []const u8,
    product: Product = .no2_nadir,
    derivative_mode: DerivativeMode = .semi_analytical,
    layer_count: u32 = 48,
    has_clouds: bool = false,
    has_aerosols: bool = false,
    solar_zenith_deg: f64 = 32.5,
    viewing_zenith_deg: f64 = 9.0,
    relative_azimuth_deg: f64 = 145.0,
    destination_uri: []const u8,
};

pub const MissionRun = struct {
    plan_template: PlanTemplate,
    request: Request,
    export_request: ExportSpec.ExportRequest,
    measurement_summary: ?Measurement = null,
};

pub const OperationalOptions = struct {
    scene_id: []const u8,
    spectral_input_path: []const u8,
    destination_uri: []const u8,
    product: Product = .no2_nadir,
    derivative_mode: DerivativeMode = .semi_analytical,
    layer_count: u32 = 48,
    has_clouds: bool = false,
    has_aerosols: bool = false,
    solar_zenith_deg: f64 = 32.5,
    viewing_zenith_deg: f64 = 9.0,
    relative_azimuth_deg: f64 = 145.0,
    instrument: []const u8 = "tropomi",
    sampling: []const u8 = "measured_channels",
    noise_model: []const u8 = "snr_from_input",
};

pub fn build(options: BuildOptions) MissionRun {
    const spectral_grid = switch (options.product) {
        .no2_nadir => SpectralGrid{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
        .hcho_nadir => SpectralGrid{
            .start_nm = 328.0,
            .end_nm = 360.0,
            .sample_count = 97,
        },
    };

    const requested_product = switch (options.product) {
        .no2_nadir => "slant_column.no2",
        .hcho_nadir => "slant_column.hcho",
    };

    const scene: Scene = .{
        .id = options.scene_id,
        .atmosphere = .{
            .layer_count = options.layer_count,
            .has_clouds = options.has_clouds,
            .has_aerosols = options.has_aerosols,
        },
        .geometry = .{
            .solar_zenith_deg = options.solar_zenith_deg,
            .viewing_zenith_deg = options.viewing_zenith_deg,
            .relative_azimuth_deg = options.relative_azimuth_deg,
        },
        .spectral_grid = spectral_grid,
        .observation_model = .{
            .instrument = "tropomi",
            .sampling = "native",
            .noise_model = "shot_noise",
        },
    };

    var request = Request.init(scene);
    request.expected_derivative_mode = options.derivative_mode;
    request.requested_products = &[_][]const u8{requested_product};

    return .{
        .plan_template = .{
            .model_family = "disamar_standard",
            .transport = "transport.dispatcher",
            .scene_blueprint = .{
                .id = options.scene_id,
                .spectral_grid = spectral_grid,
                .derivative_mode = options.derivative_mode,
                .layer_count_hint = options.layer_count,
                .measurement_count_hint = spectral_grid.sample_count,
            },
        },
        .request = request,
        .export_request = .{
            .format = ExportFormat.netcdf_cf,
            .destination_uri = options.destination_uri,
            .dataset_name = options.scene_id,
        },
    };
}

pub fn buildOperational(allocator: std.mem.Allocator, options: OperationalOptions) !MissionRun {
    var loaded = try SpectralAscii.parseFile(allocator, options.spectral_input_path);
    defer loaded.deinit(allocator);

    const spectral_grid = loaded.spectralGrid() orelse return error.InvalidOperationalInput;
    const measurement_summary = loaded.measurement("radiance");
    const requested_product = switch (options.product) {
        .no2_nadir => "slant_column.no2",
        .hcho_nadir => "slant_column.hcho",
    };

    const scene: Scene = .{
        .id = options.scene_id,
        .atmosphere = .{
            .layer_count = options.layer_count,
            .has_clouds = options.has_clouds,
            .has_aerosols = options.has_aerosols,
        },
        .geometry = .{
            .solar_zenith_deg = options.solar_zenith_deg,
            .viewing_zenith_deg = options.viewing_zenith_deg,
            .relative_azimuth_deg = options.relative_azimuth_deg,
        },
        .spectral_grid = spectral_grid,
        .observation_model = .{
            .instrument = options.instrument,
            .sampling = options.sampling,
            .noise_model = options.noise_model,
        },
    };

    var request = Request.init(scene);
    request.expected_derivative_mode = options.derivative_mode;
    request.requested_products = &[_][]const u8{requested_product};

    return .{
        .plan_template = .{
            .model_family = "disamar_standard",
            .transport = "transport.dispatcher",
            .scene_blueprint = .{
                .id = options.scene_id,
                .spectral_grid = spectral_grid,
                .derivative_mode = options.derivative_mode,
                .layer_count_hint = options.layer_count,
                .measurement_count_hint = measurement_summary.sample_count,
            },
        },
        .request = request,
        .export_request = .{
            .format = ExportFormat.netcdf_cf,
            .destination_uri = options.destination_uri,
            .dataset_name = options.scene_id,
        },
        .measurement_summary = measurement_summary,
    };
}

test "s5p mission adapter builds typed plan, request, and export inputs" {
    const mission_run = build(.{
        .scene_id = "s5p-no2",
        .destination_uri = "file://out/s5p-no2.nc",
    });

    try std.testing.expectEqualStrings("s5p-no2", mission_run.plan_template.scene_blueprint.id);
    try std.testing.expectEqual(DerivativeMode.semi_analytical, mission_run.plan_template.scene_blueprint.derivative_mode);
    try std.testing.expectEqualStrings("tropomi", mission_run.request.scene.observation_model.instrument);
    try std.testing.expectEqualStrings("slant_column.no2", mission_run.request.requested_products[0]);
    try std.testing.expectEqual(ExportFormat.netcdf_cf, mission_run.export_request.format);
}

test "s5p operational adapter derives spectral grid from measured input" {
    const mission_run = try buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-op-no2",
        .spectral_input_path = "data/examples/irr_rad_channels_demo.txt",
        .destination_uri = "file://out/s5p-op-no2.nc",
    });

    try std.testing.expectEqualStrings("s5p-op-no2", mission_run.plan_template.scene_blueprint.id);
    try std.testing.expectEqual(@as(u32, 2), mission_run.plan_template.scene_blueprint.measurement_count_hint);
    try std.testing.expectEqualStrings("measured_channels", mission_run.request.scene.observation_model.sampling);
    try std.testing.expectEqualStrings("snr_from_input", mission_run.request.scene.observation_model.noise_model);
    try std.testing.expectEqual(@as(u32, 2), mission_run.measurement_summary.?.sample_count);
}

const std = @import("std");
