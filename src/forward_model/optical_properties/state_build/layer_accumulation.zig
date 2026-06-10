const std = @import("std");
const AerosolModel = @import("../../../input/Aerosol.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const Rayleigh = @import("../../../input/reference/rayleigh.zig");
const Context = @import("context.zig").PreparationContext;
const Absorbers = @import("absorbers.zig");
const LayerSpectroscopy = @import("layer_spectroscopy.zig");
const Spectroscopy = @import("spectroscopy.zig");
const State = @import("state.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const Trace = @import("../../instrumentation/trace.zig");
const work_partition = @import("../../work_partition.zig");
const ClimatologyProfile = @import("../../../input/reference/climatology.zig").ClimatologyProfile;
const spline = @import("../../../common/math/interpolation/spline.zig");
const internal = @import("internal.zig");

const Allocator = std.mem.Allocator;
const min_parallel_parity_support_row_count: usize = 64;
const parity_support_row_chunk_size: usize = 8;
const oxygen_volume_mixing_ratio = Spectroscopy.default_o2_volume_mixing_ratio;
const centimeters_per_kilometer = 1.0e5;
const boltzmann_hpa_cm3_per_k = internal.boltzmann_hpa_cm3_per_k;
const max_collision_complex_profile_nodes: usize = 64;
const profile_pressure_tolerance_hpa: f64 = 1.0e-9;
const profile_spectral_tolerance: f64 = 1.0e-12;

const pressureFromParitySupportBounds = internal.pressureFromParitySupportBounds;
const paritySupportThermodynamicsFromProfile = internal.paritySupportThermodynamicsFromProfile;

// layer_accumulation.zig ------------------------------------------------------------------------------------    |
// Layer and support-row accumulation stage for PreparedOpticalState.                                             |
//                                                                                                                |
// called by                                                                                                      |
//   accumulation.zig after Context.init and Absorbers.build; Finalize.assemble later moves the filled rows.      |
//                                                                                                                |
// main paths                                                                                                     |
//   normal grid           : populate each sublayer, accumulate its parent layer, and write PreparedLayer rows.   |
//   DISAMAR parity grid   : populate all shared support rows first, then reduce those rows into transport        |
//                           layers with the DISAMAR support-row placement kept intact.                           |
//   aerosol input         : scalar controls build a distribution; profile layers are pressure-overlap            |
//                           reduced into 48 B support-row properties, then collapsed to one equivalent HG phase  |
//                           row for the prepared state.                                                          |
//   spectroscopy/CIA      : midpoint profile spectroscopy and collision-complex caches avoid repeated setup      |
//                           while each support row is filled.                                                    |
//                                                                                                                |
// outputs                                                                                                        |
//   Writes context.sublayers, context.layers, context.aerosol_phase_coefficients, absorber density columns,      |
//   and the LayerAccumulation totals returned to accumulation.zig as PreparedMeans inputs.                       |
//                                                                                                                |
// hot path                                                                                                       |
//   Runs once per optical-state refresh before repeated wavelength solves. DISAMAR-parity support-row fill can   |
//   split independent support rows across worker chunks. Profile aerosol helpers reuse the same compact property |
//   rows for phase collapse and support-row fill. LayerAccumulation is a compact f64 total row, and              |
//   CollisionComplexProfileCache keeps the 64-node spline second-derivative table inline so per-row CIA sampling |
//   does not rebuild spline scratch.                                                                             |
//                                                                                                                |
// math                                                                                                           |
//   column = number_density * path_cm                                                                            |
//   tau_gas = sigma_cont*N_cont + sigma_line*N_line + sigma_xs*N_xs + tau_rayleigh                               |
//   tau_cia = sigma_cia * collision_pair_density * path_cm                                                       |
//   tau_aerosol uses scalar/profile placement at the reference wavelength; midpoint scaling is used only to      |
//   choose the equivalent phase row here. Wavelength scaling for RTM support rows happens later in               |
//   carrier_eval.zig.                                                                                            |
//                                                                                                                |
// memory                                                                                                         |
//   Context owns the output layer/support-row arrays during this stage. Worker rows borrow context, absorber,    |
//   cache, queue, aerosol, and error-state storage, and keep only private LayerAccumulation totals before the    |
//   final merge.                                                                                                 |
// ------------------------------------------------------------------------------------------------------------   |

// AerosolSublayerProperties ---------------------------------------------------------------------------------    |
// Profile aerosol values prepared for one support row before they are copied into PreparedSublayer storage.      |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 48 B (0.047 KiB), align: 8 B                                                                             |
//                                                                                                                |
// memory                                                                                                         |
// [ 0.. 7] optical_depth          : f64                                                                          |
// [ 8..15] base_optical_depth     : f64                                                                          |
// [16..23] single_scatter_albedo  : f64                                                                          |
// [24..31] reference_wavelength_nm: f64                                                                          |
// [32..39] angstrom_exponent      : f64                                                                          |
// [40..47] asymmetry_factor       : f64                                                                          |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// footprint: per instance = 48 B; total = per support row when profile aerosol input is active                   |
//                                                                                                                |
// hot path                                                                                                       |
//   Profile-aerosol preparation writes this compact row once, then later rows read it by pointer while filling   |
//   support rows and building the equivalent phase row. The phase collapse reads optical-depth scaling fields    |
//   through profileScatteringAtMidpoint, then reads asymmetry_factor at [40..47]; keeping one row avoids a       |
//   separate phase-only column that would duplicate the ownership path used by support-row fill.                 |
const AerosolSublayerProperties = struct {
    optical_depth: f64 = 0.0,
    base_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    reference_wavelength_nm: f64 = 550.0,
    angstrom_exponent: f64 = 0.0,
    asymmetry_factor: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------   |

const ScalarAerosolSublayers = struct {
    distribution: []const f64,
    single_scatter_albedo: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    asymmetry_factor: f64,
    fraction: f64,
};

const AerosolSublayers = union(enum) {
    scalar: ScalarAerosolSublayers,
    profile: []const AerosolSublayerProperties,

    fn deinit(self: AerosolSublayers, allocator: Allocator) void {
        switch (self) {
            .scalar => |scalar| allocator.free(scalar.distribution),
            .profile => |profile| allocator.free(profile),
        }
    }

    fn propertyAt(self: AerosolSublayers, index: usize) AerosolSublayerProperties {
        return switch (self) {
            .scalar => |scalar| if (index < scalar.distribution.len) .{
                .optical_depth = scalar.distribution[index] * scalar.fraction,
                .base_optical_depth = scalar.distribution[index],
                .single_scatter_albedo = scalar.single_scatter_albedo,
                .reference_wavelength_nm = scalar.reference_wavelength_nm,
                .angstrom_exponent = scalar.angstrom_exponent,
                .asymmetry_factor = scalar.asymmetry_factor,
            } else .{},
            .profile => |profile| if (index < profile.len) profile[index] else .{},
        };
    }

    fn singleScatterAlbedo(self: AerosolSublayers, context: *const Context) f64 {
        return switch (self) {
            .scalar => context.scene.aerosol.single_scatter_albedo,
            .profile => |profile| profileMeanSingleScatterAlbedo(context, profile),
        };
    }

    fn phaseCoefficients(
        self: AerosolSublayers,
        context: *const Context,
    ) [PhaseFunctions.phase_coefficient_count]f64 {
        return switch (self) {
            .scalar => PhaseFunctions.hgPhaseCoefficientsWithThreshold(
                context.scene.aerosol.asymmetry_factor,
                context.scene.phase_function_truncation_threshold,
            ),
            .profile => |profile| profileEquivalentPhaseCoefficients(context, profile),
        };
    }
};

// CollisionComplexProfileCache ------------------------------------------------------------------------------    |
// Fixed-capacity spline cache for collision-complex pair-density sampling.                                       |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 1048 B (1.023 KiB), align: 8 B                                                                           |
//                                                                                                                |
// memory                                                                                                         |
// [   0..   7] node_count               : usize                                                                  |
// [   8..  23] altitudes_km             : []const f64                                                            |
// [  24.. 535] log_complex_vmr_fraction : [64]f64                                                                |
// [ 536..1047] log_complex_second       : [64]f64                                                                |
//                                                                                                                |
// out-of-line                                                                                                    |
//   altitudes_km borrows the spectroscopy-profile altitude rows.                                                 |
//                                                                                                                |
// hot path                                                                                                       |
//   Pair-density samples reuse the 512 B spline-second table and avoid endpoint-secant scratch per sample.       |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 17 cache lines at 64 B per line                                                                    |
// footprint: per instance = 1048 B plus borrowed altitude storage                                                |
// capacity: enabled collision-complex requests with more than 64 profile nodes are rejected                      |
const CollisionComplexProfileCache = struct {
    node_count: usize = 0,
    altitudes_km: []const f64 = &.{},
    log_complex_vmr_fraction: [max_collision_complex_profile_nodes]f64 = undefined,
    log_complex_second: [max_collision_complex_profile_nodes]f64 = undefined,

    fn init(context: *const Context) !CollisionComplexProfileCache {
        if (context.collision_induced_absorption == null and !context.operational_o2o2_lut.enabled()) {
            return .{};
        }
        const node_count = context.spectroscopy_profile_altitudes_km.len;
        if (node_count > max_collision_complex_profile_nodes) return error.InvalidRequest;

        if (node_count < 3 or
            context.spectroscopy_profile_pressures_hpa.len != node_count or
            context.spectroscopy_profile_temperatures_k.len != node_count)
        {
            return .{};
        }

        var cache = CollisionComplexProfileCache{
            .node_count = node_count,
            .altitudes_km = context.spectroscopy_profile_altitudes_km[0..node_count],
            .log_complex_vmr_fraction = undefined,
            .log_complex_second = undefined,
        };
        for (0..node_count) |index| {
            const pressure_hpa = context.spectroscopy_profile_pressures_hpa[index];
            const temperature_k = context.spectroscopy_profile_temperatures_k[index];

            // math: n_air = p / (k_B * T); complex VMR proxy = n_o2^2 / n_air, stored as log for spline sampling.
            const node_air_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k;
            const parent_fraction = Spectroscopy.speciesMixingRatioAtPressure(
                context.scene,
                .o2,
                &.{},
                pressure_hpa,
                oxygen_volume_mixing_ratio,
            ) orelse oxygen_volume_mixing_ratio;

            const parent_density_cm3 = node_air_density_cm3 * parent_fraction;
            const complex_vmr_fraction = if (node_air_density_cm3 > 0.0)
                parent_density_cm3 * parent_density_cm3 / node_air_density_cm3
            else
                0.0;
            if (complex_vmr_fraction <= 0.0) return .{};

            cache.log_complex_vmr_fraction[index] = @log(complex_vmr_fraction);
        }
        spline.endpointSecantSecondDerivatives(
            cache.altitudes_km[0..node_count],
            cache.log_complex_vmr_fraction[0..node_count],
            cache.log_complex_second[0..node_count],
        ) catch return .{};

        return cache;
    }

    fn pairDensityCm6(
        self: *const CollisionComplexProfileCache,
        altitude_km: f64,
        air_number_density_cm3: f64,
        fallback_oxygen_number_density_cm3: f64,
    ) f64 {
        if (self.node_count < 3 or air_number_density_cm3 <= 0.0) {

            // math: fallback collision-pair density = n_O2^2.
            return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;
        }
        const altitudes = self.altitudes_km[0..self.node_count];
        const log_complex_vmr_fraction = self.log_complex_vmr_fraction[0..self.node_count];
        const log_complex_second = self.log_complex_second[0..self.node_count];
        if (altitude_km <= altitudes[0]) {

            // math: lower-edge pair density = exp(log(n_o2^2/n_air)) * n_air.
            return @exp(log_complex_vmr_fraction[0]) * air_number_density_cm3;
        }
        if (altitude_km >= altitudes[self.node_count - 1]) {

            // math: upper-edge pair density = exp(log(n_o2^2/n_air)) * n_air.
            return @exp(log_complex_vmr_fraction[self.node_count - 1]) * air_number_density_cm3;
        }
        const sampled_log_vmr = spline.sampleWithSecondDerivatives(
            altitudes,
            log_complex_vmr_fraction,
            log_complex_second,
            altitude_km,
        ) catch return fallback_oxygen_number_density_cm3 * fallback_oxygen_number_density_cm3;

        // math: n_pair = exp(spline(log(n_o2^2 / n_air), z)) * n_air
        return @exp(sampled_log_vmr) * air_number_density_cm3;
    }
};
// ------------------------------------------------------------------------------------------------------------   |

// ParitySupportRowErrorState --------------------------------------------------------------------------------    |
// Shared first-error slot for parity support-row workers.                                                        |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 24 B (0.023 KiB), align: 8 B                                                                             |
//                                                                                                                |
// memory                                                                                                         |
// [ 0..15] mutex   : Thread.Mutex                                                                                |
// [16..17] err     : ?anyerror                                                                                   |
// [18..23] padding : 6 B                                                                                         |
//                                                                                                                |
// unused bits: 48 padding + 0 bool-storage slack = 48 bits                                                       |
// footprint: per instance = 24 B; shared by workers in one parallel accumulation call                            |
const ParitySupportRowErrorState = struct {
    mutex: std.Thread.Mutex = .{},
    err: ?anyerror = null,

    fn store(self: *ParitySupportRowErrorState, err: anyerror) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.err == null) self.err = err;
    }
};
// ------------------------------------------------------------------------------------------------------------   |

// LayerAccumulationRequest ----------------------------------------------------------------------------------    |
// Borrowed inputs shared by layer and parity support-row accumulation. This value owns no arrays; Context and    |
// AbsorberBuildState keep ownership of output rows, absorber density columns, and spectroscopy caches.           |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 96 B (0.094 KiB), align: 8 B                                                                             |
//                                                                                                                |
// memory                                                                                                         |
// [ 0.. 7] context                    : *PreparationContext                                                      |
// [ 8..15] absorbers                  : *AbsorberBuildState                                                      |
// [16..23] profile_spectroscopy_cache : ?*const ProfileSpectroscopyCache                                         |
// [24..31] collision_complex_cache    : *const CollisionComplexProfileCache                                      |
// [32..95] aerosol_sublayers          : AerosolSublayers                                                         |
//                                                                                                                |
// out-of-line                                                                                                    |
//   all fields borrow setup data prepared by populate(); no heap storage moves through this view.                |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 2 cache lines at 64 B per line                                                                     |
// footprint: per instance = 96 B plus borrowed storage                                                           |
const LayerAccumulationRequest = struct {
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
    collision_complex_cache: *const CollisionComplexProfileCache,
    aerosol_sublayers: AerosolSublayers,
};
// ------------------------------------------------------------------------------------------------------------   |

// SublayerTarget --------------------------------------------------------------------------------------------    |
// Row indexes and physical layer thickness for one output support row.                                           |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 32 B (0.031 KiB), align: 8 B                                                                             |
//                                                                                                                |
// memory                                                                                                         |
// [ 0.. 7] layer_thickness_km  : f64                                                                             |
// [ 8..15] parent_layer_index  : usize                                                                           |
// [16..23] sublayer_index      : usize                                                                           |
// [24..31] write_index         : usize                                                                           |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// footprint: per instance = 32 B; stack value for one support row                                                |
const SublayerTarget = struct {
    layer_thickness_km: f64,
    parent_layer_index: usize,
    sublayer_index: usize,
    write_index: usize,
};
// ------------------------------------------------------------------------------------------------------------   |

// ParitySupportRowWorker ------------------------------------------------------------------------------------    |
// Worker row used by parallel parity support-row accumulation.                                                   |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 184 B (0.180 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0.. 15] allocator    : Allocator                                                                            |
// [ 16.. 23] request      : *const LayerAccumulationRequest                                                      |
// [ 24.. 31] queue        : *ChunkQueue                                                                          |
// [ 32.. 39] error_state  : *ParitySupportRowErrorState                                                          |
// [ 40.. 47] worker_index : usize                                                                                |
// [ 48..183] totals       : LayerAccumulation                                                                    |
//                                                                                                                |
// out-of-line                                                                                                    |
//   request, queue, and error-state storage are borrowed. Each worker owns only its private totals row.          |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 3 cache lines at 64 B per line                                                                     |
// footprint: per instance = 184 B plus borrowed request/queue/error storage                                      |
const ParitySupportRowWorker = struct {
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
    queue: *work_partition.ChunkQueue,
    error_state: *ParitySupportRowErrorState,
    worker_index: usize,
    totals: LayerAccumulation = .{},
};
// ------------------------------------------------------------------------------------------------------------   |

fn collisionComplexPairDensityCm6(
    collision_complex_cache: *const CollisionComplexProfileCache,
    altitude_km: f64,
    air_number_density_cm3: f64,
    fallback_oxygen_number_density_cm3: f64,
) f64 {
    return collision_complex_cache.pairDensityCm6(
        altitude_km,
        air_number_density_cm3,
        fallback_oxygen_number_density_cm3,
    );
}

// LayerAccumulation -----------------------------------------------------------------------------------------    |
// Running f64 totals for one layer or worker partition.                                                          |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 136 B (0.133 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0..  7] base_single_scatter_albedo          : f64                                                           |
// [  8.. 15] aerosol_single_scatter_albedo       : f64                                                           |
// [ 16.. 23] total_optical_depth                 : f64                                                           |
// [ 24.. 31] total_temperature_weighted          : f64                                                           |
// [ 32.. 39] total_pressure_weighted             : f64                                                           |
// [ 40.. 47] total_weight                        : f64                                                           |
// [ 48.. 55] air_column_density_factor           : f64                                                           |
// [ 56.. 63] oxygen_column_density_factor        : f64                                                           |
// [ 64.. 71] column_density_factor               : f64                                                           |
// [ 72.. 79] cia_pair_path_factor_cm5            : f64                                                           |
// [ 80.. 87] total_gas_optical_depth             : f64                                                           |
// [ 88.. 95] total_cia_optical_depth             : f64                                                           |
// [ 96..103] total_aerosol_optical_depth         : f64                                                           |
// [104..111] total_aerosol_base_optical_depth    : f64                                                           |
// [112..119] total_scattering_optical_depth      : f64                                                           |
// [120..127] total_d_optical_depth_d_temperature : f64                                                           |
// [128..135] depolarization_weighted             : f64                                                           |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 3 cache lines at 64 B per line                                                                     |
// footprint: per instance = 136 B; one row per accumulated layer or worker total                                 |
pub const LayerAccumulation = struct {
    base_single_scatter_albedo: f64 = 0.0,
    aerosol_single_scatter_albedo: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    total_temperature_weighted: f64 = 0.0,
    total_pressure_weighted: f64 = 0.0,
    total_weight: f64 = 0.0,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64 = 0.0,
    cia_pair_path_factor_cm5: f64 = 0.0,
    total_gas_optical_depth: f64 = 0.0,
    total_cia_optical_depth: f64 = 0.0,
    total_aerosol_optical_depth: f64 = 0.0,
    total_aerosol_base_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    total_d_optical_depth_d_temperature: f64 = 0.0,
    depolarization_weighted: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------   |

// LayerGeometry ---------------------------------------------------------------------------------------------    |
// Layer altitude, pressure, sublayer span, and thickness used while accumulating one layer.                      |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 64 B (0.062 KiB), align: 8 B                                                                             |
//                                                                                                                |
// memory                                                                                                         |
// [ 0.. 7] top_altitude_km        : f64                                                                          |
// [ 8..15] bottom_altitude_km     : f64                                                                          |
// [16..23] center_altitude_km     : f64                                                                          |
// [24..31] top_pressure_hpa       : f64                                                                          |
// [32..39] bottom_pressure_hpa    : f64                                                                          |
// [40..47] thickness_km           : f64                                                                          |
// [48..51] sublayer_start_index   : u32                                                                          |
// [52..55] sublayer_count         : u32                                                                          |
// [56..59] interval_index_1based  : u32                                                                          |
// [60..63] padding                : 4 B                                                                          |
//                                                                                                                |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                       |
// cache span: 1 cache line at 64 B per line                                                                      |
// footprint: per instance = 64 B; stack value during layer accumulation                                          |
const LayerGeometry = struct {
    top_altitude_km: f64,
    bottom_altitude_km: f64,
    center_altitude_km: f64,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    sublayer_start_index: u32,
    sublayer_count: u32,
    interval_index_1based: u32,
    thickness_km: f64,
};
// ------------------------------------------------------------------------------------------------------------   |

// LayerSums -------------------------------------------------------------------------------------------------    |
// Per-layer f64 sums before they are normalized into LayerAccumulation fields.                                   |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 120 B (0.117 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0..  7] density_weight                    : f64                                                             |
// [  8.. 15] density                           : f64                                                             |
// [ 16.. 23] temperature_weighted              : f64                                                             |
// [ 24.. 31] pressure_weighted                 : f64                                                             |
// [ 32.. 39] line_sigma                        : f64                                                             |
// [ 40.. 47] line_mixing                       : f64                                                             |
// [ 48.. 55] d_cross_section_d_temperature     : f64                                                             |
// [ 56.. 63] gas_optical_depth                 : f64                                                             |
// [ 64.. 71] gas_scattering_optical_depth      : f64                                                             |
// [ 72.. 79] cia_optical_depth                 : f64                                                             |
// [ 80.. 87] aerosol_optical_depth             : f64                                                             |
// [ 88.. 95] aerosol_base_optical_depth        : f64                                                             |
// [ 96..103] aerosol_scattering_optical_depth  : f64                                                             |
// [104..111] aerosol_reference_wavelength_sum  : f64                                                             |
// [112..119] aerosol_angstrom_sum              : f64                                                             |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 2 cache lines at 64 B per line                                                                     |
// footprint: per instance = 120 B; stack value before normalization                                              |
const LayerSums = struct {
    density_weight: f64 = 0.0,
    density: f64 = 0.0,
    temperature_weighted: f64 = 0.0,
    pressure_weighted: f64 = 0.0,
    line_sigma: f64 = 0.0,
    line_mixing: f64 = 0.0,
    d_cross_section_d_temperature: f64 = 0.0,
    gas_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_base_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    aerosol_reference_wavelength_sum: f64 = 0.0,
    aerosol_angstrom_sum: f64 = 0.0,

    fn addSublayer(self: *LayerSums, terms: SublayerLayerTerms) void {

        // math: layer means are density-weighted, e.g. T_bar numerator += T_i * n_i * w_i and denominator += n_i * w_i.
        self.density_weight += terms.density * terms.weight;
        self.density += terms.density * terms.weight;
        self.temperature_weighted += terms.temperature * terms.density * terms.weight;
        self.pressure_weighted += terms.pressure * terms.density * terms.weight;
        self.line_sigma += terms.line_sigma;
        self.line_mixing += terms.line_mixing;
        self.d_cross_section_d_temperature += terms.d_cross_section_d_temperature;
        self.gas_optical_depth += terms.gas_absorption_optical_depth + terms.gas_scattering_optical_depth;
        self.gas_scattering_optical_depth += terms.gas_scattering_optical_depth;
        self.cia_optical_depth += terms.cia_optical_depth;
        self.aerosol_optical_depth += terms.aerosol_optical_depth;
        self.aerosol_base_optical_depth += terms.aerosol_base_optical_depth;
        self.aerosol_scattering_optical_depth += terms.aerosol_scattering_optical_depth;
        self.aerosol_reference_wavelength_sum += terms.aerosol_optical_depth * terms.aerosol_reference_wavelength_nm;
        self.aerosol_angstrom_sum += terms.aerosol_optical_depth * terms.aerosol_angstrom_exponent;
    }

    fn temperature(self: LayerSums) f64 {
        return if (self.density_weight == 0.0) 0.0 else self.temperature_weighted / self.density_weight;
    }

    fn pressure(self: LayerSums) f64 {
        return if (self.density_weight == 0.0) 0.0 else self.pressure_weighted / self.density_weight;
    }

    fn meanLineSigma(self: LayerSums, sublayer_count: u32) f64 {
        return self.line_sigma / @as(f64, @floatFromInt(@max(sublayer_count, 1)));
    }

    fn meanLineMixing(self: LayerSums, sublayer_count: u32) f64 {
        return self.line_mixing / @as(f64, @floatFromInt(@max(sublayer_count, 1)));
    }

    fn meanTemperatureDerivative(self: LayerSums, sublayer_count: u32) f64 {
        return self.d_cross_section_d_temperature / @as(f64, @floatFromInt(@max(sublayer_count, 1)));
    }
};
// ------------------------------------------------------------------------------------------------------------   |

// SublayerLayerTerms ----------------------------------------------------------------------------------------    |
// One sublayer's f64 contribution terms before they are added into LayerSums.                                    |
//                                                                                                                |
// layout(64-bit)                                                                                                 |
// size: 120 B (0.117 KiB), align: 8 B                                                                            |
//                                                                                                                |
// memory                                                                                                         |
// [  0..  7] density                           : f64                                                             |
// [  8.. 15] temperature                       : f64                                                             |
// [ 16.. 23] pressure                          : f64                                                             |
// [ 24.. 31] weight                            : f64                                                             |
// [ 32.. 39] line_sigma                        : f64                                                             |
// [ 40.. 47] line_mixing                       : f64                                                             |
// [ 48.. 55] d_cross_section_d_temperature     : f64                                                             |
// [ 56.. 63] gas_absorption_optical_depth      : f64                                                             |
// [ 64.. 71] gas_scattering_optical_depth      : f64                                                             |
// [ 72.. 79] cia_optical_depth                 : f64                                                             |
// [ 80.. 87] aerosol_optical_depth             : f64                                                             |
// [ 88.. 95] aerosol_base_optical_depth        : f64                                                             |
// [ 96..103] aerosol_scattering_optical_depth  : f64                                                             |
// [104..111] aerosol_reference_wavelength_nm   : f64                                                             |
// [112..119] aerosol_angstrom_exponent         : f64                                                             |
//                                                                                                                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                         |
// cache span: 2 cache lines at 64 B per line                                                                     |
// footprint: per instance = 120 B; stack value inside the sublayer loop                                          |
const SublayerLayerTerms = struct {
    density: f64,
    temperature: f64,
    pressure: f64,
    weight: f64,
    line_sigma: f64,
    line_mixing: f64,
    d_cross_section_d_temperature: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
};

pub fn populate(
    allocator: Allocator,
    context: *Context,
    absorbers: *Absorbers.AbsorberBuildState,
) !LayerAccumulation {
    // populate ------------------------------------------------------------------------------------------------  |
    // Accumulates particles, phase coefficients, spectroscopy carriers, support rows, and RTM layer data.        |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs once per optical-state preparation before repeated wavelength solves. Particle placement and        |
    //   phase-coefficient setup are kept here so carrier and transport paths read prepared rows.                 |
    //                                                                                                            |
    // calls                                                                                                      |
    //   populateParitySupportRowsParallel                                                                        |
    //   populateLayer                                                                                            |
    //   shared carrier reduction                                                                                 |
    //                                                                                                            |
    // math                                                                                                       |
    //   aerosol_tau_i = fraction_i * Angstrom-scaled sublayer weight                                             |
    //   phase rows use HG(g) before gas/aerosol mixing                                                           |
    // ---------------------------------------------------------------------------------------------------------  |

    var totals: LayerAccumulation = .{
        .base_single_scatter_albedo = PhaseFunctions.computeSingleScatterAlbedo(
            context.scene,
            context.midpoint_nm,
        ),
    };

    const aerosol_sublayers = try buildAerosolSublayers(allocator, context);
    defer aerosol_sublayers.deinit(allocator);

    totals.aerosol_single_scatter_albedo = aerosol_sublayers.singleScatterAlbedo(context);
    context.aerosol_phase_coefficients = aerosol_sublayers.phaseCoefficients(context);
    var profile_spectroscopy_cache = try LayerSpectroscopy.ProfileSpectroscopyCache.init(
        context,
        absorbers,
        context.midpoint_nm,
    );
    const profile_spectroscopy_cache_ptr = if (profile_spectroscopy_cache.node_count != 0)
        &profile_spectroscopy_cache
    else
        null;
    const collision_complex_cache = try CollisionComplexProfileCache.init(context);
    const accumulation_request = LayerAccumulationRequest{
        .context = context,
        .absorbers = absorbers,
        .profile_spectroscopy_cache = profile_spectroscopy_cache_ptr,
        .collision_complex_cache = &collision_complex_cache,
        .aerosol_sublayers = aerosol_sublayers,
    };

    if (usesDisamarParitySupportGrid(context)) {
        seedParitySupportRowLayerIndices(context);
        if (canParallelPopulateParitySupportRows(context, absorbers, profile_spectroscopy_cache_ptr)) {
            const parity_totals = try populateParitySupportRowsParallel(
                allocator,
                &accumulation_request,
            );
            mergeLayerAccumulationTotals(&totals, parity_totals);
        } else {
            const parity_totals = try populateParitySupportRows(
                allocator,
                &accumulation_request,
            );
            mergeLayerAccumulationTotals(&totals, parity_totals);
        }
        for (context.layers, 0..) |*layer, index| {
            reduceParityLayer(
                context,
                layer,
                index,
            );
        }
        return totals;
    }

    for (context.layers, 0..) |*layer, index| {
        const layer_totals = try populateLayer(
            allocator,
            &accumulation_request,
            layer,
            index,
        );
        mergeLayerAccumulationTotals(&totals, layer_totals);
    }

    return totals;
}

fn buildAerosolSublayers(
    allocator: Allocator,
    context: *const Context,
) !AerosolSublayers {
    if (context.aerosol_profile_layers.len != 0) {
        return .{ .profile = try buildAerosolProfileSublayerProperties(allocator, context) };
    }

    const distribution = try ParticleProfiles.buildAerosolSublayerDistribution(
        allocator,
        context.scene,
        context.vertical_grid.borrow(),
    );

    const aerosol_fraction = choose_aerosol_fraction: {
        break :choose_aerosol_fraction if (context.scene.aerosol.fraction.enabled)
            context.scene.aerosol.fraction.valueAtWavelength(context.midpoint_nm)
        else if (context.scene.aerosol.enabled)
            @as(f64, 1.0)
        else
            @as(f64, 0.0);
    };

    return .{
        .scalar = .{
            .distribution = distribution,
            .single_scatter_albedo = context.scene.aerosol.single_scatter_albedo,
            .reference_wavelength_nm = context.scene.aerosol.reference_wavelength_nm,
            .angstrom_exponent = context.scene.aerosol.angstrom_exponent,
            .asymmetry_factor = context.scene.aerosol.asymmetry_factor,
            .fraction = aerosol_fraction,
        },
    };
}

fn buildAerosolProfileSublayerProperties(
    allocator: Allocator,
    context: *const Context,
) ![]AerosolSublayerProperties {
    const sublayer_count = context.vertical_grid.sublayer_mid_altitudes_km.len;
    const properties = try allocator.alloc(AerosolSublayerProperties, sublayer_count);
    errdefer allocator.free(properties);
    @memset(properties, AerosolSublayerProperties{});

    for (context.aerosol_profile_layers) |profile_layer| {
        const layer_pressure_span = profile_layer.bottom_pressure_hpa - profile_layer.top_pressure_hpa;
        if (layer_pressure_span <= 0.0 or profile_layer.optical_depth == 0.0) continue;
        var covered_pressure_span: f64 = 0.0;
        for (
            properties,
            context.vertical_grid.sublayer_top_pressures_hpa,
            context.vertical_grid.sublayer_bottom_pressures_hpa,
        ) |*property, sublayer_top_pressure, sublayer_bottom_pressure| {
            const overlap_top = @max(profile_layer.top_pressure_hpa, sublayer_top_pressure);

            const overlap_bottom = @min(profile_layer.bottom_pressure_hpa, sublayer_bottom_pressure);
            const overlap = overlap_bottom - overlap_top;
            if (overlap <= 0.0) continue;
            covered_pressure_span += overlap;

            const added_optical_depth = profile_layer.optical_depth * (overlap / layer_pressure_span);
            if (added_optical_depth <= 0.0) continue;
            const old_optical_depth = property.optical_depth;
            if (old_optical_depth > 0.0 and !profileSpectralScalingMatches(property, profile_layer)) {
                return error.InvalidRequest;
            }
            const new_optical_depth = old_optical_depth + added_optical_depth;
            const old_scattering = old_optical_depth * property.single_scatter_albedo;
            const added_scattering = added_optical_depth * profile_layer.single_scatter_albedo;
            const new_scattering = old_scattering + added_scattering;

            property.base_optical_depth = new_optical_depth;
            property.optical_depth = new_optical_depth;
            property.single_scatter_albedo = if (new_optical_depth > 0.0)
                std.math.clamp(new_scattering / new_optical_depth, 0.0, 1.0)
            else
                0.0;

            property.reference_wavelength_nm = choose_value: {
                break :choose_value if (new_optical_depth > 0.0)
                    (old_optical_depth * property.reference_wavelength_nm +
                        added_optical_depth * profile_layer.reference_wavelength_nm) / new_optical_depth
                else
                    profile_layer.reference_wavelength_nm;
            };
            property.angstrom_exponent = choose_value: {
                break :choose_value if (new_optical_depth > 0.0)
                    (old_optical_depth * property.angstrom_exponent +
                        added_optical_depth * profile_layer.angstrom_exponent) / new_optical_depth
                else
                    profile_layer.angstrom_exponent;
            };

            property.asymmetry_factor = choose_value: {
                break :choose_value if (new_scattering > 0.0)
                    (old_scattering * property.asymmetry_factor +
                        added_scattering * profile_layer.asymmetry_factor) / new_scattering
                else
                    profile_layer.asymmetry_factor;
            };
        }
        if (covered_pressure_span + profile_pressure_tolerance_hpa < layer_pressure_span) {
            return error.InvalidRequest;
        }
    }
    return properties;
}

fn profileSpectralScalingMatches(
    property: *const AerosolSublayerProperties,
    profile_layer: AerosolModel.ProfileLayer,
) bool {
    return std.math.approxEqAbs(
        f64,
        property.reference_wavelength_nm,
        profile_layer.reference_wavelength_nm,
        profile_spectral_tolerance,
    ) and std.math.approxEqAbs(
        f64,
        property.angstrom_exponent,
        profile_layer.angstrom_exponent,
        profile_spectral_tolerance,
    );
}

fn profileScatteringAtMidpoint(
    context: *const Context,
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    single_scatter_albedo: f64,
) f64 {
    // profileScatteringAtMidpoint -----------------------------------------------------------------------------  |
    // Compute profile-aerosol scattering optical depth at the preparation midpoint wavelength.                   |
    //                                                                                                            |
    // math                                                                                                       |
    //   scattering_i = scaled_tau_i(midpoint_nm) * single_scatter_albedo_i                                       |
    // ---------------------------------------------------------------------------------------------------------  |

    if (optical_depth <= 0.0 or single_scatter_albedo <= 0.0) return 0.0;
    const scaled_optical_depth = ParticleProfiles.scaleOpticalDepth(
        optical_depth,
        reference_wavelength_nm,
        angstrom_exponent,
        context.midpoint_nm,
    );
    return scaled_optical_depth * single_scatter_albedo;
}

fn profileMeanSingleScatterAlbedo(
    context: *const Context,
    aerosol_sublayers: []const AerosolSublayerProperties,
) f64 {
    // profileMeanSingleScatterAlbedo ----------------------------------------------------------------------------|
    // Collapse profile-aerosol support rows into the scalar aerosol single-scatter albedo kept in totals.        |
    //                                                                                                            |
    // memory                                                                                                     |
    //   Walks the 48 B profile rows by pointer. Each active row reads optical_depth [0..7],                      |
    //   single_scatter_albedo [16..23], reference_wavelength_nm [24..31], and angstrom_exponent [32..39].        |
    //                                                                                                            |
    // math                                                                                                       |
    //   ssa_mean = sum(scaled_tau_i * single_scatter_albedo_i) / sum(scaled_tau_i)                               |
    // ---------------------------------------------------------------------------------------------------------  |

    var optical_depth: f64 = 0.0;
    var scattering: f64 = 0.0;

    for (aerosol_sublayers) |*property| {
        if (property.optical_depth <= 0.0) continue;
        const scaled_optical_depth = ParticleProfiles.scaleOpticalDepth(
            property.optical_depth,
            property.reference_wavelength_nm,
            property.angstrom_exponent,
            context.midpoint_nm,
        );

        optical_depth += scaled_optical_depth;
        scattering += scaled_optical_depth * property.single_scatter_albedo;
    }
    return if (optical_depth > 0.0)
        std.math.clamp(scattering / optical_depth, 0.0, 1.0)
    else
        0.0;
}

fn profileEquivalentPhaseCoefficients(
    context: *const Context,
    aerosol_sublayers: []const AerosolSublayerProperties,
) [PhaseFunctions.phase_coefficient_count]f64 {
    // profileEquivalentPhaseCoefficients ----------------------------------------------------------------------  |
    // Collapse a profile aerosol layer set into one Henyey-Greenstein phase row for the prepared state.          |
    //                                                                                                            |
    // call path                                                                                                  |
    //   AerosolSublayers.phaseCoefficients calls this once during preparation for profile aerosol input.         |
    //                                                                                                            |
    // memory                                                                                                     |
    //   AerosolSublayerProperties is a 48 B support-row property record. The local loop reads                    |
    //   asymmetry_factor at [40..47]; profileScatteringAtMidpoint performs the optical-depth,                    |
    //   reference-wavelength, Angstrom, and single-scatter-albedo reads.                                         |
    //   This writes one final phase coefficient row into context.aerosol_phase_coefficients.                     |
    //                                                                                                            |
    // math                                                                                                       |
    //   g_equiv = sum(scattering_i * asymmetry_i) / sum(scattering_i)                                            |
    //   scattering_i is midpoint-wavelength aerosol optical depth times single-scatter albedo.                   |
    // ---------------------------------------------------------------------------------------------------------  |

    var scattering: f64 = 0.0;
    var asymmetry_sum: f64 = 0.0;

    for (aerosol_sublayers) |*property| {
        const sublayer_scattering = profileScatteringAtMidpoint(
            context,
            property.optical_depth,
            property.reference_wavelength_nm,
            property.angstrom_exponent,
            property.single_scatter_albedo,
        );
        if (sublayer_scattering <= 0.0) continue;
        scattering += sublayer_scattering;

        asymmetry_sum += sublayer_scattering * property.asymmetry_factor;
    }
    const asymmetry_factor = if (scattering > 0.0)
        asymmetry_sum / scattering
    else
        context.scene.aerosol.asymmetry_factor;

    return PhaseFunctions.hgPhaseCoefficientsWithThreshold(
        asymmetry_factor,
        context.scene.phase_function_truncation_threshold,
    );
}

fn populateParitySupportRows(
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
) !LayerAccumulation {
    var totals: LayerAccumulation = .{};
    for (0..request.context.sublayers.len) |write_index| {
        const current_layer_index: usize = @intCast(request.context.sublayers[write_index].parent_layer_index);
        const row_totals = try populateParitySupportRow(
            allocator,
            request,
            current_layer_index,
            @intCast(request.context.sublayers[write_index].sublayer_index),
            write_index,
        );
        mergeLayerAccumulationTotals(&totals, row_totals);
    }
    return totals;
}

fn populateParitySupportRowsParallel(
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
) !LayerAccumulation {
    // populateParitySupportRowsParallel -----------------------------------------------------------------------  |
    // Fills independent parity support rows used by later wavelength carrier caching.                            |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Splits support-row preparation across worker chunks when the sublayer count is large enough. Each        |
    //   worker writes private totals and support rows, then reduceParityLayer folds the result.                  |
    //                                                                                                            |
    // calls                                                                                                      |
    //   paritySupportRowWorkerMain                                                                               |
    //   reduceParityLayer                                                                                        |
    // ---------------------------------------------------------------------------------------------------------  |

    const worker_count = preferredParitySupportRowWorkerCount(request.context.sublayers.len);
    if (worker_count == 1) {
        return populateParitySupportRows(
            allocator,
            request,
        );
    }

    var error_state = ParitySupportRowErrorState{};
    var queue = work_partition.ChunkQueue.init(request.context.sublayers.len, parity_support_row_chunk_size);
    var worker_buffer: [work_partition.max_workers]ParitySupportRowWorker = undefined;
    var thread_buffer: [work_partition.max_workers - 1]std.Thread = undefined;
    const workers = worker_buffer[0..worker_count];
    const threads = thread_buffer[0 .. worker_count - 1];
    var started_thread_count: usize = 0;

    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .allocator = allocator,
            .request = request,
            .queue = &queue,
            .error_state = &error_state,
            .worker_index = worker_index,
        };

        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                paritySupportRowWorkerMain,
                .{&workers[worker_index]},
            ) catch {
                paritySupportRowWorkerMain(&workers[worker_index]);

                continue;
            };
            started_thread_count += 1;
        } else {
            paritySupportRowWorkerMain(&workers[worker_index]);
        }
    }
    for (threads[0..started_thread_count]) |thread| thread.join();

    if (error_state.err) |err| return err;

    var totals: LayerAccumulation = .{};
    for (workers) |worker| {
        mergeLayerAccumulationTotals(&totals, worker.totals);
    }
    return totals;
}

fn paritySupportRowWorkerMain(worker: *ParitySupportRowWorker) void {
    var thread_name_buffer: [64]u8 = undefined;
    const thread_name = std.fmt.bufPrintZ(
        &thread_name_buffer,
        "zdisamar-accum-{d}",
        .{worker.worker_index},
    ) catch "zdisamar-accum-worker";

    // instrumentation: trace thread label
    // captures: parity support-row worker identity
    // why: make parallel optical-accumulation lanes separable in timeline traces.
    Trace.setThreadName(thread_name);

    // instrumentation: trace zone
    // captures: parity support-row worker wall time
    // why: expose load balance while support rows are filled before layer reduction.
    const worker_zone = Trace.staticZone(@src(), "optical_prepare.parity_rows_worker");
    worker_zone.value(@intCast(worker.worker_index));
    defer worker_zone.end();

    while (worker.queue.next()) |chunk| {
        {

            // instrumentation: trace zone
            // captures: parity support-row chunk wall time and row count
            // why: reveal chunking overhead in optical-state support-row preparation.
            const chunk_zone = Trace.deepStaticZone(@src(), "optical_prepare.parity_rows_chunk");
            chunk_zone.value(@intCast(chunk.end - chunk.start));
            defer chunk_zone.end();

            for (chunk.start..chunk.end) |write_index| {

                // Hot path:
                //   Parent-layer ownership is seeded into the support-row
                //   output buffer before fanout. Workers then load the row-local
                //   indexes directly instead of scanning layer starts.
                const context = worker.request.context;
                const current_layer_index: usize = @intCast(context.sublayers[write_index].parent_layer_index);
                const row_totals = populateParitySupportRow(
                    worker.allocator,
                    worker.request,
                    current_layer_index,
                    @intCast(context.sublayers[write_index].sublayer_index),
                    write_index,
                ) catch |err| {
                    worker.error_state.store(err);
                    return;
                };
                mergeLayerAccumulationTotals(&worker.totals, row_totals);
            }
        }
    }
}

fn populateParitySupportRow(
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
    current_layer_index: usize,
    current_sublayer_index: usize,
    write_index: usize,
) !LayerAccumulation {
    const context = request.context;
    const layer_thickness_km = @max(
        context.vertical_grid.layer_top_altitudes_km[current_layer_index] -
            context.vertical_grid.layer_bottom_altitudes_km[current_layer_index],
        1.0e-9,
    );
    var ignored_layer_sums: LayerSums = .{};
    return populateSublayer(
        allocator,
        request,
        .{
            .layer_thickness_km = layer_thickness_km,
            .parent_layer_index = current_layer_index,
            .sublayer_index = current_sublayer_index,
            .write_index = write_index,
        },
        &ignored_layer_sums,
    );
}

fn canParallelPopulateParitySupportRows(
    context: *const Context,
    absorbers: *const Absorbers.AbsorberBuildState,
    profile_spectroscopy_cache: ?*const LayerSpectroscopy.ProfileSpectroscopyCache,
) bool {
    return context.sublayers.len >= min_parallel_parity_support_row_count and
        profile_spectroscopy_cache != null and
        absorbers.owned_cross_section_absorbers.len == 0 and
        absorbers.owned_line_absorbers.len == 0 and
        absorbers.strong_line_states == null;
}

fn preferredParitySupportRowWorkerCount(row_count: usize) usize {
    return work_partition.preferredWorkerCount(row_count, min_parallel_parity_support_row_count);
}

fn seedParitySupportRowLayerIndices(context: *Context) void {
    if (context.layers.len == 0) return;
    var layer_index: usize = 0;
    for (0..context.sublayers.len) |write_index| {
        while (layer_index + 1 < context.layers.len and
            write_index >= @as(usize, @intCast(context.layers[layer_index + 1].sublayer_start_index)))
        {
            layer_index += 1;
        }
        const layer_start_index = @as(usize, @intCast(context.layers[layer_index].sublayer_start_index));
        context.sublayers[write_index].parent_layer_index = @intCast(layer_index);
        context.sublayers[write_index].sublayer_index = @intCast(if (write_index >= layer_start_index)
            write_index - layer_start_index
        else
            0);
    }
}

fn mergeLayerAccumulationTotals(total: *LayerAccumulation, local: LayerAccumulation) void {
    total.base_single_scatter_albedo += local.base_single_scatter_albedo;
    total.aerosol_single_scatter_albedo += local.aerosol_single_scatter_albedo;
    total.total_optical_depth += local.total_optical_depth;
    total.total_temperature_weighted += local.total_temperature_weighted;
    total.total_pressure_weighted += local.total_pressure_weighted;
    total.total_weight += local.total_weight;
    total.air_column_density_factor += local.air_column_density_factor;
    total.oxygen_column_density_factor += local.oxygen_column_density_factor;
    total.column_density_factor += local.column_density_factor;
    total.cia_pair_path_factor_cm5 += local.cia_pair_path_factor_cm5;
    total.total_gas_optical_depth += local.total_gas_optical_depth;
    total.total_cia_optical_depth += local.total_cia_optical_depth;
    total.total_aerosol_optical_depth += local.total_aerosol_optical_depth;
    total.total_aerosol_base_optical_depth += local.total_aerosol_base_optical_depth;
    total.total_scattering_optical_depth += local.total_scattering_optical_depth;
    total.total_d_optical_depth_d_temperature += local.total_d_optical_depth_d_temperature;
    total.depolarization_weighted += local.depolarization_weighted;
}

fn reduceParityLayer(
    context: *Context,
    layer: *State.PreparedLayer,
    index: usize,
) void {

    // math: parity layer totals sum interior support rows; tau = tau_gas + tau_cia + tau_aerosol, omega0 = tau_sca /
    // max(tau_abs + tau_sca, eps).
    const layer_top_altitude_km = context.vertical_grid.layer_top_altitudes_km[index];
    const layer_bottom_altitude_km = context.vertical_grid.layer_bottom_altitudes_km[index];
    const layer_top_pressure_hpa = context.vertical_grid.layer_top_pressures_hpa[index];
    const layer_bottom_pressure_hpa = context.vertical_grid.layer_bottom_pressures_hpa[index];
    const layer_sublayer_start_index = context.vertical_grid.layer_sublayer_starts[index];
    const layer_sublayer_count = context.vertical_grid.layer_sublayer_counts[index];
    const layer_interval_index_1based = context.vertical_grid.layer_interval_indices_1based[index];
    const start_index: usize = @intCast(layer_sublayer_start_index);
    const count: usize = @intCast(layer_sublayer_count);
    const support_rows = context.sublayers[start_index .. start_index + count];
    const lower_boundary = support_rows[0];

    var layer_line_sigma_sum: f64 = 0.0;
    var layer_line_mixing_sum: f64 = 0.0;
    var layer_d_cross_section_sum: f64 = 0.0;
    var layer_gas_optical_depth: f64 = 0.0;
    var layer_gas_scattering_optical_depth: f64 = 0.0;
    var layer_cia_optical_depth: f64 = 0.0;
    var layer_aerosol_optical_depth: f64 = 0.0;
    var layer_aerosol_base_optical_depth: f64 = 0.0;
    var layer_aerosol_scattering_optical_depth: f64 = 0.0;
    var layer_reference_wavelength_sum: f64 = 0.0;
    var layer_angstrom_sum: f64 = 0.0;
    var support_point_count: usize = 0;

    if (support_rows.len > 2) {
        for (support_rows[1 .. support_rows.len - 1]) |support_row| {
            layer_line_sigma_sum += support_row.line_cross_section_cm2_per_molecule;
            layer_line_mixing_sum += support_row.line_mixing_cross_section_cm2_per_molecule;
            layer_d_cross_section_sum += support_row.d_cross_section_d_temperature_cm2_per_molecule_per_k;
            layer_gas_optical_depth +=
                support_row.gas_absorption_optical_depth + support_row.gas_scattering_optical_depth;
            layer_gas_scattering_optical_depth += support_row.gas_scattering_optical_depth;
            layer_cia_optical_depth += support_row.cia_optical_depth;
            layer_aerosol_optical_depth += support_row.aerosol_optical_depth;
            layer_aerosol_base_optical_depth += support_row.aerosol_base_optical_depth;
            layer_aerosol_scattering_optical_depth +=
                support_row.aerosol_optical_depth * support_row.aerosol_single_scatter_albedo;
            layer_reference_wavelength_sum +=
                support_row.aerosol_optical_depth * support_row.aerosol_reference_wavelength_nm;
            layer_angstrom_sum += support_row.aerosol_optical_depth * support_row.aerosol_angstrom_exponent;
            support_point_count += 1;
        }
    }

    const aerosol_scattering = layer_aerosol_scattering_optical_depth;
    const gas_scattering = layer_gas_scattering_optical_depth;
    const optical_depth =
        layer_gas_optical_depth +
        layer_cia_optical_depth +
        layer_aerosol_optical_depth;
    const scattering = aerosol_scattering + gas_scattering;
    const absorption = @max(optical_depth - scattering, 1.0e-9);
    const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1.0e-9);
    const depolarization = PhaseFunctions.computeLayerDepolarization(
        context.scene,
        gas_scattering,
        aerosol_scattering,
    );
    var layer_line_cross_section: f64 = 0.0;
    var layer_line_mixing_cross_section: f64 = 0.0;
    var layer_d_cross_section_d_temperature: f64 = 0.0;
    if (support_point_count != 0) {
        const support_point_divisor = @as(f64, @floatFromInt(support_point_count));
        layer_line_cross_section = layer_line_sigma_sum / support_point_divisor;
        layer_line_mixing_cross_section = layer_line_mixing_sum / support_point_divisor;
        layer_d_cross_section_d_temperature = layer_d_cross_section_sum / support_point_divisor;
    }

    var layer_aerosol_single_scatter_albedo = lower_boundary.aerosol_single_scatter_albedo;
    var layer_aerosol_reference_wavelength_nm = lower_boundary.aerosol_reference_wavelength_nm;
    var layer_aerosol_angstrom_exponent = lower_boundary.aerosol_angstrom_exponent;
    if (layer_aerosol_optical_depth > 0.0) {
        layer_aerosol_single_scatter_albedo = std.math.clamp(
            layer_aerosol_scattering_optical_depth / layer_aerosol_optical_depth,
            0.0,
            1.0,
        );
        layer_aerosol_reference_wavelength_nm =
            layer_reference_wavelength_sum / layer_aerosol_optical_depth;
        layer_aerosol_angstrom_exponent = layer_angstrom_sum / layer_aerosol_optical_depth;
    }

    layer.* = .{
        .layer_index = @intCast(index),
        .sublayer_start_index = layer_sublayer_start_index,
        .sublayer_count = layer_sublayer_count,
        .altitude_km = 0.5 * (layer_top_altitude_km + layer_bottom_altitude_km),
        .pressure_hpa = lower_boundary.pressure_hpa,
        .temperature_k = lower_boundary.temperature_k,
        .number_density_cm3 = lower_boundary.number_density_cm3,
        .continuum_cross_section_cm2_per_molecule = lower_boundary.continuum_cross_section_cm2_per_molecule,
        .line_cross_section_cm2_per_molecule = layer_line_cross_section,
        .line_mixing_cross_section_cm2_per_molecule = layer_line_mixing_cross_section,
        .cia_optical_depth = layer_cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_d_cross_section_d_temperature,
        .gas_optical_depth = layer_gas_optical_depth,
        .gas_scattering_optical_depth = gas_scattering,
        .aerosol_optical_depth = layer_aerosol_optical_depth,
        .aerosol_base_optical_depth = layer_aerosol_base_optical_depth,
        .aerosol_single_scatter_albedo = layer_aerosol_single_scatter_albedo,
        .aerosol_reference_wavelength_nm = layer_aerosol_reference_wavelength_nm,
        .aerosol_angstrom_exponent = layer_aerosol_angstrom_exponent,
        .layer_single_scatter_albedo = layer_single_scatter_albedo,
        .depolarization_factor = depolarization,
        .optical_depth = optical_depth,
        .top_altitude_km = layer_top_altitude_km,
        .bottom_altitude_km = layer_bottom_altitude_km,
        .top_pressure_hpa = layer_top_pressure_hpa,
        .bottom_pressure_hpa = layer_bottom_pressure_hpa,
        .interval_index_1based = layer_interval_index_1based,
        .aerosol_fraction = lower_boundary.aerosol_fraction,
    };
}

fn populateLayer(
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
    layer: *State.PreparedLayer,
    index: usize,
) !LayerAccumulation {
    // populateLayer -------------------------------------------------------------------------------------------  |
    // Iterates sublayers and accumulates optical depth, scattering, particle, and phase terms for one layer.     |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs for each physical transport layer during optical-state accumulation. The output row is consumed     |
    //   by forward input construction and shared carrier reduction.                                              |
    //                                                                                                            |
    // calls                                                                                                      |
    //   populateSublayer                                                                                         |
    //                                                                                                            |
    // math                                                                                                       |
    //   tau_layer = sum(tau_gas_i + tau_cia_i + tau_aerosol_i)                                                   |
    //   tau_sca   = tau_gas_sca + tau_aerosol * omega0_aerosol                                                   |
    //   omega0    = tau_sca / max(tau_layer, eps)                                                                |
    // ---------------------------------------------------------------------------------------------------------  |

    const context = request.context;
    const geometry = layerGeometry(context, index);
    var layer_sums: LayerSums = .{};
    var layer_totals: LayerAccumulation = .{};

    for (0..geometry.sublayer_count) |sublayer_index| {
        const write_index = @as(usize, geometry.sublayer_start_index) + sublayer_index;
        const sublayer_totals = try populateSublayer(
            allocator,
            request,
            .{
                .layer_thickness_km = geometry.thickness_km,
                .parent_layer_index = index,
                .sublayer_index = sublayer_index,
                .write_index = write_index,
            },
            &layer_sums,
        );
        mergeLayerAccumulationTotals(&layer_totals, sublayer_totals);
    }

    const density = layer_sums.density;
    const temperature = layer_sums.temperature();
    const pressure = layer_sums.pressure();
    const gas_optical_depth = layer_sums.gas_optical_depth;
    const aerosol_optical_depth = layer_sums.aerosol_optical_depth;
    const aerosol_base_optical_depth = layer_sums.aerosol_base_optical_depth;
    const optical_depth = gas_optical_depth + layer_sums.cia_optical_depth + aerosol_optical_depth;
    const aerosol_scattering = layer_sums.aerosol_scattering_optical_depth;
    const gas_scattering = layer_sums.gas_scattering_optical_depth;
    const scattering = aerosol_scattering + gas_scattering;
    const absorption = @max(optical_depth - scattering, 1e-9);
    const layer_single_scatter_albedo = scattering / @max(scattering + absorption, 1e-9);
    const depolarization = PhaseFunctions.computeLayerDepolarization(
        context.scene,
        gas_scattering,
        aerosol_scattering,
    );
    const layer_aerosol_fraction = if (aerosol_base_optical_depth > 0.0)
        aerosol_optical_depth / aerosol_base_optical_depth
    else
        0.0;
    var layer_aerosol_single_scatter_albedo: f64 = 0.0;
    var layer_aerosol_reference_wavelength_nm: f64 = context.scene.aerosol.reference_wavelength_nm;
    var layer_aerosol_angstrom_exponent: f64 = context.scene.aerosol.angstrom_exponent;
    var layer_aerosol_fraction_value: f64 = 0.0;
    if (aerosol_optical_depth > 0.0) {
        layer_aerosol_single_scatter_albedo =
            std.math.clamp(aerosol_scattering / aerosol_optical_depth, 0.0, 1.0);
        layer_aerosol_reference_wavelength_nm =
            layer_sums.aerosol_reference_wavelength_sum / aerosol_optical_depth;
        layer_aerosol_angstrom_exponent = layer_sums.aerosol_angstrom_sum / aerosol_optical_depth;
        layer_aerosol_fraction_value = layer_aerosol_fraction;
    }

    layer_totals.total_optical_depth += optical_depth;
    layer_totals.total_temperature_weighted += temperature * density;
    layer_totals.total_pressure_weighted += pressure * density;
    layer_totals.total_weight += density;
    layer_totals.total_gas_optical_depth += gas_optical_depth;
    layer_totals.total_cia_optical_depth += layer_sums.cia_optical_depth;
    layer_totals.total_aerosol_optical_depth += aerosol_optical_depth;
    layer_totals.total_aerosol_base_optical_depth += aerosol_base_optical_depth;
    layer_totals.total_scattering_optical_depth += scattering;
    layer_totals.depolarization_weighted += depolarization * optical_depth;
    const layer_temperature_derivative = layer_sums.meanTemperatureDerivative(geometry.sublayer_count);

    layer.* = .{
        .layer_index = @intCast(index),
        .sublayer_start_index = geometry.sublayer_start_index,
        .sublayer_count = geometry.sublayer_count,
        .altitude_km = geometry.center_altitude_km,
        .pressure_hpa = pressure,
        .temperature_k = temperature,
        .number_density_cm3 = density,
        .continuum_cross_section_cm2_per_molecule = request.absorbers.mean_sigma,
        .line_cross_section_cm2_per_molecule = layer_sums.meanLineSigma(geometry.sublayer_count),
        .line_mixing_cross_section_cm2_per_molecule = layer_sums.meanLineMixing(geometry.sublayer_count),
        .cia_optical_depth = layer_sums.cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = layer_temperature_derivative,
        .gas_optical_depth = gas_optical_depth,
        .gas_scattering_optical_depth = gas_scattering,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_base_optical_depth = aerosol_base_optical_depth,
        .aerosol_single_scatter_albedo = layer_aerosol_single_scatter_albedo,
        .aerosol_reference_wavelength_nm = layer_aerosol_reference_wavelength_nm,
        .aerosol_angstrom_exponent = layer_aerosol_angstrom_exponent,
        .layer_single_scatter_albedo = layer_single_scatter_albedo,
        .depolarization_factor = depolarization,
        .optical_depth = optical_depth,
        .top_altitude_km = geometry.top_altitude_km,
        .bottom_altitude_km = geometry.bottom_altitude_km,
        .top_pressure_hpa = geometry.top_pressure_hpa,
        .bottom_pressure_hpa = geometry.bottom_pressure_hpa,
        .interval_index_1based = geometry.interval_index_1based,
        .aerosol_fraction = layer_aerosol_fraction_value,
    };
    return layer_totals;
}

fn populateSublayer(
    allocator: Allocator,
    request: *const LayerAccumulationRequest,
    target: SublayerTarget,
    layer_sums: *LayerSums,
) !LayerAccumulation {
    // populateSublayer ----------------------------------------------------------------------------------------  |
    // Evaluates cross sections, line spectroscopy, CIA, Rayleigh, and particles for one sublayer/support row.    |
    //                                                                                                            |
    // hot path                                                                                                   |
    //   Runs for each sublayer or parity support row. The computed optical-depth outputs feed layer totals and   |
    //   the carrier-evaluation support-row consumers.                                                            |
    //                                                                                                            |
    // calls                                                                                                      |
    //   resolveSpectroscopyEvaluation                                                                            |
    //                                                                                                            |
    // math                                                                                                       |
    //   column = density * path_cm                                                                               |
    //   tau_abs = sigma_cont * N_cont + sigma_line * N_line + sigma_xs * N_xs                                    |
    //   tau_cia = sigma_cia * pair_density * path_cm                                                             |
    //   tau_rayleigh = sigma_rayleigh * N_air                                                                    |
    // ---------------------------------------------------------------------------------------------------------  |

    const context = request.context;
    const absorbers = request.absorbers;
    const write_index = target.write_index;
    const top_altitude_km = context.vertical_grid.sublayer_top_altitudes_km[write_index];
    const bottom_altitude_km = context.vertical_grid.sublayer_bottom_altitudes_km[write_index];
    const top_pressure_hpa = context.vertical_grid.sublayer_top_pressures_hpa[write_index];
    const bottom_pressure_hpa = context.vertical_grid.sublayer_bottom_pressures_hpa[write_index];
    const altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
    const disamar_support_grid = usesDisamarParitySupportGrid(context);

    const parity_support_state = if (disamar_support_grid)
        paritySupportThermodynamicsFromProfile(context.profile, altitude_km)
    else
        null;
    const pressure = choose_pressure: {
        if (parity_support_state) |state| {
            break :choose_pressure state.pressure_hpa;
        }

        if (context.scene.atmosphere.interval_grid.enabled() and
            top_pressure_hpa > 0.0 and
            bottom_pressure_hpa > 0.0)
        {

            // math: midpoint pressure for log-spaced pressure bounds is geometric mean sqrt(p_top * p_bottom).
            break :choose_pressure @sqrt(top_pressure_hpa * bottom_pressure_hpa);
        }

        break :choose_pressure context.profile.interpolatePressure(altitude_km);
    };
    var temperature: f64 = undefined;
    var density: f64 = undefined;
    if (parity_support_state) |state| {
        temperature = state.temperature_k;
        density = state.density_cm3;
    } else {
        temperature = context.profile.interpolateTemperature(altitude_km);
        density = context.profile.interpolateDensity(altitude_km);
    }

    const support_weight_km = if (disamar_support_grid)
        context.vertical_grid.sublayer_support_weights_km[write_index]
    else
        @max(top_altitude_km - bottom_altitude_km, 0.0);

    const sublayer_path_length_cm = if (usesDisamarParitySupportGrid(context))
        @max(support_weight_km, 0.0) * centimeters_per_kilometer
    else
        @max(support_weight_km, 1.0e-9) * centimeters_per_kilometer;
    const sublayer_weight = support_weight_km / target.layer_thickness_km;
    const oxygen_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
        context.scene,
        .o2,
        &.{},

        pressure,
        oxygen_volume_mixing_ratio,
    ) orelse oxygen_volume_mixing_ratio;

    var absorber_density_cm3: f64 = 0.0;
    var cross_section_absorber_density_cm3: f64 = 0.0;
    var cross_section_optical_depth: f64 = 0.0;
    var cross_section_d_optical_depth_d_temperature: f64 = 0.0;
    for (
        absorbers.owned_cross_section_absorbers,
        absorbers.active_cross_section_absorbers,
    ) |*cross_section_absorber, active_absorber| {
        const absorber_mixing_ratio = Spectroscopy.speciesMixingRatioAtPressure(
            context.scene,
            cross_section_absorber.species,
            active_absorber.volume_mixing_ratio_profile_ppmv,
            pressure,
            if (cross_section_absorber.species == .o2) oxygen_volume_mixing_ratio else null,
        ) orelse return error.InvalidRequest;

        const absorber_density = density * absorber_mixing_ratio;
        cross_section_absorber.number_densities_cm3[write_index] = absorber_density;
        cross_section_absorber_density_cm3 += absorber_density;
        if (absorber_density <= 0.0) continue;

        const sigma = cross_section_absorber.sigmaAt(context.midpoint_nm, temperature, pressure);
        const d_sigma_d_temperature = cross_section_absorber.dSigmaDTemperatureAt(
            context.midpoint_nm,
            temperature,
            pressure,
        );
        cross_section_optical_depth += sigma * absorber_density * sublayer_path_length_cm;
        cross_section_d_optical_depth_d_temperature +=
            d_sigma_d_temperature * absorber_density * sublayer_path_length_cm;
        cross_section_absorber.column_density_factor += absorber_density * sublayer_path_length_cm;
    }

    const spectroscopy_eval = choose_spectroscopy_eval: {
        break :choose_spectroscopy_eval if (absorbers.owned_line_absorbers.len == 0 and
            absorbers.strong_line_states == null and
            request.profile_spectroscopy_cache != null)
            LayerSpectroscopy.resolveCachedSingleLineEvaluation(
                context,
                absorbers,
                write_index,
                density,
                pressure,
                temperature,
                &absorber_density_cm3,
                request.profile_spectroscopy_cache.?,
            )
        else
            try LayerSpectroscopy.resolveSpectroscopyEvaluation(
                allocator,
                context,
                absorbers,
                write_index,
                density,
                pressure,
                temperature,
                oxygen_mixing_ratio,
                sublayer_path_length_cm,
                &absorber_density_cm3,
                request.profile_spectroscopy_cache,
            );
    };

    const o2_density_cm3 = density * oxygen_mixing_ratio;
    const continuum_density_cm3 = LayerSpectroscopy.continuumCarrierDensity(
        absorbers,
        context,
        write_index,
        absorber_density_cm3,
        o2_density_cm3,
    );

    const has_only_cross_section_absorbers =
        absorbers.owned_cross_section_absorbers.len != 0 and !absorbers.has_line_absorbers;
    const total_gas_density_cm3 = if (has_only_cross_section_absorbers)
        cross_section_absorber_density_cm3
    else
        absorber_density_cm3 + cross_section_absorber_density_cm3;
    const line_gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
    const continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;

    const total_gas_column_density_cm2 = total_gas_density_cm3 * sublayer_path_length_cm;
    const molecular_gas_optical_depth =
        absorbers.midpoint_continuum_sigma * continuum_column_density_cm2 +
        spectroscopy_eval.total_sigma_cm2_per_molecule * line_gas_column_density_cm2 +
        cross_section_optical_depth;
    const cia_sigma_cm5_per_molecule2 = choose_cia_sigma_cm5_per_molecule2: {
        break :choose_cia_sigma_cm5_per_molecule2 if (context.operational_o2o2_lut.enabled())
            context.operational_o2o2_lut.sigmaAt(context.midpoint_nm, temperature, pressure)
        else if (context.collision_induced_absorption) |cia_table|
            cia_table.sigmaAt(context.midpoint_nm, temperature)
        else
            0.0;
    };

    const d_cia_sigma_d_temperature = choose_d_cia_sigma_d_temperature: {
        break :choose_d_cia_sigma_d_temperature if (context.operational_o2o2_lut.enabled())
            context.operational_o2o2_lut.dSigmaDTemperatureAt(context.midpoint_nm, temperature, pressure)
        else if (context.collision_induced_absorption) |cia_table|
            cia_table.dSigmaDTemperatureAt(context.midpoint_nm, temperature)
        else
            0.0;
    };

    const cia_pair_density_cm6 = collisionComplexPairDensityCm6(
        request.collision_complex_cache,
        altitude_km,
        density,
        o2_density_cm3,
    );

    const cia_pair_column_factor_cm5 = cia_pair_density_cm6 * sublayer_path_length_cm;
    const cia_optical_depth = cia_sigma_cm5_per_molecule2 * cia_pair_column_factor_cm5;
    const gas_scattering_optical_depth = Rayleigh.scatteringOpticalDepthForColumn(
        context.midpoint_nm,
        density * sublayer_path_length_cm,
    );

    const gas_absorption_optical_depth = molecular_gas_optical_depth;
    const gas_extinction_optical_depth =
        gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
    const d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * cia_pair_column_factor_cm5;
    const spectroscopy_temperature_derivative =
        spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k;
    const d_gas_optical_depth_d_temperature =
        spectroscopy_temperature_derivative * line_gas_column_density_cm2 +
        cross_section_d_optical_depth_d_temperature;

    // math: tau_aerosol(lambda_ref) is already distributed onto the prepared
    // sublayer grid. Single-layer cases use the existing placement logic;
    // aerosol-profile cases write the pressure-overlap profile directly.
    const aerosol_property = request.aerosol_sublayers.propertyAt(write_index);
    const aerosol_base_optical_depth = aerosol_property.base_optical_depth;
    const aerosol_optical_depth = aerosol_property.optical_depth;
    const sublayer_aerosol_fraction = if (aerosol_base_optical_depth > 0.0)
        aerosol_optical_depth / aerosol_base_optical_depth
    else
        0.0;

    const continuum_cross_section = if (absorbers.owned_cross_section_absorbers.len == 0)
        absorbers.midpoint_continuum_sigma
    else
        0.0;

    const support_row_kind: State.PreparedSupportRowKind = choose_support_row_kind: {
        if (!disamar_support_grid) break :choose_support_row_kind .physical;
        if (support_weight_km > 0.0) break :choose_support_row_kind .parity_active;
        break :choose_support_row_kind .parity_boundary;
    };

    context.sublayers[write_index] = .{
        .parent_layer_index = @intCast(target.parent_layer_index),
        .sublayer_index = @intCast(target.sublayer_index),
        .global_sublayer_index = @intCast(write_index),
        .altitude_km = altitude_km,
        .pressure_hpa = pressure,
        .temperature_k = temperature,
        .number_density_cm3 = density,
        .oxygen_number_density_cm3 = density * oxygen_mixing_ratio,
        .cia_pair_density_cm6 = cia_pair_density_cm6,
        .absorber_number_density_cm3 = total_gas_density_cm3,
        .path_length_cm = sublayer_path_length_cm,
        .continuum_cross_section_cm2_per_molecule = continuum_cross_section,
        .line_cross_section_cm2_per_molecule = spectroscopy_eval.line_sigma_cm2_per_molecule,
        .line_mixing_cross_section_cm2_per_molecule = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
        .cia_sigma_cm5_per_molecule2 = cia_sigma_cm5_per_molecule2,
        .cia_optical_depth = cia_optical_depth,
        .d_cross_section_d_temperature_cm2_per_molecule_per_k = spectroscopy_temperature_derivative,
        .gas_absorption_optical_depth = gas_absorption_optical_depth,
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .gas_extinction_optical_depth = gas_extinction_optical_depth,
        .d_gas_optical_depth_d_temperature = d_gas_optical_depth_d_temperature,
        .d_cia_optical_depth_d_temperature = d_cia_optical_depth_d_temperature,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_base_optical_depth = aerosol_base_optical_depth,
        .aerosol_single_scatter_albedo = aerosol_property.single_scatter_albedo,
        .aerosol_reference_wavelength_nm = aerosol_property.reference_wavelength_nm,
        .aerosol_angstrom_exponent = aerosol_property.angstrom_exponent,
        .top_altitude_km = top_altitude_km,
        .bottom_altitude_km = bottom_altitude_km,
        .top_pressure_hpa = top_pressure_hpa,
        .bottom_pressure_hpa = bottom_pressure_hpa,
        .interval_index_1based = context.vertical_grid.sublayer_interval_indices_1based[write_index],
        .aerosol_fraction = sublayer_aerosol_fraction,
        .support_row_kind = support_row_kind,
    };

    layer_sums.addSublayer(.{
        .density = density,
        .temperature = temperature,
        .pressure = pressure,
        .weight = sublayer_weight,
        .line_sigma = spectroscopy_eval.line_sigma_cm2_per_molecule,
        .line_mixing = spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
        .d_cross_section_d_temperature = spectroscopy_eval.d_sigma_d_temperature_cm2_per_molecule_per_k,
        .gas_absorption_optical_depth = gas_absorption_optical_depth,
        .gas_scattering_optical_depth = gas_scattering_optical_depth,
        .cia_optical_depth = cia_optical_depth,
        .aerosol_optical_depth = aerosol_optical_depth,
        .aerosol_base_optical_depth = aerosol_base_optical_depth,
        .aerosol_scattering_optical_depth = aerosol_optical_depth * aerosol_property.single_scatter_albedo,
        .aerosol_reference_wavelength_nm = aerosol_property.reference_wavelength_nm,
        .aerosol_angstrom_exponent = aerosol_property.angstrom_exponent,
    });
    return .{
        .air_column_density_factor = density * sublayer_path_length_cm,
        .oxygen_column_density_factor = o2_density_cm3 * sublayer_path_length_cm,
        .column_density_factor = total_gas_column_density_cm2,
        .cia_pair_path_factor_cm5 = cia_pair_column_factor_cm5,
        .total_d_optical_depth_d_temperature = d_gas_optical_depth_d_temperature +
            d_cia_optical_depth_d_temperature,
    };
}

fn layerGeometry(context: *const Context, index: usize) LayerGeometry {
    const top_altitude_km = context.vertical_grid.layer_top_altitudes_km[index];
    const bottom_altitude_km = context.vertical_grid.layer_bottom_altitudes_km[index];
    return .{
        .top_altitude_km = top_altitude_km,
        .bottom_altitude_km = bottom_altitude_km,
        .center_altitude_km = 0.5 * (top_altitude_km + bottom_altitude_km),
        .top_pressure_hpa = context.vertical_grid.layer_top_pressures_hpa[index],
        .bottom_pressure_hpa = context.vertical_grid.layer_bottom_pressures_hpa[index],
        .sublayer_start_index = context.vertical_grid.layer_sublayer_starts[index],
        .sublayer_count = context.vertical_grid.layer_sublayer_counts[index],
        .interval_index_1based = context.vertical_grid.layer_interval_indices_1based[index],
        .thickness_km = @max(top_altitude_km - bottom_altitude_km, 1.0e-9),
    };
}

fn usesDisamarParitySupportGrid(context: *const Context) bool {
    const radiance_integration_mode =
        context.scene.observation_model.resolvedChannelControls(.radiance).response.integration_mode;
    const irradiance_integration_mode =
        context.scene.observation_model.resolvedChannelControls(.irradiance).response.integration_mode;

    return radiance_integration_mode == .disamar_hr_grid or
        irradiance_integration_mode == .disamar_hr_grid;
}
