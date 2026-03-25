//! Purpose:
//!   Decode canonical YAML documents into typed plan, scene, and execution
//!   records.
//!
//! Physics:
//!   The document adapter maps vendor-style configuration into typed runtime
//!   controls without changing the underlying radiative-transfer semantics.
//!
//! Vendor:
//!   Canonical document resolution and typed vendor-config mapping.
//!
//! Design:
//!   Keep parsing, validation, and resolution in one module so the adapter can
//!   preserve provenance and source-path ownership through the entire import
//!   pipeline.
//!
//! Invariants:
//!   Canonical documents must preserve source ownership, and resolved stages
//!   must stay consistent with their plan templates and scene blueprints.
//!
//! Validation:
//!   Canonical config tests cover document parsing, path resolution, and
//!   stage compilation.

const std = @import("std");
const yaml = @import("yaml.zig");
const fields = @import("document_fields.zig");
const yaml_helpers = @import("document_yaml_helpers.zig");
const PlanTemplate = @import("../../core/Plan.zig").Template;
const SolverMode = @import("../../core/Plan.zig").SolverMode;
const DiagnosticsSpec = @import("../../core/diagnostics.zig").DiagnosticsSpec;
const AbsorberModel = @import("../../model/Absorber.zig");
const Binding = @import("../../model/Binding.zig").Binding;
const BindingKind = @import("../../model/Binding.zig").BindingKind;
const SpectralGrid = @import("../../model/Spectrum.zig").SpectralGrid;
const SpectralWindow = @import("../../model/Bands.zig").SpectralWindow;
const SpectralBand = @import("../../model/Bands.zig").SpectralBand;
const SpectralBandSet = @import("../../model/Bands.zig").SpectralBandSet;
const AtmosphereModel = @import("../../model/Atmosphere.zig");
const Atmosphere = @import("../../model/Atmosphere.zig").Atmosphere;
const Geometry = @import("../../model/Geometry.zig").Geometry;
const GeometryModel = @import("../../model/Geometry.zig").Model;
const Absorber = @import("../../model/Absorber.zig").Absorber;
const AbsorberSet = @import("../../model/Absorber.zig").AbsorberSet;
const LineGasControls = @import("../../model/Absorber.zig").LineGasControls;
const Spectroscopy = @import("../../model/Absorber.zig").Spectroscopy;
const SpectroscopyStage = @import("../../model/Absorber.zig").SpectroscopyStage;
const SpectroscopyMode = @import("../../model/Absorber.zig").SpectroscopyMode;
const Surface = @import("../../model/Surface.zig").Surface;
const SurfaceParameter = @import("../../model/Surface.zig").Parameter;
const Cloud = @import("../../model/Cloud.zig").Cloud;
const Aerosol = @import("../../model/Aerosol.zig").Aerosol;
const ObservationModel = @import("../../model/ObservationModel.zig").ObservationModel;
const CrossSectionFitControls = @import("../../model/ObservationModel.zig").CrossSectionFitControls;
const ObservationRegime = @import("../../model/ObservationModel.zig").ObservationRegime;
const InstrumentId = @import("../../model/Instrument.zig").Id;
const BuiltinLineShapeKind = @import("../../model/Instrument.zig").BuiltinLineShapeKind;
const Scene = @import("../../model/Scene.zig").Scene;
const InverseProblem = @import("../../model/InverseProblem.zig").InverseProblem;
const DerivativeMode = @import("../../model/InverseProblem.zig").DerivativeMode;
const CovarianceBlock = @import("../../model/InverseProblem.zig").CovarianceBlock;
const FitControls = @import("../../model/InverseProblem.zig").FitControls;
const Convergence = @import("../../model/InverseProblem.zig").Convergence;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const MeasurementMask = @import("../../model/Measurement.zig").SpectralMask;
const MeasurementErrorModel = @import("../../model/Measurement.zig").ErrorModel;
const StateVector = @import("../../model/StateVector.zig").StateVector;
const StateParameter = @import("../../model/StateVector.zig").Parameter;
const StateTarget = @import("../../model/StateVector.zig").Target;
const StateTransform = @import("../../model/StateVector.zig").Transform;
const StatePrior = @import("../../model/StateVector.zig").Prior;
const StateBounds = @import("../../model/StateVector.zig").Bounds;
const ReferenceData = @import("../../model/ReferenceData.zig");
const reference_assets = @import("../ingest/reference_assets.zig");
const spectral_ascii = @import("../ingest/spectral_ascii.zig");
const spectral_ascii_runtime = @import("../ingest/spectral_ascii_runtime.zig");
const spectra_grid = @import("../../kernels/spectra/grid.zig");
const transport_common = @import("../../kernels/transport/common.zig");
const ExportFormat = @import("../exporters/format.zig").ExportFormat;
const Allocator = std.mem.Allocator;
const parseAssetKind = fields.parseAssetKind;
const parseIngestAdapter = fields.parseIngestAdapter;
const parseSolverMode = fields.parseSolverMode;
const parseDerivativeMode = fields.parseDerivativeMode;
const parseGeometryModel = fields.parseGeometryModel;
const parseObservationRegime = fields.parseObservationRegime;
const parseSamplingMode = fields.parseSamplingMode;
const parseNoiseModelKind = fields.parseNoiseModelKind;
const parseSpectroscopyMode = fields.parseSpectroscopyMode;
const parseSurfaceKind = fields.parseSurfaceKind;
const parseStateTransform = fields.parseStateTransform;
const parseProductKind = fields.parseProductKind;
const parseExportFormat = fields.parseExportFormat;
const normalizeTransportProvider = fields.normalizeTransportProvider;
const normalizeRetrievalProvider = fields.normalizeRetrievalProvider;
const normalizeSurfaceProvider = fields.normalizeSurfaceProvider;
const normalizeInstrumentProvider = fields.normalizeInstrumentProvider;
const resolveInputPath = yaml_helpers.resolveInputPath;
const pathExists = yaml_helpers.pathExists;
const cloneMapSkipping = yaml_helpers.cloneMapSkipping;
const ensureKnownFields = yaml_helpers.ensureKnownFields;
const containsString = yaml_helpers.containsString;
const expectMap = yaml_helpers.expectMap;
const expectSeq = yaml_helpers.expectSeq;
const expectString = yaml_helpers.expectString;
const expectBool = yaml_helpers.expectBool;
const expectI64 = yaml_helpers.expectI64;
const expectU64 = yaml_helpers.expectU64;
const expectF64 = yaml_helpers.expectF64;
const requiredField = yaml_helpers.requiredField;
const mapGet = yaml_helpers.mapGet;

pub const Error = error{
    UnknownField,
    MissingField,
    InvalidType,
    InvalidValue,
    InvalidReference,
    ReferenceCycle,
    MissingTemplate,
    MissingStage,
    MissingAsset,
    MissingIngest,
    MissingIngestOutput,
    MissingStageProduct,
    UnsupportedIngestAdapter,
    UnsupportedProvider,
    UnsupportedMultiplicity,
};

pub const Metadata = struct {
    id: []const u8 = "",
    workspace: []const u8 = "",
    description: []const u8 = "",
};

pub const AssetKind = fields.AssetKind;

pub const Asset = struct {
    name: []const u8,
    kind: AssetKind,
    format: []const u8,
    path: []const u8,
    resolved_path: []const u8,
};

pub const IngestAdapter = fields.IngestAdapter;

pub const Ingest = struct {
    name: []const u8,
    adapter: IngestAdapter,
    asset_name: []const u8,
    loaded_spectra: spectral_ascii.LoadedSpectra,
};

pub const ProductKind = fields.ProductKind;

pub const Product = struct {
    name: []const u8,
    kind: ProductKind,
    observable: ?MeasurementQuantity = null,
    apply_noise: bool = false,
};

pub const OutputSpec = struct {
    from: []const u8,
    format: ExportFormat,
    destination_uri: []const u8,
    include_provenance: bool = false,
};

pub const SyntheticRetrievalPolicy = struct {
    warn_if_models_are_identical: bool = true,
    require_explicit_acknowledgement_if_identical: bool = false,
};

pub const Validation = struct {
    strict_unknown_fields: bool = true,
    require_resolved_assets: bool = false,
    require_resolved_stage_references: bool = false,
    synthetic_retrieval: SyntheticRetrievalPolicy = .{},
};

pub const WarningKind = enum {
    identical_synthetic_models,
};

pub const Warning = struct {
    kind: WarningKind,
    message: []const u8,
};

pub const StageKind = enum {
    simulation,
    retrieval,
};

/// Vendor-compat records which vendor (DISAMAR) method controls are active.
/// Carried per-stage so simulation and retrieval can differ.
pub const VendorCompat = struct {
    /// Vendor simulation method (0=OE_LBL, 1=DISMAS)
    simulation_method: ?fields.SimulationMethod = null,
    /// Vendor retrieval method (0=OE, 1=DISMAS, 2=DOAS, 3=classic_DOAS, 4=DOMINO)
    retrieval_method: ?fields.RetrievalMethod = null,
    /// Whether this is simulation-only (no retrieval)
    simulation_only: bool = false,
    /// Whether to use adding method vs LABOS
    use_adding_sim: ?bool = null,
    use_adding_retr: ?bool = null,
};

/// Typed representation of the vendor RADIATIVE_TRANSFER section.
/// Captures spectral sampling, scattering transport, and RTM threshold controls.
pub const RadiativeTransferConfig = struct {
    // Spectral sampling (FWHM subdivision)
    num_div_points_fwhm_sim: ?u32 = null,
    num_div_points_fwhm_retr: ?u32 = null,
    // Line-absorbing sampling limits
    num_div_points_max_sim: ?u32 = null,
    num_div_points_min_sim: ?u32 = null,
    num_div_points_max_retr: ?u32 = null,
    num_div_points_min_retr: ?u32 = null,
    // Transport configuration
    scattering_mode_sim: fields.ScatteringMode = .multiple,
    scattering_mode_retr: fields.ScatteringMode = .multiple,
    stokes_dimension_sim: u8 = 1,
    stokes_dimension_retr: u8 = 1,
    nstreams_sim: u32 = 16,
    nstreams_retr: u32 = 16,
    use_adding_sim: bool = false,
    use_adding_retr: bool = false,
    fourier_floor_scalar_sim: ?f64 = null,
    fourier_floor_scalar_retr: ?f64 = null,
    num_orders_max_sim: ?u32 = null,
    num_orders_max_retr: ?u32 = null,
    threshold_trunc_phase_sim: ?f64 = null,
    threshold_trunc_phase_retr: ?f64 = null,
    use_polarization_correction: bool = false,
    // RTM convergence thresholds
    use_correction_spherical_atm: bool = false,
    threshold_cloud_fraction: ?f64 = null,
    threshold_conv_first: ?f64 = null,
    threshold_conv_mult: ?f64 = null,
    threshold_doubling: ?f64 = null,
    threshold_multiplier: ?f64 = null,
    // Per-interval altitude division points (one entry per spectral interval)
    num_div_points_alt_sim: ?[]const u32 = null,
    num_div_points_alt_retr: ?[]const u32 = null,
};

/// Per-band rotational Raman scattering / Ring-effect settings.
pub const RrsRingConfig = struct {
    pub const PerBand = struct {
        use_rrs: bool = false,
        approximate_rrs: bool = false,
        fraction_raman_lines: f64 = 1.0,
        use_cabannes: bool = false,
        degree_poly: u32 = 0,
        include_absorption: bool = false,
    };

    sim: ?[]const PerBand = null,
    retr: ?[]const PerBand = null,
};

/// Flags for optional diagnostic / supplementary output channels.
pub const AdditionalOutputConfig = struct {
    refl_hr_grid_sim: bool = false,
    refl_instr_grid_sim: bool = false,
    refl_deriv_hr_grid_sim: bool = false,
    refl_deriv_hr_grid_retr: bool = false,
    refl_deriv_instr_grid_sim: bool = false,
    refl_deriv_instr_grid_retr: bool = false,
    signal_to_noise_ratio: bool = false,
    contrib_refl_sim: bool = false,
    contrib_refl_retr: bool = false,
    alt_resolved_amf_sim: bool = false,
    alt_resolved_amf_retr: bool = false,
    absorption_xsec_sim: bool = false,
    absorption_xsec_retr: bool = false,
    ring_spectra: bool = false,
    diff_ring_spectra: bool = false,
    filling_in_spectra: bool = false,
    test_derivatives: bool = false,
    pol_correction_file: bool = false,
};

/// Typed representation of the vendor GENERAL section.
/// Only fields with exact/approximate parity status are included.
pub const GeneralConfig = struct {
    // Counts (approximate -- derived from list lengths in Zig)
    number_spectral_bands: ?u32 = null,
    number_trace_gases: ?u32 = null,
    // Mode
    simulation_only: bool = false,
    // Retrieval fitting toggles
    aerosol_layer_height: bool = false,
    fit_surface_albedo: bool = false,
    fit_aerosol_tau: bool = false,
    fit_cloud_tau: bool = false,
    fit_mul_offset: bool = false,
    fit_stray_light: bool = false,
    fit_temperature_offset: bool = false,
    fit_ln_cld_tau: bool = false,
    num_interval_fit: ?u32 = null,
    use_eff_xsec_oe_sim: bool = false,
    use_eff_xsec_oe_retr: bool = false,
    use_poly_exp_xsec_sim: bool = false,
    use_poly_exp_xsec_retr: bool = false,
    xsec_strong_abs_sim: ?[]const bool = null,
    xsec_strong_abs_retr: ?[]const bool = null,
    degree_poly_sim: ?[]const u32 = null,
    degree_poly_retr: ?[]const u32 = null,
    // Method codes
    simulation_method: ?fields.SimulationMethod = null,
    retrieval_method: ?fields.RetrievalMethod = null,
    // Reference file paths
    solar_irr_file_sim: ?[]const u8 = null,
    solar_irr_file_retr: ?[]const u8 = null,
    temperature_climatology: ?[]const u8 = null,
    ozone_climatology: ?[]const u8 = null,
};

/// Typed representation of the vendor INSTRUMENT section.
/// Wavelength range fields are per-band; slit/noise fields are scalar.
pub const InstrumentConfig = struct {
    pub const PerBand = struct {
        wavelength_start: ?f64 = null,
        wavelength_end: ?f64 = null,
        wavelength_step: ?f64 = null,
        exclude: ?[]const [2]f64 = null,
        fwhm_irradiance_sim: ?f64 = null,
        fwhm_irradiance_retr: ?f64 = null,
        fwhm_radiance_sim: ?f64 = null,
        fwhm_radiance_retr: ?f64 = null,
    };
    bands: ?[]const PerBand = null,
    add_noise_irr_sim: bool = false,
    add_noise_rad_sim: bool = false,
};

/// Typed representation of the vendor GEOMETRY section.
/// All eight angle fields have exact parity status.
pub const GeometryConfig = struct {
    solar_zenith_angle_sim: ?f64 = null,
    solar_zenith_angle_retr: ?f64 = null,
    solar_azimuth_angle_sim: ?f64 = null,
    solar_azimuth_angle_retr: ?f64 = null,
    instrument_nadir_angle_sim: ?f64 = null,
    instrument_nadir_angle_retr: ?f64 = null,
    instrument_azimuth_angle_sim: ?f64 = null,
    instrument_azimuth_angle_retr: ?f64 = null,
};

/// Typed representation of the vendor PRESSURE_TEMPERATURE section.
/// P/T profiles are pressure-value pairs, one set for sim and one for retr.
pub const PressureTemperatureConfig = struct {
    pt_sim: ?[]const [2]f64 = null,
    pt_retr: ?[]const [2]f64 = null,
};

/// Typed representation of the vendor SURFACE section.
pub const SurfaceConfig = struct {
    surf_pressure_sim: ?f64 = null,
    surf_pressure_retr: ?f64 = null,
    surface_type_sim: ?fields.SurfaceType = null,
    surface_type_retr: ?fields.SurfaceType = null,
    // Wavelength-independent albedo
    surf_albedo_sim: ?f64 = null,
    surf_albedo_retr: ?f64 = null,
    var_surf_albedo_retr: ?f64 = null,
    // Wavelength-dependent albedo (per-band arrays)
    wavel_surf_albedo_sim: ?[]const f64 = null,
    surf_albedo_array_sim: ?[]const f64 = null,
    wavel_surf_albedo_retr: ?[]const f64 = null,
    surf_albedo_array_retr: ?[]const f64 = null,
};

/// Typed representation of the vendor ATMOSPHERIC_INTERVALS section.
pub const AtmosphericIntervalsConfig = struct {
    pub const IntervalEntry = struct {
        top_pressure_hpa: f64,
        bottom_pressure_hpa: f64,
        top_altitude_km: ?f64 = null,
        bottom_altitude_km: ?f64 = null,
        top_pressure_variance_hpa2: ?f64 = null,
        bottom_pressure_variance_hpa2: ?f64 = null,
        altitude_divisions: ?u32 = null,
    };

    sim: ?[]const IntervalEntry = null,
    retr: ?[]const IntervalEntry = null,
};

/// Typed representation of the vendor CLOUD_AEROSOL_FRACTION section.
pub const CloudAerosolFractionConfig = struct {
    target_sim: ?AtmosphereModel.FractionTarget = null,
    target_retr: ?AtmosphereModel.FractionTarget = null,
    kind_sim: AtmosphereModel.FractionKind = .none,
    kind_retr: AtmosphereModel.FractionKind = .none,
    values_sim: ?[]const f64 = null,
    values_retr: ?[]const f64 = null,
    apriori_values_retr: ?[]const f64 = null,
    variance_values_retr: ?[]const f64 = null,
    wavelengths_sim_nm: ?[]const f64 = null,
    wavelengths_retr_nm: ?[]const f64 = null,
    threshold_cloud_fraction: ?f64 = null,
    threshold_variance: ?f64 = null,
};

/// Typed representation of the vendor CLOUD section.
pub const CloudConfig = struct {
    cloud_type_sim: ?fields.CloudType = null,
    cloud_type_retr: ?fields.CloudType = null,
    // HG scattering (sim)
    hg_optical_thickness_sim: ?f64 = null,
    hg_angstrom_coefficient_sim: ?f64 = null,
    hg_single_scattering_albedo_sim: ?f64 = null,
    hg_parameter_g_sim: ?f64 = null,
    // HG scattering (retr -- approximate)
    hg_optical_thickness_retr: ?f64 = null,
    // Mie scattering
    mie_optical_thickness_sim: ?f64 = null,
    mie_optical_thickness_retr: ?f64 = null,
};

/// Typed representation of the vendor AEROSOL section.
pub const AerosolConfig = struct {
    aerosol_type_sim: ?fields.AerosolType = null,
    aerosol_type_retr: ?fields.AerosolType = null,
    // HG scattering (sim)
    hg_optical_thickness_sim: ?f64 = null,
    hg_angstrom_coefficient_sim: ?f64 = null,
    hg_single_scattering_albedo_sim: ?f64 = null,
    hg_parameter_g_sim: ?f64 = null,
    // HG scattering (retr -- approximate)
    hg_optical_thickness_retr: ?f64 = null,
    // Mie scattering
    mie_optical_thickness_sim: ?f64 = null,
    mie_optical_thickness_retr: ?f64 = null,
};

/// Typed representation of the vendor SUBCOLUMNS section.
pub const SubcolumnsConfig = struct {
    pub const Entry = struct {
        label: AtmosphereModel.PartitionLabel = .unspecified,
        bottom_altitude_km: ?f64 = null,
        top_altitude_km: ?f64 = null,
        gaussian_nodes: ?[]const f64 = null,
        gaussian_weights: ?[]const f64 = null,
    };

    enabled: bool = false,
    boundary_layer_top_pressure_hpa: ?f64 = null,
    boundary_layer_top_altitude_km: ?f64 = null,
    tropopause_pressure_hpa: ?f64 = null,
    tropopause_altitude_km: ?f64 = null,
    entries: ?[]const Entry = null,
};

/// Typed representation of the vendor RETRIEVAL section.
pub const RetrievalConfig = struct {
    max_num_iterations: ?u32 = null,
    state_vector_conv_threshold: ?f64 = null,
};

/// Typed representation of per-gas controls from the vendor ABSORBING_GAS section.
pub const AbsorbingGasConfig = struct {
    pub const Hitran = struct {
        factor_lm_sim: ?f64 = null,
        factor_lm_retr: ?f64 = null,
        isotopes_sim: ?[]const u8 = null,
        isotopes_retr: ?[]const u8 = null,
        threshold_line_sim: ?f64 = null,
        threshold_line_retr: ?f64 = null,
        cutoff_sim_cm1: ?f64 = null,
        cutoff_retr_cm1: ?f64 = null,
    };

    pub const GasEntry = struct {
        species: ?fields.AbsorberSpecies = null,
        xsection_file_sim: ?[]const u8 = null,
        xsection_file_retr: ?[]const u8 = null,
        fit_column: bool = false,
        profile_sim: ?[]const [2]f64 = null,
        hitran: ?Hitran = null,
    };
    gases: ?[]const GasEntry = null,
};

pub const Stage = struct {
    kind: StageKind,
    plan: PlanTemplate,
    scene: Scene,
    inverse: ?InverseProblem = null,
    products: []const Product = &[_]Product{},
    diagnostics: DiagnosticsSpec = .{},
    // TODO(WP-01): algorithm_name should be ?fields.RetrievalMethod (maps to
    // normalizeRetrievalProvider); 5 call sites in Document.zig. Deferred to
    // avoid disrupting the resolve pipeline mid-WP.
    algorithm_name: []const u8 = "",
    // TODO(WP-01): algorithm_damping should be ?FitControls.TrustRegion
    // (already resolved in applyAlgorithmParameters); 7+ call sites in
    // Document.zig. Deferred to avoid shotgun surgery.
    algorithm_damping: []const u8 = "",
    // TODO(WP-01): spectral_response_shape should be ?BuiltinLineShapeKind
    // (validated against BuiltinLineShapeKind.parse in execution.zig); 9 call
    // sites across Document.zig and execution.zig. Deferred.
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
    // Typed vendor-section configs (optional; absent when canonical YAML omits them)
    vendor_compat: ?VendorCompat = null,
    radiative_transfer: ?RadiativeTransferConfig = null,
    rrs_ring: ?RrsRingConfig = null,
    additional_output: ?AdditionalOutputConfig = null,
    general: ?GeneralConfig = null,
    instrument: ?InstrumentConfig = null,
    geometry: ?GeometryConfig = null,
    pressure_temperature: ?PressureTemperatureConfig = null,
    surface_config: ?SurfaceConfig = null,
    atmospheric_intervals: ?AtmosphericIntervalsConfig = null,
    cloud_aerosol_fraction: ?CloudAerosolFractionConfig = null,
    cloud_config: ?CloudConfig = null,
    aerosol_config: ?AerosolConfig = null,
    subcolumns: ?SubcolumnsConfig = null,
    retrieval_config: ?RetrievalConfig = null,
    absorbing_gas: ?AbsorbingGasConfig = null,
};

pub const Document = struct {
    owner_allocator: Allocator,
    arena_state: *std.heap.ArenaAllocator,
    source_path: []const u8,
    source_dir: []const u8,
    source_bytes: []const u8,
    root: yaml.Value,

    /// Purpose:
    ///   Parse a canonical YAML document from disk and retain owned source
    ///   metadata.
    pub fn parseFile(allocator: Allocator, path: []const u8) !Document {
        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const absolute_path = try std.fs.cwd().realpathAlloc(arena, path);
        const file = try std.fs.openFileAbsolute(absolute_path, .{});
        defer file.close();

        const bytes = try file.readToEndAlloc(arena, 8 * 1024 * 1024);
        const root = try yaml.parse(arena, bytes);

        return .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = absolute_path,
            .source_dir = try arena.dupe(u8, std.fs.path.dirname(absolute_path) orelse "."),
            .source_bytes = bytes,
            .root = root,
        };
    }

    /// Purpose:
    ///   Parse a canonical YAML document from an in-memory buffer.
    pub fn parse(allocator: Allocator, source_name: []const u8, base_dir: []const u8, source_bytes: []const u8) !Document {
        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const bytes = try arena.dupe(u8, source_bytes);
        const root = try yaml.parse(arena, bytes);

        return .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = try arena.dupe(u8, source_name),
            .source_dir = try arena.dupe(u8, base_dir),
            .source_bytes = bytes,
            .root = root,
        };
    }

    /// Purpose:
    ///   Release the arena-backed document state.
    pub fn deinit(self: *Document) void {
        self.arena_state.deinit();
        self.owner_allocator.destroy(self.arena_state);
        self.* = undefined;
    }

    /// Purpose:
    ///   Resolve the parsed document into a typed experiment.
    pub fn resolve(self: *const Document, allocator: Allocator) !*ResolvedExperiment {
        const resolved = try allocator.create(ResolvedExperiment);
        errdefer allocator.destroy(resolved);

        const arena_state = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena_state);
        arena_state.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const root_map = try expectMap(self.root);
        const validation = try decodeValidation(arena, mapGet(root_map, "validation"), decodeStrictUnknownFields(root_map));
        const strict = validation.strict_unknown_fields;
        try ensureKnownFields(root_map, &.{
            "schema_version",
            "metadata",
            "inputs",
            "templates",
            "experiment",
            "outputs",
            "validation",
        }, strict);

        const schema_version = try expectI64(requiredField(root_map, "schema_version"));
        if (schema_version != 1) return Error.InvalidValue;

        const metadata = try decodeMetadata(arena, mapGet(root_map, "metadata"), strict);
        const assets = try decodeAssets(arena, self, root_map, strict);
        const ingests = try decodeIngests(arena, root_map, assets, strict);

        const experiment_value = requiredField(root_map, "experiment");
        const experiment_map = try expectMap(experiment_value);
        try ensureKnownFields(experiment_map, &.{ "simulation", "retrieval" }, strict);

        var resolution_context = ResolveContext{
            .allocator = arena,
            .document = self,
            .root = root_map,
            .validation = validation,
            .strict_unknown_fields = strict,
            .assets = assets,
            .ingests = ingests,
        };

        const simulation = try resolution_context.resolveStage(.simulation, mapGet(experiment_map, "simulation"), null);
        const retrieval = try resolution_context.resolveStage(.retrieval, mapGet(experiment_map, "retrieval"), if (simulation) |value| &value.stage else null);
        const outputs = try decodeOutputs(
            arena,
            mapGet(root_map, "outputs"),
            simulation,
            retrieval,
            strict,
            validation,
        );
        const warnings = try buildWarnings(arena, validation, simulation, retrieval);

        resolved.* = .{
            .owner_allocator = allocator,
            .arena_state = arena_state,
            .source_path = try arena.dupe(u8, self.source_path),
            .metadata = metadata,
            .assets = assets,
            .ingests = ingests,
            .simulation = if (simulation) |value| &value.stage else null,
            .retrieval = if (retrieval) |value| &value.stage else null,
            .outputs = outputs,
            .validation = validation,
            .warnings = warnings,
        };
        return resolved;
    }
};

pub const ResolvedExperiment = struct {
    owner_allocator: Allocator,
    arena_state: *std.heap.ArenaAllocator,
    source_path: []const u8,
    metadata: Metadata = .{},
    assets: []const Asset = &[_]Asset{},
    ingests: []const Ingest = &[_]Ingest{},
    simulation: ?*const Stage = null,
    retrieval: ?*const Stage = null,
    outputs: []const OutputSpec = &[_]OutputSpec{},
    validation: Validation = .{},
    warnings: []const Warning = &[_]Warning{},

    pub fn deinit(self: *ResolvedExperiment) void {
        const owner_allocator = self.owner_allocator;
        self.arena_state.deinit();
        owner_allocator.destroy(self.arena_state);
        self.* = undefined;
        owner_allocator.destroy(self);
    }

    pub fn findAsset(self: ResolvedExperiment, name: []const u8) ?Asset {
        for (self.assets) |asset| {
            if (std.mem.eql(u8, asset.name, name)) return asset;
        }
        return null;
    }

    pub fn findIngest(self: ResolvedExperiment, name: []const u8) ?Ingest {
        for (self.ingests) |ingest| {
            if (std.mem.eql(u8, ingest.name, name)) return ingest;
        }
        return null;
    }

    pub fn findProduct(self: ResolvedExperiment, name: []const u8) ?Product {
        if (self.simulation) |stage| {
            if (findStageProduct(stage.*, name)) |product| return product;
        }
        if (self.retrieval) |stage| {
            if (findStageProduct(stage.*, name)) |product| return product;
        }
        return null;
    }
};

/// Purpose:
///   Parse and resolve a canonical experiment file from disk.
pub fn resolveFile(allocator: Allocator, path: []const u8) !*ResolvedExperiment {
    var document = try Document.parseFile(allocator, path);
    defer document.deinit();
    return document.resolve(allocator);
}

const StageResolution = struct {
    merged: yaml.Value,
    stage: Stage,
};

const MeasurementDecode = struct {
    measurement: Measurement,
    source_name: []const u8,
};

const ObservationMetadata = struct {
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
    instrument_response_provider: []const u8 = "",
};

const InverseDecode = struct {
    inverse: InverseProblem,
    algorithm_name: []const u8 = "",
    algorithm_damping: []const u8 = "",
};

const SceneMetadata = struct {
    spectral_response_shape: []const u8 = "",
    spectral_response_table_source: Binding = .none,
    noise_seed: ?u64 = null,
    surface_model_provider: []const u8 = "",
    instrument_response_provider: []const u8 = "",
};

const ResolveContext = struct {
    allocator: Allocator,
    document: *const Document,
    root: []const yaml.Entry,
    validation: Validation,
    strict_unknown_fields: bool,
    assets: []const Asset,
    ingests: []const Ingest,

    fn resolveStage(
        self: *const ResolveContext,
        kind: StageKind,
        raw_stage: ?yaml.Value,
        simulation_stage: ?*const Stage,
    ) !?*StageResolution {
        const stage_value = raw_stage orelse return null;
        if (stage_value == .null) return null;

        var stack = std.ArrayListUnmanaged([]const u8){};
        defer stack.deinit(self.allocator);

        const resolution = try self.allocator.create(StageResolution);
        resolution.* = .{
            .merged = try self.resolveComposableNode(stage_value, &stack),
            .stage = undefined,
        };
        try self.populateStage(kind, resolution.merged, simulation_stage, &resolution.stage);
        return resolution;
    }

    fn resolveComposableNode(
        self: *const ResolveContext,
        value: yaml.Value,
        stack: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!yaml.Value {
        const map = try expectMap(value);
        const overlay = try cloneMapSkipping(self.allocator, map, &.{"from"});

        if (mapGet(map, "from")) |from_value| {
            const reference = try expectString(from_value);
            if (containsString(stack.items, reference)) return Error.ReferenceCycle;
            try stack.append(self.allocator, reference);
            defer _ = stack.pop();

            const base = try self.resolveReference(reference, stack);
            return yaml.merge(base, overlay, self.allocator);
        }

        return overlay;
    }

    fn resolveReference(
        self: *const ResolveContext,
        reference: []const u8,
        stack: *std.ArrayListUnmanaged([]const u8),
    ) anyerror!yaml.Value {
        if (std.mem.eql(u8, reference, "experiment.simulation")) {
            const experiment_map = try expectMap(requiredField(self.root, "experiment"));
            const stage_value = mapGet(experiment_map, "simulation") orelse return Error.MissingStage;
            if (stage_value == .null) return Error.MissingStage;
            return self.resolveComposableNode(stage_value, stack);
        }
        if (std.mem.eql(u8, reference, "experiment.retrieval")) {
            const experiment_map = try expectMap(requiredField(self.root, "experiment"));
            const stage_value = mapGet(experiment_map, "retrieval") orelse return Error.MissingStage;
            if (stage_value == .null) return Error.MissingStage;
            return self.resolveComposableNode(stage_value, stack);
        }

        const templates_value = mapGet(self.root, "templates") orelse return Error.MissingTemplate;
        const templates_map = try expectMap(templates_value);
        const template_name = if (std.mem.startsWith(u8, reference, "templates."))
            reference["templates.".len..]
        else
            reference;
        const template_value = mapGet(templates_map, template_name) orelse return Error.MissingTemplate;
        return self.resolveComposableNode(template_value, stack);
    }

    fn populateStage(
        self: *const ResolveContext,
        kind: StageKind,
        merged: yaml.Value,
        simulation_stage: ?*const Stage,
        stage: *Stage,
    ) !void {
        const stage_map = try expectMap(merged);
        try ensureKnownFields(stage_map, if (kind == .simulation)
            &.{ "plan", "scene", "products", "diagnostics", "label", "description", "vendor_compat", "radiative_transfer", "rrs_ring", "additional_output", "general", "instrument", "geometry", "pressure_temperature", "surface_config", "atmospheric_intervals", "cloud_aerosol_fraction", "cloud_config", "aerosol_config", "subcolumns", "retrieval_config", "absorbing_gas" }
        else
            &.{ "plan", "scene", "inverse", "products", "diagnostics", "label", "description", "vendor_compat", "radiative_transfer", "rrs_ring", "additional_output", "general", "instrument", "geometry", "pressure_temperature", "surface_config", "atmospheric_intervals", "cloud_aerosol_fraction", "cloud_config", "aerosol_config", "subcolumns", "retrieval_config", "absorbing_gas" }, self.strict_unknown_fields);

        stage.* = .{
            .kind = kind,
            .plan = try decodePlan(self.allocator, mapGet(stage_map, "plan"), self.strict_unknown_fields),
            .scene = undefined,
            .products = try decodeProducts(self.allocator, mapGet(stage_map, "products"), self.strict_unknown_fields),
            .diagnostics = try decodeDiagnostics(mapGet(stage_map, "diagnostics"), self.strict_unknown_fields),
        };
        const scene_metadata = try self.populateScene(kind, mapGet(stage_map, "scene"), &stage.scene);
        stage.spectral_response_shape = scene_metadata.spectral_response_shape;
        stage.spectral_response_table_source = scene_metadata.spectral_response_table_source;
        stage.noise_seed = scene_metadata.noise_seed;

        stage.plan.providers.surface_model = normalizeSurfaceProvider(
            scene_metadata.surface_model_provider,
            stage.scene.surface.kind,
        );
        stage.plan.providers.instrument_response = normalizeInstrumentProvider(
            scene_metadata.instrument_response_provider,
            stage.scene.observation_model.instrument,
        );
        stage.plan.scene_blueprint = .{
            .id = stage.scene.id,
            .spectral_grid = stage.scene.spectral_grid,
            .observation_regime = stage.scene.observation_model.regime,
            .derivative_mode = stage.plan.scene_blueprint.derivative_mode,
            .layer_count_hint = stage.scene.atmosphere.preparedLayerCount(),
            .measurement_count_hint = stage.scene.spectral_grid.sample_count,
        };

        if (kind == .retrieval) {
            const inverse_result = try self.decodeInverse(mapGet(stage_map, "inverse"), stage.scene, simulation_stage);
            stage.inverse = inverse_result.inverse;
            stage.algorithm_name = inverse_result.algorithm_name;
            stage.algorithm_damping = inverse_result.algorithm_damping;
            if (stage.inverse) |*inverse| {
                try applyAlgorithmParameters(inverse, stage.algorithm_damping);
            }
            try hydrateSceneFromIngestMeasurement(self.allocator, self.ingests, &stage.scene, inverse_result.inverse.measurements.source);
            stage.plan.providers.retrieval_algorithm = stage.plan.providers.retrieval_algorithm orelse normalizeRetrievalProvider(
                inverse_result.algorithm_name,
                stage.plan.providers.retrieval_algorithm,
            );
            stage.plan.scene_blueprint.spectral_grid = stage.scene.spectral_grid;
            stage.plan.scene_blueprint.state_parameter_count_hint = inverse_result.inverse.state_vector.count();
            stage.plan.scene_blueprint.measurement_count_hint = inverse_result.inverse.measurements.sample_count;
        }

        // Decode optional typed vendor sections
        stage.vendor_compat = try decodeVendorCompat(mapGet(stage_map, "vendor_compat"), self.strict_unknown_fields);
        stage.radiative_transfer = try decodeRadiativeTransferConfig(self.allocator, mapGet(stage_map, "radiative_transfer"), self.strict_unknown_fields);
        stage.plan.rtm_controls = try compileStageRtmControls(kind, stage.vendor_compat, stage.radiative_transfer);
        try applyAdaptiveReferenceGrid(kind, stage.radiative_transfer, &stage.scene.observation_model);
        stage.rrs_ring = try decodeRrsRingConfig(self.allocator, mapGet(stage_map, "rrs_ring"), self.strict_unknown_fields);
        stage.additional_output = try decodeAdditionalOutputConfig(mapGet(stage_map, "additional_output"), self.strict_unknown_fields);
        stage.general = try decodeGeneralConfig(self.allocator, mapGet(stage_map, "general"), self.strict_unknown_fields);
        try applyGeneralConfigToObservationModel(self.allocator, kind, stage.general, &stage.scene);
        stage.instrument = try decodeInstrumentConfig(self.allocator, mapGet(stage_map, "instrument"), self.strict_unknown_fields);
        stage.geometry = try decodeGeometryConfig(mapGet(stage_map, "geometry"), self.strict_unknown_fields);
        try applyGeometryConfigToScene(kind, stage.geometry, &stage.scene.geometry);
        stage.pressure_temperature = try decodePressureTemperatureConfig(self.allocator, mapGet(stage_map, "pressure_temperature"), self.strict_unknown_fields);
        try applyPressureTemperatureConfigToScene(kind, stage.pressure_temperature, &stage.scene);
        stage.surface_config = try decodeSurfaceConfig(self.allocator, mapGet(stage_map, "surface_config"), self.strict_unknown_fields);
        try applySurfaceConfigToScene(kind, stage.surface_config, &stage.scene);
        stage.atmospheric_intervals = try decodeAtmosphericIntervalsConfig(self.allocator, mapGet(stage_map, "atmospheric_intervals"), self.strict_unknown_fields);
        try applyAtmosphericIntervalsConfigToScene(
            self.allocator,
            kind,
            stage.general,
            stage.radiative_transfer,
            stage.atmospheric_intervals,
            &stage.scene,
        );
        stage.cloud_aerosol_fraction = try decodeCloudAerosolFractionConfig(self.allocator, mapGet(stage_map, "cloud_aerosol_fraction"), self.strict_unknown_fields);
        try applyCloudAerosolFractionConfigToScene(kind, stage.cloud_aerosol_fraction, &stage.scene);
        stage.cloud_config = try decodeCloudConfig(mapGet(stage_map, "cloud_config"), self.strict_unknown_fields);
        try applyCloudConfigToScene(kind, stage.cloud_config, &stage.scene);
        stage.aerosol_config = try decodeAerosolConfig(mapGet(stage_map, "aerosol_config"), self.strict_unknown_fields);
        try applyAerosolConfigToScene(kind, stage.aerosol_config, &stage.scene);
        stage.subcolumns = try decodeSubcolumnsConfig(self.allocator, mapGet(stage_map, "subcolumns"), self.strict_unknown_fields);
        try applySubcolumnsConfigToScene(self.allocator, stage.subcolumns, &stage.scene);
        stage.retrieval_config = try decodeRetrievalConfig(mapGet(stage_map, "retrieval_config"), self.strict_unknown_fields);
        stage.absorbing_gas = try decodeAbsorbingGasConfig(self.allocator, mapGet(stage_map, "absorbing_gas"), self.strict_unknown_fields);
        try applyAbsorbingGasConfigToScene(self.allocator, kind, stage.absorbing_gas, &stage.scene);
        stage.plan.scene_blueprint.layer_count_hint = stage.scene.atmosphere.preparedLayerCount();

        try ensureDistinctProducts(stage.products);
        try stage.plan.validate();
        try stage.scene.validate();
        if (stage.inverse) |inverse| try inverse.validate();
    }

    fn applyAlgorithmParameters(inverse: *InverseProblem, algorithm_damping: []const u8) !void {
        if (algorithm_damping.len == 0) return;

        const normalized: FitControls.TrustRegion = if (std.mem.eql(u8, algorithm_damping, "levenberg_marquardt"))
            .lm
        else if (std.mem.eql(u8, algorithm_damping, "lm"))
            .lm
        else
            return Error.InvalidValue;

        if (inverse.fit_controls.trust_region == .none) {
            inverse.fit_controls.trust_region = normalized;
            return;
        }
        if (inverse.fit_controls.trust_region != normalized) {
            return Error.InvalidValue;
        }
    }

    fn populateScene(
        self: *const ResolveContext,
        kind: StageKind,
        value: ?yaml.Value,
        scene: *Scene,
    ) !SceneMetadata {
        const scene_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(scene_map, &.{
            "id",
            "geometry",
            "atmosphere",
            "bands",
            "absorbers",
            "surface",
            "clouds",
            "aerosols",
            "measurement_model",
            "label",
            "description",
        }, self.strict_unknown_fields);

        var observation_model: ObservationModel = .{};
        const observation_metadata = try self.populateObservationModel(
            mapGet(scene_map, "measurement_model"),
            &observation_model,
        );
        const surface_result = try decodeSurface(self.allocator, mapGet(scene_map, "surface"), self.strict_unknown_fields);
        scene.* = .{
            .id = if (mapGet(scene_map, "id")) |scene_id| try self.allocator.dupe(u8, try expectString(scene_id)) else switch (kind) {
                .simulation => "simulation-stage",
                .retrieval => "retrieval-stage",
            },
            .geometry = try decodeGeometry(mapGet(scene_map, "geometry"), self.strict_unknown_fields),
            .atmosphere = try decodeAtmosphere(self.allocator, mapGet(scene_map, "atmosphere"), self.strict_unknown_fields),
            .bands = try decodeBands(self.allocator, mapGet(scene_map, "bands"), self.strict_unknown_fields),
            .surface = surface_result.surface,
            .cloud = try decodeCloud(mapGet(scene_map, "clouds"), self.strict_unknown_fields),
            .aerosol = try decodeAerosol(mapGet(scene_map, "aerosols"), self.strict_unknown_fields),
            .observation_model = observation_model,
        };

        scene.spectral_grid = try inferSpectralGrid(scene.bands);
        scene.observation_model.regime = observation_model.regime;
        scene.atmosphere.has_clouds = scene.cloud.enabled;
        scene.atmosphere.has_aerosols = scene.aerosol.enabled;
        scene.absorbers = try self.decodeAbsorbers(mapGet(scene_map, "absorbers"), &scene.observation_model);

        return .{
            .spectral_response_shape = observation_metadata.spectral_response_shape,
            .spectral_response_table_source = observation_metadata.spectral_response_table_source,
            .noise_seed = observation_metadata.noise_seed,
            .surface_model_provider = surface_result.provider,
            .instrument_response_provider = observation_metadata.instrument_response_provider,
        };
    }

    fn populateObservationModel(
        self: *const ResolveContext,
        value: ?yaml.Value,
        model: *ObservationModel,
    ) !ObservationMetadata {
        const model_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(model_map, &.{
            "regime",
            "instrument",
            "sampling",
            "spectral_response",
            "illumination",
            "supporting_data",
            "calibration",
            "noise",
            "label",
            "description",
        }, self.strict_unknown_fields);

        model.* = .{};
        var result: ObservationMetadata = .{};

        if (mapGet(model_map, "regime")) |regime| {
            model.regime = try parseObservationRegime(try expectString(regime));
        }

        if (mapGet(model_map, "instrument")) |instrument_value| {
            const instrument_map = try expectMap(instrument_value);
            try ensureKnownFields(instrument_map, &.{ "name", "response_provider" }, self.strict_unknown_fields);
            model.instrument = InstrumentId.parse(try expectString(requiredField(instrument_map, "name")));
            if (mapGet(instrument_map, "response_provider")) |response_provider| {
                result.instrument_response_provider = try self.allocator.dupe(u8, try expectString(response_provider));
            }
        }

        if (mapGet(model_map, "sampling")) |sampling_value| {
            const sampling_map = try expectMap(sampling_value);
            try ensureKnownFields(sampling_map, &.{ "mode", "high_resolution_step_nm", "high_resolution_half_span_nm" }, self.strict_unknown_fields);
            if (mapGet(sampling_map, "mode")) |mode| model.sampling = try parseSamplingMode(try expectString(mode));
            if (mapGet(sampling_map, "high_resolution_step_nm")) |step| model.high_resolution_step_nm = try expectF64(step);
            if (mapGet(sampling_map, "high_resolution_half_span_nm")) |span| model.high_resolution_half_span_nm = try expectF64(span);
        }

        if (mapGet(model_map, "spectral_response")) |response_value| {
            const response_map = try expectMap(response_value);
            try ensureKnownFields(response_map, &.{ "shape", "fwhm_nm", "table" }, self.strict_unknown_fields);
            if (mapGet(response_map, "shape")) |shape| {
                const shape_name = try expectString(shape);
                result.spectral_response_shape = try self.allocator.dupe(u8, shape_name);
                if (std.mem.eql(u8, shape_name, "table")) {
                    if (mapGet(response_map, "table") == null) return Error.MissingField;
                } else {
                    model.builtin_line_shape = try BuiltinLineShapeKind.parse(shape_name);
                }
            }
            if (mapGet(response_map, "fwhm_nm")) |fwhm| model.instrument_line_fwhm_nm = try expectF64(fwhm);
            if (mapGet(response_map, "table")) |table_value| {
                const binding = try self.decodeIngestBinding(table_value);
                result.spectral_response_table_source = binding;
                model.instrument_line_shape_table = try resolveInstrumentLineShapeTable(self.ingests, binding);
            }
        }

        if (mapGet(model_map, "illumination")) |illumination_value| {
            const illumination_map = try expectMap(illumination_value);
            try ensureKnownFields(illumination_map, &.{"solar_spectrum"}, self.strict_unknown_fields);
            if (mapGet(illumination_map, "solar_spectrum")) |spectrum_value| {
                const binding = try self.decodeSourceBinding(spectrum_value);
                model.solar_spectrum_source = binding;
                if (binding.kind() == .ingest) {
                    model.operational_solar_spectrum = try resolveOperationalSolarSpectrum(self.allocator, self.ingests, binding);
                }
            }
        }

        if (mapGet(model_map, "supporting_data")) |support_value| {
            const support_map = try expectMap(support_value);
            try ensureKnownFields(support_map, &.{"weighted_reference_grid"}, self.strict_unknown_fields);
            if (mapGet(support_map, "weighted_reference_grid")) |grid_value| {
                const binding = try self.decodeIngestBinding(grid_value);
                model.weighted_reference_grid_source = binding;
                model.operational_refspec_grid = try resolveOperationalReferenceGrid(self.allocator, self.ingests, binding);
            }
        }

        if (mapGet(model_map, "calibration")) |calibration_value| {
            const calibration_map = try expectMap(calibration_value);
            try ensureKnownFields(calibration_map, &.{ "wavelength_shift_nm", "multiplicative_offset", "stray_light" }, self.strict_unknown_fields);
            if (mapGet(calibration_map, "wavelength_shift_nm")) |shift| model.wavelength_shift_nm = try expectF64(shift);
            if (mapGet(calibration_map, "multiplicative_offset")) |offset| model.multiplicative_offset = try expectF64(offset);
            if (mapGet(calibration_map, "stray_light")) |stray_light| model.stray_light = try expectF64(stray_light);
        }

        if (mapGet(model_map, "noise")) |noise_value| {
            const noise_map = try expectMap(noise_value);
            try ensureKnownFields(noise_map, &.{ "model", "seed" }, self.strict_unknown_fields);
            if (mapGet(noise_map, "model")) |noise_model| model.noise_model = try parseNoiseModelKind(try expectString(noise_model));
            if (mapGet(noise_map, "seed")) |seed| result.noise_seed = @intCast(try expectU64(seed));
        }

        return result;
    }

    fn decodeAbsorbers(self: *const ResolveContext, value: ?yaml.Value, observation_model: *ObservationModel) !AbsorberSet {
        const absorber_map = try expectMap(value orelse return Error.MissingField);
        const absorbers = try self.allocator.alloc(Absorber, absorber_map.len);
        var initialized: usize = 0;
        errdefer {
            for (absorbers[0..initialized]) |*absorber| absorber.deinitOwned(self.allocator);
            self.allocator.free(absorbers);
        }

        for (absorber_map, 0..) |entry, index| {
            const item_map = try expectMap(entry.value);
            try ensureKnownFields(item_map, &.{ "species", "profile", "spectroscopy", "label", "description" }, self.strict_unknown_fields);

            var absorber: Absorber = .{
                .id = try self.allocator.dupe(u8, entry.key),
                .species = try self.allocator.dupe(u8, try expectString(requiredField(item_map, "species"))),
                .resolved_species = try fields.parseAbsorberSpecies(try expectString(requiredField(item_map, "species"))),
            };
            errdefer absorber.deinitOwned(self.allocator);

            if (mapGet(item_map, "profile")) |profile_value| {
                const profile_map = try expectMap(profile_value);
                try ensureKnownFields(profile_map, &.{"source"}, self.strict_unknown_fields);
                if (mapGet(profile_map, "source")) |source_value| {
                    absorber.profile_source = try decodeProfileBinding(self.allocator, source_value);
                }
            } else {
                absorber.profile_source = .atmosphere;
            }

            if (mapGet(item_map, "spectroscopy")) |spectroscopy_value| {
                const spectroscopy_map = try expectMap(spectroscopy_value);
                try ensureKnownFields(spectroscopy_map, &.{
                    "model",
                    "provider",
                    "line_list_asset",
                    "line_mixing_asset",
                    "strong_lines_asset",
                    "cia_asset",
                    "cross_section_asset",
                    "operational_lut",
                }, self.strict_unknown_fields);

                absorber.spectroscopy.mode = try parseSpectroscopyMode(try expectString(requiredField(spectroscopy_map, "model")));
                if (mapGet(spectroscopy_map, "provider")) |provider| {
                    absorber.spectroscopy.provider = try self.allocator.dupe(u8, try expectString(provider));
                }
                if (mapGet(spectroscopy_map, "line_list_asset")) |line_list_asset| {
                    absorber.spectroscopy.line_list = try self.decodeAssetBinding(line_list_asset);
                }
                if (mapGet(spectroscopy_map, "line_mixing_asset")) |line_mixing_asset| {
                    absorber.spectroscopy.line_mixing = try self.decodeAssetBinding(line_mixing_asset);
                }
                if (mapGet(spectroscopy_map, "strong_lines_asset")) |strong_lines_asset| {
                    absorber.spectroscopy.strong_lines = try self.decodeAssetBinding(strong_lines_asset);
                }
                if (mapGet(spectroscopy_map, "cia_asset")) |cia_asset| {
                    absorber.spectroscopy.cia_table = try self.decodeAssetBinding(cia_asset);
                }
                if (mapGet(spectroscopy_map, "cross_section_asset")) |cross_section_asset| {
                    absorber.spectroscopy.cross_section_table = try self.decodeAssetBinding(cross_section_asset);
                }
                if (mapGet(spectroscopy_map, "operational_lut")) |operational_lut| {
                    const binding = try self.decodeIngestBinding(operational_lut);
                    const ingest_ref = binding.ingestReference().?;
                    absorber.spectroscopy.operational_lut = binding;
                    var resolved_lut = try resolveOperationalLut(self.allocator, self.ingests, binding);
                    errdefer resolved_lut.deinitOwned(self.allocator);
                    var pending_o2_operational_lut: ?@import("../../model/Instrument.zig").OperationalCrossSectionLut = null;
                    errdefer if (pending_o2_operational_lut) |*lut| lut.deinitOwned(self.allocator);
                    var pending_o2o2_operational_lut: ?@import("../../model/Instrument.zig").OperationalCrossSectionLut = null;
                    errdefer if (pending_o2o2_operational_lut) |*lut| lut.deinitOwned(self.allocator);

                    const resolved_species = resolvedAbsorberSpecies(absorber);
                    const species_is_o2 = resolved_species == .o2;
                    const species_is_o2o2 = resolved_species == .o2_o2;
                    if (species_is_o2) {
                        if (!std.mem.eql(u8, ingest_ref.output_name, "o2_operational_lut")) {
                            return Error.MissingIngestOutput;
                        }
                        if (absorber.spectroscopy.mode == .line_by_line) {
                            pending_o2_operational_lut = try resolved_lut.clone(self.allocator);
                        }
                    } else if (species_is_o2o2) {
                        if (!std.mem.eql(u8, ingest_ref.output_name, "o2o2_operational_lut") and
                            !std.mem.eql(u8, ingest_ref.output_name, "o2_o2_operational_lut"))
                        {
                            return Error.MissingIngestOutput;
                        }
                        if (absorber.spectroscopy.mode == .cia) {
                            pending_o2o2_operational_lut = try resolved_lut.clone(self.allocator);
                        }
                    }
                    absorber.spectroscopy.resolved_cross_section_lut = resolved_lut;
                    if (pending_o2_operational_lut) |lut| {
                        observation_model.o2_operational_lut = lut;
                    }
                    if (pending_o2o2_operational_lut) |lut| {
                        observation_model.o2o2_operational_lut = lut;
                    }
                }
                absorber.spectroscopy.resolved_line_list = try resolveSpectroscopyLineList(
                    self.allocator,
                    self.assets,
                    absorber.spectroscopy,
                );
                absorber.spectroscopy.resolved_cia_table = try resolveCollisionInducedAbsorptionTable(
                    self.allocator,
                    self.assets,
                    absorber.spectroscopy.cia_table,
                );
                absorber.spectroscopy.resolved_cross_section_table = try resolveCrossSectionTable(
                    self.allocator,
                    self.assets,
                    absorber.spectroscopy.cross_section_table,
                );
            }

            absorbers[index] = absorber;
            initialized += 1;
        }

        return .{ .items = absorbers };
    }

    fn decodeInverse(
        self: *const ResolveContext,
        value: ?yaml.Value,
        scene: Scene,
        simulation_stage: ?*const Stage,
    ) !InverseDecode {
        const inverse_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(inverse_map, &.{
            "algorithm",
            "measurement",
            "state",
            "covariance",
            "fit_controls",
            "convergence",
            "label",
            "description",
        }, self.strict_unknown_fields);

        const algorithm = try decodeAlgorithm(self.allocator, mapGet(inverse_map, "algorithm"), self.strict_unknown_fields);
        const measurement_result = try self.decodeMeasurement(mapGet(inverse_map, "measurement"), scene, simulation_stage);
        const state_vector = try decodeStateVector(self.allocator, mapGet(inverse_map, "state"), self.strict_unknown_fields);
        const covariance_blocks = try decodeCovariance(self.allocator, state_vector, mapGet(inverse_map, "covariance"), self.strict_unknown_fields);
        const fit_controls = try decodeFitControls(mapGet(inverse_map, "fit_controls"), self.strict_unknown_fields);
        const convergence = try decodeConvergence(mapGet(inverse_map, "convergence"), self.strict_unknown_fields);

        return .{
            .inverse = .{
                .id = try std.fmt.allocPrint(self.allocator, "{s}-inverse", .{scene.id}),
                .state_vector = state_vector,
                .measurements = measurement_result.measurement,
                .covariance_blocks = covariance_blocks,
                .fit_controls = fit_controls,
                .convergence = convergence,
            },
            .algorithm_name = algorithm.name,
            .algorithm_damping = algorithm.damping,
        };
    }

    fn decodeMeasurement(
        self: *const ResolveContext,
        value: ?yaml.Value,
        scene: Scene,
        simulation_stage: ?*const Stage,
    ) !MeasurementDecode {
        const measurement_map = try expectMap(value orelse return Error.MissingField);
        try ensureKnownFields(measurement_map, &.{ "source", "observable", "mask", "error_model" }, self.strict_unknown_fields);

        const source_name = try self.allocator.dupe(u8, try expectString(requiredField(measurement_map, "source")));
        const binding = try resolveMeasurementSource(source_name, simulation_stage, self.validation, self.ingests);
        const observable = if (mapGet(measurement_map, "observable")) |observable_value|
            try parseMeasurementQuantity(try expectString(observable_value))
        else
            try inferMeasurementQuantity(source_name, binding, simulation_stage, self.ingests);
        const source_scene = if (binding.kind() == .stage_product and simulation_stage != null)
            simulation_stage.?.scene
        else
            scene;
        var measurement: Measurement = .{
            .product_name = observable.label(),
            .observable = observable,
            .sample_count = source_scene.spectral_grid.sample_count,
            .source = binding,
        };
        if (binding.kind() == .ingest) {
            measurement.sample_count = ingestMeasurementSampleCount(self.ingests, binding);
        }

        if (mapGet(measurement_map, "mask")) |mask_value| {
            measurement.mask = try decodeMeasurementMask(self.allocator, mask_value, self.strict_unknown_fields);
            measurement.sample_count = if (binding.kind() == .ingest)
                try maskedIngestMeasurementSampleCount(self.allocator, self.ingests, binding, measurement.mask)
            else
                try maskedMeasurementSampleCount(source_scene, measurement.mask);
        }
        if (mapGet(measurement_map, "error_model")) |error_model| {
            measurement.error_model = try decodeMeasurementErrorModel(error_model, self.strict_unknown_fields);
        }

        return .{
            .measurement = measurement,
            .source_name = source_name,
        };
    }

    fn maskedMeasurementSampleCount(scene: Scene, mask: MeasurementMask) !u32 {
        if (mask.exclude.len == 0) return scene.spectral_grid.sample_count;

        const axis: spectra_grid.ResolvedAxis = .{
            .base = .{
                .start_nm = scene.spectral_grid.start_nm,
                .end_nm = scene.spectral_grid.end_nm,
                .sample_count = scene.spectral_grid.sample_count,
            },
            .explicit_wavelengths_nm = scene.observation_model.measured_wavelengths_nm,
        };
        try axis.validate();

        var count: u32 = 0;
        const measurement: Measurement = .{
            .product_name = "radiance",
            .observable = .radiance,
            .sample_count = scene.spectral_grid.sample_count,
            .mask = mask,
        };
        for (0..scene.spectral_grid.sample_count) |index| {
            const wavelength_nm = try axis.sampleAt(@intCast(index));
            if (measurement.includesWavelength(wavelength_nm)) count += 1;
        }
        return count;
    }

    fn decodeAssetBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        const asset_name = try expectString(value);
        if (!hasAsset(self.assets, asset_name)) return Error.MissingAsset;
        return .{ .asset = .{ .name = try self.allocator.dupe(u8, asset_name) } };
    }

    fn decodeSourceBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        if (value == .string) {
            const source = value.string;
            if (std.mem.eql(u8, source, "bundle_default")) return .bundle_default;
            return .{ .external_observation = .{ .name = try self.allocator.dupe(u8, source) } };
        }

        const source_map = try expectMap(value);
        try ensureKnownFields(source_map, &.{ "source", "from_ingest" }, self.strict_unknown_fields);
        if (mapGet(source_map, "from_ingest")) |from_ingest| {
            return self.decodeIngestReference(try expectString(from_ingest));
        }
        if (mapGet(source_map, "source")) |source_value| {
            const source = try expectString(source_value);
            if (std.mem.eql(u8, source, "bundle_default")) return .bundle_default;
            return .{ .asset = .{ .name = try self.allocator.dupe(u8, source) } };
        }
        return Error.InvalidReference;
    }

    fn decodeIngestBinding(self: *const ResolveContext, value: yaml.Value) !Binding {
        const source_map = try expectMap(value);
        try ensureKnownFields(source_map, &.{"from_ingest"}, self.strict_unknown_fields);
        const from_ingest = try expectString(requiredField(source_map, "from_ingest"));
        return self.decodeIngestReference(from_ingest);
    }

    fn decodeIngestReference(self: *const ResolveContext, reference: []const u8) !Binding {
        const dot_index = std.mem.indexOfScalar(u8, reference, '.') orelse return Error.InvalidReference;
        const ingest_name = reference[0..dot_index];
        if (!hasIngest(self.ingests, ingest_name)) return Error.MissingIngest;
        return .{ .ingest = @import("../../model/Binding.zig").IngestRef.fromFullName(try self.allocator.dupe(u8, reference)) };
    }
};

fn decodeMetadata(allocator: Allocator, value: ?yaml.Value, strict: bool) !Metadata {
    const metadata_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(metadata_map, &.{ "id", "workspace", "description" }, strict);
    return .{
        .id = try allocator.dupe(u8, try expectString(requiredField(metadata_map, "id"))),
        .workspace = if (mapGet(metadata_map, "workspace")) |workspace|
            try allocator.dupe(u8, try expectString(workspace))
        else
            "",
        .description = if (mapGet(metadata_map, "description")) |description|
            try allocator.dupe(u8, try expectString(description))
        else
            "",
    };
}

fn decodeStrictUnknownFields(root: []const yaml.Entry) bool {
    const validation_value = mapGet(root, "validation") orelse return true;
    const validation_map = expectMap(validation_value) catch return true;
    const strict_unknown_fields = mapGet(validation_map, "strict_unknown_fields") orelse return true;
    return expectBool(strict_unknown_fields) catch true;
}

fn decodeValidation(allocator: Allocator, value: ?yaml.Value, strict: bool) !Validation {
    const validation_value = value orelse return .{};
    const validation_map = try expectMap(validation_value);
    try ensureKnownFields(validation_map, &.{
        "strict_unknown_fields",
        "require_resolved_assets",
        "require_resolved_stage_references",
        "synthetic_retrieval",
    }, strict);

    var validation: Validation = .{};
    if (mapGet(validation_map, "strict_unknown_fields")) |strict_unknown_fields| validation.strict_unknown_fields = try expectBool(strict_unknown_fields);
    if (mapGet(validation_map, "require_resolved_assets")) |require_assets| validation.require_resolved_assets = try expectBool(require_assets);
    if (mapGet(validation_map, "require_resolved_stage_references")) |require_stage_refs| validation.require_resolved_stage_references = try expectBool(require_stage_refs);
    if (mapGet(validation_map, "synthetic_retrieval")) |synthetic_retrieval| {
        const synthetic_map = try expectMap(synthetic_retrieval);
        try ensureKnownFields(synthetic_map, &.{ "warn_if_models_are_identical", "require_explicit_acknowledgement_if_identical" }, validation.strict_unknown_fields);
        if (mapGet(synthetic_map, "warn_if_models_are_identical")) |warn| validation.synthetic_retrieval.warn_if_models_are_identical = try expectBool(warn);
        if (mapGet(synthetic_map, "require_explicit_acknowledgement_if_identical")) |ack| validation.synthetic_retrieval.require_explicit_acknowledgement_if_identical = try expectBool(ack);
    }
    _ = allocator;
    return validation;
}

fn decodeAssets(allocator: Allocator, document: *const Document, root: []const yaml.Entry, strict: bool) ![]const Asset {
    const inputs_value = mapGet(root, "inputs") orelse return &[_]Asset{};
    const inputs_map = try expectMap(inputs_value);
    try ensureKnownFields(inputs_map, &.{ "assets", "ingests" }, strict);

    const assets_value = mapGet(inputs_map, "assets") orelse return &[_]Asset{};
    const assets_map = try expectMap(assets_value);
    const assets = try allocator.alloc(Asset, assets_map.len);

    for (assets_map, 0..) |entry, index| {
        const asset_map = try expectMap(entry.value);
        try ensureKnownFields(asset_map, &.{ "kind", "path", "format", "label", "description" }, strict);

        const kind_string = try expectString(requiredField(asset_map, "kind"));
        const path = try expectString(requiredField(asset_map, "path"));
        assets[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .kind = try parseAssetKind(kind_string),
            .format = try allocator.dupe(u8, try expectString(requiredField(asset_map, "format"))),
            .path = try allocator.dupe(u8, path),
            .resolved_path = try resolveInputPath(allocator, document.source_dir, path),
        };
    }

    return assets;
}

fn decodeIngests(allocator: Allocator, root: []const yaml.Entry, assets: []const Asset, strict: bool) ![]const Ingest {
    const inputs_value = mapGet(root, "inputs") orelse return &[_]Ingest{};
    const inputs_map = try expectMap(inputs_value);
    const ingests_value = mapGet(inputs_map, "ingests") orelse return &[_]Ingest{};
    const ingests_map = try expectMap(ingests_value);

    const ingests = try allocator.alloc(Ingest, ingests_map.len);
    for (ingests_map, 0..) |entry, index| {
        const ingest_map = try expectMap(entry.value);
        try ensureKnownFields(ingest_map, &.{ "adapter", "asset", "label", "description" }, strict);

        const adapter = try parseIngestAdapter(try expectString(requiredField(ingest_map, "adapter")));
        const asset_name = try expectString(requiredField(ingest_map, "asset"));
        const asset = findAsset(assets, asset_name) orelse return Error.MissingAsset;
        ingests[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .adapter = adapter,
            .asset_name = try allocator.dupe(u8, asset_name),
            .loaded_spectra = switch (adapter) {
                .spectral_ascii => try spectral_ascii.parseFile(allocator, asset.resolved_path),
            },
        };
    }
    return ingests;
}

fn decodePlan(allocator: Allocator, value: ?yaml.Value, strict: bool) !PlanTemplate {
    var template: PlanTemplate = .{};
    const plan_value = value orelse return template;
    const plan_map = try expectMap(plan_value);
    try ensureKnownFields(plan_map, &.{ "model_family", "transport", "execution", "providers" }, strict);

    if (mapGet(plan_map, "model_family")) |model_family| template.model_family = try allocator.dupe(u8, try expectString(model_family));

    if (mapGet(plan_map, "transport")) |transport_value| {
        const transport_map = try expectMap(transport_value);
        try ensureKnownFields(transport_map, &.{ "solver", "provider" }, strict);
        const solver = if (mapGet(transport_map, "solver")) |solver_value| try expectString(solver_value) else "";
        const provider = if (mapGet(transport_map, "provider")) |provider_value| try expectString(provider_value) else "";
        template.providers.transport_solver = normalizeTransportProvider(solver, provider);
    }

    if (mapGet(plan_map, "execution")) |execution_value| {
        const execution_map = try expectMap(execution_value);
        try ensureKnownFields(execution_map, &.{ "solver_mode", "derivative_mode" }, strict);
        if (mapGet(execution_map, "solver_mode")) |solver_mode| template.solver_mode = try parseSolverMode(try expectString(solver_mode));
        if (mapGet(execution_map, "derivative_mode")) |derivative_mode| template.scene_blueprint.derivative_mode = try parseDerivativeMode(try expectString(derivative_mode));
    }

    if (mapGet(plan_map, "providers")) |providers_value| {
        const providers_map = try expectMap(providers_value);
        try ensureKnownFields(providers_map, &.{
            "transport_solver",
            "retrieval_algorithm",
            "surface_model",
            "instrument_response",
            "absorber_provider",
            "noise_model",
            "diagnostics_metric",
        }, strict);
        if (mapGet(providers_map, "transport_solver")) |transport_solver| template.providers.transport_solver = try allocator.dupe(u8, try expectString(transport_solver));
        if (mapGet(providers_map, "retrieval_algorithm")) |retrieval_algorithm| template.providers.retrieval_algorithm = try allocator.dupe(u8, try expectString(retrieval_algorithm));
        if (mapGet(providers_map, "surface_model")) |surface_model| template.providers.surface_model = try allocator.dupe(u8, try expectString(surface_model));
        if (mapGet(providers_map, "instrument_response")) |instrument_response| template.providers.instrument_response = try allocator.dupe(u8, try expectString(instrument_response));
        if (mapGet(providers_map, "absorber_provider")) |absorber_provider| template.providers.absorber_provider = try allocator.dupe(u8, try expectString(absorber_provider));
        if (mapGet(providers_map, "noise_model")) |noise_model| template.providers.noise_model = try allocator.dupe(u8, try expectString(noise_model));
        if (mapGet(providers_map, "diagnostics_metric")) |diagnostics_metric| template.providers.diagnostics_metric = try allocator.dupe(u8, try expectString(diagnostics_metric));
    }
    return template;
}

fn decodeGeometry(value: ?yaml.Value, strict: bool) !Geometry {
    const geometry_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(geometry_map, &.{ "model", "solar_zenith_deg", "viewing_zenith_deg", "relative_azimuth_deg" }, strict);
    return .{
        .model = try parseGeometryModel(try expectString(requiredField(geometry_map, "model"))),
        .solar_zenith_deg = try expectF64(requiredField(geometry_map, "solar_zenith_deg")),
        .viewing_zenith_deg = try expectF64(requiredField(geometry_map, "viewing_zenith_deg")),
        .relative_azimuth_deg = try expectF64(requiredField(geometry_map, "relative_azimuth_deg")),
    };
}

fn decodeAtmosphere(allocator: Allocator, value: ?yaml.Value, strict: bool) !Atmosphere {
    const atmosphere_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(atmosphere_map, &.{ "layering", "thermodynamics", "boundary" }, strict);

    var atmosphere: Atmosphere = .{};
    if (mapGet(atmosphere_map, "layering")) |layering_value| {
        const layering_map = try expectMap(layering_value);
        try ensureKnownFields(layering_map, &.{ "layer_count", "sublayer_divisions" }, strict);
        if (mapGet(layering_map, "layer_count")) |layer_count| atmosphere.layer_count = @intCast(try expectU64(layer_count));
        if (mapGet(layering_map, "sublayer_divisions")) |sublayer_divisions| atmosphere.sublayer_divisions = @intCast(try expectU64(sublayer_divisions));
    }
    if (mapGet(atmosphere_map, "thermodynamics")) |thermodynamics_value| {
        const thermodynamics_map = try expectMap(thermodynamics_value);
        try ensureKnownFields(thermodynamics_map, &.{"profile"}, strict);
        if (mapGet(thermodynamics_map, "profile")) |profile_value| {
            const profile_map = try expectMap(profile_value);
            try ensureKnownFields(profile_map, &.{"source"}, strict);
            atmosphere.profile_source = try decodeProfileBinding(allocator, requiredField(profile_map, "source"));
        }
    }
    if (mapGet(atmosphere_map, "boundary")) |boundary_value| {
        const boundary_map = try expectMap(boundary_value);
        try ensureKnownFields(boundary_map, &.{"surface_pressure_hpa"}, strict);
        if (mapGet(boundary_map, "surface_pressure_hpa")) |surface_pressure_hpa| atmosphere.surface_pressure_hpa = try expectF64(surface_pressure_hpa);
    }
    return atmosphere;
}

fn decodeBands(allocator: Allocator, value: ?yaml.Value, strict: bool) !SpectralBandSet {
    const band_map = try expectMap(value orelse return Error.MissingField);
    const bands = try allocator.alloc(SpectralBand, band_map.len);
    for (band_map, 0..) |entry, index| {
        const band_value_map = try expectMap(entry.value);
        try ensureKnownFields(band_value_map, &.{ "start_nm", "end_nm", "step_nm", "exclude", "label", "description" }, strict);
        bands[index] = .{
            .id = try allocator.dupe(u8, entry.key),
            .start_nm = try expectF64(requiredField(band_value_map, "start_nm")),
            .end_nm = try expectF64(requiredField(band_value_map, "end_nm")),
            .step_nm = try expectF64(requiredField(band_value_map, "step_nm")),
            .exclude = try decodeWindows(allocator, mapGet(band_value_map, "exclude")),
        };
    }
    return .{ .items = bands };
}

fn decodeWindows(allocator: Allocator, value: ?yaml.Value) ![]const SpectralWindow {
    const window_value = value orelse return &[_]SpectralWindow{};
    const windows = try expectSeq(window_value);
    const decoded = try allocator.alloc(SpectralWindow, windows.len);
    for (windows, 0..) |window, index| {
        const pair = try expectSeq(window);
        if (pair.len != 2) return Error.InvalidValue;
        decoded[index] = .{
            .start_nm = try expectF64(pair[0]),
            .end_nm = try expectF64(pair[1]),
        };
    }
    return decoded;
}

const SurfaceDecode = struct {
    surface: Surface,
    provider: []const u8 = "",
};

fn decodeSurface(allocator: Allocator, value: ?yaml.Value, strict: bool) !SurfaceDecode {
    const surface_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(surface_map, &.{ "model", "provider", "albedo", "parameters", "label", "description" }, strict);

    var result: SurfaceDecode = .{
        .surface = .{
            .kind = try parseSurfaceKind(try expectString(requiredField(surface_map, "model"))),
        },
    };
    if (mapGet(surface_map, "provider")) |provider| result.provider = try allocator.dupe(u8, try expectString(provider));
    if (mapGet(surface_map, "albedo")) |albedo| result.surface.albedo = try expectF64(albedo);
    if (mapGet(surface_map, "parameters")) |parameters_value| {
        const parameters_map = try expectMap(parameters_value);
        const parameters = try allocator.alloc(SurfaceParameter, parameters_map.len);
        for (parameters_map, 0..) |entry, index| {
            parameters[index] = .{
                .name = try allocator.dupe(u8, entry.key),
                .value = try expectF64(entry.value),
            };
        }
        result.surface.parameters = parameters;
    }
    return result;
}

fn decodeCloud(value: ?yaml.Value, strict: bool) !Cloud {
    const clouds_value = value orelse return .{};
    const clouds_map = try expectMap(clouds_value);
    if (clouds_map.len == 0) return .{};
    if (clouds_map.len > 1) return Error.UnsupportedMultiplicity;

    const entry = clouds_map[0];
    const cloud_map = try expectMap(entry.value);
    try ensureKnownFields(cloud_map, &.{
        "model",
        "provider",
        "optical_thickness",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "reference_wavelength_nm",
        "top_altitude_km",
        "thickness_km",
    }, strict);

    return .{
        .id = entry.key,
        .enabled = true,
        .cloud_type = try fields.parseCloudType(try expectString(requiredField(cloud_map, "model"))),
        .provider = if (mapGet(cloud_map, "provider")) |provider| try expectString(provider) else "",
        .optical_thickness = try expectF64(requiredField(cloud_map, "optical_thickness")),
        .single_scatter_albedo = if (mapGet(cloud_map, "single_scatter_albedo")) |ssa| try expectF64(ssa) else 0.999,
        .asymmetry_factor = if (mapGet(cloud_map, "asymmetry_factor")) |asymmetry_factor| try expectF64(asymmetry_factor) else 0.85,
        .angstrom_exponent = if (mapGet(cloud_map, "angstrom_exponent")) |angstrom_exponent| try expectF64(angstrom_exponent) else 0.3,
        .reference_wavelength_nm = if (mapGet(cloud_map, "reference_wavelength_nm")) |reference_wavelength| try expectF64(reference_wavelength) else 550.0,
        .top_altitude_km = if (mapGet(cloud_map, "top_altitude_km")) |top_altitude| try expectF64(top_altitude) else 6.0,
        .thickness_km = if (mapGet(cloud_map, "thickness_km")) |thickness| try expectF64(thickness) else 1.5,
    };
}

fn decodeAerosol(value: ?yaml.Value, strict: bool) !Aerosol {
    const aerosols_value = value orelse return .{};
    const aerosols_map = try expectMap(aerosols_value);
    if (aerosols_map.len == 0) return .{};
    if (aerosols_map.len > 1) return Error.UnsupportedMultiplicity;

    const entry = aerosols_map[0];
    const aerosol_map = try expectMap(entry.value);
    try ensureKnownFields(aerosol_map, &.{
        "model",
        "provider",
        "optical_depth_550_nm",
        "single_scatter_albedo",
        "asymmetry_factor",
        "angstrom_exponent",
        "layer_center_km",
        "layer_width_km",
    }, strict);

    return .{
        .id = entry.key,
        .enabled = true,
        .aerosol_type = try fields.parseAerosolType(try expectString(requiredField(aerosol_map, "model"))),
        .provider = if (mapGet(aerosol_map, "provider")) |provider| try expectString(provider) else "",
        .optical_depth = try expectF64(requiredField(aerosol_map, "optical_depth_550_nm")),
        .single_scatter_albedo = if (mapGet(aerosol_map, "single_scatter_albedo")) |ssa| try expectF64(ssa) else 0.93,
        .asymmetry_factor = if (mapGet(aerosol_map, "asymmetry_factor")) |asymmetry_factor| try expectF64(asymmetry_factor) else 0.65,
        .angstrom_exponent = if (mapGet(aerosol_map, "angstrom_exponent")) |angstrom_exponent| try expectF64(angstrom_exponent) else 1.3,
        .layer_center_km = if (mapGet(aerosol_map, "layer_center_km")) |center| try expectF64(center) else 2.5,
        .layer_width_km = if (mapGet(aerosol_map, "layer_width_km")) |width| try expectF64(width) else 3.0,
    };
}

fn decodeProducts(allocator: Allocator, value: ?yaml.Value, strict: bool) ![]const Product {
    const products_value = value orelse return &[_]Product{};
    const products_map = try expectMap(products_value);
    const products = try allocator.alloc(Product, products_map.len);
    for (products_map, 0..) |entry, index| {
        const product_map = try expectMap(entry.value);
        try ensureKnownFields(product_map, &.{ "kind", "observable", "apply_noise", "label", "description" }, strict);
        products[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .kind = try parseProductKind(try expectString(requiredField(product_map, "kind"))),
            .observable = if (mapGet(product_map, "observable")) |observable|
                try parseMeasurementQuantity(try expectString(observable))
            else
                null,
            .apply_noise = if (mapGet(product_map, "apply_noise")) |apply_noise| try expectBool(apply_noise) else false,
        };
    }
    return products;
}

fn decodeDiagnostics(value: ?yaml.Value, strict: bool) !DiagnosticsSpec {
    const diagnostics_value = value orelse return .{};
    const diagnostics_map = try expectMap(diagnostics_value);
    try ensureKnownFields(diagnostics_map, &.{ "provenance", "jacobians" }, strict);
    return .{
        .provenance = if (mapGet(diagnostics_map, "provenance")) |provenance| try expectBool(provenance) else true,
        .jacobians = if (mapGet(diagnostics_map, "jacobians")) |jacobians| try expectBool(jacobians) else false,
    };
}

fn decodeAlgorithm(allocator: Allocator, value: ?yaml.Value, strict: bool) !struct {
    name: []const u8,
    provider: ?[]const u8,
    damping: []const u8,
} {
    const algorithm_map = try expectMap(value orelse return Error.MissingField);
    try ensureKnownFields(algorithm_map, &.{ "name", "provider", "parameters" }, strict);

    var damping: []const u8 = "";
    if (mapGet(algorithm_map, "parameters")) |parameters_value| {
        const parameters_map = try expectMap(parameters_value);
        try ensureKnownFields(parameters_map, &.{"damping"}, strict);
        if (mapGet(parameters_map, "damping")) |damping_value| damping = try allocator.dupe(u8, try expectString(damping_value));
    }

    return .{
        .name = try allocator.dupe(u8, try expectString(requiredField(algorithm_map, "name"))),
        .provider = if (mapGet(algorithm_map, "provider")) |provider|
            try allocator.dupe(u8, try expectString(provider))
        else
            null,
        .damping = damping,
    };
}

fn decodeStateVector(allocator: Allocator, value: ?yaml.Value, strict: bool) !StateVector {
    const state_value = value orelse return StateVector{ .value_count = 0 };
    const state_map = try expectMap(state_value);
    const parameters = try allocator.alloc(StateParameter, state_map.len);
    errdefer allocator.free(parameters);

    for (state_map, 0..) |entry, index| {
        const parameter_map = try expectMap(entry.value);
        try ensureKnownFields(parameter_map, &.{ "target", "transform", "prior", "bounds", "label", "description" }, strict);
        parameters[index] = .{
            .name = try allocator.dupe(u8, entry.key),
            .target = try StateTarget.parse(try expectString(requiredField(parameter_map, "target"))),
            .transform = if (mapGet(parameter_map, "transform")) |transform| try parseStateTransform(try expectString(transform)) else .none,
            .prior = try decodePrior(mapGet(parameter_map, "prior"), strict),
            .bounds = try decodeBounds(mapGet(parameter_map, "bounds")),
        };
    }

    return .{
        .value_count = @intCast(parameters.len),
        .parameters = parameters,
    };
}

fn decodePrior(value: ?yaml.Value, strict: bool) !StatePrior {
    const prior_value = value orelse return .{};
    const prior_map = try expectMap(prior_value);
    try ensureKnownFields(prior_map, &.{ "mean", "sigma" }, strict);
    return .{
        .enabled = true,
        .mean = try expectF64(requiredField(prior_map, "mean")),
        .sigma = try expectF64(requiredField(prior_map, "sigma")),
    };
}

fn decodeBounds(value: ?yaml.Value) !StateBounds {
    const bounds_value = value orelse return .{};
    const pair = try expectSeq(bounds_value);
    if (pair.len != 2) return Error.InvalidValue;
    return .{
        .enabled = true,
        .min = try expectF64(pair[0]),
        .max = try expectF64(pair[1]),
    };
}

fn decodeCovariance(allocator: Allocator, state_vector: StateVector, value: ?yaml.Value, strict: bool) ![]const CovarianceBlock {
    const covariance_value = value orelse return &[_]CovarianceBlock{};
    const covariance_map = try expectMap(covariance_value);
    try ensureKnownFields(covariance_map, &.{"blocks"}, strict);

    const blocks_value = mapGet(covariance_map, "blocks") orelse return &[_]CovarianceBlock{};
    const blocks = try expectSeq(blocks_value);
    const decoded = try allocator.alloc(CovarianceBlock, blocks.len);
    for (blocks, 0..) |block_value, index| {
        const block_map = try expectMap(block_value);
        try ensureKnownFields(block_map, &.{ "members", "correlation" }, strict);
        const members = try expectSeq(requiredField(block_map, "members"));
        const parameter_indices = try allocator.alloc(u32, members.len);
        for (members, 0..) |member, member_index| {
            const member_name = try expectString(member);
            const parameter_index = state_vector.parameterIndex(member_name) orelse return Error.InvalidValue;
            parameter_indices[member_index] = @intCast(parameter_index);
        }
        decoded[index] = .{
            .parameter_indices = parameter_indices,
            .correlation = try expectF64(requiredField(block_map, "correlation")),
        };
    }
    return decoded;
}

fn decodeFitControls(value: ?yaml.Value, strict: bool) !FitControls {
    const fit_controls_value = value orelse return .{};
    const fit_controls_map = try expectMap(fit_controls_value);
    try ensureKnownFields(fit_controls_map, &.{ "max_iterations", "trust_region" }, strict);
    return .{
        .max_iterations = if (mapGet(fit_controls_map, "max_iterations")) |max_iterations| @intCast(try expectU64(max_iterations)) else 0,
        .trust_region = if (mapGet(fit_controls_map, "trust_region")) |trust_region|
            try parseTrustRegion(try expectString(trust_region))
        else
            .none,
    };
}

fn decodeConvergence(value: ?yaml.Value, strict: bool) !Convergence {
    const convergence_value = value orelse return .{};
    const convergence_map = try expectMap(convergence_value);
    try ensureKnownFields(convergence_map, &.{ "cost_relative", "state_relative" }, strict);
    return .{
        .cost_relative = if (mapGet(convergence_map, "cost_relative")) |cost_relative| try expectF64(cost_relative) else 0.0,
        .state_relative = if (mapGet(convergence_map, "state_relative")) |state_relative| try expectF64(state_relative) else 0.0,
    };
}

// --- Vendor-section decoders ---

fn decodeVendorCompat(value: ?yaml.Value, strict: bool) !?VendorCompat {
    const vc_value = value orelse return null;
    const vc_map = try expectMap(vc_value);
    try ensureKnownFields(vc_map, &.{
        "simulation_method",
        "retrieval_method",
        "simulation_only",
        "use_adding_sim",
        "use_adding_retr",
    }, strict);

    var vc: VendorCompat = .{};
    if (mapGet(vc_map, "simulation_method")) |v| vc.simulation_method = try fields.parseSimulationMethod(try expectString(v));
    if (mapGet(vc_map, "retrieval_method")) |v| vc.retrieval_method = try fields.parseRetrievalMethod(try expectString(v));
    if (mapGet(vc_map, "simulation_only")) |v| vc.simulation_only = try expectBool(v);
    if (mapGet(vc_map, "use_adding_sim")) |v| vc.use_adding_sim = try expectBool(v);
    if (mapGet(vc_map, "use_adding_retr")) |v| vc.use_adding_retr = try expectBool(v);
    return vc;
}

fn decodeRadiativeTransferConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?RadiativeTransferConfig {
    const rt_value = value orelse return null;
    const rt_map = try expectMap(rt_value);
    try ensureKnownFields(rt_map, &.{
        "num_div_points_fwhm_sim",
        "num_div_points_fwhm_retr",
        "num_div_points_max_sim",
        "num_div_points_min_sim",
        "num_div_points_max_retr",
        "num_div_points_min_retr",
        "scattering_mode_sim",
        "scattering_mode_retr",
        "stokes_dimension_sim",
        "stokes_dimension_retr",
        "nstreams_sim",
        "nstreams_retr",
        "use_adding_sim",
        "use_adding_retr",
        "fourier_floor_scalar_sim",
        "fourier_floor_scalar_retr",
        "num_orders_max_sim",
        "num_orders_max_retr",
        "threshold_trunc_phase_sim",
        "threshold_trunc_phase_retr",
        "use_polarization_correction",
        "use_correction_spherical_atm",
        "threshold_cloud_fraction",
        "threshold_conv_first",
        "threshold_conv_mult",
        "threshold_doubling",
        "threshold_multiplier",
        "num_div_points_alt_sim",
        "num_div_points_alt_retr",
    }, strict);

    var rt: RadiativeTransferConfig = .{};
    if (mapGet(rt_map, "num_div_points_fwhm_sim")) |v| rt.num_div_points_fwhm_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_div_points_fwhm_retr")) |v| rt.num_div_points_fwhm_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_div_points_max_sim")) |v| rt.num_div_points_max_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_div_points_min_sim")) |v| rt.num_div_points_min_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_div_points_max_retr")) |v| rt.num_div_points_max_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_div_points_min_retr")) |v| rt.num_div_points_min_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "scattering_mode_sim")) |v| rt.scattering_mode_sim = try fields.parseScatteringMode(try expectString(v));
    if (mapGet(rt_map, "scattering_mode_retr")) |v| rt.scattering_mode_retr = try fields.parseScatteringMode(try expectString(v));
    if (mapGet(rt_map, "stokes_dimension_sim")) |v| rt.stokes_dimension_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "stokes_dimension_retr")) |v| rt.stokes_dimension_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "nstreams_sim")) |v| rt.nstreams_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "nstreams_retr")) |v| rt.nstreams_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "use_adding_sim")) |v| rt.use_adding_sim = try expectBool(v);
    if (mapGet(rt_map, "use_adding_retr")) |v| rt.use_adding_retr = try expectBool(v);
    if (mapGet(rt_map, "fourier_floor_scalar_sim")) |v| rt.fourier_floor_scalar_sim = try expectF64(v);
    if (mapGet(rt_map, "fourier_floor_scalar_retr")) |v| rt.fourier_floor_scalar_retr = try expectF64(v);
    if (mapGet(rt_map, "num_orders_max_sim")) |v| rt.num_orders_max_sim = @intCast(try expectU64(v));
    if (mapGet(rt_map, "num_orders_max_retr")) |v| rt.num_orders_max_retr = @intCast(try expectU64(v));
    if (mapGet(rt_map, "threshold_trunc_phase_sim")) |v| rt.threshold_trunc_phase_sim = try expectF64(v);
    if (mapGet(rt_map, "threshold_trunc_phase_retr")) |v| rt.threshold_trunc_phase_retr = try expectF64(v);
    if (mapGet(rt_map, "use_polarization_correction")) |v| rt.use_polarization_correction = try expectBool(v);
    if (mapGet(rt_map, "use_correction_spherical_atm")) |v| rt.use_correction_spherical_atm = try expectBool(v);
    if (mapGet(rt_map, "threshold_cloud_fraction")) |v| rt.threshold_cloud_fraction = try expectF64(v);
    if (mapGet(rt_map, "threshold_conv_first")) |v| rt.threshold_conv_first = try expectF64(v);
    if (mapGet(rt_map, "threshold_conv_mult")) |v| rt.threshold_conv_mult = try expectF64(v);
    if (mapGet(rt_map, "threshold_doubling")) |v| rt.threshold_doubling = try expectF64(v);
    if (mapGet(rt_map, "threshold_multiplier")) |v| rt.threshold_multiplier = try expectF64(v);
    if (mapGet(rt_map, "num_div_points_alt_sim")) |v| rt.num_div_points_alt_sim = try decodeU32Sequence(allocator, v);
    if (mapGet(rt_map, "num_div_points_alt_retr")) |v| rt.num_div_points_alt_retr = try decodeU32Sequence(allocator, v);
    return rt;
}

fn compileStageRtmControls(
    kind: StageKind,
    vendor_compat: ?VendorCompat,
    radiative_transfer: ?RadiativeTransferConfig,
) !transport_common.RtmControls {
    var controls = transport_common.RtmControls.default_vendor;

    if (radiative_transfer) |rt| {
        try rejectUnsupportedRtmControls(kind, rt);
        const scattering_mode = switch (kind) {
            .simulation => rt.scattering_mode_sim,
            .retrieval => rt.scattering_mode_retr,
        };
        controls.scattering = switch (scattering_mode) {
            .none => .none,
            .single => .single,
            .multiple => .multiple,
        };
        controls.integrate_source_function = scattering_mode != .none;
        controls.stokes_dimension = switch (kind) {
            .simulation => rt.stokes_dimension_sim,
            .retrieval => rt.stokes_dimension_retr,
        };
        controls.n_streams = @intCast(switch (kind) {
            .simulation => rt.nstreams_sim,
            .retrieval => rt.nstreams_retr,
        });
        controls.use_adding = switch (kind) {
            .simulation => rt.use_adding_sim,
            .retrieval => rt.use_adding_retr,
        };
        controls.fourier_floor_scalar = @intFromFloat(@max(switch (kind) {
            .simulation => rt.fourier_floor_scalar_sim orelse @as(f64, @floatFromInt(controls.fourier_floor_scalar)),
            .retrieval => rt.fourier_floor_scalar_retr orelse @as(f64, @floatFromInt(controls.fourier_floor_scalar)),
        }, 0.0));
        controls.num_orders_max = @intCast(switch (kind) {
            .simulation => rt.num_orders_max_sim orelse controls.num_orders_max,
            .retrieval => rt.num_orders_max_retr orelse controls.num_orders_max,
        });
        controls.use_spherical_correction = rt.use_correction_spherical_atm;
        controls.threshold_conv_first = rt.threshold_conv_first orelse controls.threshold_conv_first;
        controls.threshold_conv_mult = rt.threshold_conv_mult orelse controls.threshold_conv_mult;
        controls.threshold_doubl = rt.threshold_doubling orelse controls.threshold_doubl;
        controls.threshold_mul = rt.threshold_multiplier orelse controls.threshold_mul;
    }

    if (vendor_compat) |compat| {
        const compat_use_adding = switch (kind) {
            .simulation => compat.use_adding_sim,
            .retrieval => compat.use_adding_retr,
        };
        if (compat_use_adding) |value| {
            if (radiative_transfer != null and controls.use_adding != value) return Error.InvalidValue;
            controls.use_adding = value;
        }
    }

    return controls;
}

fn rejectUnsupportedRtmControls(
    kind: StageKind,
    rt: RadiativeTransferConfig,
) Error!void {
    const trunc_threshold = switch (kind) {
        .simulation => rt.threshold_trunc_phase_sim,
        .retrieval => rt.threshold_trunc_phase_retr,
    };
    if (trunc_threshold != null) return Error.InvalidValue;
    if (rt.use_polarization_correction) return Error.InvalidValue;
    if (rt.threshold_cloud_fraction != null) return Error.InvalidValue;
}

fn applyAdaptiveReferenceGrid(
    kind: StageKind,
    radiative_transfer: ?RadiativeTransferConfig,
    observation_model: *ObservationModel,
) !void {
    const rt = radiative_transfer orelse return;
    const points_per_fwhm = switch (kind) {
        .simulation => rt.num_div_points_fwhm_sim,
        .retrieval => rt.num_div_points_fwhm_retr,
    };
    const strong_line_min_divisions = switch (kind) {
        .simulation => rt.num_div_points_min_sim,
        .retrieval => rt.num_div_points_min_retr,
    };
    const strong_line_max_divisions = switch (kind) {
        .simulation => rt.num_div_points_max_sim,
        .retrieval => rt.num_div_points_max_retr,
    };

    const any_present = points_per_fwhm != null or
        strong_line_min_divisions != null or
        strong_line_max_divisions != null;
    if (!any_present) return;
    if (points_per_fwhm == null or strong_line_min_divisions == null or strong_line_max_divisions == null) {
        return Error.InvalidValue;
    }
    if (points_per_fwhm.? > std.math.maxInt(u16) or
        strong_line_min_divisions.? > std.math.maxInt(u16) or
        strong_line_max_divisions.? > std.math.maxInt(u16))
    {
        return Error.InvalidValue;
    }

    observation_model.adaptive_reference_grid = .{
        .points_per_fwhm = @intCast(points_per_fwhm.?),
        .strong_line_min_divisions = @intCast(strong_line_min_divisions.?),
        .strong_line_max_divisions = @intCast(strong_line_max_divisions.?),
    };
}

fn decodeRrsRingConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?RrsRingConfig {
    const rrs_value = value orelse return null;
    const rrs_map = try expectMap(rrs_value);
    try ensureKnownFields(rrs_map, &.{ "sim", "retr" }, strict);

    var rrs: RrsRingConfig = .{};
    if (mapGet(rrs_map, "sim")) |v| rrs.sim = try decodeRrsPerBandSeq(allocator, v, strict);
    if (mapGet(rrs_map, "retr")) |v| rrs.retr = try decodeRrsPerBandSeq(allocator, v, strict);
    return rrs;
}

fn decodeRrsPerBandSeq(allocator: Allocator, value: yaml.Value, strict: bool) ![]const RrsRingConfig.PerBand {
    const seq = try expectSeq(value);
    const bands = try allocator.alloc(RrsRingConfig.PerBand, seq.len);
    for (seq, 0..) |entry, index| {
        const band_map = try expectMap(entry);
        try ensureKnownFields(band_map, &.{
            "use_rrs",
            "approximate_rrs",
            "fraction_raman_lines",
            "use_cabannes",
            "degree_poly",
            "include_absorption",
        }, strict);

        var band: RrsRingConfig.PerBand = .{};
        if (mapGet(band_map, "use_rrs")) |v| band.use_rrs = try expectBool(v);
        if (mapGet(band_map, "approximate_rrs")) |v| band.approximate_rrs = try expectBool(v);
        if (mapGet(band_map, "fraction_raman_lines")) |v| band.fraction_raman_lines = try expectF64(v);
        if (mapGet(band_map, "use_cabannes")) |v| band.use_cabannes = try expectBool(v);
        if (mapGet(band_map, "degree_poly")) |v| band.degree_poly = @intCast(try expectU64(v));
        if (mapGet(band_map, "include_absorption")) |v| band.include_absorption = try expectBool(v);
        bands[index] = band;
    }
    return bands;
}

fn decodeAdditionalOutputConfig(value: ?yaml.Value, strict: bool) !?AdditionalOutputConfig {
    const ao_value = value orelse return null;
    const ao_map = try expectMap(ao_value);
    try ensureKnownFields(ao_map, &.{
        "refl_hr_grid_sim",
        "refl_instr_grid_sim",
        "refl_deriv_hr_grid_sim",
        "refl_deriv_hr_grid_retr",
        "refl_deriv_instr_grid_sim",
        "refl_deriv_instr_grid_retr",
        "signal_to_noise_ratio",
        "contrib_refl_sim",
        "contrib_refl_retr",
        "alt_resolved_amf_sim",
        "alt_resolved_amf_retr",
        "absorption_xsec_sim",
        "absorption_xsec_retr",
        "ring_spectra",
        "diff_ring_spectra",
        "filling_in_spectra",
        "test_derivatives",
        "pol_correction_file",
    }, strict);

    var ao: AdditionalOutputConfig = .{};
    if (mapGet(ao_map, "refl_hr_grid_sim")) |v| ao.refl_hr_grid_sim = try expectBool(v);
    if (mapGet(ao_map, "refl_instr_grid_sim")) |v| ao.refl_instr_grid_sim = try expectBool(v);
    if (mapGet(ao_map, "refl_deriv_hr_grid_sim")) |v| ao.refl_deriv_hr_grid_sim = try expectBool(v);
    if (mapGet(ao_map, "refl_deriv_hr_grid_retr")) |v| ao.refl_deriv_hr_grid_retr = try expectBool(v);
    if (mapGet(ao_map, "refl_deriv_instr_grid_sim")) |v| ao.refl_deriv_instr_grid_sim = try expectBool(v);
    if (mapGet(ao_map, "refl_deriv_instr_grid_retr")) |v| ao.refl_deriv_instr_grid_retr = try expectBool(v);
    if (mapGet(ao_map, "signal_to_noise_ratio")) |v| ao.signal_to_noise_ratio = try expectBool(v);
    if (mapGet(ao_map, "contrib_refl_sim")) |v| ao.contrib_refl_sim = try expectBool(v);
    if (mapGet(ao_map, "contrib_refl_retr")) |v| ao.contrib_refl_retr = try expectBool(v);
    if (mapGet(ao_map, "alt_resolved_amf_sim")) |v| ao.alt_resolved_amf_sim = try expectBool(v);
    if (mapGet(ao_map, "alt_resolved_amf_retr")) |v| ao.alt_resolved_amf_retr = try expectBool(v);
    if (mapGet(ao_map, "absorption_xsec_sim")) |v| ao.absorption_xsec_sim = try expectBool(v);
    if (mapGet(ao_map, "absorption_xsec_retr")) |v| ao.absorption_xsec_retr = try expectBool(v);
    if (mapGet(ao_map, "ring_spectra")) |v| ao.ring_spectra = try expectBool(v);
    if (mapGet(ao_map, "diff_ring_spectra")) |v| ao.diff_ring_spectra = try expectBool(v);
    if (mapGet(ao_map, "filling_in_spectra")) |v| ao.filling_in_spectra = try expectBool(v);
    if (mapGet(ao_map, "test_derivatives")) |v| ao.test_derivatives = try expectBool(v);
    if (mapGet(ao_map, "pol_correction_file")) |v| ao.pol_correction_file = try expectBool(v);
    return ao;
}

fn decodeGeneralConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?GeneralConfig {
    const gc_value = value orelse return null;
    const gc_map = try expectMap(gc_value);
    try ensureKnownFields(gc_map, &.{
        "number_spectral_bands",
        "number_trace_gases",
        "simulation_only",
        "aerosol_layer_height",
        "fit_surface_albedo",
        "fit_aerosol_tau",
        "fit_cloud_tau",
        "fit_mul_offset",
        "fit_stray_light",
        "fit_temperature_offset",
        "fit_ln_cld_tau",
        "num_interval_fit",
        "useEffXsec_OE_sim",
        "useEffXsec_OE_retr",
        "usePolyExpXsecSim",
        "usePolyExpXsecRetr",
        "XsecStrongAbsSim",
        "XsecStrongAbsRetr",
        "degreePolySim",
        "degreePolyRetr",
        "simulation_method",
        "retrieval_method",
        "solar_irr_file_sim",
        "solar_irr_file_retr",
        "temperature_climatology",
        "ozone_climatology",
    }, strict);

    var gc: GeneralConfig = .{};
    if (mapGet(gc_map, "number_spectral_bands")) |v| gc.number_spectral_bands = @intCast(try expectU64(v));
    if (mapGet(gc_map, "number_trace_gases")) |v| gc.number_trace_gases = @intCast(try expectU64(v));
    if (mapGet(gc_map, "simulation_only")) |v| gc.simulation_only = try expectBool(v);
    if (mapGet(gc_map, "aerosol_layer_height")) |v| gc.aerosol_layer_height = try expectBool(v);
    if (mapGet(gc_map, "fit_surface_albedo")) |v| gc.fit_surface_albedo = try expectBool(v);
    if (mapGet(gc_map, "fit_aerosol_tau")) |v| gc.fit_aerosol_tau = try expectBool(v);
    if (mapGet(gc_map, "fit_cloud_tau")) |v| gc.fit_cloud_tau = try expectBool(v);
    if (mapGet(gc_map, "fit_mul_offset")) |v| gc.fit_mul_offset = try expectBool(v);
    if (mapGet(gc_map, "fit_stray_light")) |v| gc.fit_stray_light = try expectBool(v);
    if (mapGet(gc_map, "fit_temperature_offset")) |v| gc.fit_temperature_offset = try expectBool(v);
    if (mapGet(gc_map, "fit_ln_cld_tau")) |v| gc.fit_ln_cld_tau = try expectBool(v);
    if (mapGet(gc_map, "num_interval_fit")) |v| gc.num_interval_fit = @intCast(try expectU64(v));
    if (mapGet(gc_map, "useEffXsec_OE_sim")) |v| gc.use_eff_xsec_oe_sim = try expectBool(v);
    if (mapGet(gc_map, "useEffXsec_OE_retr")) |v| gc.use_eff_xsec_oe_retr = try expectBool(v);
    if (mapGet(gc_map, "usePolyExpXsecSim")) |v| gc.use_poly_exp_xsec_sim = try expectBool(v);
    if (mapGet(gc_map, "usePolyExpXsecRetr")) |v| gc.use_poly_exp_xsec_retr = try expectBool(v);
    if (mapGet(gc_map, "XsecStrongAbsSim")) |v| gc.xsec_strong_abs_sim = try decodeBoolSequence(allocator, v);
    if (mapGet(gc_map, "XsecStrongAbsRetr")) |v| gc.xsec_strong_abs_retr = try decodeBoolSequence(allocator, v);
    if (mapGet(gc_map, "degreePolySim")) |v| gc.degree_poly_sim = try decodeU32Sequence(allocator, v);
    if (mapGet(gc_map, "degreePolyRetr")) |v| gc.degree_poly_retr = try decodeU32Sequence(allocator, v);
    if (mapGet(gc_map, "simulation_method")) |v| gc.simulation_method = try fields.parseSimulationMethod(try expectString(v));
    if (mapGet(gc_map, "retrieval_method")) |v| gc.retrieval_method = try fields.parseRetrievalMethod(try expectString(v));
    if (mapGet(gc_map, "solar_irr_file_sim")) |v| gc.solar_irr_file_sim = try expectString(v);
    if (mapGet(gc_map, "solar_irr_file_retr")) |v| gc.solar_irr_file_retr = try expectString(v);
    if (mapGet(gc_map, "temperature_climatology")) |v| gc.temperature_climatology = try expectString(v);
    if (mapGet(gc_map, "ozone_climatology")) |v| gc.ozone_climatology = try expectString(v);
    return gc;
}

fn decodeInstrumentConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?InstrumentConfig {
    const ic_value = value orelse return null;
    const ic_map = try expectMap(ic_value);
    try ensureKnownFields(ic_map, &.{
        "bands",
        "add_noise_irr_sim",
        "add_noise_rad_sim",
    }, strict);

    var ic: InstrumentConfig = .{};
    if (mapGet(ic_map, "add_noise_irr_sim")) |v| ic.add_noise_irr_sim = try expectBool(v);
    if (mapGet(ic_map, "add_noise_rad_sim")) |v| ic.add_noise_rad_sim = try expectBool(v);
    if (mapGet(ic_map, "bands")) |v| ic.bands = try decodeInstrumentPerBandSeq(allocator, v, strict);
    return ic;
}

fn decodeInstrumentPerBandSeq(allocator: Allocator, value: yaml.Value, strict: bool) ![]const InstrumentConfig.PerBand {
    const seq = try expectSeq(value);
    const bands = try allocator.alloc(InstrumentConfig.PerBand, seq.len);
    for (seq, 0..) |entry, index| {
        const band_map = try expectMap(entry);
        try ensureKnownFields(band_map, &.{
            "wavelength_start",
            "wavelength_end",
            "wavelength_step",
            "exclude",
            "fwhm_irradiance_sim",
            "fwhm_irradiance_retr",
            "fwhm_radiance_sim",
            "fwhm_radiance_retr",
        }, strict);

        var band: InstrumentConfig.PerBand = .{};
        if (mapGet(band_map, "wavelength_start")) |v| band.wavelength_start = try expectF64(v);
        if (mapGet(band_map, "wavelength_end")) |v| band.wavelength_end = try expectF64(v);
        if (mapGet(band_map, "wavelength_step")) |v| band.wavelength_step = try expectF64(v);
        if (mapGet(band_map, "exclude")) |v| band.exclude = try decodeF64PairSequence(allocator, v);
        if (mapGet(band_map, "fwhm_irradiance_sim")) |v| band.fwhm_irradiance_sim = try expectF64(v);
        if (mapGet(band_map, "fwhm_irradiance_retr")) |v| band.fwhm_irradiance_retr = try expectF64(v);
        if (mapGet(band_map, "fwhm_radiance_sim")) |v| band.fwhm_radiance_sim = try expectF64(v);
        if (mapGet(band_map, "fwhm_radiance_retr")) |v| band.fwhm_radiance_retr = try expectF64(v);
        bands[index] = band;
    }
    return bands;
}

fn decodeGeometryConfig(value: ?yaml.Value, strict: bool) !?GeometryConfig {
    const geo_value = value orelse return null;
    const geo_map = try expectMap(geo_value);
    try ensureKnownFields(geo_map, &.{
        "solar_zenith_angle_sim",
        "solar_zenith_angle_retr",
        "solar_azimuth_angle_sim",
        "solar_azimuth_angle_retr",
        "instrument_nadir_angle_sim",
        "instrument_nadir_angle_retr",
        "instrument_azimuth_angle_sim",
        "instrument_azimuth_angle_retr",
    }, strict);

    var geo: GeometryConfig = .{};
    if (mapGet(geo_map, "solar_zenith_angle_sim")) |v| geo.solar_zenith_angle_sim = try expectF64(v);
    if (mapGet(geo_map, "solar_zenith_angle_retr")) |v| geo.solar_zenith_angle_retr = try expectF64(v);
    if (mapGet(geo_map, "solar_azimuth_angle_sim")) |v| geo.solar_azimuth_angle_sim = try expectF64(v);
    if (mapGet(geo_map, "solar_azimuth_angle_retr")) |v| geo.solar_azimuth_angle_retr = try expectF64(v);
    if (mapGet(geo_map, "instrument_nadir_angle_sim")) |v| geo.instrument_nadir_angle_sim = try expectF64(v);
    if (mapGet(geo_map, "instrument_nadir_angle_retr")) |v| geo.instrument_nadir_angle_retr = try expectF64(v);
    if (mapGet(geo_map, "instrument_azimuth_angle_sim")) |v| geo.instrument_azimuth_angle_sim = try expectF64(v);
    if (mapGet(geo_map, "instrument_azimuth_angle_retr")) |v| geo.instrument_azimuth_angle_retr = try expectF64(v);
    return geo;
}

fn decodePressureTemperatureConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?PressureTemperatureConfig {
    const pt_value = value orelse return null;
    const pt_map = try expectMap(pt_value);
    try ensureKnownFields(pt_map, &.{ "pt_sim", "pt_retr" }, strict);

    var pt: PressureTemperatureConfig = .{};
    if (mapGet(pt_map, "pt_sim")) |v| pt.pt_sim = try decodeF64PairSequence(allocator, v);
    if (mapGet(pt_map, "pt_retr")) |v| pt.pt_retr = try decodeF64PairSequence(allocator, v);
    return pt;
}

fn decodeSurfaceConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?SurfaceConfig {
    const sc_value = value orelse return null;
    const sc_map = try expectMap(sc_value);
    try ensureKnownFields(sc_map, &.{
        "surf_pressure_sim",
        "surf_pressure_retr",
        "surface_type_sim",
        "surface_type_retr",
        "surf_albedo_sim",
        "surf_albedo_retr",
        "var_surf_albedo_retr",
        "wavel_surf_albedo_sim",
        "surf_albedo_array_sim",
        "wavel_surf_albedo_retr",
        "surf_albedo_array_retr",
    }, strict);

    var sc: SurfaceConfig = .{};
    if (mapGet(sc_map, "surf_pressure_sim")) |v| sc.surf_pressure_sim = try expectF64(v);
    if (mapGet(sc_map, "surf_pressure_retr")) |v| sc.surf_pressure_retr = try expectF64(v);
    if (mapGet(sc_map, "surface_type_sim")) |v| sc.surface_type_sim = try fields.parseSurfaceType(try expectString(v));
    if (mapGet(sc_map, "surface_type_retr")) |v| sc.surface_type_retr = try fields.parseSurfaceType(try expectString(v));
    if (mapGet(sc_map, "surf_albedo_sim")) |v| sc.surf_albedo_sim = try expectF64(v);
    if (mapGet(sc_map, "surf_albedo_retr")) |v| sc.surf_albedo_retr = try expectF64(v);
    if (mapGet(sc_map, "var_surf_albedo_retr")) |v| sc.var_surf_albedo_retr = try expectF64(v);
    if (mapGet(sc_map, "wavel_surf_albedo_sim")) |v| sc.wavel_surf_albedo_sim = try decodeF64Sequence(allocator, v);
    if (mapGet(sc_map, "surf_albedo_array_sim")) |v| sc.surf_albedo_array_sim = try decodeF64Sequence(allocator, v);
    if (mapGet(sc_map, "wavel_surf_albedo_retr")) |v| sc.wavel_surf_albedo_retr = try decodeF64Sequence(allocator, v);
    if (mapGet(sc_map, "surf_albedo_array_retr")) |v| sc.surf_albedo_array_retr = try decodeF64Sequence(allocator, v);
    return sc;
}

fn decodeAtmosphericIntervalsConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?AtmosphericIntervalsConfig {
    const intervals_value = value orelse return null;
    const intervals_map = try expectMap(intervals_value);
    try ensureKnownFields(intervals_map, &.{ "sim", "retr" }, strict);

    var config: AtmosphericIntervalsConfig = .{};
    if (mapGet(intervals_map, "sim")) |sim| config.sim = try decodeAtmosphericIntervalEntrySeq(allocator, sim, strict);
    if (mapGet(intervals_map, "retr")) |retr| config.retr = try decodeAtmosphericIntervalEntrySeq(allocator, retr, strict);
    return config;
}

fn decodeAtmosphericIntervalEntrySeq(allocator: Allocator, value: yaml.Value, strict: bool) ![]const AtmosphericIntervalsConfig.IntervalEntry {
    const seq = try expectSeq(value);
    const entries = try allocator.alloc(AtmosphericIntervalsConfig.IntervalEntry, seq.len);
    for (seq, 0..) |entry, index| {
        const interval_map = try expectMap(entry);
        try ensureKnownFields(interval_map, &.{
            "top_pressure_hpa",
            "bottom_pressure_hpa",
            "top_altitude_km",
            "bottom_altitude_km",
            "top_pressure_variance_hpa2",
            "bottom_pressure_variance_hpa2",
            "altitude_divisions",
        }, strict);

        var interval: AtmosphericIntervalsConfig.IntervalEntry = .{
            .top_pressure_hpa = try expectF64(requiredField(interval_map, "top_pressure_hpa")),
            .bottom_pressure_hpa = try expectF64(requiredField(interval_map, "bottom_pressure_hpa")),
        };
        if (mapGet(interval_map, "top_altitude_km")) |v| interval.top_altitude_km = try expectF64(v);
        if (mapGet(interval_map, "bottom_altitude_km")) |v| interval.bottom_altitude_km = try expectF64(v);
        if (mapGet(interval_map, "top_pressure_variance_hpa2")) |v| interval.top_pressure_variance_hpa2 = try expectF64(v);
        if (mapGet(interval_map, "bottom_pressure_variance_hpa2")) |v| interval.bottom_pressure_variance_hpa2 = try expectF64(v);
        if (mapGet(interval_map, "altitude_divisions")) |v| interval.altitude_divisions = @intCast(try expectU64(v));
        entries[index] = interval;
    }
    return entries;
}

fn decodeCloudAerosolFractionConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?CloudAerosolFractionConfig {
    const fraction_value = value orelse return null;
    const fraction_map = try expectMap(fraction_value);
    try ensureKnownFields(fraction_map, &.{
        "target_sim",
        "target_retr",
        "kind_sim",
        "kind_retr",
        "values_sim",
        "values_retr",
        "apriori_values_retr",
        "variance_values_retr",
        "wavelengths_sim_nm",
        "wavelengths_retr_nm",
        "threshold_cloud_fraction",
        "threshold_variance",
    }, strict);

    var config: CloudAerosolFractionConfig = .{};
    if (mapGet(fraction_map, "target_sim")) |v| config.target_sim = try parseFractionTarget(try expectString(v));
    if (mapGet(fraction_map, "target_retr")) |v| config.target_retr = try parseFractionTarget(try expectString(v));
    if (mapGet(fraction_map, "kind_sim")) |v| config.kind_sim = try parseFractionKind(try expectString(v));
    if (mapGet(fraction_map, "kind_retr")) |v| config.kind_retr = try parseFractionKind(try expectString(v));
    if (mapGet(fraction_map, "values_sim")) |v| config.values_sim = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "values_retr")) |v| config.values_retr = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "apriori_values_retr")) |v| config.apriori_values_retr = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "variance_values_retr")) |v| config.variance_values_retr = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "wavelengths_sim_nm")) |v| config.wavelengths_sim_nm = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "wavelengths_retr_nm")) |v| config.wavelengths_retr_nm = try decodeF64Sequence(allocator, v);
    if (mapGet(fraction_map, "threshold_cloud_fraction")) |v| config.threshold_cloud_fraction = try expectF64(v);
    if (mapGet(fraction_map, "threshold_variance")) |v| config.threshold_variance = try expectF64(v);
    return config;
}

fn decodeCloudConfig(value: ?yaml.Value, strict: bool) !?CloudConfig {
    const cc_value = value orelse return null;
    const cc_map = try expectMap(cc_value);
    try ensureKnownFields(cc_map, &.{
        "cloud_type_sim",
        "cloud_type_retr",
        "hg_optical_thickness_sim",
        "hg_angstrom_coefficient_sim",
        "hg_single_scattering_albedo_sim",
        "hg_parameter_g_sim",
        "hg_optical_thickness_retr",
        "mie_optical_thickness_sim",
        "mie_optical_thickness_retr",
    }, strict);

    var cc: CloudConfig = .{};
    if (mapGet(cc_map, "cloud_type_sim")) |v| cc.cloud_type_sim = try fields.parseCloudType(try expectString(v));
    if (mapGet(cc_map, "cloud_type_retr")) |v| cc.cloud_type_retr = try fields.parseCloudType(try expectString(v));
    if (mapGet(cc_map, "hg_optical_thickness_sim")) |v| cc.hg_optical_thickness_sim = try expectF64(v);
    if (mapGet(cc_map, "hg_angstrom_coefficient_sim")) |v| cc.hg_angstrom_coefficient_sim = try expectF64(v);
    if (mapGet(cc_map, "hg_single_scattering_albedo_sim")) |v| cc.hg_single_scattering_albedo_sim = try expectF64(v);
    if (mapGet(cc_map, "hg_parameter_g_sim")) |v| cc.hg_parameter_g_sim = try expectF64(v);
    if (mapGet(cc_map, "hg_optical_thickness_retr")) |v| cc.hg_optical_thickness_retr = try expectF64(v);
    if (mapGet(cc_map, "mie_optical_thickness_sim")) |v| cc.mie_optical_thickness_sim = try expectF64(v);
    if (mapGet(cc_map, "mie_optical_thickness_retr")) |v| cc.mie_optical_thickness_retr = try expectF64(v);
    return cc;
}

fn decodeAerosolConfig(value: ?yaml.Value, strict: bool) !?AerosolConfig {
    const ac_value = value orelse return null;
    const ac_map = try expectMap(ac_value);
    try ensureKnownFields(ac_map, &.{
        "aerosol_type_sim",
        "aerosol_type_retr",
        "hg_optical_thickness_sim",
        "hg_angstrom_coefficient_sim",
        "hg_single_scattering_albedo_sim",
        "hg_parameter_g_sim",
        "hg_optical_thickness_retr",
        "mie_optical_thickness_sim",
        "mie_optical_thickness_retr",
    }, strict);

    var ac: AerosolConfig = .{};
    if (mapGet(ac_map, "aerosol_type_sim")) |v| ac.aerosol_type_sim = try fields.parseAerosolType(try expectString(v));
    if (mapGet(ac_map, "aerosol_type_retr")) |v| ac.aerosol_type_retr = try fields.parseAerosolType(try expectString(v));
    if (mapGet(ac_map, "hg_optical_thickness_sim")) |v| ac.hg_optical_thickness_sim = try expectF64(v);
    if (mapGet(ac_map, "hg_angstrom_coefficient_sim")) |v| ac.hg_angstrom_coefficient_sim = try expectF64(v);
    if (mapGet(ac_map, "hg_single_scattering_albedo_sim")) |v| ac.hg_single_scattering_albedo_sim = try expectF64(v);
    if (mapGet(ac_map, "hg_parameter_g_sim")) |v| ac.hg_parameter_g_sim = try expectF64(v);
    if (mapGet(ac_map, "hg_optical_thickness_retr")) |v| ac.hg_optical_thickness_retr = try expectF64(v);
    if (mapGet(ac_map, "mie_optical_thickness_sim")) |v| ac.mie_optical_thickness_sim = try expectF64(v);
    if (mapGet(ac_map, "mie_optical_thickness_retr")) |v| ac.mie_optical_thickness_retr = try expectF64(v);
    return ac;
}

fn decodeSubcolumnsConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?SubcolumnsConfig {
    const subcolumns_value = value orelse return null;
    const subcolumns_map = try expectMap(subcolumns_value);
    try ensureKnownFields(subcolumns_map, &.{
        "enabled",
        "boundary_layer_top_pressure_hpa",
        "boundary_layer_top_altitude_km",
        "tropopause_pressure_hpa",
        "tropopause_altitude_km",
        "entries",
    }, strict);

    var config: SubcolumnsConfig = .{};
    if (mapGet(subcolumns_map, "enabled")) |v| config.enabled = try expectBool(v);
    if (mapGet(subcolumns_map, "boundary_layer_top_pressure_hpa")) |v| config.boundary_layer_top_pressure_hpa = try expectF64(v);
    if (mapGet(subcolumns_map, "boundary_layer_top_altitude_km")) |v| config.boundary_layer_top_altitude_km = try expectF64(v);
    if (mapGet(subcolumns_map, "tropopause_pressure_hpa")) |v| config.tropopause_pressure_hpa = try expectF64(v);
    if (mapGet(subcolumns_map, "tropopause_altitude_km")) |v| config.tropopause_altitude_km = try expectF64(v);
    if (mapGet(subcolumns_map, "entries")) |v| config.entries = try decodeSubcolumnEntrySeq(allocator, v, strict);
    return config;
}

fn decodeSubcolumnEntrySeq(allocator: Allocator, value: yaml.Value, strict: bool) ![]const SubcolumnsConfig.Entry {
    const seq = try expectSeq(value);
    const entries = try allocator.alloc(SubcolumnsConfig.Entry, seq.len);
    for (seq, 0..) |entry, index| {
        const subcolumn_map = try expectMap(entry);
        try ensureKnownFields(subcolumn_map, &.{
            "label",
            "bottom_altitude_km",
            "top_altitude_km",
            "gaussian_nodes",
            "gaussian_weights",
        }, strict);

        var decoded: SubcolumnsConfig.Entry = .{};
        if (mapGet(subcolumn_map, "label")) |v| decoded.label = try parsePartitionLabel(try expectString(v));
        if (mapGet(subcolumn_map, "bottom_altitude_km")) |v| decoded.bottom_altitude_km = try expectF64(v);
        if (mapGet(subcolumn_map, "top_altitude_km")) |v| decoded.top_altitude_km = try expectF64(v);
        if (mapGet(subcolumn_map, "gaussian_nodes")) |v| decoded.gaussian_nodes = try decodeF64Sequence(allocator, v);
        if (mapGet(subcolumn_map, "gaussian_weights")) |v| decoded.gaussian_weights = try decodeF64Sequence(allocator, v);
        entries[index] = decoded;
    }
    return entries;
}

fn decodeRetrievalConfig(value: ?yaml.Value, strict: bool) !?RetrievalConfig {
    const rc_value = value orelse return null;
    const rc_map = try expectMap(rc_value);
    try ensureKnownFields(rc_map, &.{
        "max_num_iterations",
        "state_vector_conv_threshold",
    }, strict);

    var rc: RetrievalConfig = .{};
    if (mapGet(rc_map, "max_num_iterations")) |v| rc.max_num_iterations = @intCast(try expectU64(v));
    if (mapGet(rc_map, "state_vector_conv_threshold")) |v| rc.state_vector_conv_threshold = try expectF64(v);
    return rc;
}

fn decodeAbsorbingGasConfig(allocator: Allocator, value: ?yaml.Value, strict: bool) !?AbsorbingGasConfig {
    const ag_value = value orelse return null;
    const ag_map = try expectMap(ag_value);
    try ensureKnownFields(ag_map, &.{"gases"}, strict);

    var ag: AbsorbingGasConfig = .{};
    if (mapGet(ag_map, "gases")) |v| ag.gases = try decodeGasEntrySeq(allocator, v, strict);
    return ag;
}

fn decodeGasEntrySeq(allocator: Allocator, value: yaml.Value, strict: bool) ![]const AbsorbingGasConfig.GasEntry {
    const seq = try expectSeq(value);
    const entries = try allocator.alloc(AbsorbingGasConfig.GasEntry, seq.len);
    for (seq, 0..) |entry, index| {
        const gas_map = try expectMap(entry);
        try ensureKnownFields(gas_map, &.{
            "species",
            "xsection_file_sim",
            "xsection_file_retr",
            "fit_column",
            "profile_sim",
            "hitran",
        }, strict);

        var ge: AbsorbingGasConfig.GasEntry = .{};
        if (mapGet(gas_map, "species")) |v| ge.species = try fields.parseAbsorberSpecies(try expectString(v));
        if (mapGet(gas_map, "xsection_file_sim")) |v| ge.xsection_file_sim = try expectString(v);
        if (mapGet(gas_map, "xsection_file_retr")) |v| ge.xsection_file_retr = try expectString(v);
        if (mapGet(gas_map, "fit_column")) |v| ge.fit_column = try expectBool(v);
        if (mapGet(gas_map, "profile_sim")) |v| ge.profile_sim = try decodeF64PairSequence(allocator, v);
        if (mapGet(gas_map, "hitran")) |v| ge.hitran = try decodeGasHitranConfig(allocator, v, strict);
        entries[index] = ge;
    }
    return entries;
}

fn decodeGasHitranConfig(allocator: Allocator, value: yaml.Value, strict: bool) !AbsorbingGasConfig.Hitran {
    const hitran_map = try expectMap(value);
    try ensureKnownFields(hitran_map, &.{
        "factor_lm_sim",
        "factor_lm_retr",
        "isotopes_sim",
        "isotopes_retr",
        "threshold_line_sim",
        "threshold_line_retr",
        "cutoff_sim_cm1",
        "cutoff_retr_cm1",
    }, strict);

    var hitran: AbsorbingGasConfig.Hitran = .{};
    if (mapGet(hitran_map, "factor_lm_sim")) |v| hitran.factor_lm_sim = try expectF64(v);
    if (mapGet(hitran_map, "factor_lm_retr")) |v| hitran.factor_lm_retr = try expectF64(v);
    if (mapGet(hitran_map, "isotopes_sim")) |v| hitran.isotopes_sim = try decodeU8Sequence(allocator, v);
    if (mapGet(hitran_map, "isotopes_retr")) |v| hitran.isotopes_retr = try decodeU8Sequence(allocator, v);
    if (mapGet(hitran_map, "threshold_line_sim")) |v| hitran.threshold_line_sim = try expectF64(v);
    if (mapGet(hitran_map, "threshold_line_retr")) |v| hitran.threshold_line_retr = try expectF64(v);
    if (mapGet(hitran_map, "cutoff_sim_cm1")) |v| hitran.cutoff_sim_cm1 = try expectF64(v);
    if (mapGet(hitran_map, "cutoff_retr_cm1")) |v| hitran.cutoff_retr_cm1 = try expectF64(v);
    return hitran;
}

/// Decode a YAML sequence of 2-element sub-sequences into a slice of f64 pairs.
fn decodeF64PairSequence(allocator: Allocator, value: yaml.Value) ![]const [2]f64 {
    const seq = try expectSeq(value);
    const result = try allocator.alloc([2]f64, seq.len);
    for (seq, 0..) |entry, index| {
        const pair = try expectSeq(entry);
        if (pair.len != 2) return Error.InvalidValue;
        result[index] = .{ try expectF64(pair[0]), try expectF64(pair[1]) };
    }
    return result;
}

/// Decode a YAML sequence of scalars into a slice of f64.
fn decodeF64Sequence(allocator: Allocator, value: yaml.Value) ![]const f64 {
    const seq = try expectSeq(value);
    const result = try allocator.alloc(f64, seq.len);
    for (seq, 0..) |entry, index| {
        result[index] = try expectF64(entry);
    }
    return result;
}

fn decodeU32Sequence(allocator: Allocator, value: yaml.Value) ![]const u32 {
    const seq = try expectSeq(value);
    const result = try allocator.alloc(u32, seq.len);
    for (seq, 0..) |entry, index| {
        result[index] = @intCast(try expectU64(entry));
    }
    return result;
}

fn decodeBoolSequence(allocator: Allocator, value: yaml.Value) ![]const bool {
    const seq = try expectSeq(value);
    const result = try allocator.alloc(bool, seq.len);
    for (seq, 0..) |entry, index| {
        result[index] = try expectBool(entry);
    }
    return result;
}

fn decodeU8Sequence(allocator: Allocator, value: yaml.Value) ![]const u8 {
    const seq = try expectSeq(value);
    const result = try allocator.alloc(u8, seq.len);
    for (seq, 0..) |entry, index| {
        result[index] = @intCast(try expectU64(entry));
    }
    return result;
}

fn applyGeometryConfigToScene(
    kind: StageKind,
    config: ?GeometryConfig,
    geometry: *Geometry,
) !void {
    const geo = config orelse return;
    switch (kind) {
        .simulation => {
            if (geo.solar_zenith_angle_sim) |v| geometry.solar_zenith_deg = v;
            if (geo.instrument_nadir_angle_sim) |v| geometry.viewing_zenith_deg = v;
            if (geo.instrument_azimuth_angle_sim) |instrument_azimuth| {
                const solar_azimuth = geo.solar_azimuth_angle_sim orelse 0.0;
                geometry.relative_azimuth_deg = normalizeRelativeAzimuthDeg(instrument_azimuth - solar_azimuth);
            } else if (geo.solar_azimuth_angle_sim) |solar_azimuth| {
                geometry.relative_azimuth_deg = normalizeRelativeAzimuthDeg(geometry.relative_azimuth_deg - solar_azimuth);
            }
        },
        .retrieval => {
            if (geo.solar_zenith_angle_retr) |v| geometry.solar_zenith_deg = v;
            if (geo.instrument_nadir_angle_retr) |v| geometry.viewing_zenith_deg = v;
            if (geo.instrument_azimuth_angle_retr) |instrument_azimuth| {
                const solar_azimuth = geo.solar_azimuth_angle_retr orelse 0.0;
                geometry.relative_azimuth_deg = normalizeRelativeAzimuthDeg(instrument_azimuth - solar_azimuth);
            } else if (geo.solar_azimuth_angle_retr) |solar_azimuth| {
                geometry.relative_azimuth_deg = normalizeRelativeAzimuthDeg(geometry.relative_azimuth_deg - solar_azimuth);
            }
        },
    }
}

fn normalizeRelativeAzimuthDeg(value_deg: f64) f64 {
    const wrapped = @mod(value_deg, 360.0);
    return if (wrapped < 0.0) wrapped + 360.0 else wrapped;
}

fn applyPressureTemperatureConfigToScene(
    kind: StageKind,
    config: ?PressureTemperatureConfig,
    scene: *Scene,
) !void {
    const pt = config orelse return;
    const profile = switch (kind) {
        .simulation => pt.pt_sim,
        .retrieval => pt.pt_retr,
    } orelse return;
    if (profile.len == 0) return;

    var max_pressure_hpa: f64 = 0.0;
    for (profile) |entry| {
        if (entry[0] > max_pressure_hpa) max_pressure_hpa = entry[0];
    }
    if (max_pressure_hpa > 0.0) {
        if (scene.atmosphere.surface_pressure_hpa == 0.0) scene.atmosphere.surface_pressure_hpa = max_pressure_hpa;
        if (scene.surface.pressure_hpa == 0.0) scene.surface.pressure_hpa = max_pressure_hpa;
    }
}

fn applySurfaceConfigToScene(
    kind: StageKind,
    config: ?SurfaceConfig,
    scene: *Scene,
) !void {
    const surface_config = config orelse return;
    const surface_type = switch (kind) {
        .simulation => surface_config.surface_type_sim,
        .retrieval => surface_config.surface_type_retr,
    };
    if (surface_type) |value| {
        scene.surface.kind = switch (value) {
            .wavel_independent => .lambertian,
            .wavel_dependent => .wavel_dependent,
        };
    }

    const pressure_hpa = switch (kind) {
        .simulation => surface_config.surf_pressure_sim,
        .retrieval => surface_config.surf_pressure_retr,
    };
    if (pressure_hpa) |value| {
        scene.surface.pressure_hpa = value;
        scene.atmosphere.surface_pressure_hpa = value;
    }

    const albedo = switch (kind) {
        .simulation => surface_config.surf_albedo_sim,
        .retrieval => surface_config.surf_albedo_retr,
    };
    if (albedo) |value| scene.surface.albedo = value;
}

fn applyAtmosphericIntervalsConfigToScene(
    allocator: Allocator,
    kind: StageKind,
    general: ?GeneralConfig,
    radiative_transfer: ?RadiativeTransferConfig,
    config: ?AtmosphericIntervalsConfig,
    scene: *Scene,
) !void {
    const intervals_config = config orelse return;
    const interval_entries = switch (kind) {
        .simulation => intervals_config.sim,
        .retrieval => intervals_config.retr,
    } orelse return;
    if (interval_entries.len == 0) return;

    const intervals = try allocator.alloc(AtmosphereModel.VerticalInterval, interval_entries.len);
    for (interval_entries, 0..) |entry, index| {
        const default_divisions = stageIntervalDivisions(kind, radiative_transfer, index, scene.atmosphere.sublayer_divisions);
        intervals[index] = .{
            .index_1based = @intCast(index + 1),
            .top_pressure_hpa = entry.top_pressure_hpa,
            .bottom_pressure_hpa = entry.bottom_pressure_hpa,
            .top_altitude_km = entry.top_altitude_km orelse std.math.nan(f64),
            .bottom_altitude_km = entry.bottom_altitude_km orelse std.math.nan(f64),
            .top_pressure_variance_hpa2 = entry.top_pressure_variance_hpa2 orelse 0.0,
            .bottom_pressure_variance_hpa2 = entry.bottom_pressure_variance_hpa2 orelse 0.0,
            .altitude_divisions = entry.altitude_divisions orelse default_divisions,
        };
    }

    scene.atmosphere.interval_grid = .{
        .semantics = .explicit_pressure_bounds,
        .fit_interval_index_1based = if (general) |resolved_general| resolved_general.num_interval_fit orelse 0 else 0,
        .intervals = intervals,
        .owns_intervals = true,
    };
    scene.atmosphere.layer_count = @intCast(intervals.len);

    if (scene.atmosphere.surface_pressure_hpa == 0.0) {
        scene.atmosphere.surface_pressure_hpa = intervals[intervals.len - 1].bottom_pressure_hpa;
    }
    if (scene.surface.pressure_hpa == 0.0 and scene.atmosphere.surface_pressure_hpa > 0.0) {
        scene.surface.pressure_hpa = scene.atmosphere.surface_pressure_hpa;
    }
    if (scene.geometry.surface_altitude_km == 0.0 and intervals[intervals.len - 1].bottom_altitude_km > 0.0) {
        scene.geometry.surface_altitude_km = intervals[intervals.len - 1].bottom_altitude_km;
    }
}

fn fractionConfigHasStageInputs(kind: StageKind, config: CloudAerosolFractionConfig) bool {
    return switch (kind) {
        .simulation => config.kind_sim != .none or
            config.values_sim != null or
            config.wavelengths_sim_nm != null,
        .retrieval => config.kind_retr != .none or
            config.values_retr != null or
            config.apriori_values_retr != null or
            config.variance_values_retr != null or
            config.wavelengths_retr_nm != null,
    };
}

fn applyCloudAerosolFractionConfigToScene(
    kind: StageKind,
    config: ?CloudAerosolFractionConfig,
    scene: *Scene,
) !void {
    const fraction_config = config orelse return;
    const target = switch (kind) {
        .simulation => fraction_config.target_sim,
        .retrieval => fraction_config.target_retr,
    };
    if (target == null) {
        if (fractionConfigHasStageInputs(kind, fraction_config)) return Error.InvalidValue;
        return;
    }
    if (target.? == .none) return;
    const fraction_kind = switch (kind) {
        .simulation => fraction_config.kind_sim,
        .retrieval => fraction_config.kind_retr,
    };

    const values = switch (kind) {
        .simulation => fraction_config.values_sim,
        .retrieval => fraction_config.values_retr orelse fraction_config.apriori_values_retr,
    } orelse return Error.InvalidValue;
    const wavelengths_nm = switch (kind) {
        .simulation => fraction_config.wavelengths_sim_nm orelse &.{},
        .retrieval => fraction_config.wavelengths_retr_nm orelse &.{},
    };
    const control: AtmosphereModel.FractionControl = .{
        .enabled = true,
        .target = target.?,
        .kind = fraction_kind,
        .threshold_cloud_fraction = fraction_config.threshold_cloud_fraction orelse 0.0,
        .threshold_variance = fraction_config.threshold_variance orelse 0.0,
        .wavelengths_nm = wavelengths_nm,
        .values = values,
        .apriori_values = if (kind == .retrieval) fraction_config.apriori_values_retr orelse &.{} else &.{},
        .variance_values = if (kind == .retrieval) fraction_config.variance_values_retr orelse &.{} else &.{},
        .owns_arrays = false,
    };

    switch (target.?) {
        .cloud => scene.cloud.fraction = control,
        .aerosol => scene.aerosol.fraction = control,
        .none => unreachable,
    }
}

fn applyCloudConfigToScene(
    kind: StageKind,
    config: ?CloudConfig,
    scene: *Scene,
) !void {
    const cloud_config = config orelse return;
    const fit_interval = scene.atmosphere.interval_grid.fitInterval();
    const cloud_type = switch (kind) {
        .simulation => cloud_config.cloud_type_sim,
        .retrieval => cloud_config.cloud_type_retr,
    };
    const hg_optical_thickness = switch (kind) {
        .simulation => cloud_config.hg_optical_thickness_sim,
        .retrieval => cloud_config.hg_optical_thickness_retr,
    };
    const mie_optical_thickness = switch (kind) {
        .simulation => cloud_config.mie_optical_thickness_sim,
        .retrieval => cloud_config.mie_optical_thickness_retr,
    };

    if (cloud_type) |value| {
        scene.cloud.cloud_type = value;
        scene.cloud.enabled = value != .none;
    }
    if (hg_optical_thickness) |value| {
        scene.cloud.enabled = true;
        scene.cloud.optical_thickness = value;
        if (kind == .simulation) {
            scene.cloud.single_scatter_albedo = cloud_config.hg_single_scattering_albedo_sim orelse scene.cloud.single_scatter_albedo;
            scene.cloud.asymmetry_factor = cloud_config.hg_parameter_g_sim orelse scene.cloud.asymmetry_factor;
            scene.cloud.angstrom_exponent = cloud_config.hg_angstrom_coefficient_sim orelse scene.cloud.angstrom_exponent;
            if (scene.cloud.cloud_type == .none) scene.cloud.cloud_type = .hg_scattering;
        }
    }
    if (mie_optical_thickness) |value| {
        scene.cloud.enabled = true;
        scene.cloud.optical_thickness = value;
        if (scene.cloud.cloud_type == .none) scene.cloud.cloud_type = .mie_scattering;
    }
    if (scene.cloud.enabled) {
        if (scene.cloud.id.len == 0) scene.cloud.id = "vendor_cloud";
        if (fit_interval) |interval| scene.cloud.placement = placementForInterval(interval);
    }
    scene.atmosphere.has_clouds = scene.cloud.enabled;
}

fn applyAerosolConfigToScene(
    kind: StageKind,
    config: ?AerosolConfig,
    scene: *Scene,
) !void {
    const aerosol_config = config orelse return;
    const fit_interval = scene.atmosphere.interval_grid.fitInterval();
    const aerosol_type = switch (kind) {
        .simulation => aerosol_config.aerosol_type_sim,
        .retrieval => aerosol_config.aerosol_type_retr,
    };
    const hg_optical_thickness = switch (kind) {
        .simulation => aerosol_config.hg_optical_thickness_sim,
        .retrieval => aerosol_config.hg_optical_thickness_retr,
    };
    const mie_optical_thickness = switch (kind) {
        .simulation => aerosol_config.mie_optical_thickness_sim,
        .retrieval => aerosol_config.mie_optical_thickness_retr,
    };

    if (aerosol_type) |value| {
        scene.aerosol.aerosol_type = value;
        scene.aerosol.enabled = value != .none;
    }
    if (hg_optical_thickness) |value| {
        scene.aerosol.enabled = true;
        scene.aerosol.optical_depth = value;
        if (kind == .simulation) {
            scene.aerosol.single_scatter_albedo = aerosol_config.hg_single_scattering_albedo_sim orelse scene.aerosol.single_scatter_albedo;
            scene.aerosol.asymmetry_factor = aerosol_config.hg_parameter_g_sim orelse scene.aerosol.asymmetry_factor;
            scene.aerosol.angstrom_exponent = aerosol_config.hg_angstrom_coefficient_sim orelse scene.aerosol.angstrom_exponent;
            if (scene.aerosol.aerosol_type == .none) scene.aerosol.aerosol_type = .hg_scattering;
        }
    }
    if (mie_optical_thickness) |value| {
        scene.aerosol.enabled = true;
        scene.aerosol.optical_depth = value;
        if (scene.aerosol.aerosol_type == .none) scene.aerosol.aerosol_type = .mie_scattering;
    }
    if (scene.aerosol.enabled) {
        if (scene.aerosol.id.len == 0) scene.aerosol.id = "vendor_aerosol";
        if (fit_interval) |interval| scene.aerosol.placement = placementForInterval(interval);
    }
    scene.atmosphere.has_aerosols = scene.aerosol.enabled;
}

fn applySubcolumnsConfigToScene(
    allocator: Allocator,
    config: ?SubcolumnsConfig,
    scene: *Scene,
) !void {
    const subcolumns_config = config orelse return;
    if (!subcolumns_config.enabled) return;

    const decoded_entries = subcolumns_config.entries orelse return Error.InvalidValue;
    const subcolumns = try allocator.alloc(AtmosphereModel.Subcolumn, decoded_entries.len);
    for (decoded_entries, 0..) |entry, index| {
        subcolumns[index] = .{
            .index_1based = @intCast(index + 1),
            .label = entry.label,
            .bottom_altitude_km = entry.bottom_altitude_km orelse 0.0,
            .top_altitude_km = entry.top_altitude_km orelse 0.0,
            .gaussian_nodes = entry.gaussian_nodes orelse &.{},
            .gaussian_weights = entry.gaussian_weights orelse &.{},
            .owns_arrays = false,
        };
    }

    scene.atmosphere.subcolumns = .{
        .enabled = true,
        .boundary_layer_top_pressure_hpa = subcolumns_config.boundary_layer_top_pressure_hpa orelse 0.0,
        .boundary_layer_top_altitude_km = subcolumns_config.boundary_layer_top_altitude_km orelse 0.0,
        .tropopause_pressure_hpa = subcolumns_config.tropopause_pressure_hpa orelse 0.0,
        .tropopause_altitude_km = subcolumns_config.tropopause_altitude_km orelse 0.0,
        .subcolumns = subcolumns,
        .owns_subcolumns = true,
    };
}

fn applyAbsorbingGasConfigToScene(
    allocator: Allocator,
    kind: StageKind,
    config: ?AbsorbingGasConfig,
    scene: *Scene,
) !void {
    const active_stage: SpectroscopyStage = switch (kind) {
        .simulation => .simulation,
        .retrieval => .retrieval,
    };

    for (0..scene.absorbers.items.len) |index| {
        const absorber = @constCast(&scene.absorbers.items[index]);
        if (absorber.resolved_species) |species| {
            if (species.isLineAbsorbing()) {
                absorber.spectroscopy.line_gas_controls.active_stage = active_stage;
            }
        }
    }

    const gases = if (config) |absorbing_gas|
        absorbing_gas.gases orelse return
    else
        return;

    for (gases) |entry| {
        const species = entry.species orelse return Error.InvalidValue;
        if (!species.isLineAbsorbing()) continue;

        const absorber = findAbsorberForSpecies(scene.absorbers, species) orelse return Error.InvalidValue;
        if (active_stage == .simulation) {
            if (entry.profile_sim) |profile_ppmv| {
                absorber.volume_mixing_ratio_profile_ppmv = try allocator.dupe([2]f64, profile_ppmv);
            }
        }
        const hitran = entry.hitran orelse continue;
        const isotopes_sim = if (hitran.isotopes_sim) |values| try allocator.dupe(u8, values) else &.{};
        errdefer if (hitran.isotopes_sim != null) allocator.free(isotopes_sim);
        const isotopes_retr = if (hitran.isotopes_retr) |values| try allocator.dupe(u8, values) else &.{};
        errdefer if (hitran.isotopes_retr != null) allocator.free(isotopes_retr);

        absorber.spectroscopy.line_gas_controls.deinitOwned(allocator);
        absorber.spectroscopy.line_gas_controls = LineGasControls{
            .factor_lm_sim = hitran.factor_lm_sim,
            .factor_lm_retr = hitran.factor_lm_retr,
            .isotopes_sim = isotopes_sim,
            .isotopes_retr = isotopes_retr,
            .threshold_line_sim = hitran.threshold_line_sim,
            .threshold_line_retr = hitran.threshold_line_retr,
            .cutoff_sim_cm1 = hitran.cutoff_sim_cm1,
            .cutoff_retr_cm1 = hitran.cutoff_retr_cm1,
            .active_stage = active_stage,
        };
    }
}

fn applyGeneralConfigToObservationModel(
    allocator: Allocator,
    kind: StageKind,
    config: ?GeneralConfig,
    scene: *Scene,
) !void {
    const general = config orelse return;
    const strong_absorption_bands = switch (kind) {
        .simulation => general.xsec_strong_abs_sim,
        .retrieval => general.xsec_strong_abs_retr,
    };
    const polynomial_degree_bands = switch (kind) {
        .simulation => general.degree_poly_sim,
        .retrieval => general.degree_poly_retr,
    };

    const owned_strong_absorption_bands = if (strong_absorption_bands) |values|
        try allocator.dupe(bool, values)
    else
        &.{};
    errdefer if (owned_strong_absorption_bands.len != 0) allocator.free(owned_strong_absorption_bands);

    const owned_polynomial_degree_bands = if (polynomial_degree_bands) |values|
        try allocator.dupe(u32, values)
    else
        &.{};
    errdefer if (owned_polynomial_degree_bands.len != 0) allocator.free(owned_polynomial_degree_bands);

    scene.observation_model.cross_section_fit = CrossSectionFitControls{
        .use_effective_cross_section_oe = switch (kind) {
            .simulation => general.use_eff_xsec_oe_sim,
            .retrieval => general.use_eff_xsec_oe_retr,
        },
        .use_polynomial_expansion = switch (kind) {
            .simulation => general.use_poly_exp_xsec_sim,
            .retrieval => general.use_poly_exp_xsec_retr,
        },
        .xsec_strong_absorption_bands = owned_strong_absorption_bands,
        .polynomial_degree_bands = owned_polynomial_degree_bands,
    };
}

fn placementForInterval(interval: AtmosphereModel.VerticalInterval) AtmosphereModel.IntervalPlacement {
    return .{
        .semantics = .explicit_interval_bounds,
        .interval_index_1based = interval.index_1based,
        .top_pressure_hpa = interval.top_pressure_hpa,
        .bottom_pressure_hpa = interval.bottom_pressure_hpa,
        .top_altitude_km = interval.top_altitude_km,
        .bottom_altitude_km = interval.bottom_altitude_km,
    };
}

fn stageIntervalDivisions(
    kind: StageKind,
    radiative_transfer: ?RadiativeTransferConfig,
    index: usize,
    fallback: u8,
) u32 {
    const rt = radiative_transfer orelse return fallback;
    const values = switch (kind) {
        .simulation => rt.num_div_points_alt_sim,
        .retrieval => rt.num_div_points_alt_retr,
    } orelse return fallback;
    if (index >= values.len) return fallback;
    return values[index];
}

fn parseFractionTarget(value: []const u8) !AtmosphereModel.FractionTarget {
    if (std.mem.eql(u8, value, "cloud")) return .cloud;
    if (std.mem.eql(u8, value, "aerosol")) return .aerosol;
    if (std.mem.eql(u8, value, "none")) return .none;
    return Error.InvalidValue;
}

fn parseFractionKind(value: []const u8) !AtmosphereModel.FractionKind {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "wavel_independent") or std.mem.eql(u8, value, "wavelength_independent")) {
        return .wavel_independent;
    }
    if (std.mem.eql(u8, value, "wavel_dependent") or std.mem.eql(u8, value, "wavelength_dependent")) {
        return .wavel_dependent;
    }
    return Error.InvalidValue;
}

fn parsePartitionLabel(value: []const u8) !AtmosphereModel.PartitionLabel {
    if (std.mem.eql(u8, value, "unspecified")) return .unspecified;
    if (std.mem.eql(u8, value, "boundary_layer")) return .boundary_layer;
    if (std.mem.eql(u8, value, "free_troposphere")) return .free_troposphere;
    if (std.mem.eql(u8, value, "fit_interval")) return .fit_interval;
    if (std.mem.eql(u8, value, "stratosphere")) return .stratosphere;
    return Error.InvalidValue;
}

fn findAbsorberForSpecies(absorbers: AbsorberSet, species: fields.AbsorberSpecies) ?*Absorber {
    for (0..absorbers.items.len) |index| {
        const absorber = @constCast(&absorbers.items[index]);
        if (resolvedAbsorberSpecies(absorber.*) == species) return absorber;
    }
    return null;
}

fn resolvedAbsorberSpecies(absorber: Absorber) ?fields.AbsorberSpecies {
    return AbsorberModel.resolvedAbsorberSpecies(absorber);
}

fn decodeMeasurementMask(allocator: Allocator, value: yaml.Value, strict: bool) !MeasurementMask {
    const mask_map = try expectMap(value);
    try ensureKnownFields(mask_map, &.{ "band", "exclude" }, strict);
    return .{
        .band = if (mapGet(mask_map, "band")) |band| try allocator.dupe(u8, try expectString(band)) else "",
        .exclude = try decodeWindows(allocator, mapGet(mask_map, "exclude")),
    };
}

fn decodeMeasurementErrorModel(value: yaml.Value, strict: bool) !MeasurementErrorModel {
    const error_map = try expectMap(value);
    try ensureKnownFields(error_map, &.{ "from_source_noise", "floor_radiance" }, strict);
    return .{
        .from_source_noise = if (mapGet(error_map, "from_source_noise")) |from_source_noise| try expectBool(from_source_noise) else false,
        .floor = if (mapGet(error_map, "floor_radiance")) |floor| try expectF64(floor) else 0.0,
    };
}

fn decodeOutputs(
    allocator: Allocator,
    value: ?yaml.Value,
    simulation: ?*const StageResolution,
    retrieval: ?*const StageResolution,
    strict: bool,
    validation: Validation,
) ![]const OutputSpec {
    const outputs_value = value orelse return &[_]OutputSpec{};
    const outputs = try expectSeq(outputs_value);
    const decoded = try allocator.alloc(OutputSpec, outputs.len);
    for (outputs, 0..) |output_value, index| {
        const output_map = try expectMap(output_value);
        try ensureKnownFields(output_map, &.{ "from", "format", "destination_uri", "include_provenance" }, strict);
        const source_name = try expectString(requiredField(output_map, "from"));
        if (validation.require_resolved_stage_references and
            findProductAcrossStages(simulation, retrieval, source_name) == null)
        {
            return Error.MissingStageProduct;
        }
        decoded[index] = .{
            .from = try allocator.dupe(u8, source_name),
            .format = try parseExportFormat(try expectString(requiredField(output_map, "format"))),
            .destination_uri = try allocator.dupe(u8, try expectString(requiredField(output_map, "destination_uri"))),
            .include_provenance = if (mapGet(output_map, "include_provenance")) |include_provenance| try expectBool(include_provenance) else false,
        };
    }
    return decoded;
}

fn buildWarnings(
    allocator: Allocator,
    validation: Validation,
    simulation: ?*const StageResolution,
    retrieval: ?*const StageResolution,
) ![]const Warning {
    if (simulation == null or retrieval == null) return &[_]Warning{};
    const simulation_stage = simulation.?.*;
    const retrieval_stage = retrieval.?.*;

    if (retrieval_stage.stage.inverse == null) return &[_]Warning{};
    if (retrieval_stage.stage.inverse.?.measurements.source.kind() != .stage_product) return &[_]Warning{};
    if (!validation.synthetic_retrieval.warn_if_models_are_identical) return &[_]Warning{};

    const simulation_plan = simulation_stage.merged.get("plan") orelse .null;
    const retrieval_plan = retrieval_stage.merged.get("plan") orelse .null;
    const simulation_scene = simulation_stage.merged.get("scene") orelse .null;
    const retrieval_scene = retrieval_stage.merged.get("scene") orelse .null;
    if (!simulation_plan.eql(retrieval_plan) or !simulation_scene.eql(retrieval_scene)) {
        return &[_]Warning{};
    }

    if (validation.synthetic_retrieval.require_explicit_acknowledgement_if_identical) {
        return Error.InvalidReference;
    }

    const warnings = try allocator.alloc(Warning, 1);
    warnings[0] = .{
        .kind = .identical_synthetic_models,
        .message = "simulation and retrieval model contexts are identical; review inverse-crime risk",
    };
    return warnings;
}

fn decodeProfileBinding(allocator: Allocator, value: yaml.Value) !Binding {
    if (value == .string) {
        const source = try expectString(value);
        if (std.mem.eql(u8, source, "atmosphere")) return .atmosphere;
        return .{ .asset = .{ .name = try allocator.dupe(u8, source) } };
    }
    const source_map = try expectMap(value);
    try ensureKnownFields(source_map, &.{"asset"}, true);
    const asset_name = try expectString(requiredField(source_map, "asset"));
    return .{ .asset = .{ .name = try allocator.dupe(u8, asset_name) } };
}

fn resolveMeasurementSource(
    source_name: []const u8,
    simulation_stage: ?*const Stage,
    validation: Validation,
    ingests: []const Ingest,
) !Binding {
    if (simulation_stage) |stage| {
        if (findStageProduct(stage.*, source_name) != null) {
            return .{ .stage_product = .{ .name = source_name } };
        }
    }

    if (std.mem.indexOfScalar(u8, source_name, '.')) |dot_index| {
        if (hasIngest(ingests, source_name[0..dot_index])) {
            return .{ .ingest = @import("../../model/Binding.zig").IngestRef.fromFullName(source_name) };
        }
    }

    if (validation.require_resolved_stage_references and std.mem.indexOfScalar(u8, source_name, '.') == null) {
        return Error.MissingStageProduct;
    }

    return .{ .external_observation = .{ .name = source_name } };
}

fn parseMeasurementQuantity(value: []const u8) !MeasurementQuantity {
    return MeasurementQuantity.parse(value) catch Error.InvalidValue;
}

fn parseTrustRegion(value: []const u8) !FitControls.TrustRegion {
    if (std.mem.eql(u8, value, "lm") or std.mem.eql(u8, value, "levenberg_marquardt")) {
        return .lm;
    }
    return Error.InvalidValue;
}

fn inferMeasurementQuantity(
    source_name: []const u8,
    binding: Binding,
    simulation_stage: ?*const Stage,
    ingests: []const Ingest,
) !MeasurementQuantity {
    switch (binding.kind()) {
        .stage_product => {
            const stage = simulation_stage orelse return Error.InvalidReference;
            const product = findStageProduct(stage.*, source_name) orelse return Error.MissingStageProduct;
            return product.observable orelse Error.InvalidReference;
        },
        .ingest => {
            _ = ingests;
            const ingest_ref = binding.ingestReference().?;
            return parseMeasurementQuantity(ingest_ref.output_name);
        },
        .external_observation => return parseMeasurementQuantity(source_name),
        .none, .asset, .bundle_default, .atmosphere => return Error.InvalidReference,
    }
}

fn ingestMeasurementSampleCount(ingests: []const Ingest, binding: Binding) u32 {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (std.mem.eql(u8, ingest_ref.output_name, "radiance")) return ingest.loaded_spectra.sampleCount(.radiance);
    if (std.mem.eql(u8, ingest_ref.output_name, "irradiance")) return ingest.loaded_spectra.sampleCount(.irradiance);
    return 0;
}

fn maskedIngestMeasurementSampleCount(
    allocator: Allocator,
    ingests: []const Ingest,
    binding: Binding,
    mask: MeasurementMask,
) !u32 {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    const kind = if (std.mem.eql(u8, ingest_ref.output_name, "radiance"))
        spectral_ascii.ChannelKind.radiance
    else if (std.mem.eql(u8, ingest_ref.output_name, "irradiance"))
        spectral_ascii.ChannelKind.irradiance
    else
        return Error.MissingIngestOutput;
    const wavelengths_nm = try ingest.loaded_spectra.wavelengthsForKind(allocator, kind);
    defer if (wavelengths_nm.len != 0) allocator.free(wavelengths_nm);

    if (mask.exclude.len == 0) return @intCast(wavelengths_nm.len);
    try spectra_grid.validateExplicitSamples(wavelengths_nm);

    const measurement: Measurement = .{
        .product_name = "radiance",
        .observable = .radiance,
        .sample_count = @intCast(wavelengths_nm.len),
        .mask = mask,
    };
    return measurement.selectedSampleCount(wavelengths_nm);
}

fn resolveInstrumentLineShapeTable(ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").InstrumentLineShapeTable {
    const ingest_ref = binding.ingestReference().?;
    const ingest = findIngest(ingests, ingest_ref.ingest_name) orelse return Error.MissingIngest;
    if (!std.mem.eql(u8, ingest_ref.output_name, "instrument_line_shape_table")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.instrument_line_shape_table;
}

fn hydrateSceneFromIngestMeasurement(
    allocator: Allocator,
    ingests: []const Ingest,
    scene: *Scene,
    binding: Binding,
) !void {
    if (binding.kind() != .ingest) return;

    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "radiance")) return;

    scene.observation_model.sampling = .measured_channels;
    scene.observation_model.measured_wavelengths_nm = try ingest.loaded_spectra.wavelengthsForKind(allocator, .radiance);
    scene.observation_model.owns_measured_wavelengths = scene.observation_model.measured_wavelengths_nm.len != 0;
    scene.observation_model.reference_radiance = try spectral_ascii_runtime.channelValuesForKind(allocator, ingest.loaded_spectra, .radiance);
    scene.observation_model.owns_reference_radiance = scene.observation_model.reference_radiance.len != 0;
    scene.observation_model.ingested_noise_sigma = try ingest.loaded_spectra.noiseSigmaForKind(allocator, .radiance);
    if (!scene.observation_model.operational_solar_spectrum.enabled()) {
        scene.observation_model.operational_solar_spectrum = if (ingest.loaded_spectra.metadata.operational_solar_spectrum.enabled())
            try ingest.loaded_spectra.metadata.operational_solar_spectrum.clone(allocator)
        else
            try ingest.loaded_spectra.solarSpectrumForKind(allocator, .irradiance);
    }
    if (scene.observation_model.measured_wavelengths_nm.len != 0) {
        scene.spectral_grid.start_nm = scene.observation_model.measured_wavelengths_nm[0];
        scene.spectral_grid.end_nm = scene.observation_model.measured_wavelengths_nm[scene.observation_model.measured_wavelengths_nm.len - 1];
        scene.spectral_grid.sample_count = @intCast(scene.observation_model.measured_wavelengths_nm.len);
    }
}

fn resolveOperationalSolarSpectrum(allocator: Allocator, ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").OperationalSolarSpectrum {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "operational_solar_spectrum")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.operational_solar_spectrum.clone(allocator);
}

fn resolveOperationalReferenceGrid(allocator: Allocator, ingests: []const Ingest, binding: Binding) !@import("../../model/Instrument.zig").OperationalReferenceGrid {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    if (!std.mem.eql(u8, ingest_ref.output_name, "operational_refspec_grid")) return Error.MissingIngestOutput;
    return ingest.loaded_spectra.metadata.operational_refspec_grid.clone(allocator);
}

fn resolveSpectroscopyLineList(
    allocator: Allocator,
    assets: []const Asset,
    spectroscopy: Spectroscopy,
) !?ReferenceData.SpectroscopyLineList {
    if (spectroscopy.line_list.kind() != .asset) return null;

    var line_asset = try loadResolvedAsset(allocator, assets, spectroscopy.line_list, .spectroscopy_line_list);
    defer line_asset.deinit(allocator);

    var line_list = try line_asset.toSpectroscopyLineList(allocator);
    errdefer line_list.deinit(allocator);

    const wants_sidecars = spectroscopy.strong_lines.kind() == .asset or spectroscopy.line_mixing.kind() == .asset;
    if (wants_sidecars) {
        if (spectroscopy.strong_lines.kind() != .asset or spectroscopy.line_mixing.kind() != .asset) {
            return Error.InvalidReference;
        }

        var strong_asset = try loadResolvedAsset(allocator, assets, spectroscopy.strong_lines, .spectroscopy_strong_line_set);
        defer strong_asset.deinit(allocator);
        var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
        defer strong_lines.deinit(allocator);

        var relaxation_asset = try loadResolvedAsset(allocator, assets, spectroscopy.line_mixing, .spectroscopy_relaxation_matrix);
        defer relaxation_asset.deinit(allocator);
        var relaxation_matrix = try relaxation_asset.toSpectroscopyRelaxationMatrix(allocator);
        defer relaxation_matrix.deinit(allocator);

        try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    }

    return line_list;
}

fn resolveCollisionInducedAbsorptionTable(
    allocator: Allocator,
    assets: []const Asset,
    binding: Binding,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    if (binding.kind() != .asset) return null;

    var loaded = try loadResolvedAsset(
        allocator,
        assets,
        binding,
        .collision_induced_absorption_table,
    );
    defer loaded.deinit(allocator);
    const table = try loaded.toCollisionInducedAbsorptionTable(allocator);
    return table;
}

fn resolveCrossSectionTable(
    allocator: Allocator,
    assets: []const Asset,
    binding: Binding,
) !?ReferenceData.CrossSectionTable {
    if (binding.kind() != .asset) return null;

    var loaded = try loadResolvedAsset(
        allocator,
        assets,
        binding,
        .cross_section_table,
    );
    defer loaded.deinit(allocator);
    const table = try loaded.toCrossSectionTable(allocator);
    return table;
}

fn loadResolvedAsset(
    allocator: Allocator,
    assets: []const Asset,
    binding: Binding,
    kind: reference_assets.AssetKind,
) !reference_assets.LoadedAsset {
    const asset = findAsset(assets, binding.name()) orelse return Error.MissingAsset;
    return reference_assets.loadExternalAsset(
        allocator,
        kind,
        asset.name,
        asset.resolved_path,
        asset.format,
    );
}

fn resolveOperationalLut(
    allocator: Allocator,
    ingests: []const Ingest,
    binding: Binding,
) !@import("../../model/Instrument.zig").OperationalCrossSectionLut {
    const ingest_ref = binding.ingestReference().?;
    const ingest = getReferencedIngest(ingests, ingest_ref);
    const lut = ingest.loaded_spectra.metadata.operationalLut(ingest_ref.output_name) orelse return Error.MissingIngestOutput;
    return lut.clone(allocator);
}

fn getReferencedIngest(ingests: []const Ingest, reference: @import("../../model/Binding.zig").IngestRef) Ingest {
    return findIngest(ingests, reference.ingest_name) orelse unreachable;
}

fn findAsset(assets: []const Asset, name: []const u8) ?Asset {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.name, name)) return asset;
    }
    return null;
}

fn hasAsset(assets: []const Asset, name: []const u8) bool {
    return findAsset(assets, name) != null;
}

fn findIngest(ingests: []const Ingest, name: []const u8) ?Ingest {
    for (ingests) |ingest| {
        if (std.mem.eql(u8, ingest.name, name)) return ingest;
    }
    return null;
}

fn hasIngest(ingests: []const Ingest, name: []const u8) bool {
    return findIngest(ingests, name) != null;
}

fn ensureDistinctProducts(products: []const Product) !void {
    for (products, 0..) |product, index| {
        for (products[index + 1 ..]) |other| {
            if (std.mem.eql(u8, product.name, other.name)) return Error.InvalidValue;
        }
    }
}

fn findStageProduct(stage: Stage, name: []const u8) ?Product {
    for (stage.products) |product| {
        if (std.mem.eql(u8, product.name, name)) return product;
    }
    return null;
}

fn findProductAcrossStages(simulation: ?*const StageResolution, retrieval: ?*const StageResolution, name: []const u8) ?Product {
    if (simulation) |value| {
        if (findStageProduct(value.stage, name)) |product| return product;
    }
    if (retrieval) |value| {
        if (findStageProduct(value.stage, name)) |product| return product;
    }
    return null;
}

fn inferSpectralGrid(bands: SpectralBandSet) !SpectralGrid {
    if (bands.items.len == 0) return Error.MissingField;

    var start_nm = bands.items[0].start_nm;
    var end_nm = bands.items[0].end_nm;
    var step_nm = bands.items[0].step_nm;
    for (bands.items[1..]) |band| {
        start_nm = @min(start_nm, band.start_nm);
        end_nm = @max(end_nm, band.end_nm);
        step_nm = @min(step_nm, band.step_nm);
    }

    const sample_count = @as(u32, @intFromFloat(@round(((end_nm - start_nm) / step_nm) + 1.0)));
    return .{
        .start_nm = start_nm,
        .end_nm = end_nm,
        .sample_count = sample_count,
    };
}

test "document finds absorbers by public species string when resolved species is unset" {
    const absorbers: AbsorberSet = .{
        .items = &.{
            Absorber{
                .id = "nh3",
                .species = "nh3",
            },
        },
    };

    const absorber = findAbsorberForSpecies(absorbers, .nh3) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("nh3", absorber.species);
}

test "document resolves revised common example" {
    var document = try Document.parseFile(std.testing.allocator, "data/examples/zdisamar_common_use.yaml");
    defer document.deinit();

    var resolved = try document.resolve(std.testing.allocator);
    defer resolved.deinit();

    try std.testing.expectEqualStrings("o2a_twin_common", resolved.metadata.id);
    try std.testing.expect(resolved.simulation != null);
    try std.testing.expect(resolved.retrieval != null);
    try std.testing.expectEqual(@as(usize, 2), resolved.outputs.len);
    try std.testing.expectEqualStrings("truth_radiance", resolved.retrieval.?.inverse.?.measurements.source.name());
    try std.testing.expectEqual(@as(u32, 1301), resolved.simulation.?.scene.spectral_grid.sample_count);
}

test "document rejects unknown fields in strict mode" {
    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: bad
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: sim
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 10
        \\        viewing_zenith_deg: 5
        \\        relative_azimuth_deg: 20
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 4
        \\      bands:
        \\        o2a:
        \\          start_nm: 758.0
        \\          end_nm: 759.0
        \\          step_nm: 0.5
        \\      surface:
        \\        model: lambertian
        \\        unknown_flag: true
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var document = try Document.parse(std.testing.allocator, "inline.yaml", ".", source);
    defer document.deinit();

    try std.testing.expectError(Error.UnknownField, document.resolve(std.testing.allocator));
}

fn applyCrossSectionFitGeneralConfigWithAllocator(allocator: Allocator) !void {
    var scene: Scene = .{};
    defer scene.observation_model.deinitOwned(allocator);

    try applyGeneralConfigToObservationModel(
        allocator,
        .simulation,
        .{
            .use_eff_xsec_oe_sim = true,
            .use_poly_exp_xsec_sim = true,
            .xsec_strong_abs_sim = &.{ true, false },
            .degree_poly_sim = &.{ 5, 3 },
        },
        &scene,
    );

    try std.testing.expect(scene.observation_model.cross_section_fit.strongAbsorptionForBand(0));
    try std.testing.expectEqual(@as(u32, 3), scene.observation_model.cross_section_fit.polynomialOrderForBand(1));
}

test "document applies cross-section fit controls without leaks across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        applyCrossSectionFitGeneralConfigWithAllocator,
        .{},
    );
}

fn resolveOperationalLutWithAllocator(allocator: Allocator) !void {
    const path = "zig-cache/test-o2o2-operational-lut-allocation-failure.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o2_o2_refspec_ntemperature 2
        \\meta o2_o2_refspec_npressure 2
        \\meta o2_o2_refspec_temperature_min 220.0
        \\meta o2_o2_refspec_temperature_max 320.0
        \\meta o2_o2_refspec_pressure_min 150.0
        \\meta o2_o2_refspec_pressure_max 1000.0
        \\meta o2_o2_refspec_wavelength_1 760.8
        \\meta o2_o2_refspec_wavelength_2 761.0
        \\meta o2_o2_refspec_wavelength_3 761.2
        \\meta o2_o2_refspec_coeff_1_1_1 1.2e-46
        \\meta o2_o2_refspec_coeff_2_1_1 0.2e-46
        \\meta o2_o2_refspec_coeff_1_2_1 0.1e-46
        \\meta o2_o2_refspec_coeff_2_2_1 0.03e-46
        \\meta o2_o2_refspec_coeff_1_1_2 1.5e-46
        \\meta o2_o2_refspec_coeff_2_1_2 0.2e-46
        \\meta o2_o2_refspec_coeff_1_2_2 0.1e-46
        \\meta o2_o2_refspec_coeff_2_2_2 0.03e-46
        \\meta o2_o2_refspec_coeff_1_1_3 1.1e-46
        \\meta o2_o2_refspec_coeff_2_1_3 0.18e-46
        \\meta o2_o2_refspec_coeff_1_2_3 0.08e-46
        \\meta o2_o2_refspec_coeff_2_2_3 0.02e-46
        \\start_channel_rad
        \\rad 760.8 1485.0 1.116153E+13
        \\rad 761.0 1445.0 1.096153E+13
        \\rad 761.2 1405.0 1.076153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o2o2-operational-lut-allocation-failure
        \\inputs:
        \\  assets:
        \\    o2o2_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o2o2-operational-lut-allocation-failure.txt
        \\    no2_cross_section:
        \\      kind: file
        \\      format: csv
        \\      path: data/cross_sections/no2_405_465_demo.csv
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o2o2_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o2o2-cia-allocation-failure
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2_o2:
        \\          species: o2_o2
        \\          spectroscopy:
        \\            model: cia
        \\            operational_lut:
        \\              from_ingest: demo.o2_o2_operational_lut
        \\            cross_section_asset: no2_cross_section
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var document = try Document.parse(allocator, "inline.yaml", ".", source);
    defer document.deinit();

    var resolved = try document.resolve(allocator);
    defer resolved.deinit();
}

test "document resolves operational LUT observation-model clones without leaks across allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        resolveOperationalLutWithAllocator,
        .{},
    );
}

fn resolveOperationalLutFollowOnFailureWithAllocator(allocator: Allocator) !void {
    const path = "zig-cache/test-o2-operational-lut-follow-on-failure.txt";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data =
        \\meta o2_refspec_ntemperature 2
        \\meta o2_refspec_npressure 2
        \\meta o2_refspec_temperature_min 220.0
        \\meta o2_refspec_temperature_max 320.0
        \\meta o2_refspec_pressure_min 150.0
        \\meta o2_refspec_pressure_max 1000.0
        \\meta o2_refspec_wavelength_1 760.8
        \\meta o2_refspec_wavelength_2 761.0
        \\meta o2_refspec_wavelength_3 761.2
        \\meta o2_refspec_coeff_1_1_1 2.0e-24
        \\meta o2_refspec_coeff_2_1_1 0.3e-24
        \\meta o2_refspec_coeff_1_2_1 0.2e-24
        \\meta o2_refspec_coeff_2_2_1 0.05e-24
        \\meta o2_refspec_coeff_1_1_2 2.6e-24
        \\meta o2_refspec_coeff_2_1_2 0.35e-24
        \\meta o2_refspec_coeff_1_2_2 0.25e-24
        \\meta o2_refspec_coeff_2_2_2 0.06e-24
        \\meta o2_refspec_coeff_1_1_3 2.2e-24
        \\meta o2_refspec_coeff_2_1_3 0.32e-24
        \\meta o2_refspec_coeff_1_2_3 0.22e-24
        \\meta o2_refspec_coeff_2_2_3 0.05e-24
        \\start_channel_rad
        \\rad 760.8 1485.0 1.116153E+13
        \\rad 761.0 1445.0 1.096153E+13
        \\rad 761.2 1405.0 1.076153E+13
        \\end_channel_rad
        \\
        ,
    });

    const source =
        \\schema_version: 1
        \\metadata:
        \\  id: o2-operational-lut-follow-on-failure
        \\inputs:
        \\  assets:
        \\    o2_metadata:
        \\      kind: file
        \\      format: spectral_ascii
        \\      path: zig-cache/test-o2-operational-lut-follow-on-failure.txt
        \\  ingests:
        \\    demo:
        \\      adapter: spectral_ascii
        \\      asset: o2_metadata
        \\experiment:
        \\  simulation:
        \\    scene:
        \\      id: o2-line-by-line-follow-on-failure
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 8
        \\      bands:
        \\        a_band:
        \\          start_nm: 760.0
        \\          end_nm: 762.0
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\            line_list_asset: missing_o2_lines
        \\            operational_lut:
        \\              from_ingest: demo.o2_operational_lut
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var document = try Document.parse(allocator, "inline.yaml", ".", source);
    defer document.deinit();

    try std.testing.expectError(Error.MissingAsset, document.resolve(allocator));
}

test "document frees absorber LUT state when later spectroscopy resolution fails" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        std.testing.expectEqual(std.heap.Check.ok, status) catch unreachable;
    }

    try resolveOperationalLutFollowOnFailureWithAllocator(gpa.allocator());
}
