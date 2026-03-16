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

    pub fn deinit(self: *MissionRun, allocator: std.mem.Allocator) void {
        self.request.scene.deinitOwned(allocator);
        self.* = undefined;
    }
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
            .providers = .{
                .transport_solver = "builtin.dispatcher",
            },
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
            .plugin_id = "builtin.netcdf_cf",
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
    const metadata = loaded.metadata;
    const requested_product = switch (options.product) {
        .no2_nadir => "slant_column.no2",
        .hcho_nadir => "slant_column.hcho",
    };

    const has_clouds = options.has_clouds or metadata.hasClouds();
    const has_aerosols = options.has_aerosols or metadata.hasAerosols();

    var scene: Scene = .{
        .id = options.scene_id,
        .atmosphere = .{
            .layer_count = options.layer_count,
            .has_clouds = has_clouds,
            .has_aerosols = has_aerosols,
        },
        .geometry = .{
            .solar_zenith_deg = metadata.solar_zenith_deg orelse options.solar_zenith_deg,
            .viewing_zenith_deg = metadata.viewing_zenith_deg orelse options.viewing_zenith_deg,
            .relative_azimuth_deg = metadata.relative_azimuth_deg orelse options.relative_azimuth_deg,
        },
        .spectral_grid = spectral_grid,
        .surface = if (metadata.surface_albedo) |albedo|
            .{
                .albedo = albedo,
            }
        else
            .{},
        .cloud = if (has_clouds)
            .{
                .enabled = true,
                .optical_thickness = metadata.cloud_optical_thickness orelse 0.20,
                .single_scatter_albedo = metadata.cloud_single_scatter_albedo orelse 0.998,
                .asymmetry_factor = metadata.cloud_asymmetry_factor orelse 0.84,
                .angstrom_exponent = metadata.cloud_angstrom_exponent orelse 0.25,
                .top_altitude_km = metadata.cloud_top_altitude_km orelse 6.0,
                .thickness_km = metadata.cloud_thickness_km orelse 1.5,
            }
        else
            .{},
        .aerosol = if (has_aerosols)
            .{
                .enabled = true,
                .optical_depth = metadata.aerosol_optical_depth orelse 0.10,
                .single_scatter_albedo = metadata.aerosol_single_scatter_albedo orelse 0.93,
                .asymmetry_factor = metadata.aerosol_asymmetry_factor orelse 0.68,
                .angstrom_exponent = metadata.aerosol_angstrom_exponent orelse 1.2,
                .layer_center_km = metadata.aerosol_layer_center_km orelse 2.5,
                .layer_width_km = metadata.aerosol_layer_width_km orelse 2.5,
            }
        else
            .{},
        .observation_model = .{
            .instrument = options.instrument,
            .sampling = options.sampling,
            .noise_model = options.noise_model,
            .wavelength_shift_nm = metadata.wavelength_shift_nm orelse 0.0,
            .instrument_line_fwhm_nm = metadata.isrf_fwhm_nm orelse 0.0,
            .high_resolution_step_nm = metadata.high_resolution_step_nm orelse 0.0,
            .high_resolution_half_span_nm = metadata.high_resolution_half_span_nm orelse 0.0,
            .instrument_line_shape = metadata.instrument_line_shape,
            .instrument_line_shape_table = metadata.instrument_line_shape_table,
        },
    };
    errdefer scene.deinitOwned(allocator);

    scene.observation_model.operational_refspec_grid = try metadata.operational_refspec_grid.clone(allocator);
    scene.observation_model.operational_solar_spectrum = try metadata.operational_solar_spectrum.clone(allocator);
    scene.observation_model.o2_operational_lut = try metadata.o2_operational_lut.clone(allocator);
    scene.observation_model.o2o2_operational_lut = try metadata.o2o2_operational_lut.clone(allocator);
    scene.observation_model.ingested_noise_sigma = try loaded.noiseSigmaForKind(allocator, .radiance);

    var request = Request.init(scene);
    request.expected_derivative_mode = options.derivative_mode;
    request.requested_products = &[_][]const u8{requested_product};

    return .{
        .plan_template = .{
            .model_family = "disamar_standard",
            .providers = .{
                .transport_solver = "builtin.dispatcher",
            },
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
            .plugin_id = "builtin.netcdf_cf",
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
    var mission_run = try buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-op-no2",
        .spectral_input_path = "data/examples/irr_rad_channels_demo.txt",
        .destination_uri = "file://out/s5p-op-no2.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("s5p-op-no2", mission_run.plan_template.scene_blueprint.id);
    try std.testing.expectEqual(@as(u32, 2), mission_run.plan_template.scene_blueprint.measurement_count_hint);
    try std.testing.expectEqualStrings("measured_channels", mission_run.request.scene.observation_model.sampling);
    try std.testing.expectEqualStrings("snr_from_input", mission_run.request.scene.observation_model.noise_model);
    try std.testing.expectEqual(@as(u32, 2), mission_run.measurement_summary.?.sample_count);
}

test "s5p operational adapter replaces geometry and auxiliary scene fields from metadata" {
    var mission_run = try buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-op-aux",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_aux_demo.txt",
        .destination_uri = "file://out/s5p-op-aux.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f64, 31.7), mission_run.request.scene.geometry.solar_zenith_deg);
    try std.testing.expectEqual(@as(f64, 7.9), mission_run.request.scene.geometry.viewing_zenith_deg);
    try std.testing.expectEqual(@as(f64, 143.4), mission_run.request.scene.geometry.relative_azimuth_deg);
    try std.testing.expectEqual(@as(f64, 0.065), mission_run.request.scene.surface.albedo);
    try std.testing.expect(mission_run.request.scene.atmosphere.has_clouds);
    try std.testing.expect(mission_run.request.scene.atmosphere.has_aerosols);
    try std.testing.expect(mission_run.request.scene.cloud.enabled);
    try std.testing.expect(mission_run.request.scene.aerosol.enabled);
    try std.testing.expectEqual(@as(f64, 0.22), mission_run.request.scene.cloud.optical_thickness);
    try std.testing.expectEqual(@as(f64, 0.12), mission_run.request.scene.aerosol.optical_depth);
    try std.testing.expectEqual(@as(f64, 0.018), mission_run.request.scene.observation_model.wavelength_shift_nm);
    try std.testing.expectEqual(@as(f64, 0.54), mission_run.request.scene.observation_model.instrument_line_fwhm_nm);
    try std.testing.expectEqual(@as(u32, 3), mission_run.measurement_summary.?.sample_count);
}

test "s5p operational adapter maps explicit high-resolution grid and isrf table metadata" {
    var mission_run = try buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-op-isrf-table",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_isrf_table_demo.txt",
        .destination_uri = "file://out/s5p-op-isrf-table.nc",
    });
    defer mission_run.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f64, 0.08), mission_run.request.scene.observation_model.high_resolution_step_nm);
    try std.testing.expectEqual(@as(f64, 0.32), mission_run.request.scene.observation_model.high_resolution_half_span_nm);
    try std.testing.expectEqual(@as(u8, 5), mission_run.request.scene.observation_model.instrument_line_shape.sample_count);
    try std.testing.expectEqual(@as(f64, -0.32), mission_run.request.scene.observation_model.instrument_line_shape.offsets_nm[0]);
    try std.testing.expectEqual(@as(f64, 0.36), mission_run.request.scene.observation_model.instrument_line_shape.weights[2]);
    try std.testing.expectEqual(@as(u16, 3), mission_run.request.scene.observation_model.instrument_line_shape_table.nominal_count);
    try std.testing.expectEqual(@as(f64, 406.0), mission_run.request.scene.observation_model.instrument_line_shape_table.nominal_wavelengths_nm[1]);
    try std.testing.expectEqual(@as(f64, 0.30), mission_run.request.scene.observation_model.instrument_line_shape_table.weightAt(1, 1));
}

test "s5p operational adapter maps O2 and O2-O2 refspec LUT metadata" {
    var mission_run = try buildOperational(std.testing.allocator, .{
        .scene_id = "s5p-op-refspec",
        .spectral_input_path = "data/examples/irr_rad_channels_operational_refspec_demo.txt",
        .destination_uri = "file://out/s5p-op-refspec.nc",
        .sampling = "operational",
        .noise_model = "s5p_operational",
    });
    defer mission_run.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("operational", mission_run.request.scene.observation_model.sampling);
    try std.testing.expectEqualStrings("s5p_operational", mission_run.request.scene.observation_model.noise_model);
    try std.testing.expect(mission_run.request.scene.observation_model.operational_refspec_grid.enabled());
    try std.testing.expect(mission_run.request.scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expectEqual(@as(usize, 3), mission_run.request.scene.observation_model.operational_refspec_grid.wavelengths_nm.len);
    try std.testing.expectEqual(@as(usize, 5), mission_run.request.scene.observation_model.operational_solar_spectrum.wavelengths_nm.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.70), mission_run.request.scene.observation_model.operational_refspec_grid.weights[1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.8e14), mission_run.request.scene.observation_model.operational_solar_spectrum.interpolateIrradiance(761.0), 1.0e9);
    try std.testing.expect(mission_run.request.scene.observation_model.o2_operational_lut.enabled());
    try std.testing.expect(mission_run.request.scene.observation_model.o2o2_operational_lut.enabled());
    try std.testing.expectEqual(@as(usize, 3), mission_run.request.scene.observation_model.o2_operational_lut.wavelengths_nm.len);
    try std.testing.expect(
        mission_run.request.scene.observation_model.o2_operational_lut.sigmaAt(761.0, 260.0, 700.0) >
            mission_run.request.scene.observation_model.o2_operational_lut.sigmaAt(760.8, 260.0, 700.0),
    );
    try std.testing.expect(
        mission_run.request.scene.observation_model.o2o2_operational_lut.sigmaAt(761.0, 260.0, 700.0) >
            mission_run.request.scene.observation_model.o2o2_operational_lut.sigmaAt(760.8, 260.0, 700.0),
    );
}

const std = @import("std");
