const std = @import("std");
const AbsorberModel = @import("../../input/Absorber.zig");
const AerosolModel = @import("../../input/Aerosol.zig");
const AtmosphereModel = @import("../../input/Atmosphere.zig");
const InstrumentModel = @import("../../input/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const InstrumentGrid = @import("../../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../../forward_model/optical_properties/root.zig");
const ObservationModel = @import("../../input/ObservationModel.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const Trace = @import("../../forward_model/instrumentation/trace.zig");
const bundled_optics = @import("../../input/reference_data/bundled/assets.zig");
const reference_assets = @import("../../input/reference_data/ingest/reference_assets.zig");
const transport_common = @import("../../forward_model/radiative_transfer/root.zig");
const reference_types = @import("types.zig");
const adaptive_plan = @import("../../forward_model/implementations/instrument/adaptive_plan.zig");
const instrument_types = @import("../../forward_model/implementations/instrument/types.zig");
const fixed_asset_cache = @import("fixed_asset_cache.zig");

const Allocator = std.mem.Allocator;
pub const AbsorberSpecies = reference_types.AbsorberSpecies;
pub const SolveConfig = reference_types.SolveConfig;
pub const RadiativeTransferControls = reference_types.RadiativeTransferControls;
pub const ReferenceSample = reference_types.ReferenceSample;
pub const ExternalAsset = reference_types.ExternalAsset;
pub const PlanSpec = reference_types.PlanSpec;
pub const Metadata = reference_types.Metadata;
pub const GeometrySpec = reference_types.GeometrySpec;
pub const AerosolSpec = reference_types.AerosolSpec;
pub const ObservationSpec = reference_types.ObservationSpec;
pub const LineGasSpec = reference_types.LineGasSpec;
pub const CiaSpec = reference_types.CiaSpec;
pub const InputsSpec = reference_types.InputsSpec;
pub const ResolvedVendorO2ACase = reference_types.ResolvedVendorO2ACase;
pub const LoadedVendorO2AInputs = reference_types.LoadedVendorO2AInputs;
pub const SolarSpectrumSample = reference_types.SolarSpectrumSample;

// run.zig --------------------------------------------------------------------------------------------------- |
// Runtime assembly for resolved O2 A reference cases. This is the place where parsed case rows become loaded  |
// reference data, a forward-model Scene, a PreparedOpticalState, and optionally an instrument-grid product.   |
//                                                                                                             |
// called by                                                                                                   |
//   o2a_reference/root.zig exposes the public zdisamar.o2a facade. metrics.zig wraps the returned runtime     |
//   owners in validation-friendly structs. Validation tests and o2a_plot_spectrum_cli run the full product    |
//   route. optimal_estimation/retrieval.zig calls this file directly so one OE session can keep loaded inputs,|
//   a mutable scene, weak-cutoff support, and borrowed profile preparation alive across many state updates.   |
//                                                                                                             |
// full validation route                                                                                       |
//   ResolvedVendorO2ACase                                                                                     |
//     -> loadResolvedVendorO2AInputs       fixed/bundled reference assets become owned loaded tables          |
//     -> buildResolvedVendorO2AScene       parsed controls become Scene, absorber set, and solar support      |
//     -> OpticsPrepare.prepare             Scene + loaded tables become PreparedOpticalState                  |
//     -> installVendorWeakCutoffGrid       line-list cutoff support follows the realized instrument grid      |
//     -> rewindowParitySolarSupport...     solar support is trimmed to the shared radiance/irradiance kernel  |
//     -> prepareResolvedVendorO2ASolveConfig -> InstrumentGrid.simulateProduct                                |
//                                                                                                             |
// retrieval session route                                                                                     |
//   RetrievalPreparedCase loads inputs once, owns one mutable Scene, and calls the session-cache optical      |
//   refresh after each state write. Static continuum/CIA tables are borrowed from LoadedVendorO2AInputs, the  |
//   weak-cutoff grid is built once from the realized support, and solar rewindowing is installed once per     |
//   session. Each iteration then focuses on scene mutation, optical-state rebuild, product simulation, and    |
//   Jacobian rows.                                                                                            |
//                                                                                                             |
// cache and ownership rules                                                                                   |
//   fixed_asset_cache returns caller-owned clones, never retained cache slices. LoadedVendorO2AInputs owns    |
//   loaded profile, spectroscopy profile, continuum, line list, optional CIA, LUT, reference, and solar rows. |
//   PreparedRuntimeCase is an owner/view header over reference rows, Scene, solve config, and prepared        |
//   optical state; callers deinit the moved owners in that order.                                             |
//                                                                                                             |
// performance boundary                                                                                        |
//   This file runs setup and retrieval refresh work before the RTM wavelength loop. The repeated retrieval    |
//   preparation boundary avoids file I/O, static reference-table reloads, weak-line support-grid rebuilds,    |
//   and solar rewindowing when the instrument/grid support did not change. Trace zones split those costs so   |
//   benchmark traces show which setup work moved or disappeared.                                              |
// ----------------------------------------------------------------------------------------------------------- |

// PreparedRuntimeCase --------------------------------------------------------------------------------------- |
// Prepared O2 A case with reference samples, before instrument-grid product simulation.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2904 B (2.836 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] reference  : []ReferenceSample                                                                 |
// [  16.. 687] scene      : Scene                                                                             |
// [ 688.. 767] rtm_config : SolveConfig                                                                       |
// [ 768..2903] prepared   : PreparedOpticalState                                                              |
//                                                                                                             |
// out-of-line                                                                                                 |
//   reference is owned by the runtime case. scene and prepared are inline headers with nested owned storage.  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 46 cache lines at 64 B per line                                                                 |
// footprint: per instance = 2904 B plus referenced scene/prepared/reference storage                           |
pub const PreparedRuntimeCase = struct {
    reference: []ReferenceSample,
    scene: Scene,
    rtm_config: SolveConfig,
    prepared: OpticsPrepare.PreparedOpticalState,
};

// WeakCutoffGridCache --------------------------------------------------------------------------------------- |
// Retrieval-scoped weak-line cutoff support grid reused across state evaluations.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelengths_nm  : []f64                                                                            |
// [16..31] wavenumbers_cm1 : []f64                                                                            |
//                                                                                                             |
// out-of-line                                                                                                 |
//   wavelength and wavenumber grids are owned dense f64 buffers.                                              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 32 B plus 16 B per retained support wavelength                                    |
pub const WeakCutoffGridCache = struct {
    wavelengths_nm: []f64 = &.{},
    wavenumbers_cm1: []f64 = &.{},

    pub fn deinit(self: *WeakCutoffGridCache, allocator: Allocator) void {
        allocator.free(self.wavelengths_nm);
        allocator.free(self.wavenumbers_cm1);
        self.* = .{};
    }

    fn valid(self: WeakCutoffGridCache) bool {
        return self.wavelengths_nm.len >= 2 and self.wavelengths_nm.len == self.wavenumbers_cm1.len;
    }

    fn replaceFromSupport(
        self: *WeakCutoffGridCache,
        allocator: Allocator,
        support_wavelengths_nm: []const f64,
    ) !void {
        const owned_wavelengths = try allocator.dupe(f64, support_wavelengths_nm);
        errdefer allocator.free(owned_wavelengths);
        const owned_wavenumbers = try allocator.alloc(f64, support_wavelengths_nm.len);
        errdefer allocator.free(owned_wavenumbers);
        for (support_wavelengths_nm, owned_wavenumbers) |wavelength_nm, *wavenumber_cm1| {
            wavenumber_cm1.* = 1.0e7 / @max(wavelength_nm, 1.0e-9);
        }

        self.deinit(allocator);
        self.wavelengths_nm = owned_wavelengths;
        self.wavenumbers_cm1 = owned_wavenumbers;
    }
};

pub fn loadReferenceSamples(allocator: Allocator, path: []const u8) ![]ReferenceSample {
    // loadReferenceSamples ---------------------------------------------------------------------------------- |
    // Load the DISAMAR/vendor reference CSV used as validation truth. The parser reads the file once, skips   |
    // the header row, and keeps wavelength, irradiance, and reflectance. The third CSV column is required so  |
    // malformed rows fail, but it is not part of ReferenceSample.                                             |
    //                                                                                                         |
    // ownership                                                                                               |
    //   Returns an owned []ReferenceSample in the caller allocator. fixed_asset_cache may clone this result   |
    //   for later calls, but callers still deinit their returned slice normally.                              |
    // --------------------------------------------------------------------------------------------------------|

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(ReferenceSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;
        _ = columns.next() orelse return error.InvalidData;
        const reflectance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
            .reflectance = try std.fmt.parseFloat(f64, std.mem.trim(u8, reflectance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

pub fn loadSolarSpectrumSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]SolarSpectrumSample {
    // loadSolarSpectrumSamples ------------------------------------------------------------------------------ |
    // Load the high-resolution solar irradiance CSV used to build operational solar support. This accepts     |
    // only the reference solar CSV asset format, then keeps wavelength and irradiance rows for later window   |
    // trimming in buildResolvedVendorO2AScene and rewindowParitySolarSupportToMeasurementKernel.              |
    //                                                                                                         |
    // ownership                                                                                               |
    //   Returns an owned []SolarSpectrumSample in the caller allocator. No Scene borrows this raw slice;      |
    //   Scene construction allocates its own retained wavelength and irradiance arrays.                       |
    // --------------------------------------------------------------------------------------------------------|

    if (!std.mem.eql(u8, asset.format, "solar_reference_csv")) return error.UnsupportedSolarReferenceAssetFormat;

    const file = try std.fs.cwd().openFile(asset.path, .{});
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    var samples = std.ArrayList(SolarSpectrumSample).empty;
    errdefer samples.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        const wavelength_text = columns.next() orelse return error.InvalidData;
        const irradiance_text = columns.next() orelse return error.InvalidData;

        try samples.append(allocator, .{
            .wavelength_nm = try std.fmt.parseFloat(f64, std.mem.trim(u8, wavelength_text, " \t")),
            .irradiance = try std.fmt.parseFloat(f64, std.mem.trim(u8, irradiance_text, " \t")),
        });
    }

    return try samples.toOwnedSlice(allocator);
}

pub fn loadResolvedVendorO2AInputs(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !LoadedVendorO2AInputs {
    // loadResolvedVendorO2AInputs --------------------------------------------------------------------------- |
    // Hydrate one resolved O2 A case into the owned reference-data bundle consumed by Scene/optics setup.     |
    // This is the expensive input boundary for both one-shot validation and retrieval-session preparation.    |
    //                                                                                                         |
    // steps                                                                                                   |
    //   1. load the fixed atmosphere profile, then densify it to the case surface pressure                    |
    //   2. build the spectroscopy profile on the original vendor pressure nodes                               |
    //   3. load continuum, O2 line-list sidecars, optional O2-O2 CIA, airmass LUT, reference, and solar rows  |
    //   4. return a LoadedVendorO2AInputs owner bundle that later preparation routes may borrow from safely   |
    //                                                                                                         |
    // ownership                                                                                               |
    //   Fixed-asset caches return clones in allocator. The returned bundle owns every loaded table/slice.     |
    //   Retrieval keeps this bundle alive so optical refreshes can borrow static continuum/CIA tables safely. |
    // --------------------------------------------------------------------------------------------------------|

    var profile = try loadFixedClimatologyProfile(allocator, resolved.inputs.atmosphere_profile);
    errdefer profile.deinit(allocator);
    var dense_profile = try profile.densifyVendorPressureGrid(allocator, resolved.surface_pressure_hpa);
    errdefer dense_profile.deinit(allocator);
    var spectroscopy_profile = try buildVendorTraceGasSpectroscopyProfile(
        allocator,
        profile,
        dense_profile,
    );
    errdefer spectroscopy_profile.deinit(allocator);
    profile.deinit(allocator);
    profile = dense_profile;
    dense_profile = .{ .rows = &.{} };

    var cross_sections = try bundled_optics.zeroContinuumTable(allocator, 758.0, 771.0);
    errdefer cross_sections.deinit(allocator);

    var line_list = try loadResolvedVendorO2ALineList(allocator, resolved.o2);
    errdefer line_list.deinit(allocator);

    var cia_table: ?ReferenceDataModel.CollisionInducedAbsorptionTable = null;
    errdefer if (cia_table) |*table| table.deinit(allocator);
    if (resolved.o2o2.enabled) {
        const cia_asset = resolved.o2o2.cia_asset orelse return error.MissingCollisionInducedAbsorptionAsset;
        cia_table = try loadFixedCiaTable(allocator, cia_asset);
    }

    var lut = try loadFixedAirmassLut(allocator, resolved.inputs.airmass_factor_lut);
    errdefer lut.deinit(allocator);

    const reference = try loadFixedReferenceSamples(allocator, resolved.inputs.vendor_reference_csv);
    errdefer allocator.free(reference);
    const raw_solar_spectrum = try loadFixedSolarSpectrumSamples(allocator, resolved.inputs.raw_solar_reference);
    errdefer allocator.free(raw_solar_spectrum);

    return .{
        .profile = profile,
        .spectroscopy_profile = spectroscopy_profile,
        .cross_sections = cross_sections,
        .line_list = line_list,
        .cia_table = cia_table,
        .lut = lut,
        .reference = reference,
        .raw_solar_spectrum = raw_solar_spectrum,
    };
}

fn loadFixedClimatologyProfile(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.ClimatologyProfile {
    if (try fixed_asset_cache.loadProfile(allocator, asset)) |cached| return cached;

    var profile_asset = try reference_assets.loadExternalAsset(
        allocator,
        .climatology_profile,
        asset.id,
        asset.path,
        asset.format,
    );
    defer profile_asset.deinit(allocator);
    var profile = try profile_asset.toClimatologyProfile(allocator);
    errdefer profile.deinit(allocator);
    try fixed_asset_cache.storeProfile(asset, profile);
    return profile;
}

fn loadFixedCiaTable(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.CollisionInducedAbsorptionTable {
    if (try fixed_asset_cache.loadCia(allocator, asset)) |cached| return cached;

    var loaded_cia = try reference_assets.loadExternalAsset(
        allocator,
        .collision_induced_absorption_table,
        asset.id,
        asset.path,
        asset.format,
    );
    defer loaded_cia.deinit(allocator);
    var table = try loaded_cia.toCollisionInducedAbsorptionTable(allocator);
    errdefer table.deinit(allocator);
    try fixed_asset_cache.storeCia(asset, table);
    return table;
}

fn loadFixedAirmassLut(
    allocator: Allocator,
    asset: ExternalAsset,
) !ReferenceDataModel.AirmassFactorLut {
    if (try fixed_asset_cache.loadAirmassLut(allocator, asset)) |cached| return cached;

    var lut_asset = try reference_assets.loadExternalAsset(
        allocator,
        .lookup_table,
        asset.id,
        asset.path,
        asset.format,
    );
    defer lut_asset.deinit(allocator);
    var lut = try lut_asset.toAirmassFactorLut(allocator);
    errdefer lut.deinit(allocator);
    try fixed_asset_cache.storeAirmassLut(asset, lut);
    return lut;
}

fn loadFixedReferenceSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]ReferenceSample {
    if (try fixed_asset_cache.loadReferenceSamples(allocator, asset)) |cached| return cached;

    const samples = try loadReferenceSamples(allocator, asset.path);
    errdefer allocator.free(samples);
    try fixed_asset_cache.storeReferenceSamples(asset, samples);
    return samples;
}

fn loadFixedSolarSpectrumSamples(
    allocator: Allocator,
    asset: ExternalAsset,
) ![]SolarSpectrumSample {
    if (try fixed_asset_cache.loadSolarSamples(allocator, asset)) |cached| return cached;

    const samples = try loadSolarSpectrumSamples(allocator, asset);
    errdefer allocator.free(samples);
    try fixed_asset_cache.storeSolarSamples(asset, samples);
    return samples;
}

fn buildVendorTraceGasSpectroscopyProfile(
    allocator: Allocator,
    source_profile: ReferenceDataModel.ClimatologyProfile,
    dense_profile: ReferenceDataModel.ClimatologyProfile,
) !ReferenceDataModel.ClimatologyProfile {
    const rows = try allocator.alloc(ReferenceDataModel.ClimatologyPoint, source_profile.rows.len);
    errdefer allocator.free(rows);

    for (source_profile.rows, rows) |source_row, *target_row| {
        const pressure_hpa = source_row.pressure_hpa;
        const temperature_k = source_row.temperature_k;
        target_row.* = .{
            .altitude_km = dense_profile.interpolateAltitudeForPressureSpline(pressure_hpa),
            .pressure_hpa = pressure_hpa,
            .temperature_k = temperature_k,
            .air_number_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / 1.380658e-19,
        };
    }

    return .{ .rows = rows };
}

pub fn buildResolvedVendorO2AScene(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    raw_solar_spectrum: []const SolarSpectrumSample,
) !Scene {
    // buildResolvedVendorO2AScene --------------------------------------------------------------------------- |
    // Translate parsed O2 A controls into the mutable Scene used by optical preparation and RTM execution.    |
    // This function owns the conversion from reference-case schema names to the public forward-model input    |
    // shape: surface, geometry, atmosphere, aerosol controls, absorber set, observation model, and band       |
    // support.                                                                                                |
    //                                                                                                         |
    // ownership                                                                                               |
    //   raw_solar_spectrum is borrowed. retainSolarSupport allocates the Scene-owned solar arrays, and the    |
    //   returned Scene owns absorber ids/isotope controls plus operational_band_support storage.              |
    //                                                                                                         |
    // calls                                                                                                   |
    //   retainSolarSupport                                                                                    |
    //   buildO2AbsorberSet                                                                                    |
    //   sceneFromResolvedO2A                                                                                  |
    //   attachResolvedIntervals                                                                               |
    // --------------------------------------------------------------------------------------------------------|

    var solar_spectrum = try retainSolarSupport(allocator, resolved, raw_solar_spectrum);
    var solar_spectrum_owned = true;
    errdefer if (solar_spectrum_owned) solar_spectrum.deinitOwned(allocator);

    const operational_band_support = try allocator.alloc(Instrument.OperationalBandSupport, 1);
    var operational_band_support_owned = true;
    errdefer if (operational_band_support_owned) {
        operational_band_support[0].deinitOwned(allocator);
        allocator.free(operational_band_support);
    };
    operational_band_support[0] = .{
        .id = "primary",
        .high_resolution_step_nm = resolved.observation.high_resolution_step_nm,
        .high_resolution_half_span_nm = resolved.observation.high_resolution_half_span_nm,
        .operational_solar_spectrum = solar_spectrum,
    };
    solar_spectrum_owned = false;

    var absorber_set = try buildO2AbsorberSet(allocator, resolved);
    var absorber_set_owned = true;
    errdefer if (absorber_set_owned) absorber_set.deinitOwned(allocator);

    var scene = sceneFromResolvedO2A(
        resolved,
        absorber_set,
        operational_band_support,
    );
    operational_band_support_owned = false;
    absorber_set_owned = false;
    errdefer scene.deinitOwned(allocator);

    attachResolvedIntervals(&scene, resolved);
    try primaryOperationalBandSupportOwned(&scene).operational_solar_spectrum.prepareInterpolation(allocator);
    return scene;
}

fn retainSolarSupport(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
    raw_solar_spectrum: []const SolarSpectrumSample,
) !InstrumentModel.OperationalSolarSpectrum {
    const solar_support_margin_nm = 2.0 * resolved.observation.instrument_line_fwhm_nm;
    const solar_support_start_nm = resolved.spectral_grid.start_nm - solar_support_margin_nm;
    const solar_support_end_nm = resolved.spectral_grid.end_nm + solar_support_margin_nm;

    var retained_solar_count: usize = 0;
    for (raw_solar_spectrum) |sample| {
        if (sample.wavelength_nm <= solar_support_start_nm) continue;
        if (sample.wavelength_nm >= solar_support_end_nm) continue;

        retained_solar_count += 1;
    }

    if (retained_solar_count < 3) return error.InvalidData;

    const solar_wavelengths = try allocator.alloc(f64, retained_solar_count);
    errdefer allocator.free(solar_wavelengths);
    const solar_irradiance = try allocator.alloc(f64, retained_solar_count);
    errdefer allocator.free(solar_irradiance);
    var solar_index: usize = 0;
    for (raw_solar_spectrum) |sample| {
        if (sample.wavelength_nm <= solar_support_start_nm) continue;
        if (sample.wavelength_nm >= solar_support_end_nm) continue;

        solar_wavelengths[solar_index] = sample.wavelength_nm;
        solar_irradiance[solar_index] = sample.irradiance;
        solar_index += 1;
    }

    return .{
        .wavelengths_nm = solar_wavelengths,
        .irradiance = solar_irradiance,
    };
}

fn buildO2AbsorberSet(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !AbsorberModel.AbsorberSet {
    const absorber_items = try allocator.alloc(AbsorberModel.Absorber, 1);
    errdefer allocator.free(absorber_items);
    const absorber_id = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_id);
    const absorber_species = try allocator.dupe(u8, "o2");
    errdefer allocator.free(absorber_species);
    const isotopes_sim = if (resolved.o2.isotopes_sim.len != 0)
        try allocator.dupe(u8, resolved.o2.isotopes_sim)
    else
        &.{};
    errdefer if (isotopes_sim.len != 0) allocator.free(isotopes_sim);

    absorber_items[0] = .{
        .id = absorber_id,
        .species = absorber_species,
        .resolved_species = std.meta.stringToEnum(AbsorberSpecies, "o2").?,
        .profile_source = .atmosphere,
        .spectroscopy = .{
            .mode = .line_by_line,
            .line_gas_controls = .{
                .factor_lm_sim = resolved.o2.line_mixing_factor,
                .isotopes_sim = isotopes_sim,
                .threshold_line_sim = resolved.o2.threshold_line_sim,
                .cutoff_sim_cm1 = resolved.o2.cutoff_sim_cm1,
                .active_stage = .simulation,
            },
        },
    };

    return .{
        .items = absorber_items,
    };
}

fn sceneFromResolvedO2A(
    resolved: *const ResolvedVendorO2ACase,
    absorber_set: AbsorberModel.AbsorberSet,
    operational_band_support: []Instrument.OperationalBandSupport,
) Scene {
    const aerosol = scalarAerosolView(resolved.aerosol);
    const phase_function_truncation_threshold =
        resolved.rtm_controls.performance_thresholds.phase_function_truncation_threshold;

    return .{
        .id = resolved.scene_id,
        .surface = .{
            .albedo = resolved.surface_albedo,
            .pressure_hpa = resolved.surface_pressure_hpa,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = aerosol.optical_depth,
            .single_scatter_albedo = aerosol.single_scatter_albedo,
            .asymmetry_factor = aerosol.asymmetry_factor,
            .angstrom_exponent = aerosol.angstrom_exponent,
            .reference_wavelength_nm = aerosol.reference_wavelength_nm,
            .placement = aerosol.placement,
        },
        .geometry = .{
            .model = resolved.geometry.model,
            .solar_zenith_deg = resolved.geometry.solar_zenith_deg,
            .viewing_zenith_deg = resolved.geometry.viewing_zenith_deg,
            .relative_azimuth_deg = resolved.geometry.relative_azimuth_deg,
        },
        .atmosphere = .{
            .layer_count = resolved.layer_count,
            .sublayer_divisions = resolved.sublayer_divisions,
            .surface_pressure_hpa = resolved.surface_pressure_hpa,
            .has_aerosols = true,
        },
        .spectral_grid = resolved.spectral_grid,
        .absorbers = absorber_set,
        .observation_model = .{
            .instrument = .{ .custom = resolved.observation.instrument_name },
            .regime = resolved.observation.regime,
            .sampling = resolved.observation.sampling,
            .instrument_line_fwhm_nm = resolved.observation.instrument_line_fwhm_nm,
            .builtin_line_shape = resolved.observation.builtin_line_shape,
            .integration_mode = .disamar_hr_grid,
            .adaptive_reference_grid = resolved.observation.adaptive_reference_grid,
            .operational_band_support = operational_band_support,
            .owns_operational_band_support = true,
            .measured_wavelengths_nm = resolved.observation.measured_wavelengths_nm,
        },
        .phase_function_truncation_threshold = phase_function_truncation_threshold,
    };
}

// ScalarAerosolView ------------------------------------------------------------------------------------------|
// Stack value used while reducing an O2 A aerosol specification into scalar scene controls.                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] optical_depth          : f64                                                                       |
// [ 8..15] single_scatter_albedo  : f64                                                                       |
// [16..23] asymmetry_factor       : f64                                                                       |
// [24..31] angstrom_exponent      : f64                                                                       |
// [32..39] reference_wavelength_nm: f64                                                                       |
// [40..79] placement              : IntervalPlacement                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 80 B (0.078 KiB); stack return value                                              |
const ScalarAerosolView = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    placement: AtmosphereModel.IntervalPlacement,
};
// ------------------------------------------------------------------------------------------------------------|

fn scalarAerosolView(aerosol: AerosolSpec) ScalarAerosolView {
    if (aerosol.profile.len == 1) {
        const layer = aerosol.profile[0];
        var placement = aerosol.placement;
        placement.top_pressure_hpa = layer.top_pressure_hpa;
        placement.bottom_pressure_hpa = layer.bottom_pressure_hpa;

        return .{
            .optical_depth = layer.optical_depth,
            .single_scatter_albedo = layer.single_scatter_albedo,
            .asymmetry_factor = layer.asymmetry_factor,
            .angstrom_exponent = layer.angstrom_exponent,
            .reference_wavelength_nm = layer.reference_wavelength_nm,
            .placement = placement,
        };
    }

    return .{
        .optical_depth = aerosol.optical_depth,
        .single_scatter_albedo = aerosol.single_scatter_albedo,
        .asymmetry_factor = aerosol.asymmetry_factor,
        .angstrom_exponent = aerosol.angstrom_exponent,
        .reference_wavelength_nm = aerosol.reference_wavelength_nm,
        .placement = aerosol.placement,
    };
}

fn aerosolProfileLayersForOptics(aerosol: AerosolSpec) []const AerosolModel.ProfileLayer {
    return if (aerosol.profile.len > 1) aerosol.profile else &.{};
}

fn attachResolvedIntervals(scene: *Scene, resolved: *const ResolvedVendorO2ACase) void {
    if (resolved.intervals.len != 0) {
        scene.atmosphere.interval_grid = .{
            .semantics = .explicit_pressure_bounds,
            .fit_interval_index_1based = resolved.fit_interval_index_1based,
            .intervals = resolved.intervals,
        };
    }
}

pub fn prepareResolvedVendorO2ASolveConfig(plan: PlanSpec, rtm_controls: RadiativeTransferControls) !SolveConfig {
    return transport_common.prepareSolveConfig(.{
        .derivative_mode = plan.derivativeMode(),
        .rtm_controls = rtm_controls,
    });
}

pub fn prepareResolvedVendorO2ASolveConfigFromResolved(resolved: *const ResolvedVendorO2ACase) !SolveConfig {
    return transport_common.prepareSolveConfig(.{
        .derivative_mode = resolved.plan.derivativeMode(),
        .rtm_controls = resolved.rtm_controls,
    });
}

pub fn runResolvedVendorO2AReflectanceCase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !struct {

    // runResolvedVendorO2AReflectanceCase payload ----------------------------------------------------------  |
    // Anonymous success payload returned after product simulation.                                            |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 3144 B (3.070 KiB), align: 8 B                                                                    |
    //                                                                                                         |
    // memory                                                                                                  |
    // [   0..  15] reference  : []ReferenceSample                                                             |
    // [  16.. 687] scene      : Scene                                                                         |
    // [ 688.. 767] rtm_config : SolveConfig                                                                   |
    // [ 768..2903] prepared   : PreparedOpticalState                                                          |
    // [2904..3143] product    : InstrumentGridProduct                                                         |
    //                                                                                                         |
    // out-of-line                                                                                             |
    //   reference is an owned slice. scene, prepared, and product carry nested owned storage.                 |
    //                                                                                                         |
    // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                  |
    // footprint: per successful return payload = 3144 B plus referenced runtime storage                       |
    reference: []ReferenceSample,
    scene: Scene,
    rtm_config: SolveConfig,
    prepared: OpticsPrepare.PreparedOpticalState,
    product: InstrumentGrid.InstrumentGridProduct,
} {
    // runResolvedVendorO2AReflectanceCase ------------------------------------------------------------------- |
    // One-shot validation/plotting route: prepare the complete runtime case, run the instrument-grid product, |
    // and return all owners needed by metrics.zig and callers that inspect both reference and simulated rows. |
    //                                                                                                         |
    // ownership                                                                                               |
    //   On success ownership moves from PreparedRuntimeCase into the anonymous payload. On error the local    |
    //   errdefer path releases prepared optical state, Scene storage, reference slice, and product storage.   |
    // --------------------------------------------------------------------------------------------------------|

    var prepared_case = try prepareResolvedVendorO2ACase(allocator, resolved);
    errdefer {
        prepared_case.prepared.deinit(allocator);
        prepared_case.scene.deinitOwned(allocator);
        allocator.free(prepared_case.reference);
    }

    var product = try InstrumentGrid.simulateProduct(
        allocator,
        &prepared_case.scene,
        prepared_case.rtm_config,
        &prepared_case.prepared,
    );
    errdefer product.deinit(allocator);

    return .{
        .reference = prepared_case.reference,
        .scene = prepared_case.scene,
        .rtm_config = prepared_case.rtm_config,
        .prepared = prepared_case.prepared,
        .product = product,
    };
}

pub fn prepareResolvedVendorO2ACase(
    allocator: Allocator,
    resolved: *const ResolvedVendorO2ACase,
) !PreparedRuntimeCase {
    // prepareResolvedVendorO2ACase -------------------------------------------------------------------------- |
    // Full one-shot preparation route before product simulation. This path is used by metrics wrappers and    |
    // validation tests when they need the same runtime shape as a complete O2 A reflectance run.              |
    //                                                                                                         |
    // route                                                                                                   |
    //   load inputs -> build Scene -> prepare optical state -> install weak-cutoff support -> rewindow solar  |
    //   support -> prepare RTM solve config                                                                   |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   Trace zones surround each setup stage so retained benchmark traces can tell file loading, scene       |
    //   translation, optical preparation, cutoff-grid setup, solar rewindowing, and RTM config apart.         |
    // --------------------------------------------------------------------------------------------------------|

    var inputs = inputs: {

        // instrumentation: trace zone: prepare.load_inputs -------------------------------------------------- |
        // captures: O2 A reference input loading wall time                                                    |
        // why: keep file/data preparation separate from model setup in trace runs.                            |
        const zone = Trace.staticZone(@src(), "prepare.load_inputs");
        defer zone.end();
        // end instrumentation: trace zone: prepare.load_inputs ---------------------------------------------- |

        break :inputs try loadResolvedVendorO2AInputs(allocator, resolved);
    };
    defer inputs.deinit(allocator);

    var scene = scene: {

        // instrumentation: trace zone: prepare.build_scene -------------------------------------------------- |
        // captures: typed scene construction wall time                                                        |
        // why: separate input translation from optical-state preparation.                                     |
        const zone = Trace.staticZone(@src(), "prepare.build_scene");
        defer zone.end();
        // end instrumentation: trace zone: prepare.build_scene ---------------------------------------------- |

        break :scene try buildResolvedVendorO2AScene(allocator, resolved, inputs.raw_solar_spectrum);
    };
    errdefer scene.deinitOwned(allocator);

    const reference = inputs.reference;
    inputs.reference = inputs.reference[0..0];
    errdefer allocator.free(reference);

    var collision_induced_absorption: ?*const ReferenceDataModel.CollisionInducedAbsorptionTable = null;
    if (inputs.cia_table) |*table| {
        collision_induced_absorption = table;
    }

    var prepared = prepared: {

        // instrumentation: trace zone: prepare.optical ------------------------------------------------------ |
        // captures: optical-state preparation wall time                                                       |
        // why: expose setup cost before any instrument-grid simulation.                                       |
        const zone = Trace.staticZone(@src(), "prepare.optical");
        defer zone.end();
        // end instrumentation: trace zone: prepare.optical -------------------------------------------------- |

        break :prepared try OpticsPrepare.prepare(allocator, &scene, .{
            .profile = &inputs.profile,
            .spectroscopy_profile = &inputs.spectroscopy_profile,
            .cross_sections = &inputs.cross_sections,
            .collision_induced_absorption = collision_induced_absorption,
            .spectroscopy_lines = &inputs.line_list,
            .lut = &inputs.lut,
            .aerosol_profile_layers = aerosolProfileLayersForOptics(resolved.aerosol),
        });
    };
    errdefer prepared.deinit(allocator);

    {

        // instrumentation: trace zone: prepare.weak_cutoff_grid --------------------------------------------- |
        // captures: weak-line cutoff support-grid installation                                                |
        // why: isolate retained spectroscopy pruning setup from core optical preparation.                     |
        const zone = Trace.staticZone(@src(), "prepare.weak_cutoff_grid");
        defer zone.end();
        // end instrumentation: trace zone: prepare.weak_cutoff_grid ----------------------------------------- |

        try installVendorWeakCutoffGrid(allocator, &scene, &prepared, null);
    }

    {

        // instrumentation: trace zone: prepare.solar_rewindow ----------------------------------------------- |
        // captures: solar support rewindowing wall time                                                       |
        // why: separate instrument-kernel alignment from RTM setup.                                           |
        const zone = Trace.staticZone(@src(), "prepare.solar_rewindow");
        defer zone.end();
        // end instrumentation: trace zone: prepare.solar_rewindow ------------------------------------------- |

        try rewindowParitySolarSupportToMeasurementKernel(allocator, &scene, &prepared);
    }

    const rtm_config = rtm_config: {

        // instrumentation: trace zone: prepare.rtm_config --------------------------------------------------- |
        // captures: RTM solve-config preparation wall time                                                    |
        // why: show control setup independently from optical data construction.                               |
        const zone = Trace.staticZone(@src(), "prepare.rtm_config");
        defer zone.end();
        // end instrumentation: trace zone: prepare.rtm_config ----------------------------------------------- |

        break :rtm_config try prepareResolvedVendorO2ASolveConfig(resolved.plan, resolved.rtm_controls);
    };

    return .{
        .reference = reference,
        .scene = scene,
        .rtm_config = rtm_config,
        .prepared = prepared,
    };
}

pub fn prepareResolvedVendorO2AOpticalStateWithSceneSessionCaches(
    allocator: Allocator,
    scene: *Scene,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: *WeakCutoffGridCache,
    solar_rewindowed: *bool,
    borrowed_profile_preparation: ?*const OpticsPrepare.BorrowedProfilePreparation,
) !OpticsPrepare.PreparedOpticalState {
    // prepareResolvedVendorO2AOpticalStateWithSceneSessionCaches -------------------------------------------  |
    // Retrieval-session optical refresh. The caller owns one mutable Scene and one LoadedVendorO2AInputs      |
    // bundle for the whole inverse problem, so this route can borrow static continuum/CIA rows and optional   |
    // profile-preparation arrays while rebuilding the state-dependent optical layers.                         |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Reused: loaded inputs, weak-cutoff support, solar rewindowing, and optional profile arrays/line       |
    //   states. Rebuilt: optical layers and spectroscopy rows that depend on the current pressure/aerosol     |
    //   state.                                                                                                |
    // --------------------------------------------------------------------------------------------------------|

    // Retrieval sessions own loaded inputs for the full OE run, so each optical
    // refresh borrows immutable continuum/CIA tables with no per-refresh clone.
    return prepareResolvedVendorO2AOpticalStateWithSceneInternalProfile(
        allocator,
        scene,
        inputs,
        weak_cutoff_grid,
        solar_rewindowed,
        borrowed_profile_preparation,
        .borrow_input_tables,
        &.{},
    );
}

const StaticInputTableMode = enum {
    clone_input_tables,
    borrow_input_tables,
};

fn prepareResolvedVendorO2AOpticalStateWithSceneInternalProfile(
    allocator: Allocator,
    scene: *Scene,
    inputs: *const LoadedVendorO2AInputs,
    weak_cutoff_grid: ?*WeakCutoffGridCache,
    solar_rewindowed: *bool,
    borrowed_profile_preparation: ?*const OpticsPrepare.BorrowedProfilePreparation,
    static_input_table_mode: StaticInputTableMode,
    aerosol_profile_layers: []const AerosolModel.ProfileLayer,
) !OpticsPrepare.PreparedOpticalState {
    // prepareResolvedVendorO2AOpticalStateWithSceneInternalProfile -----------------------------------------  |
    // Common optical-state builder behind retrieval-session optical refreshes. It adapts                      |
    // LoadedVendorO2AInputs into OpticsPrepare.PreparationInputs, then applies the O2 A-only cutoff-grid and  |
    // solar-window fixes that need the prepared instrument/grid shape.                                        |
    //                                                                                                         |
    // ownership                                                                                               |
    //   clone_input_tables makes PreparedOpticalState independent of LoadedVendorO2AInputs.                   |
    //   borrow_input_tables is used only while the retrieval session keeps LoadedVendorO2AInputs alive.       |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   prepare.optical measures OpticsPrepare.prepare. prepare.weak_cutoff_grid and prepare.solar_rewindow   |
    //   isolate setup that depends on realized instrument support after raw input parsing has finished.       |
    // --------------------------------------------------------------------------------------------------------|

    var collision_induced_absorption: ?*const ReferenceDataModel.CollisionInducedAbsorptionTable = null;
    if (inputs.cia_table) |*table| {
        collision_induced_absorption = table;
    }

    var prepared = prepared: {

        // instrumentation: trace zone: prepare.optical ------------------------------------------------------ |
        // captures: optical-state preparation wall time                                                       |
        // why: show setup cost when inputs are reused across retrieval iterations.                            |
        const zone = Trace.staticZone(@src(), "prepare.optical");
        defer zone.end();
        // end instrumentation: trace zone: prepare.optical -------------------------------------------------- |

        break :prepared try OpticsPrepare.prepare(allocator, scene, .{
            .profile = &inputs.profile,
            .spectroscopy_profile = &inputs.spectroscopy_profile,
            .cross_sections = &inputs.cross_sections,
            .collision_induced_absorption = collision_induced_absorption,
            .spectroscopy_lines = &inputs.line_list,
            .lut = &inputs.lut,
            .borrowed_profile_preparation = borrowed_profile_preparation,
            .aerosol_profile_layers = aerosol_profile_layers,
            .borrow_continuum_points = static_input_table_mode == .borrow_input_tables,
            .borrow_collision_induced_absorption = static_input_table_mode == .borrow_input_tables,
        });
    };
    errdefer prepared.deinit(allocator);

    {

        // instrumentation: trace zone: prepare.weak_cutoff_grid --------------------------------------------- |
        // captures: weak-line cutoff support-grid installation                                                |
        // why: distinguish cached cutoff-grid reuse from optical-layer rebuilds.                              |
        const zone = Trace.staticZone(@src(), "prepare.weak_cutoff_grid");
        defer zone.end();
        // end instrumentation: trace zone: prepare.weak_cutoff_grid ----------------------------------------- |

        try installVendorWeakCutoffGrid(allocator, scene, &prepared, weak_cutoff_grid);
    }

    if (!solar_rewindowed.*) {

        // instrumentation: trace zone: prepare.solar_rewindow ----------------------------------------------- |
        // captures: one-time solar support rewindowing wall time                                              |
        // why: verify retrieval sessions reuse this instrument-grid setup.                                    |
        const zone = Trace.staticZone(@src(), "prepare.solar_rewindow");
        defer zone.end();
        // end instrumentation: trace zone: prepare.solar_rewindow ------------------------------------------- |

        try rewindowParitySolarSupportToMeasurementKernel(allocator, scene, &prepared);
        solar_rewindowed.* = true;
    }

    return prepared;
}

fn installVendorWeakCutoffGrid(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *OpticsPrepare.PreparedOpticalState,
    weak_cutoff_grid: ?*WeakCutoffGridCache,
) !void {
    // installVendorWeakCutoffGrid --------------------------------------------------------------------------- |
    // Attach the realized instrument-grid support to line lists that use the vendor weak-line cutoff. The     |
    // cutoff is stored in wavenumber space, but the support is built from instrument wavelengths, so each     |
    // retained wavelength also gets a cm^-1 value.                                                            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   In retrieval sessions, weak_cutoff_grid is filled once and cloned into each refreshed prepared line   |
    //   list. Without a cache, this computes adaptive support for the current prepared state.                 |
    // --------------------------------------------------------------------------------------------------------|

    const response = scene.observation_model.resolvedChannelControls(.radiance).response;
    var has_cutoff_line_list = false;
    if (prepared.spectroscopy_lines) |line_list| {
        has_cutoff_line_list = line_list.runtime_controls.cutoff_cm1 != null;
    }
    for (prepared.line_absorbers) |line_absorber| {
        has_cutoff_line_list = has_cutoff_line_list or line_absorber.line_list.runtime_controls.cutoff_cm1 != null;
    }
    if (!has_cutoff_line_list) return;

    if (weak_cutoff_grid) |grid| {
        if (grid.valid()) {
            try installCutoffGridOnPreparedLineLists(allocator, prepared, grid.*);
            return;
        }
    }

    const support = try adaptive_plan.buildAdaptiveSupportWavelengths(
        allocator,
        scene,
        prepared,
        response,
    ) orelse {
        return error.DisamarKernelRealizationFailed;
    };
    defer allocator.free(support);
    if (support.len < 2) return error.DisamarKernelRealizationFailed;

    if (weak_cutoff_grid) |grid| {
        try grid.replaceFromSupport(allocator, support);
        try installCutoffGridOnPreparedLineLists(allocator, prepared, grid.*);
        return;
    }

    if (prepared.spectroscopy_lines) |*line_list| {
        try installCutoffGridOnLineList(allocator, line_list, support);
    }
    for (prepared.line_absorbers) |*line_absorber| {
        try installCutoffGridOnLineList(allocator, &line_absorber.line_list, support);
    }
}

fn installCutoffGridOnPreparedLineLists(
    allocator: Allocator,
    prepared: *OpticsPrepare.PreparedOpticalState,
    grid: WeakCutoffGridCache,
) !void {
    if (!grid.valid()) return error.DisamarKernelRealizationFailed;
    if (prepared.spectroscopy_lines) |*line_list| {
        try installCutoffGridOnLineListFromGrid(allocator, line_list, grid);
    }
    for (prepared.line_absorbers) |*line_absorber| {
        try installCutoffGridOnLineListFromGrid(allocator, &line_absorber.line_list, grid);
    }
}

fn installCutoffGridOnLineList(
    allocator: Allocator,
    line_list: *ReferenceDataModel.SpectroscopyLineList,
    support_wavelengths_nm: []const f64,
) !void {
    if (line_list.runtime_controls.cutoff_cm1 == null) return;
    const owned_support = try allocator.dupe(f64, support_wavelengths_nm);
    errdefer allocator.free(owned_support);
    const owned_support_wavenumbers = try allocator.alloc(f64, support_wavelengths_nm.len);
    errdefer allocator.free(owned_support_wavenumbers);
    for (support_wavelengths_nm, owned_support_wavenumbers) |wavelength_nm, *wavenumber_cm1| {
        wavenumber_cm1.* = 1.0e7 / @max(wavelength_nm, 1.0e-9);
    }
    if (line_list.runtime_controls.cutoff_grid_wavelengths_nm.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavelengths_nm);
    }
    if (line_list.runtime_controls.cutoff_grid_wavenumbers_cm1.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavenumbers_cm1);
    }
    line_list.runtime_controls.cutoff_grid_wavelengths_nm = owned_support;
    line_list.runtime_controls.cutoff_grid_wavenumbers_cm1 = owned_support_wavenumbers;
}

fn installCutoffGridOnLineListFromGrid(
    allocator: Allocator,
    line_list: *ReferenceDataModel.SpectroscopyLineList,
    grid: WeakCutoffGridCache,
) !void {
    if (line_list.runtime_controls.cutoff_cm1 == null) return;
    const owned_support = try allocator.dupe(f64, grid.wavelengths_nm);
    errdefer allocator.free(owned_support);
    const owned_support_wavenumbers = try allocator.dupe(f64, grid.wavenumbers_cm1);
    errdefer allocator.free(owned_support_wavenumbers);
    if (line_list.runtime_controls.cutoff_grid_wavelengths_nm.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavelengths_nm);
    }
    if (line_list.runtime_controls.cutoff_grid_wavenumbers_cm1.len != 0) {
        allocator.free(line_list.runtime_controls.cutoff_grid_wavenumbers_cm1);
    }
    line_list.runtime_controls.cutoff_grid_wavelengths_nm = owned_support;
    line_list.runtime_controls.cutoff_grid_wavenumbers_cm1 = owned_support_wavenumbers;
}

fn rewindowParitySolarSupportToMeasurementKernel(
    allocator: Allocator,
    scene: *Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
) !void {
    // rewindowParitySolarSupportToMeasurementKernel --------------------------------------------------------  |
    // Trim the Scene-owned solar spectrum to the support range shared by radiance and irradiance integration  |
    // kernels. The earlier retainSolarSupport keeps a broad margin around the spectral grid; this pass uses   |
    // the realized instrument kernels so product simulation does not carry unused solar rows.                 |
    //                                                                                                         |
    // ownership                                                                                               |
    //   Replaces operational_solar_spectrum in place. The old Scene-owned arrays are freed only after the     |
    //   retained replacement arrays have been allocated and filled.                                           |
    // --------------------------------------------------------------------------------------------------------|

    const operational_band_support = primaryOperationalBandSupportOwned(scene);
    if (!operational_band_support.operational_solar_spectrum.enabled()) return;

    const support = try sharedParityMeasurementSupport(scene, prepared) orelse return;
    const support_start_nm = support.start_nm;
    const support_end_nm = support.end_nm;
    if (!(support_end_nm > support_start_nm)) return;

    const current = operational_band_support.operational_solar_spectrum;
    var retained_count: usize = 0;
    for (current.wavelengths_nm) |wavelength_nm| {
        if (wavelength_nm < support_start_nm) continue;
        if (wavelength_nm > support_end_nm) continue;
        retained_count += 1;
    }
    if (retained_count < 3) return error.InvalidData;

    const retained_wavelengths_nm = try allocator.alloc(f64, retained_count);
    var retained_wavelengths_owned = true;
    errdefer if (retained_wavelengths_owned) allocator.free(retained_wavelengths_nm);
    const retained_irradiance = try allocator.alloc(f64, retained_count);
    var retained_irradiance_owned = true;
    errdefer if (retained_irradiance_owned) allocator.free(retained_irradiance);

    var retained_index: usize = 0;
    for (current.wavelengths_nm, current.irradiance) |wavelength_nm, irradiance| {
        if (wavelength_nm < support_start_nm) continue;
        if (wavelength_nm > support_end_nm) continue;
        retained_wavelengths_nm[retained_index] = wavelength_nm;
        retained_irradiance[retained_index] = irradiance;
        retained_index += 1;
    }

    operational_band_support.operational_solar_spectrum.deinitOwned(allocator);
    operational_band_support.operational_solar_spectrum = .{
        .wavelengths_nm = retained_wavelengths_nm,
        .irradiance = retained_irradiance,
    };
    retained_wavelengths_owned = false;
    retained_irradiance_owned = false;
    try operational_band_support.operational_solar_spectrum.prepareInterpolation(allocator);
}

fn primaryOperationalBandSupportOwned(scene: *Scene) *Instrument.OperationalBandSupport {
    std.debug.assert(scene.observation_model.owns_operational_band_support);
    std.debug.assert(scene.observation_model.operational_band_support.len > 0);
    return @constCast(&scene.observation_model.operational_band_support[0]);
}

fn sharedParityMeasurementSupport(
    scene: *const Scene,
    prepared: *const OpticsPrepare.PreparedOpticalState,
) !?struct { start_nm: f64, end_nm: f64 } {

    // sharedParityMeasurementSupport payload ---------------------------------------------------------------  |
    // Optional wavelength support bounds shared by radiance and irradiance kernels.                           |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 16 B (0.016 KiB), align: 8 B                                                                      |
    //                                                                                                         |
    // memory                                                                                                  |
    // [0.. 7] start_nm : f64                                                                                  |
    // [8..15] end_nm   : f64                                                                                  |
    //                                                                                                         |
    // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                  |
    // footprint: per present optional payload = 16 B                                                          |
    var radiance_start: instrument_types.IntegrationKernel = undefined;
    var radiance_end: instrument_types.IntegrationKernel = undefined;
    var irradiance_start: instrument_types.IntegrationKernel = undefined;
    var irradiance_end: instrument_types.IntegrationKernel = undefined;

    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.start_nm,
        &radiance_start,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .radiance,
        scene.spectral_grid.end_nm,
        &radiance_end,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .irradiance,
        scene.spectral_grid.start_nm,
        &irradiance_start,
    );
    try @import("../../forward_model/implementations/instrument/integration.zig").integrationForWavelengthChecked(
        scene,
        prepared,
        .irradiance,
        scene.spectral_grid.end_nm,
        &irradiance_end,
    );

    if (!radiance_start.enabled or !radiance_end.enabled or
        !irradiance_start.enabled or !irradiance_end.enabled or
        radiance_start.sample_count == 0 or radiance_end.sample_count == 0 or
        irradiance_start.sample_count == 0 or irradiance_end.sample_count == 0)
    {
        return null;
    }

    try expectParityKernelBoundsMatch(radiance_start, irradiance_start);
    try expectParityKernelBoundsMatch(radiance_end, irradiance_end);

    return .{
        .start_nm = scene.spectral_grid.start_nm + radiance_start.offsets_nm[0],
        .end_nm = scene.spectral_grid.end_nm + radiance_end.offsets_nm[radiance_end.sample_count - 1],
    };
}

fn expectParityKernelBoundsMatch(
    lhs: instrument_types.IntegrationKernel,
    rhs: instrument_types.IntegrationKernel,
) !void {
    const matching_sample_count = lhs.sample_count == rhs.sample_count;
    if (!matching_sample_count) return error.InvalidRequest;

    const matching_start = @abs(lhs.offsets_nm[0] - rhs.offsets_nm[0]) <= 1.0e-12;
    if (!matching_start) return error.InvalidRequest;

    const lhs_end_offset = lhs.offsets_nm[lhs.sample_count - 1];
    const rhs_end_offset = rhs.offsets_nm[rhs.sample_count - 1];
    const matching_end = @abs(lhs_end_offset - rhs_end_offset) <= 1.0e-12;
    if (!matching_end) return error.InvalidRequest;
}

pub fn loadResolvedVendorO2ALineList(
    allocator: Allocator,
    spec: LineGasSpec,
) !ReferenceDataModel.SpectroscopyLineList {
    // loadResolvedVendorO2ALineList ------------------------------------------------------------------------- |
    // Load the O2 HITRAN line list and the LISA strong-line/relaxation sidecars, then attach the sidecars to  |
    // the runtime spectroscopy line list. The fixed cache key includes all line-gas controls that change the  |
    // prepared line-list shape.                                                                               |
    //                                                                                                         |
    // ownership                                                                                               |
    //   Returns a caller-owned SpectroscopyLineList. The cache stores and returns clones, so callers always   |
    //   release the returned line list through normal deinit.                                                 |
    // --------------------------------------------------------------------------------------------------------|

    if (try fixed_asset_cache.loadLineList(allocator, spec)) |cached| {
        return cached;
    }

    var asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_line_list,
        spec.line_list_asset.id,
        spec.line_list_asset.path,
        spec.line_list_asset.format,
    );
    defer asset.deinit(allocator);

    var line_list = try asset.toSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    var strong_lines_asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_strong_line_set,
        spec.strong_lines_asset.id,
        spec.strong_lines_asset.path,
        spec.strong_lines_asset.format,
    );
    defer strong_lines_asset.deinit(allocator);

    var strong_lines = try strong_lines_asset.toSpectroscopyStrongLineSet(allocator);
    defer strong_lines.deinit(allocator);

    var relaxation_asset = try reference_assets.loadExternalAsset(
        allocator,
        .spectroscopy_relaxation_matrix,
        spec.line_mixing_asset.id,
        spec.line_mixing_asset.path,
        spec.line_mixing_asset.format,
    );
    defer relaxation_asset.deinit(allocator);

    var relaxation_matrix = try relaxation_asset.toSpectroscopyRelaxationMatrix(allocator);
    defer relaxation_matrix.deinit(allocator);

    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    try fixed_asset_cache.storeLineList(spec, line_list);
    return line_list;
}
