const std = @import("std");
const AbsorberModel = @import("../../input/Absorber.zig");
const AerosolModel = @import("../../input/Aerosol.zig");
const AtmosphereModel = @import("../../input/Atmosphere.zig");
const InstrumentModel = @import("../../input/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const ObservationModel = @import("../../input/ObservationModel.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const transport_common = @import("../../forward_model/radiative_transfer/root.zig");

const Allocator = std.mem.Allocator;
const BuiltinLineShapeKind = InstrumentModel.BuiltinLineShapeKind;
pub const AbsorberSpecies = AbsorberModel.AbsorberSpecies;
pub const SolveConfig = transport_common.SolveConfig;
pub const RadiativeTransferPerformanceThresholds = transport_common.RadiativeTransferPerformanceThresholds;
pub const RadiativeTransferControls = transport_common.RadiativeTransferControls;

// layout(64-bit):
//   size: 24 B, align: 8 B
//   field storage: wavelength_nm=8 B, irradiance=8 B, reflectance=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 24 B (0.023 KiB); total = per instance * live instance count
pub const ReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    reflectance: f64,
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: id=16 B, path=16 B, format=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, path, format carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const ExternalAsset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
};

// layout(64-bit):
//   size: 1 B, align: 1 B
//   field storage: derivative_mode=1 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 1 B (0.001 KiB); total = per instance * live instance count
pub const PlanSpec = struct {
    derivative_mode: transport_common.DerivativeMode = .none,

    pub fn validate(self: PlanSpec) !void {
        _ = self.derivativeMode();
    }

    pub fn derivativeMode(self: PlanSpec) transport_common.DerivativeMode {
        return self.derivative_mode;
    }
};

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: id=16 B, storage=16 B, description=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, storage, description carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const Metadata = struct {
    id: []const u8,
    storage: []const u8,
    description: []const u8,
};

// layout(64-bit):
//   size: 32 B, align: 8 B
// field storage: solar_zenith_deg=8 B, viewing_zenith_deg=8 B, relative_azimuth_deg=8 B, model=1 B; padding: 7 B (56
// bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count
pub const GeometrySpec = struct {
    model: @TypeOf(@as(Scene, .{}).geometry.model),
    solar_zenith_deg: f64,
    viewing_zenith_deg: f64,
    relative_azimuth_deg: f64,
};

// layout(64-bit):
//   size: 80 B, align: 8 B
// field storage: 80 B across 6 fields; largest: placement=40 B, optical_depth=8 B, single_scatter_albedo=8 B; padding:
// 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
pub const AerosolSpec = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    placement: AtmosphereModel.IntervalPlacement,
    profile: []const AerosolModel.ProfileLayer = &.{},
};

// layout(64-bit):
//   size: 88 B, align: 8 B
// field storage: 81 B across 10 fields; largest: instrument_name=16 B, measured_wavelengths_nm=16 B; padding: 7 B (56
// bits)
//   unused bits: 56 padding + 0 bool-storage slack = 56 bits
// out-of-line: instrument_name, solar_reference_asset_id, measured_wavelengths_nm carry references/descriptors;
// referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 88 B (0.086 KiB); total also includes referenced storage above
pub const ObservationSpec = struct {
    instrument_name: []const u8,
    regime: ObservationModel.ObservationRegime = .nadir,
    sampling: Instrument.SamplingMode,
    instrument_line_fwhm_nm: f64,
    builtin_line_shape: BuiltinLineShapeKind,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_reference_grid: InstrumentModel.AdaptiveReferenceGrid,
    solar_reference_asset_id: []const u8,
    measured_wavelengths_nm: []const f64 = &.{},
};

// layout(64-bit):
//   size: 208 B, align: 8 B
// field storage: 208 B across 7 fields; largest: line_list_asset=48 B, line_mixing_asset=48 B, strong_lines_asset=48 B;
// padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: isotopes_sim carry references/descriptors; referenced storage is not included in size
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 208 B (0.203 KiB); total also includes referenced storage above
pub const LineGasSpec = struct {
    line_list_asset: ExternalAsset,
    line_mixing_asset: ExternalAsset,
    strong_lines_asset: ExternalAsset,
    line_mixing_factor: ?f64,
    isotopes_sim: []const u8,
    threshold_line_sim: ?f64,
    cutoff_sim_cm1: ?f64,
};

// layout(64-bit):
//   size: 64 B, align: 8 B
//   field storage: cia_asset=56 B, enabled=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   cache span: 1 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 64 B (0.062 KiB); total = per instance * live instance count
pub const CiaSpec = struct {
    enabled: bool,
    cia_asset: ?ExternalAsset,
};

// layout(64-bit):
//   size: 192 B, align: 8 B
// field storage: atmosphere_profile=48 B, vendor_reference_csv=48 B, raw_solar_reference=48 B, airmass_factor_lut=48 B;
// padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 3 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 192 B (0.188 KiB); total = per instance * live instance count
pub const InputsSpec = struct {
    atmosphere_profile: ExternalAsset,
    vendor_reference_csv: ExternalAsset,
    raw_solar_reference: ExternalAsset,
    airmass_factor_lut: ExternalAsset,
};

// layout(64-bit):
//   size: 16 B, align: 8 B
//   field storage: wavelength_nm=8 B, irradiance=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 16 B (0.016 KiB); total = per instance * live instance count
pub const SolarSpectrumSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
};

// layout(64-bit):
//   size: 912 B, align: 8 B
//   field storage: 908 B across 19 fields; largest: o2=208 B, inputs=192 B, aerosol=80 B; padding: 4 B (32 bits)
//   unused bits: 32 padding + 0 bool-storage slack = 32 bits
//   out-of-line: scene_id and intervals carry references/descriptors; referenced storage is not included in size
//   cache span: 15 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 912 B (0.891 KiB); total also includes referenced storage above
pub const ResolvedVendorO2ACase = struct {
    metadata: Metadata,
    plan: PlanSpec,
    inputs: InputsSpec,
    scene_id: []const u8,
    spectral_grid: SpectralGrid,
    layer_count: u32,
    sublayer_divisions: u8,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: u32,
    intervals: []const AtmosphereModel.VerticalInterval,
    surface_albedo: f64,
    geometry: GeometrySpec,
    aerosol: AerosolSpec,
    observation: ObservationSpec,
    o2: LineGasSpec,
    o2o2: CiaSpec,
    rtm_controls: RadiativeTransferControls,
};

// layout(64-bit):
//   size: 336 B, align: 8 B
//   field storage: 336 B across 8 fields; largest: line_list=208 B, cia_table=32 B, profile=16 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: reference, raw_solar_spectrum carry references/descriptors; referenced storage is not included in size
//   cache span: 6 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 336 B (0.328 KiB); total also includes referenced storage above
pub const LoadedVendorO2AInputs = struct {
    profile: ReferenceDataModel.ClimatologyProfile,
    spectroscopy_profile: ReferenceDataModel.ClimatologyProfile,
    cross_sections: ReferenceDataModel.CrossSectionTable,
    line_list: ReferenceDataModel.SpectroscopyLineList,
    cia_table: ?ReferenceDataModel.CollisionInducedAbsorptionTable,
    lut: ReferenceDataModel.AirmassFactorLut,
    reference: []ReferenceSample,
    raw_solar_spectrum: []SolarSpectrumSample,

    pub fn deinit(self: *LoadedVendorO2AInputs, allocator: Allocator) void {
        self.profile.deinit(allocator);
        self.spectroscopy_profile.deinit(allocator);
        self.cross_sections.deinit(allocator);
        self.line_list.deinit(allocator);
        if (self.cia_table) |*table| table.deinit(allocator);
        self.lut.deinit(allocator);
        if (self.reference.len != 0) allocator.free(self.reference);
        if (self.raw_solar_spectrum.len != 0) allocator.free(self.raw_solar_spectrum);
        self.* = undefined;
    }
};
