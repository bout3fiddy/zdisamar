const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const PhaseSupportKind = @import("../../../input/reference/airmass_phase.zig").PhaseSupportKind;
const transport_common = @import("../../radiative_transfer/root.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const hashing = @import("../../../common/hashing.zig");
const Types = @import("state.zig");

const Allocator = std.mem.Allocator;

// prepared_state.zig -----------------------------------------------------------------------------------------|
// Public owner/view boundary for optical properties after a Scene has been reduced into prepared rows. This   |
// file owns the stable PreparedOpticalState header, the deinit contract for moved preparation storage, and    |
// the small method facade used by downstream optical-depth, RTM, and diagnostics code.                        |
//                                                                                                             |
// build route                                                                                                 |
//   optical_properties/root.prepare                                                                           |
//     -> Context.init                  builds the vertical grid, borrowed profiles, LUT handles, and controls |
//     -> Absorbers.build               prepares active line and cross-section absorbers                       |
//     -> Accumulation.accumulate       fills PreparedLayer and optional PreparedSublayer rows                 |
//     -> Finalize.assemble             moves owned buffers into PreparedOpticalState                          |
//     -> ensureSharedRtmGeometryCache  builds retained shared-RTM geometry when interval semantics allow      |
//                                                                                                             |
// wavelength route                                                                                            |
//   instrument_grid/spectral_forward keeps one PreparedOpticalState for a product run. Each high-resolution   |
//   forward miss calls forward_input.configuredForwardInput, which then asks forward_layers, rtm_quadrature,  |
//   source_interfaces, pseudo_spherical, shared_carrier, and state_spectroscopy to read the same retained     |
//   header and row slices at the current wavelength. LABOS receives only the wavelength-specific ForwardInput.|
//                                                                                                             |
// public surface                                                                                              |
//   PreparedOpticalState : wide header over owned or borrowed out-of-line preparation storage                 |
//   deinit               : follows owns_* flags set while Context/AbsorberBuildState are moved                |
//   shape methods        : transportLayerCount, intervalSemanticsUseReducedSharedRtmLayers, and               |
//                          ensureSharedRtmGeometryCache choose the retained transport geometry                |
//   cache-key methods    : computeSpectroscopyPlanKey and computeSpectroscopyProfileCacheInputsKey protect    |
//                          wavelength-plan and profile-node spectroscopy caches from stale prepared state     |
//   wavelength helpers   : totalOpticalDepthAtWavelength keeps the validation surface small; scalar,          |
//                          spectroscopy, and optical-depth implementation lives in the owning read-side files |
//                                                                                                             |
// caller map                                                                                                  |
//   instrument_grid/grid_calculation reads this for wavelength plans, forward inputs, spectral eval, storage, |
//   and simulation setup. state_build/forward_layers, rtm_quadrature, source_interfaces, pseudo_spherical,    |
//   shared_geometry, shared_carrier, state_spectroscopy, state_optical_depth, and state_scalar read it for    |
//   RTM inputs and diagnostics. output/* modules use the same header for atmospheric budget, O2 line, O2-O2   |
//   CIA, radiative-transfer diagnostics, and instrument-response reports.                                     |
//                                                                                                             |
// module split                                                                                                |
//   state.zig defines the compiler-measured row payloads. finalize.zig writes this header once by moving      |
//   Context and AbsorberBuildState storage into it. state_spectroscopy.zig, state_optical_depth.zig, and      |
//   state_scalar.zig do the wavelength/altitude math behind the public methods below.                         |
//                                                                                                             |
// data shape                                                                                                  |
//   layers    : 208 B PreparedLayer rows. Each row stores representative layer physics plus the support-row   |
//               span tail {sublayer_start_index, layer_index, interval_index_1based, sublayer_count} at       |
//               [192..207]. This file owns the slice header; state.zig owns the row byte map.                 |
//   sublayers : optional 256 B PreparedSublayer support rows. DISAMAR-parity interval grids can share         |
//               boundary rows between adjacent transport layers, so sum(layer.sublayer_count) can be larger   |
//               than sublayers.len. Reduced shared-RTM routes keep the coarser PreparedLayer transport shape. |
//   absorbers : line/cross-section rows keep retained reference handles beside density columns. The           |
//               wavelength-specific spectroscopy work lives in state_spectroscopy.zig and carrier_eval.zig.   |
//   geometry  : shared_rtm_geometry is a retained cache built from PreparedLayer support spans when explicit  |
//               interval semantics allow one shared RTM geometry to feed multiple wavelength builders.        |
//                                                                                                             |
// layout ownership                                                                                            |
//   PreparedOpticalState is mapped below because this file owns the header and release order. Repeated row    |
//   payload maps live in state.zig beside layer_accumulation and wavelength readers. PreparedLayer is 208 B,  |
//   PreparedSublayer is 256 B, SharedRtmGeometry is a 32 B owner header over cached layer/level arrays, and   |
//   GeneratedLutAsset is 216 B. root_test.zig guards the header and row sizes with @sizeOf/@alignOf/@offsetOf.|
//                                                                                                             |
// hot reads                                                                                                   |
//   Repeated wavelength paths read this header for layer/support rows, aerosol phase coefficients,            |
//   spectroscopy handles, LUT headers, scalar optical-depth summaries, and cache keys. Index-only loops over  |
//   PreparedLayer use pointer capture so no 208 B row is copied. The shared-RTM shape check reads             |
//   sublayer_count at [204..207] only, while forward_layers, rtm_quadrature, pseudo_spherical, and            |
//   shared_geometry read the same row's support tail plus altitude, pressure, aerosol, and optical-depth      |
//   fields nearby. Keep the span fields in PreparedLayer until a measured repeated-boundary workload shows    |
//   that separate retained span storage is faster and simpler to own.                                         |
//                                                                                                             |
// header layout                                                                                               |
//   The inline [151]f64 aerosol phase array takes 1208 B and dominates this 2136 B header. Slice and optional |
//   slice fields are only pointers/lengths here; their payload storage is accounted for by the row boxes in   |
//   state.zig or by the referenced-storage notes below. The map is compiler-measured for the current 64-bit   |
//   target, not source order.                                                                                 |
//                                                                                                             |
// cache keys                                                                                                  |
//   spectroscopy_plan_key tracks the active line-list plan. spectroscopy_profile_cache_inputs_key tracks      |
//   profile arrays plus the spectroscopy controls that make profile-node caches reusable.                     |
//   The private update* helpers at the bottom intentionally hash concrete line-list fields, prepared strong   |
//   and weak line-state arrays, and runtime controls by value. They are cache invalidation code, not a        |
//   cryptographic digest or persisted file format.                                                            |
//                                                                                                             |
// ownership                                                                                                   |
//   Deinit follows the owns_* flags set by Finalize.assemble when buffers are moved out of Context and        |
//   AbsorberBuildState. Borrowed rows stay untouched; owned rows release nested storage before their slice is |
//   freed.                                                                                                    |
// ------------------------------------------------------------------------------------------------------------|

// PreparedOpticalState ---------------------------------------------------------------------------------------|
// Final optical-property state returned to transport, instrument-grid workers, diagnostics, and retrieval.    |
//                                                                                                             |
// This is a wide owner/view header over prepared optical-property rows. It keeps cheap scalar summaries       |
// inline, keeps large repeated row payloads out of line behind slice headers, and records which moved         |
// preparation buffers this header must release. Zig reorders regular struct fields, so the memory map below   |
// is compiler-measured storage order, not source order.                                                       |
//                                                                                                             |
// measured with                                                                                               |
//   @sizeOf, @alignOf, and @offsetOf for the current 64-bit Zig target.                                       |
//                                                                                                             |
// storage groups                                                                                              |
//   row headers       : layers, optional sublayers, absorber rows, spectroscopy profile arrays                |
//   retained payload  : operational LUT headers, generated LUT metadata, cached shared RTM geometry           |
//   scalar summaries  : optical depths, effective thermodynamics, column factors, aerosol parameters          |
//   phase coefficients: inline [151]f64 used by RTM phase support and diagnostics                             |
//   cache identity    : spectroscopy_plan_key and spectroscopy_profile_cache_inputs_key                       |
//   ownership flags   : bottom of the row, close to the enum/small-tag storage that Zig also packs there      |
//                                                                                                             |
// lifetime                                                                                                    |
//   Finalize.assemble writes this once by moving Context and AbsorberBuildState owner/view headers into it.   |
//   Wavelength-time callers borrow through const pointers. deinit is the only release path for moved storage. |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2136 B (2.086 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..   7] gas_optical_depth                            : f64                                             |
// [   8..  79] operational_o2o2_lut                         : OperationalCrossSectionLut                      |
// [  80..  95] strong_line_states                           : ?[]StrongLinePreparedState                      |
// [  96.. 111] spectroscopy_profile_strong_line_states      : ?[]StrongLinePreparedState                      |
// [ 112.. 127] spectroscopy_profile_weak_line_states        : ?[]WeakLinePreparedState                        |
// [ 128.. 159] shared_rtm_geometry                          : SharedRtmGeometry                               |
// [ 160.. 175] continuum_points                             : []const CrossSectionPoint                       |
// [ 176.. 191] lut_execution_entries                        : []const []const u8                              |
// [ 192.. 223] collision_induced_absorption                 : ?CollisionInducedAbsorptionTable                |
// [ 224.. 239] generated_lut_assets                         : []GeneratedLutAsset                             |
// [ 240.. 455] spectroscopy_lines                           : ?SpectroscopyLineList                           |
// [ 456.. 471] spectroscopy_profile_altitudes_km            : []f64                                           |
// [ 472.. 487] spectroscopy_profile_pressures_hpa           : []f64                                           |
// [ 488.. 503] spectroscopy_profile_temperatures_k          : []f64                                           |
// [ 504.. 511] line_mixing_mean_cross_section_cm2_per_molecule : f64                                          |
// [ 512.. 519] column_density_factor                        : f64                                             |
// [ 520.. 599] aerosol_fraction_control                     : FractionControl                                 |
// [ 600.. 607] spectroscopy_plan_key                        : u64                                             |
// [ 608.. 615] effective_air_mass_factor                    : f64                                             |
// [ 616.. 631] cross_section_absorbers                      : []PreparedCrossSectionAbsorber                  |
// [ 632.. 647] line_absorbers                               : []PreparedLineAbsorber                          |
// [ 648.. 655] aerosol_base_optical_depth                   : f64                                             |
// [ 656.. 727] operational_o2_lut                           : OperationalCrossSectionLut                      |
// [ 728.. 735] aerosol_optical_depth                        : f64                                             |
// [ 736.. 743] total_optical_depth                          : f64                                             |
// [ 744.. 751] depolarization_factor                        : f64                                             |
// [ 752.. 759] mean_cross_section_cm2_per_molecule          : f64                                             |
// [ 760.. 767] line_mean_cross_section_cm2_per_molecule     : f64                                             |
// [ 768.. 783] sublayers                                    : ?[]PreparedSublayer                             |
// [ 784.. 799] layers                                       : []PreparedLayer                                 |
// [ 800.. 807] spectroscopy_profile_cache_inputs_key        : u64                                             |
// [ 808.. 815] effective_single_scatter_albedo              : f64                                             |
// [ 816.. 823] aerosol_single_scatter_albedo                : f64                                             |
// [ 824..2031] aerosol_phase_coefficients                   : [151]f64                                        |
// [2032..2039] effective_temperature_k                      : f64                                             |
// [2040..2047] effective_pressure_hpa                       : f64                                             |
// [2048..2055] air_column_density_factor                    : f64                                             |
// [2056..2063] oxygen_column_density_factor                 : f64                                             |
// [2064..2071] cia_mean_cross_section_cm5_per_molecule2    : f64                                              |
// [2072..2079] cia_pair_path_factor_cm5                    : f64                                              |
// [2080..2087] aerosol_reference_wavelength_nm             : f64                                              |
// [2088..2095] aerosol_angstrom_exponent                   : f64                                              |
// [2096..2103] cia_optical_depth                           : f64                                              |
// [2104..2111] d_optical_depth_d_temperature               : f64                                              |
// [2112..2115] fit_interval_index_1based                   : u32                                              |
// [2116..2116] owns_spectroscopy_profile_strong_line_states: bool                                             |
// [2117..2117] has_aerosol_profile_properties              : bool                                             |
// [2118..2118] owns_spectroscopy_profile_arrays            : bool                                             |
// [2119..2119] owns_operational_o2o2_lut                   : bool                                             |
// [2120..2120] owns_operational_o2_lut                     : bool                                             |
// [2121..2121] interval_semantics                          : IntervalSemantics                                |
// [2122..2123] continuum_owner_species                     : ?AbsorberSpecies                                 |
// [2124..2124] aerosol_phase_support                       : PhaseSupportKind                                 |
// [2125..2125] owns_spectroscopy_profile_weak_line_states  : bool                                             |
// [2126..2126] owns_collision_induced_absorption           : bool                                             |
// [2127..2127] owns_generated_lut_assets                   : bool                                             |
// [2128..2128] owns_continuum_points                       : bool                                             |
// [2129..2129] owns_lut_execution_entries                  : bool                                             |
// [2130..2135] trailing padding                            : 6 B                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   layers, sublayers, absorber rows, profile states, generated LUT assets, and execution strings are         |
//   out-of-line. The owns_* flags decide whether deinit releases each buffer or treats it as borrowed.        |
//   operational LUT structs are inline headers; their table storage is retained out-of-line by those headers. |
//                                                                                                             |
// unused bits: 48 padding + 70 bool-storage slack = 118 bits                                                  |
// cache span: 34 cache lines at 64 B per line                                                                 |
// footprint: per instance = 2136 B (2.086 KiB); total also includes referenced storage above                  |
pub const PreparedOpticalState = struct {
    layers: []Types.PreparedLayer,
    sublayers: ?[]Types.PreparedSublayer = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_profile_strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_profile_weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    shared_rtm_geometry: Types.SharedRtmGeometry = .{},
    continuum_points: []const ReferenceData.CrossSectionPoint,
    owns_continuum_points: bool = true,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    owns_collision_induced_absorption: bool = true,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    spectroscopy_profile_altitudes_km: []f64 = &.{},
    spectroscopy_profile_pressures_hpa: []f64 = &.{},
    spectroscopy_profile_temperatures_k: []f64 = &.{},
    owns_spectroscopy_profile_arrays: bool = true,
    owns_spectroscopy_profile_strong_line_states: bool = true,
    owns_spectroscopy_profile_weak_line_states: bool = true,
    spectroscopy_plan_key: u64 = 0,
    spectroscopy_profile_cache_inputs_key: u64 = 0,
    cross_section_absorbers: []Types.PreparedCrossSectionAbsorber = &.{},
    line_absorbers: []Types.PreparedLineAbsorber = &.{},
    continuum_owner_species: ?AbsorberModel.AbsorberSpecies = null,
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    owns_operational_o2_lut: bool = false,
    owns_operational_o2o2_lut: bool = false,
    mean_cross_section_cm2_per_molecule: f64,
    line_mean_cross_section_cm2_per_molecule: f64,
    line_mixing_mean_cross_section_cm2_per_molecule: f64,
    cia_mean_cross_section_cm5_per_molecule2: f64,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    aerosol_single_scatter_albedo: f64 = -1.0,
    aerosol_phase_coefficients: [Types.phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64,
    cia_pair_path_factor_cm5: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    has_aerosol_profile_properties: bool = false,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64 = 0.0,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,
    interval_semantics: AtmosphereModel.IntervalSemantics = .none,
    fit_interval_index_1based: u32 = 0,
    aerosol_phase_support: PhaseSupportKind = .none,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    generated_lut_assets: []Types.GeneratedLutAsset = &.{},
    owns_generated_lut_assets: bool = false,
    lut_execution_entries: []const []const u8 = &.{},
    owns_lut_execution_entries: bool = false,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        // PreparedOpticalState.deinit ------------------------------------------------------------------------|
        // Release owned prepared optical-property storage. Borrowed tables and profile arrays stay with       |
        // their owner when the corresponding owns_* flag is false.                                            |
        // ----------------------------------------------------------------------------------------------------|

        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);

        self.shared_rtm_geometry.deinit(allocator);

        if (self.owns_continuum_points) allocator.free(self.continuum_points);

        if (self.owns_collision_induced_absorption and self.collision_induced_absorption != null) {
            const cia = self.collision_induced_absorption.?;
            var owned_cia = cia;
            owned_cia.deinit(allocator);
        }

        if (self.cross_section_absorbers.len != 0) {
            for (self.cross_section_absorbers) |*cross_section_absorber| {
                cross_section_absorber.deinit(allocator);
            }
            allocator.free(self.cross_section_absorbers);
        }

        if (self.line_absorbers.len != 0) {
            for (self.line_absorbers) |*line_absorber| {
                line_absorber.deinit(allocator);
            }
            allocator.free(self.line_absorbers);
        } else {
            if (self.strong_line_states) |states| {
                for (states) |*state| state.deinit(allocator);
                allocator.free(states);
            }

            if (self.spectroscopy_profile_strong_line_states) |states| {
                if (self.owns_spectroscopy_profile_strong_line_states) {
                    for (states) |*state| state.deinit(allocator);
                    allocator.free(states);
                }
            }

            if (self.spectroscopy_profile_weak_line_states) |states| {
                if (self.owns_spectroscopy_profile_weak_line_states) {
                    for (states) |*state| state.deinit(allocator);
                    allocator.free(states);
                }
            }

            if (self.spectroscopy_lines) |line_list| {
                var owned = line_list;
                owned.deinit(allocator);
            }
        }

        if (self.owns_spectroscopy_profile_arrays) {
            if (self.spectroscopy_profile_altitudes_km.len != 0) {
                allocator.free(self.spectroscopy_profile_altitudes_km);
            }
            if (self.spectroscopy_profile_pressures_hpa.len != 0) {
                allocator.free(self.spectroscopy_profile_pressures_hpa);
            }
            if (self.spectroscopy_profile_temperatures_k.len != 0) {
                allocator.free(self.spectroscopy_profile_temperatures_k);
            }
        }

        self.aerosol_fraction_control.deinitOwned(allocator);

        if (self.owns_operational_o2_lut) {
            var owned = self.operational_o2_lut;
            owned.deinitOwned(allocator);
        }

        if (self.owns_operational_o2o2_lut) {
            var owned = self.operational_o2o2_lut;
            owned.deinitOwned(allocator);
        }

        if (self.owns_generated_lut_assets) {
            for (self.generated_lut_assets) |*asset| asset.deinitOwned(allocator);
            if (self.generated_lut_assets.len != 0) allocator.free(self.generated_lut_assets);
        }

        if (self.owns_lut_execution_entries) {
            for (self.lut_execution_entries) |entry| allocator.free(entry);
            if (self.lut_execution_entries.len != 0) allocator.free(self.lut_execution_entries);
        }

        self.* = undefined;
    }

    pub fn transportLayerCount(self: *const PreparedOpticalState) usize {
        // PreparedOpticalState.transportLayerCount -----------------------------------------------------------|
        // Return the row count that downstream transport storage should allocate for this prepared state.     |
        //                                                                                                     |
        // route                                                                                               |
        //   reduced shared-RTM interval grid -> one transport row per PreparedLayer                           |
        //   regular sublayer grid            -> one transport row per PreparedSublayer                        |
        //   no sublayers                     -> one transport row per PreparedLayer                           |
        // ----------------------------------------------------------------------------------------------------|

        if (self.intervalSemanticsUseReducedSharedRtmLayers()) return self.layers.len;
        if (self.sublayers) |sublayers| return sublayers.len;
        return self.layers.len;
    }

    pub fn computeSpectroscopyPlanKey(self: *const PreparedOpticalState) u64 {
        // PreparedOpticalState.computeSpectroscopyPlanKey ----------------------------------------------------|
        // Hash the line-list plan inputs that change strong-line and adaptive-grid planning.                  |
        //                                                                                                     |
        // used by                                                                                             |
        //   wavelength-plan and spectroscopy caches use this to decide whether line-list planning can be      |
        //   reused.                                                                                           |
        // ----------------------------------------------------------------------------------------------------|

        var hash = std.hash.Wyhash.init(0x4f32_4132_7370_6c6e);
        hashing.updateInt(&hash, self.spectroscopy_lines != null);
        if (self.spectroscopy_lines) |line_list| {
            updateLineListPlanInputs(&hash, line_list);
        }
        hashing.updateInt(&hash, self.line_absorbers.len);
        for (self.line_absorbers) |line_absorber| {
            updateLineListPlanInputs(&hash, line_absorber.line_list);
        }
        return hash.final();
    }

    pub fn computeSpectroscopyProfileCacheInputsKey(self: *const PreparedOpticalState) u64 {
        // PreparedOpticalState.computeSpectroscopyProfileCacheInputsKey --------------------------------------|
        // Hash the vertical profile arrays plus spectroscopy controls that make profile-node state reusable.  |
        //                                                                                                     |
        // boundary                                                                                            |
        //   This is stricter than computeSpectroscopyPlanKey because changing pressure/temperature/altitude   |
        //   rows can invalidate prepared line-shape state even when the line-list plan itself is unchanged.   |
        // ----------------------------------------------------------------------------------------------------|

        var hash = std.hash.Wyhash.init(0x4f32_4132_7370_726f);
        hashing.updateFloatSlice(&hash, self.spectroscopy_profile_altitudes_km);
        hashing.updateFloatSlice(&hash, self.spectroscopy_profile_pressures_hpa);
        hashing.updateFloatSlice(&hash, self.spectroscopy_profile_temperatures_k);
        updateSpectroscopyCacheInputs(&hash, self);
        return hash.final();
    }

    pub fn intervalSemanticsUseReducedSharedRtmLayers(self: *const PreparedOpticalState) bool {
        // PreparedOpticalState.intervalSemanticsUseReducedSharedRtmLayers ------------------------------------|
        // Detect the explicit-interval mode where the prepared support grid cannot be treated as one          |
        // independent RTM layer per support row.                                                              |
        //                                                                                                     |
        // call sites                                                                                          |
        //   transportLayerCount chooses the transport row count exposed to instrument-grid storage.           |
        //   ensureSharedRtmGeometryCache and shared_geometry.usesSharedRtmGrid decide whether retained        |
        //   shared-RTM geometry is valid for forward_layers, rtm_quadrature, source_interfaces, and           |
        //   pseudo_spherical.                                                                                 |
        //                                                                                                     |
        // math                                                                                                |
        //   referenced_support_rows = sum(layer.sublayer_count) over transport layers                         |
        //                                                                                                     |
        // shape                                                                                               |
        //   If adjacent layers share a boundary support row, the summed references are larger than the unique |
        //   sublayer row count. Reduced shared-RTM handling keeps the coarser PreparedLayer transport rows    |
        //   for that interval shape.                                                                          |
        //                                                                                                     |
        // memory                                                                                              |
        //   This is an index-only PreparedLayer walk: one u32 load, sublayer_count at [204..207], from each   |
        //   208 B row. It runs during storage sizing and cache-shape selection, before the LABOS              |
        //   order/Fourier loops. The layer array stays row-based because the per-wavelength builders consume  |
        //   the same rows' altitude, pressure, aerosol, optical-depth fields, and support-span tail nearby.   |
        // ----------------------------------------------------------------------------------------------------|

        if (self.interval_semantics == .none) return false;
        const sublayers = self.sublayers orelse return false;

        var referenced_support_rows: usize = 0;
        for (self.layers) |*layer| referenced_support_rows += @as(usize, @intCast(layer.sublayer_count));

        return referenced_support_rows > sublayers.len;
    }

    pub fn ensureSharedRtmGeometryCache(
        self: *PreparedOpticalState,
        allocator: Allocator,
    ) !void {
        // PreparedOpticalState.ensureSharedRtmGeometryCache --------------------------------------------------|
        // Lazily build or refresh retained shared-RTM geometry arrays for the current transport-layer count.  |
        //                                                                                                     |
        // ownership                                                                                           |
        //   shared_rtm_geometry owns layer/level arrays through this PreparedOpticalState and is released by  |
        //   deinit. A stale cache is dropped before rebuilding so geometry always matches current interval    |
        //   semantics.                                                                                        |
        // ----------------------------------------------------------------------------------------------------|

        if (self.shared_rtm_geometry.isValidFor(self.transportLayerCount())) return;
        self.shared_rtm_geometry.deinit(allocator);
        self.shared_rtm_geometry = try @import("shared_geometry.zig").buildSharedRtmGeometry(allocator, self);
    }

    pub fn resolvedAerosolSingleScatterAlbedo(self: *const PreparedOpticalState) f64 {
        // PreparedOpticalState.resolvedAerosolSingleScatterAlbedo --------------------------------------------|
        // Return the effective aerosol SSA in physical [0, 1] bounds.                                         |
        //                                                                                                     |
        // math                                                                                                |
        // explicit aerosol SSA wins when present; otherwise the mixed effective SSA is used.                  |
        // ----------------------------------------------------------------------------------------------------|

        return std.math.clamp(
            if (self.aerosol_single_scatter_albedo >= 0.0)
                self.aerosol_single_scatter_albedo
            else
                self.effective_single_scatter_albedo,
            0.0,
            1.0,
        );
    }

    pub fn totalOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return @import("state_optical_depth.zig").opticalDepthBreakdownAtWavelength(
            self,
            wavelength_nm,
        ).totalOpticalDepth();
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn updateSpectroscopyCacheInputs(
    hash: *std.hash.Wyhash,
    prepared: *const PreparedOpticalState,
) void {
    // updateSpectroscopyCacheInputs --------------------------------------------------------------------------|
    // Add the non-profile-array inputs that can change profile-node spectroscopy reuse.                       |
    //                                                                                                         |
    // call path                                                                                               |
    //   computeSpectroscopyProfileCacheInputsKey hashes altitude, pressure, and temperature arrays first,     |
    //   then calls this helper for the retained line/LUT/control state attached to PreparedOpticalState.      |
    //                                                                                                         |
    // cache shape                                                                                             |
    //   A cache hit means the same profile arrays are paired with the same full line-list inputs, same O2     |
    //   LUT enabled state, and same prepared strong/weak line-state payloads.                                 |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateInt(hash, prepared.spectroscopy_lines != null);
    if (prepared.spectroscopy_lines) |line_list| updateFullLineListInputs(hash, line_list);
    hashing.updateInt(hash, prepared.operational_o2_lut.enabled());
    updateStrongLinePreparedStates(hash, prepared.spectroscopy_profile_strong_line_states);
    updateWeakLinePreparedStates(hash, prepared.spectroscopy_profile_weak_line_states);
}

fn updateStrongLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    // updateStrongLinePreparedStates -------------------------------------------------------------------------|
    // Hash prepared strong-line rows by presence, row count, and the arrays used by line-shape evaluation.    |
    // These rows are owned or borrowed by PreparedOpticalState; this helper only reads them.                  |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateInt(hash, states != null);
    if (states) |resolved| {
        hashing.updateInt(hash, resolved.len);
        for (resolved) |state| {
            hashing.updateInt(hash, state.line_count);
            hashing.updateFloat(hash, state.sig_moy_cm1);
            hashing.updateFloatSlice(hash, state.population_t);
            hashing.updateFloatSlice(hash, state.dipole_t);
            hashing.updateFloatSlice(hash, state.mod_sig_cm1);
            hashing.updateFloatSlice(hash, state.half_width_cm1_at_t);
            hashing.updateFloatSlice(hash, state.line_mixing_coefficients);
        }
    }
}

fn updateWeakLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    // updateWeakLinePreparedStates ---------------------------------------------------------------------------|
    // Hash prepared weak-line rows by presence, row count, thermodynamic guards, and per-line coefficients.   |
    // This protects profile-node caches from reusing line-shape work after weak-line preparation changes.     |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateInt(hash, states != null);
    if (states) |resolved| {
        hashing.updateInt(hash, resolved.len);
        for (resolved) |state| {
            hashing.updateInt(hash, state.line_count);
            hashing.updateFloat(hash, state.safe_temperature);
            hashing.updateFloat(hash, state.safe_pressure);
            hashing.updateInt(hash, state.lines.len);
            for (state.lines) |line| {
                hashing.updateFloat(hash, line.shifted_center_wavenumber_cm1);
                hashing.updateFloat(hash, line.cte);
                hashing.updateFloat(hash, line.line_shape_y);
                hashing.updateFloat(hash, line.prefactor_base);
            }
        }
    }
}

fn updateLineListPlanInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    // updateLineListPlanInputs -------------------------------------------------------------------------------|
    // Hash the small subset that changes wavelength-plan line selection: runtime threshold, line count,       |
    // center wavelength, and strength. This is intentionally narrower than updateFullLineListInputs because   |
    // planning does not need pressure broadening, partition metadata, or line-mixing payloads.                |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateOptionalFloat(hash, line_list.runtime_controls.threshold_line_scale);
    hashing.updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        hashing.updateFloat(hash, line.center_wavelength_nm);
        hashing.updateFloat(hash, line.line_strength_cm2_per_molecule);
    }
}

fn updateFullLineListInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    // updateFullLineListInputs -------------------------------------------------------------------------------|
    // Hash every retained line-list field that can change spectroscopy evaluation for a profile node.         |
    //                                                                                                         |
    // cache shape                                                                                             |
    //   This includes runtime controls, weak-line rows, strong-line rows, branch metadata, isotope filters,   |
    //   vendor partition data, and relaxation-matrix coefficients. A profile-cache hit should mean the        |
    //   same physical spectroscopy inputs, not only the same wavelength-plan shape.                           |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateFloat(hash, line_list.strong_line_tolerance_nm);
    hashing.updateInt(hash, line_list.lines_sorted_ascending);
    hashing.updateInt(hash, line_list.preserve_anchor_weak_lines);
    hashing.updateInt(hash, line_list.vendor_strong_line_partition);
    hashing.updateOptionalIntSlice(hash, line_list.strong_line_match_by_line);
    updateFullRuntimeControls(hash, line_list.runtime_controls);

    hashing.updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        hashing.updateInt(hash, line.gas_index);
        hashing.updateInt(hash, line.isotope_number);
        hashing.updateFloat(hash, line.abundance_fraction);
        hashing.updateInt(hash, line.vendor_filter_metadata_from_source);
        hashing.updateFloat(hash, line.center_wavelength_nm);
        hashing.updateFloat(hash, line.center_wavenumber_cm1);
        hashing.updateFloat(hash, line.line_strength_cm2_per_molecule);
        hashing.updateFloat(hash, line.air_half_width_nm);
        hashing.updateFloat(hash, line.air_half_width_cm1);
        hashing.updateFloat(hash, line.temperature_exponent);
        hashing.updateFloat(hash, line.lower_state_energy_cm1);
        hashing.updateFloat(hash, line.pressure_shift_nm);
        hashing.updateFloat(hash, line.pressure_shift_cm1);
        hashing.updateFloat(hash, line.line_mixing_coefficient);
        hashing.updateOptionalInt(hash, line.branch_ic1);
        hashing.updateOptionalInt(hash, line.branch_ic2);
        hashing.updateOptionalInt(hash, line.rotational_nf);
    }

    hashing.updateInt(hash, line_list.strong_lines != null);
    if (line_list.strong_lines) |strong_lines| {
        hashing.updateInt(hash, strong_lines.len);
        for (strong_lines) |line| {
            hashing.updateFloat(hash, line.center_wavenumber_cm1);
            hashing.updateFloat(hash, line.center_wavelength_nm);
            hashing.updateFloat(hash, line.population_t0);
            hashing.updateFloat(hash, line.dipole_ratio);
            hashing.updateFloat(hash, line.dipole_t0);
            hashing.updateFloat(hash, line.lower_state_energy_cm1);
            hashing.updateFloat(hash, line.air_half_width_cm1);
            hashing.updateFloat(hash, line.air_half_width_nm);
            hashing.updateFloat(hash, line.temperature_exponent);
            hashing.updateFloat(hash, line.pressure_shift_cm1);
            hashing.updateFloat(hash, line.pressure_shift_nm);
            hashing.updateInt(hash, line.rotational_index_m1);
        }
    }

    hashing.updateInt(hash, line_list.relaxation_matrix != null);
    if (line_list.relaxation_matrix) |matrix| {
        hashing.updateInt(hash, matrix.line_count);
        hashing.updateFloatSlice(hash, matrix.wt0);
        hashing.updateFloatSlice(hash, matrix.bw);
    }
}

fn updateFullRuntimeControls(hash: *std.hash.Wyhash, controls: anytype) void {
    // updateFullRuntimeControls ------------------------------------------------------------------------------|
    // Hash spectroscopy runtime controls that alter active isotopes, line pruning, cutoff grids, or           |
    // line-mixing strength. These fields belong to the cache key because they can change line evaluation      |
    // without changing the profile arrays.                                                                    |
    // --------------------------------------------------------------------------------------------------------|

    hashing.updateOptionalInt(hash, controls.gas_index);
    hashing.updateInt(hash, controls.active_isotopes.len);
    hash.update(controls.active_isotopes);
    hashing.updateOptionalFloat(hash, controls.threshold_line_scale);
    hashing.updateOptionalFloat(hash, controls.cutoff_cm1);
    hashing.updateFloatSlice(hash, controls.cutoff_grid_wavelengths_nm);
    hashing.updateFloatSlice(hash, controls.cutoff_grid_wavenumbers_cm1);
    hashing.updateFloat(hash, controls.line_mixing_factor);
}
