const std = @import("std");
const AbsorberModel = @import("../../model/Absorber.zig");
const AtmosphereModel = @import("../../model/Atmosphere.zig");
const InstrumentModel = @import("../../model/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const ObservationModel = @import("../../model/ObservationModel.zig");
const ReferenceDataModel = @import("../../model/ReferenceData.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Spectrum.zig").SpectralGrid;
const transport_common = @import("../../kernels/transport/common.zig");

const Allocator = std.mem.Allocator;
const BuiltinLineShapeKind = InstrumentModel.BuiltinLineShapeKind;
pub const AbsorberSpecies = AbsorberModel.AbsorberSpecies;
pub const Route = transport_common.Route;
pub const RtmControls = transport_common.RtmControls;

pub const PreparationPhaseProfile = struct {
    input_loading_ns: u64,
    scene_assembly_ns: u64,
    optics_preparation_ns: u64,
    plan_preparation_ns: u64,
};

pub const ReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    reflectance: f64,
};

pub const ExternalAsset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
};

pub const OutputKind = enum {
    summary_json,
    generated_spectrum_csv,
};

pub const OutputRequest = struct {
    kind: OutputKind,
    path: []const u8,
};

pub const ValidationPolicy = struct {
    strict_unknown_fields: bool,
    require_resolved_assets: bool,
    require_resolved_stage_references: bool,
};

pub const PlanSpec = struct {
    model_family: []const u8,
    transport_solver: []const u8,
    execution_solver_mode: []const u8,
    execution_derivative_mode: []const u8,
};

pub const Metadata = struct {
    id: []const u8,
    workspace: []const u8,
    description: []const u8,
};

pub const GeometrySpec = struct {
    model: @TypeOf(@as(Scene, .{}).geometry.model),
    solar_zenith_deg: f64,
    viewing_zenith_deg: f64,
    relative_azimuth_deg: f64,
};

pub const AerosolSpec = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    layer_center_km: f64,
    layer_width_km: f64,
    placement: AtmosphereModel.IntervalPlacement,
};

pub const ObservationSpec = struct {
    instrument_name: []const u8,
    regime: ObservationModel.ObservationRegime,
    sampling: Instrument.SamplingMode,
    noise_model: Instrument.NoiseModelKind,
    instrument_line_fwhm_nm: f64,
    builtin_line_shape: BuiltinLineShapeKind,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_reference_grid: InstrumentModel.AdaptiveReferenceGrid,
    solar_reference_asset_id: []const u8,
};

pub const LineGasSpec = struct {
    line_list_asset: ExternalAsset,
    line_mixing_asset: ExternalAsset,
    strong_lines_asset: ExternalAsset,
    line_mixing_factor: ?f64,
    isotopes_sim: []const u8,
    threshold_line_sim: ?f64,
    cutoff_sim_cm1: ?f64,
};

pub const CiaSpec = struct {
    enabled: bool,
    cia_asset: ?ExternalAsset,
};

pub const InputsSpec = struct {
    atmosphere_profile: ExternalAsset,
    vendor_reference_csv: ExternalAsset,
    raw_solar_reference: ExternalAsset,
    airmass_factor_lut: ExternalAsset,
};

pub const SolarSpectrumSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
};

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
    rtm_controls: RtmControls,
    outputs: []const OutputRequest,
    validation: ValidationPolicy,
};

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
