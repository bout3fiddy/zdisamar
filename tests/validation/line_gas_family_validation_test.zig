const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

const ReferenceData = internal.reference_data;
const OpticsPrepare = internal.kernels.optics.prepare;
const MeasurementSpace = internal.kernels.transport.measurement_space;
const AbsorberSpecies = @typeInfo(@TypeOf(@as(zdisamar.Absorber, .{}).resolved_species)).optional.child;

const SimulatedCase = struct {
    prepared: OpticsPrepare.PreparedOpticalState,
    product: MeasurementSpace.MeasurementSpaceProduct,

    fn deinit(self: *SimulatedCase, allocator: std.mem.Allocator) void {
        self.product.deinit(allocator);
        self.prepared.deinit(allocator);
        self.* = undefined;
    }
};

fn buildSyntheticProfile(allocator: std.mem.Allocator) !ReferenceData.ClimatologyProfile {
    return .{
        .rows = try allocator.dupe(ReferenceData.ClimatologyPoint, &.{
            .{ .altitude_km = 0.0, .pressure_hpa = 1000.0, .temperature_k = 290.0, .air_number_density_cm3 = 2.0e19 },
            .{ .altitude_km = 4.0, .pressure_hpa = 820.0, .temperature_k = 275.0, .air_number_density_cm3 = 1.7e19 },
            .{ .altitude_km = 8.0, .pressure_hpa = 620.0, .temperature_k = 255.0, .air_number_density_cm3 = 1.3e19 },
            .{ .altitude_km = 12.0, .pressure_hpa = 430.0, .temperature_k = 235.0, .air_number_density_cm3 = 9.0e18 },
        }),
    };
}

fn buildZeroContinuumTable(
    allocator: std.mem.Allocator,
    start_nm: f64,
    end_nm: f64,
) !ReferenceData.CrossSectionTable {
    const midpoint_nm = (start_nm + end_nm) * 0.5;
    return .{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = start_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = end_nm, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
}

fn buildCo2LineList(allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(ReferenceData.SpectroscopyLine, &.{
            .{
                .gas_index = 2,
                .isotope_number = 1,
                .center_wavelength_nm = 1600.14,
                .line_strength_cm2_per_molecule = 2.5e-16,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.72,
                .lower_state_energy_cm1 = 90.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
            .{
                .gas_index = 2,
                .isotope_number = 1,
                .center_wavelength_nm = 1600.22,
                .line_strength_cm2_per_molecule = 1.2e-16,
                .air_half_width_nm = 0.001,
                .temperature_exponent = 0.70,
                .lower_state_energy_cm1 = 120.0,
                .pressure_shift_nm = 0.0,
                .line_mixing_coefficient = 0.0,
            },
        }),
    };
}

fn minValueInRange(
    wavelengths_nm: []const f64,
    values: []const f64,
    start_nm: f64,
    end_nm: f64,
) f64 {
    var best = std.math.inf(f64);
    for (wavelengths_nm, values) |wavelength_nm, value| {
        if (wavelength_nm < start_nm or wavelength_nm > end_nm) continue;
        if (value < best) best = value;
    }
    return best;
}

fn simulateCo2LineGasCase(
    allocator: std.mem.Allocator,
    volume_mixing_ratio_profile_ppmv: []const [2]f64,
) !SimulatedCase {
    var profile = try buildSyntheticProfile(allocator);
    defer profile.deinit(allocator);
    var cross_sections = try buildZeroContinuumTable(allocator, 1600.0, 1600.35);
    defer cross_sections.deinit(allocator);
    var line_list = try buildCo2LineList(allocator);
    defer line_list.deinit(allocator);
    var lut = try ReferenceData.buildDemoAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    const scene: zdisamar.Scene = .{
        .id = "validation-co2-line-gas",
        .surface = .{
            .albedo = 0.28,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 35.0,
            .viewing_zenith_deg = 15.0,
            .relative_azimuth_deg = 40.0,
        },
        .atmosphere = .{
            .layer_count = 3,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 1600.0,
            .end_nm = 1600.35,
            .sample_count = 61,
        },
        .absorbers = .{
            .items = &.{
                zdisamar.Absorber{
                    .id = "co2",
                    .species = "co2",
                    .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "co2").?,
                    .profile_source = .atmosphere,
                    .volume_mixing_ratio_profile_ppmv = volume_mixing_ratio_profile_ppmv,
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_gas_controls = .{
                            .active_stage = .simulation,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = .{ .custom = "validation-co2-line-gas" },
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.08,
            .builtin_line_shape = .gaussian,
            .high_resolution_step_nm = 0.002,
            .high_resolution_half_span_nm = 0.08,
        },
    };

    var prepared = try OpticsPrepare.prepareWithSpectroscopy(
        allocator,
        &scene,
        &profile,
        &cross_sections,
        &line_list,
        &lut,
    );
    errdefer prepared.deinit(allocator);

    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .none,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.layer_count,
            .measurement_count_hint = scene.spectral_grid.sample_count,
        },
        .rtm_controls = .{
            .n_streams = 4,
            .num_orders_max = 4,
        },
    });
    defer plan.deinit();

    var product = try MeasurementSpace.simulateProduct(
        allocator,
        &scene,
        plan.transport_route,
        &prepared,
        .{
            .transport = plan.providers.transport,
            .surface = plan.providers.surface,
            .instrument = plan.providers.instrument,
            .noise = plan.providers.noise,
        },
    );
    errdefer product.deinit(allocator);

    return .{
        .prepared = prepared,
        .product = product,
    };
}

test "validation non-o2 staged line-gas profiles change prepared optics and downstream spectra" {
    var low_case = try simulateCo2LineGasCase(std.testing.allocator, &.{
        .{ 1000.0, 400.0 },
        .{ 430.0, 200.0 },
    });
    defer low_case.deinit(std.testing.allocator);
    var high_case = try simulateCo2LineGasCase(std.testing.allocator, &.{
        .{ 1000.0, 4000.0 },
        .{ 430.0, 2000.0 },
    });
    defer high_case.deinit(std.testing.allocator);

    try std.testing.expect(high_case.prepared.air_column_density_factor > high_case.prepared.column_density_factor);
    try std.testing.expect(high_case.prepared.column_density_factor < high_case.prepared.air_column_density_factor * 1.0e-2);
    try std.testing.expect(high_case.prepared.sublayers.?[0].absorber_number_density_cm3 < high_case.prepared.sublayers.?[0].oxygen_number_density_cm3);
    try std.testing.expect(high_case.prepared.totalOpticalDepthAtWavelength(1600.14) > low_case.prepared.totalOpticalDepthAtWavelength(1600.14));

    const low_trough = minValueInRange(
        low_case.product.wavelengths,
        low_case.product.reflectance,
        1600.10,
        1600.24,
    );
    const high_trough = minValueInRange(
        high_case.product.wavelengths,
        high_case.product.reflectance,
        1600.10,
        1600.24,
    );
    try std.testing.expect(high_trough < low_trough);
}
