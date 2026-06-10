const std = @import("std");
const build_options = @import("build_options");
const core_errors = @import("../../../common/errors.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const InstrumentIntegration = @import("../../implementations/instrument/integration.zig");
const OpticsPreparation = @import("../../optical_properties/root.zig");
const common = @import("../../radiative_transfer/root.zig");
const jacobian = @import("../../jacobian/root.zig");
const Cache = @import("cache.zig");
const Plan = @import("wavelength_plan.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const grid = @import("../spectral_math/grid.zig");
const convolution = @import("../spectral_math/convolution.zig");
const Types = @import("types.zig");

const Allocator = std.mem.Allocator;

// storage.zig -----------------------------------------------------------------------------------------------------------|
// Reusable memory owner for instrument-grid simulations. ProductStorage is the retained workspace behind repeated        |
// measurement runs: it owns output arrays, transport scratch, wavelength plans, forward miss plans, profile caches,      |
// optional worker pools, and the borrowed views returned by instrument_grid/root.zig.                                    |
//                                                                                                                        |
// called by                                                                                                              |
//   instrument_grid/root.zig exposes ProductStorage as the public workspace handle. simulate.zig asks for trimmed        |
//   Buffers views at the start of each product run. spectral_forward.zig uses resolved sizing helpers for worker         |
//   scratch. optimal_estimation keeps ProductStorage warm across retrieval iterations.                                   |
//                                                                                                                        |
// route map                                                                                                              |
//   ProductStorage.buffers                  -> grow/reuse output, transport, pseudo-spherical, and Jacobian buffers      |
//   ProductStorage.spectralCache            -> reset the reusable irradiance cache for this product run                  |
//   ProductStorage.forwardResultBuffer      -> dense LABOS miss result staging for spectral_forward.zig                  |
//   ProductStorage.forwardPrefetchPool      -> reusable helper threads for repeated prefetch work                        |
//   ProductStorage.invalidateWavelengthPlan -> clear wavelength sampling, forward misses, and profile caches together    |
//   validateBuffers                         -> assert a coherent one-sweep borrowed Buffers view                         |
//                                                                                                                        |
// cache boundaries                                                                                                       |
//   wavelength_plan_key guards sampling and forward-miss plans. profile_spectroscopy_cache_key guards profile-node       |
//   spectroscopy state. invalidateWavelengthPlan drops both families because they are derived from the same scene,       |
//   prepared optical state, and instrument controls and must not drift independently.                                    |
//                                                                                                                        |
// ownership                                                                                                              |
//   ProductStorage owns backing slices and retained plans. Buffers is only a trimmed borrowed view for one run.          |
//   Feature-specific buffers are freed when disabled so stale source-interface, RTM-quadrature, pseudo-spherical,        |
//   or Jacobian data cannot survive into a route that should not read them.                                              |
// -----------------------------------------------------------------------------------------------------------------------|

// migration note: Zig 0.15.2 runtime boundary ---------------------------------------------------------------------------|
// Product storage keeps the existing std.Thread.Pool route while the project is pinned to Zig 0.15.2.                    |
// The failed 0.16 migration briefly moved this path to std.Io.Threaded; do not reintroduce that API here.                |
// end migration note: Zig 0.15.2 runtime boundary -----------------------------------------------------------------------|

pub const trace_phase_timing_enabled: bool = enabled_by_build: {
    if (!@hasDecl(build_options, "enable_trace_phase_timing")) break :enabled_by_build false;
    break :enabled_by_build build_options.enable_trace_phase_timing;
};

const TracePhaseTimingRoute = if (trace_phase_timing_enabled) struct {
    const Slot = ?*TracePhaseTiming;
    const empty: Slot = null;
} else struct {
    const Slot = void;
    const empty: Slot = {};
};

const TracePhaseTimingSlot = TracePhaseTimingRoute.Slot;
const trace_phase_timing_slot_default = TracePhaseTimingRoute.empty;

pub const Error =
    core_errors.Error ||
    common.Error ||
    grid.Error ||
    convolution.Error ||
    InstrumentIntegration.Error ||
    error{
        ShapeMismatch,
        OutOfMemory,
    };

// Buffers ---------------------------------------------------------------------------------------------------------------|
// Trimmed borrowed buffer views for one simulation run. ProductStorage owns the referenced backing storage.              |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 216 B (0.211 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 15] wavelengths                      : []f64                                                                    |
// [ 16.. 31] radiance                         : []f64                                                                    |
// [ 32.. 47] irradiance                       : []f64                                                                    |
// [ 48.. 63] reflectance                      : []f64                                                                    |
// [ 64.. 79] scratch                          : []f64                                                                    |
// [ 80.. 95] scratch_aux                      : []f64                                                                    |
// [ 96..111] layer_inputs                     : []common.LayerInput                                                      |
// [112..127] source_interfaces                : []common.SourceInterfaceInput                                            |
// [128..143] rtm_quadrature_levels            : []common.RtmQuadratureLevel                                              |
// [144..159] pseudo_spherical_samples         : []common.PseudoSphericalSample                                           |
// [160..175] pseudo_spherical_level_starts    : []usize                                                                  |
// [176..191] pseudo_spherical_level_altitudes : []f64                                                                    |
// [192..207] jacobian                         : ?[]f64                                                                   |
// [208..208] jacobian_state_mask              : jacobian.StateMask                                                       |
// [209..215] padding                          : 7 B                                                                      |
//                                                                                                                        |
// all slices reference ProductStorage backing storage and do not include it in the 216 B view size.                      |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                               |
// cache span: 4 cache lines at 64 B per line                                                                             |
// footprint: per instance = 216 B (0.211 KiB); total also includes referenced storage above                              |
pub const Buffers = struct {
    wavelengths: []f64,
    radiance: []f64,
    irradiance: []f64,
    reflectance: []f64,
    scratch: []f64,
    scratch_aux: []f64,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    jacobian: ?[]f64 = null,
    jacobian_state_mask: jacobian.StateMask = 0,
};

// BufferHintRequest -----------------------------------------------------------------------------------------------------|
// Borrowed scene and RTM controls used to size ProductStorage before optical preparation gives exact transport counts.   |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 16 B (0.016 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] scene      : *const Scene                                                                                     |
// [ 8..15] rtm_config : *const common.SolveConfig                                                                        |
//                                                                                                                        |
// referenced storage: borrowed scene and solve config; the request owns no backing storage.                              |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 16 B (0.016 KiB); no out-of-line storage                                                     |
pub const BufferHintRequest = struct {
    scene: *const Scene,
    rtm_config: *const common.SolveConfig,
};

// ResolvedBufferRequirementsRequest -------------------------------------------------------------------------------------|
// Borrowed inputs used to validate one Buffers view after PreparedOpticalState has exact transport-layer counts.         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 32 B (0.031 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] scene        : *const Scene                                                                                   |
// [ 8..15] rtm_config   : *const common.SolveConfig                                                                      |
// [16..23] prepared     : *const OpticsPreparation.PreparedOpticalState                                                  |
// [24..31] sample_count : usize                                                                                          |
//                                                                                                                        |
// referenced storage: borrowed scene, solve config, and prepared optical state; no referenced storage is owned here.     |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 32 B (0.031 KiB); no out-of-line storage                                                     |
pub const ResolvedBufferRequirementsRequest = struct {
    scene: *const Scene,
    rtm_config: *const common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    sample_count: usize,
};

// BufferRequirements ----------------------------------------------------------------------------------------------------|
// Counts needed to grow or validate the one-sweep Buffers view. Scene and RTM controls are read once to build            |
// this row; allocation code then sees plain lengths and a compact Jacobian mask.                                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 64 B (0.063 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] sample_count                  : usize                                                                         |
// [ 8..15] layer_count                   : usize                                                                         |
// [16..23] source_interface_count        : usize                                                                         |
// [24..31] rtm_quadrature_level_count    : usize                                                                         |
// [32..39] pseudo_spherical_sample_count : usize                                                                         |
// [40..47] pseudo_spherical_level_count  : usize                                                                         |
// [48..55] active_jacobian_count         : usize                                                                         |
// [56..56] jacobian_state_mask           : jacobian.StateMask                                                            |
// [57..63] padding                       : 7 B                                                                           |
//                                                                                                                        |
// referenced storage: none; this is a stack value copied by value.                                                       |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                               |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 64 B (0.063 KiB); no out-of-line storage                                                     |
pub const BufferRequirements = struct {
    sample_count: usize,
    layer_count: usize,
    source_interface_count: usize,
    rtm_quadrature_level_count: usize,
    pseudo_spherical_sample_count: usize,
    pseudo_spherical_level_count: usize,
    active_jacobian_count: usize,
    jacobian_state_mask: jacobian.StateMask,

    pub fn fromSceneHint(request: *const BufferHintRequest) BufferRequirements {
        // BufferRequirements.fromSceneHint ------------------------------------------------------------------------------|
        // Build the allocation-size row from scene-level hints before wavelength-specific preparation starts.            |
        // ---------------------------------------------------------------------------------------------------------------|

        const scene = request.scene;
        const rtm_config = request.rtm_config.*;
        const sample_count: usize = @intCast(scene.spectral_grid.sample_count);
        const layer_count = transportLayerCountHint(scene, rtm_config);
        const uses_source_interfaces = configMayUseSourceInterfaces(scene, rtm_config);
        const uses_rtm_quadrature = configUsesRtmQuadrature(rtm_config);
        const uses_pseudo_spherical_grid = configUsesPseudoSphericalGrid(rtm_config);
        const active_jacobian_mask = if (rtm_config.derivative_mode != .none)
            jacobian.sanitizedMask(rtm_config.derivative_state_mask)
        else
            0;
        const active_jacobian_count = jacobian.activeStateCount(active_jacobian_mask);

        var source_interface_count: usize = 0;
        if (uses_source_interfaces) {
            source_interface_count = layer_count + 1;
        }

        var rtm_quadrature_level_count: usize = 0;
        if (uses_rtm_quadrature) {
            rtm_quadrature_level_count = layer_count + 1;
        }

        var pseudo_spherical_sample_count: usize = 0;
        var pseudo_spherical_level_count: usize = 0;
        if (uses_pseudo_spherical_grid) {
            pseudo_spherical_sample_count = pseudoSphericalSampleCountHint(scene, rtm_config);
            pseudo_spherical_level_count = layer_count + 1;
        }

        var jacobian_state_mask: jacobian.StateMask = 0;
        if (active_jacobian_count != 0) {
            jacobian_state_mask = active_jacobian_mask;
        }

        return .{
            .sample_count = sample_count,
            .layer_count = layer_count,
            .source_interface_count = source_interface_count,
            .rtm_quadrature_level_count = rtm_quadrature_level_count,
            .pseudo_spherical_sample_count = pseudo_spherical_sample_count,
            .pseudo_spherical_level_count = pseudo_spherical_level_count,
            .active_jacobian_count = active_jacobian_count,
            .jacobian_state_mask = jacobian_state_mask,
        };
    }

    pub fn fromPrepared(request: *const ResolvedBufferRequirementsRequest) BufferRequirements {
        // BufferRequirements.fromPrepared -------------------------------------------------------------------------------|
        // Build the validation row from exact PreparedOpticalState transport counts after optical preparation.           |
        // ---------------------------------------------------------------------------------------------------------------|

        const scene = request.scene;
        const rtm_config = request.rtm_config.*;
        const prepared = request.prepared;
        const sample_count = request.sample_count;
        const layer_count = resolvedTransportLayerCount(rtm_config, prepared);
        const uses_source_interfaces = configMayUseSourceInterfaces(scene, rtm_config);
        const uses_rtm_quadrature = configUsesRtmQuadrature(rtm_config);
        const uses_pseudo_spherical_grid = configUsesPseudoSphericalGrid(rtm_config);
        const active_jacobian_mask = if (rtm_config.derivative_mode != .none)
            jacobian.sanitizedMask(rtm_config.derivative_state_mask)
        else
            0;
        const active_jacobian_count = jacobian.activeStateCount(active_jacobian_mask);

        var source_interface_count: usize = 0;
        if (uses_source_interfaces) {
            source_interface_count = layer_count + 1;
        }

        var rtm_quadrature_level_count: usize = 0;
        if (uses_rtm_quadrature) {
            rtm_quadrature_level_count = layer_count + 1;
        }

        var pseudo_spherical_sample_count: usize = 0;
        var pseudo_spherical_level_count: usize = 0;
        if (uses_pseudo_spherical_grid) {
            pseudo_spherical_sample_count = resolvedPseudoSphericalSampleCount(scene, rtm_config, prepared);
            pseudo_spherical_level_count = layer_count + 1;
        }

        var jacobian_state_mask: jacobian.StateMask = 0;
        if (active_jacobian_count != 0) {
            jacobian_state_mask = active_jacobian_mask;
        }

        return .{
            .sample_count = sample_count,
            .layer_count = layer_count,
            .source_interface_count = source_interface_count,
            .rtm_quadrature_level_count = rtm_quadrature_level_count,
            .pseudo_spherical_sample_count = pseudo_spherical_sample_count,
            .pseudo_spherical_level_count = pseudo_spherical_level_count,
            .active_jacobian_count = active_jacobian_count,
            .jacobian_state_mask = jacobian_state_mask,
        };
    }
};

// ProductSampleBufferOwners ---------------------------------------------------------------------------------------------|
// Mutable owner slots for sample-sized product rows. ProductStorage owns the backing arrays; this row only               |
// groups the slots that grow together for one spectral sweep.                                                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 48 B (0.047 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] wavelengths : *[]f64                                                                                          |
// [ 8..15] radiance    : *[]f64                                                                                          |
// [16..23] irradiance  : *[]f64                                                                                          |
// [24..31] reflectance : *[]f64                                                                                          |
// [32..39] scratch     : *[]f64                                                                                          |
// [40..47] scratch_aux : *[]f64                                                                                          |
//                                                                                                                        |
// referenced storage: every field points at a ProductStorage slice slot; this row owns no backing arrays.                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 48 B (0.047 KiB); no out-of-line storage                                                     |
const ProductSampleBufferOwners = struct {
    wavelengths: *[]f64,
    radiance: *[]f64,
    irradiance: *[]f64,
    reflectance: *[]f64,
    scratch: *[]f64,
    scratch_aux: *[]f64,
};

// TransportBufferOwners -------------------------------------------------------------------------------------------------|
// Mutable owner slots for transport buffers whose capacity is decided by RTM route requirements.                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] layer_inputs          : *[]common.LayerInput                                                                  |
// [ 8..15] source_interfaces     : *[]common.SourceInterfaceInput                                                        |
// [16..23] rtm_quadrature_levels : *[]common.RtmQuadratureLevel                                                          |
//                                                                                                                        |
// referenced storage: every field points at a ProductStorage slice slot; this row owns no backing arrays.                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 24 B (0.023 KiB); no out-of-line storage                                                     |
const TransportBufferOwners = struct {
    layer_inputs: *[]common.LayerInput,
    source_interfaces: *[]common.SourceInterfaceInput,
    rtm_quadrature_levels: *[]common.RtmQuadratureLevel,
};

// PseudoSphericalBufferOwners -------------------------------------------------------------------------------------------|
// Mutable owner slots for geometric-correction support rows. The three buffers are enabled or freed together.            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 24 B (0.023 KiB), align: 8 B                                                                                     |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] samples         : *[]common.PseudoSphericalSample                                                             |
// [ 8..15] level_starts    : *[]usize                                                                                    |
// [16..23] level_altitudes : *[]f64                                                                                      |
//                                                                                                                        |
// referenced storage: every field points at a ProductStorage slice slot; this row owns no backing arrays.                |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 24 B (0.023 KiB); no out-of-line storage                                                     |
const PseudoSphericalBufferOwners = struct {
    samples: *[]common.PseudoSphericalSample,
    level_starts: *[]usize,
    level_altitudes: *[]f64,
};

// JacobianBufferOwners --------------------------------------------------------------------------------------------------|
// Mutable owner slot for the optional state-major Jacobian output row.                                                   |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 8 B (0.008 KiB), align: 8 B                                                                                      |
//                                                                                                                        |
// memory                                                                                                                 |
// [0..7] values : *[]f64                                                                                                 |
//                                                                                                                        |
// referenced storage: values points at a ProductStorage slice slot; this row owns no backing arrays.                     |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// cache span: 1 cache line at 64 B per line                                                                              |
// footprint: per instance = 8 B (0.008 KiB); no out-of-line storage                                                      |
const JacobianBufferOwners = struct {
    values: *[]f64,
};

// instrumentation: trace phase timing -----------------------------------------------------------------------------------|
// captures: coarse product-simulation phase timings for trace-harness JSON summaries                                     |
// why: keeps first-use and cached-run attribution available when very deep ztracy captures bury short zones.             |
const EnabledTracePhaseTiming = struct {
    wavelength_sampling_ns: u64 = 0,
    forward_miss_collection_ns: u64 = 0,
    profile_spectroscopy_cache_ns: u64 = 0,
    forward_prefetch_ns: u64 = 0,
    radiance_cache_integration_ns: u64 = 0,
    radiance_convolution_ns: u64 = 0,
    radiance_postprocess_ns: u64 = 0,
    irradiance_sampling_ns: u64 = 0,
    irradiance_convolution_ns: u64 = 0,
    irradiance_postprocess_ns: u64 = 0,
    reflectance_assembly_ns: u64 = 0,
    jacobian_processing_ns: u64 = 0,
    labos: common.labos.PhaseTiming = .{},

    pub fn reset(self: *@This()) void {
        // EnabledTracePhaseTiming.reset ---------------------------------------------------------------------------------|
        // Clear all phase counters before a workspace-backed product run starts.                                         |
        // ---------------------------------------------------------------------------------------------------------------|

        self.* = .{};
    }
};

const DisabledTracePhaseTiming = struct {
    pub inline fn reset(self: *@This()) void {
        // DisabledTracePhaseTiming.reset --------------------------------------------------------------------------------|
        // Compile-time no-op used when trace phase timing is not built in.                                               |
        // ---------------------------------------------------------------------------------------------------------------|

        _ = self;
    }
};

pub const TracePhaseTiming = if (trace_phase_timing_enabled) EnabledTracePhaseTiming else DisabledTracePhaseTiming;
// end instrumentation: trace phase timing -------------------------------------------------------------------------------|

pub fn configMayUseSourceInterfaces(scene: *const Scene, rtm_config: common.SolveConfig) bool {
    // configMayUseSourceInterfaces --------------------------------------------------------------------------------------|
    // Source-interface buffers are only needed when integrated-source transport is requested and the scene               |
    // still uses the coarse non-interval atmosphere contract.                                                            |
    // -------------------------------------------------------------------------------------------------------------------|

    if (!rtm_config.rtm_controls.integrate_source_function) return false;
    return scene.atmosphere.interval_grid.semantics == .none;
}

pub fn configUsesRtmQuadrature(rtm_config: common.SolveConfig) bool {
    // configUsesRtmQuadrature -------------------------------------------------------------------------------------------|
    // RTM quadrature storage follows the integrated-source flag. Some runs may later fail to populate the                |
    // quadrature table, but the buffer must be available for that attempt.                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    return rtm_config.rtm_controls.integrate_source_function;
}

pub fn configUsesPseudoSphericalGrid(rtm_config: common.SolveConfig) bool {
    // configUsesPseudoSphericalGrid -------------------------------------------------------------------------------------|
    // Pseudo-spherical support storage is only needed when geometric correction is enabled.                              |
    // -------------------------------------------------------------------------------------------------------------------|

    return rtm_config.rtm_controls.use_spherical_correction;
}

// ProductStorage --------------------------------------------------------------------------------------------------------|
// Reusable instrument-grid workspace that owns product buffers, retained wavelength plans, and the optional              |
// prefetch pool.                                                                                                         |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 552 B (0.539 KiB) normally; 560 B (0.547 KiB) with trace phase timing, align: 8 B                                |
//                                                                                                                        |
// memory, normal build                                                                                                   |
// [  0.. 63] evaluation_cache                  : ?Cache.SpectralEvaluationCache                                          |
// [ 64.. 71] shared_forward_prefetch_pool      : ?*std.Thread.Pool                                                       |
// [ 72.. 87] irradiance                        : []f64                                                                   |
// [ 88..103] reflectance                       : []f64                                                                   |
// [104..119] wavelengths                       : []f64                                                                   |
// [120..135] scratch_aux                       : []f64                                                                   |
// [136..151] forward_results                   : []Types.ForwardIntegratedSample                                         |
// [152..167] layer_inputs                      : []common.LayerInput                                                     |
// [168..183] source_interfaces                 : []common.SourceInterfaceInput                                           |
// [184..199] rtm_quadrature_levels             : []common.RtmQuadratureLevel                                             |
// [200..215] pseudo_spherical_samples          : []common.PseudoSphericalSample                                          |
// [216..231] pseudo_spherical_level_starts     : []usize                                                                 |
// [232..247] radiance                          : []f64                                                                   |
// [248..263] pseudo_spherical_level_altitudes  : []f64                                                                   |
// [264..279] scratch                           : []f64                                                                   |
// [280..327] wavelength_sampling               : Plan.OwnedWavelengthSampling                                            |
// [328..375] forward_miss_plan                 : Plan.OwnedForwardMissPlan                                               |
// [376..391] profile_spectroscopy_caches       : []SpectroscopyState.ProfileNodeSpectroscopyCache                        |
// [392..399] wavelength_plan_key               : u64                                                                     |
// [400..407] forward_prefetch_pool_worker_threads : usize                                                                |
// [408..519] forward_prefetch_pool             : std.Thread.Pool                                                         |
// [520..527] profile_spectroscopy_cache_key    : u64                                                                     |
// [528..543] jacobian                          : []f64                                                                   |
// [544..544] profile_spectroscopy_cache_valid  : bool                                                                    |
// [545..545] forward_miss_plan_valid           : bool                                                                    |
// [546..546] wavelength_plan_valid             : bool                                                                    |
// [547..547] forward_prefetch_pool_valid       : bool                                                                    |
// [548..551] padding                           : 4 B                                                                     |
//                                                                                                                        |
// trace phase timing build                                                                                               |
//   trace_phase_timing occupies [400..407], moving forward_prefetch_pool_worker_threads to [408..415],                   |
//   forward_prefetch_pool to [424..535], jacobian to [536..551], and the four bools to [552..555].                       |
//                                                                                                                        |
// slices, plans, caches, and the thread pool carry referenced storage not included in the struct size.                   |
// unused bits: 32 padding + 28 bool-storage slack = 60 bits                                                              |
// cache span: 9 cache lines at 64 B per line                                                                             |
// footprint: per instance = 552 B (0.539 KiB) normally; 560 B (0.547 KiB) with trace phase timing                        |
pub const ProductStorage = struct {
    wavelengths: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    scratch: []f64 = &.{},
    scratch_aux: []f64 = &.{},
    forward_results: []Types.ForwardIntegratedSample = &.{},
    layer_inputs: []common.LayerInput = &.{},
    source_interfaces: []common.SourceInterfaceInput = &.{},
    rtm_quadrature_levels: []common.RtmQuadratureLevel = &.{},
    pseudo_spherical_samples: []common.PseudoSphericalSample = &.{},
    pseudo_spherical_level_starts: []usize = &.{},
    pseudo_spherical_level_altitudes: []f64 = &.{},
    jacobian: []f64 = &.{},
    evaluation_cache: ?Cache.SpectralEvaluationCache = null,
    wavelength_sampling: Plan.OwnedWavelengthSampling = .{},
    forward_miss_plan: Plan.OwnedForwardMissPlan = .{},
    profile_spectroscopy_caches: []SpectroscopyState.ProfileNodeSpectroscopyCache = &.{},
    wavelength_plan_key: u64 = 0,
    wavelength_plan_valid: bool = false,
    forward_miss_plan_valid: bool = false,
    profile_spectroscopy_cache_key: u64 = 0,
    profile_spectroscopy_cache_valid: bool = false,
    shared_forward_prefetch_pool: ?*std.Thread.Pool = null,
    forward_prefetch_pool: std.Thread.Pool = undefined,
    forward_prefetch_pool_worker_threads: usize = 0,
    forward_prefetch_pool_valid: bool = false,
    trace_phase_timing: TracePhaseTimingSlot = trace_phase_timing_slot_default,

    pub fn deinit(self: *ProductStorage, allocator: Allocator) void {
        // ProductStorage.deinit -----------------------------------------------------------------------------------------|
        // Release every buffer and retained plan owned by the workspace. Shared prefetch pools are borrowed              |
        // and are not deinitialized here.                                                                                |
        // ---------------------------------------------------------------------------------------------------------------|

        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
        }
        freeBuffer(allocator, self.wavelengths);
        freeBuffer(allocator, self.radiance);
        freeBuffer(allocator, self.irradiance);
        freeBuffer(allocator, self.reflectance);
        freeBuffer(allocator, self.scratch);
        freeBuffer(allocator, self.scratch_aux);
        freeForwardResultBuffer(allocator, self.forward_results);
        freeLayerBuffer(allocator, self.layer_inputs);
        freeSourceInterfaceBuffer(allocator, self.source_interfaces);
        freeRtmQuadratureBuffer(allocator, self.rtm_quadrature_levels);
        freePseudoSphericalSampleBuffer(allocator, self.pseudo_spherical_samples);
        freeIndexBuffer(allocator, self.pseudo_spherical_level_starts);
        freeBuffer(allocator, self.pseudo_spherical_level_altitudes);
        freeBuffer(allocator, self.jacobian);
        if (self.evaluation_cache) |*cache| cache.deinit();
        self.wavelength_sampling.deinit(allocator);
        self.forward_miss_plan.deinit(allocator);
        allocator.free(self.profile_spectroscopy_caches);
        self.* = .{};
    }

    pub fn setTracePhaseTiming(self: *ProductStorage, timing: *TracePhaseTiming) void {
        // ProductStorage.setTracePhaseTiming ----------------------------------------------------------------------------|
        // Attach an opt-in phase timing sink for the next workspace-backed simulation. Product builds compile            |
        // this to a no-op when trace phase timing is disabled.                                                           |
        // ---------------------------------------------------------------------------------------------------------------|

        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = timing;
        }
    }

    pub fn clearTracePhaseTiming(self: *ProductStorage) void {
        // ProductStorage.clearTracePhaseTiming --------------------------------------------------------------------------|
        // Detach the opt-in phase timing sink so normal product runs do not retain trace state.                          |
        // ---------------------------------------------------------------------------------------------------------------|

        if (comptime trace_phase_timing_enabled) {
            self.trace_phase_timing = null;
        }
    }

    pub fn activeTracePhaseTiming(self: *ProductStorage) ?*TracePhaseTiming {
        // ProductStorage.activeTracePhaseTiming -------------------------------------------------------------------------|
        // Return the currently attached phase timing sink, or null in normal builds and normal product runs.             |
        // ---------------------------------------------------------------------------------------------------------------|

        if (comptime trace_phase_timing_enabled) {
            return self.trace_phase_timing;
        } else {
            return null;
        }
    }

    pub fn forwardPrefetchPool(
        self: *ProductStorage,
        allocator: Allocator,
        worker_count: usize,
    ) ?*std.Thread.Pool {
        // ProductStorage.forwardPrefetchPool ----------------------------------------------------------------------------|
        // Return a reusable worker pool for LABOS prefetch when parallelism is useful. The pool stores                   |
        // worker_count - 1 helper threads because the caller uses the current thread as the final worker.                |
        //                                                                                                                |
        // fallback                                                                                                       |
        //   If pool initialization fails, return null so the caller can spawn direct threads or run chunks               |
        //   locally. The simulation result is unchanged; only scheduling changes.                                        |
        // ---------------------------------------------------------------------------------------------------------------|

        if (worker_count <= 1) return null;
        if (self.shared_forward_prefetch_pool) |pool| return pool;

        const worker_thread_count = worker_count - 1;
        if (self.forward_prefetch_pool_valid and
            self.forward_prefetch_pool_worker_threads == worker_thread_count)
        {
            return &self.forward_prefetch_pool;
        }

        if (self.forward_prefetch_pool_valid) {
            self.forward_prefetch_pool.deinit();
            self.forward_prefetch_pool_valid = false;
            self.forward_prefetch_pool_worker_threads = 0;
        }

        self.forward_prefetch_pool.init(.{
            .allocator = allocator,
            .n_jobs = worker_thread_count,
        }) catch return null;
        self.forward_prefetch_pool_worker_threads = worker_thread_count;
        self.forward_prefetch_pool_valid = true;
        return &self.forward_prefetch_pool;
    }

    pub fn invalidateWavelengthPlan(self: *ProductStorage, allocator: Allocator) void {
        // ProductStorage.invalidateWavelengthPlan -----------------------------------------------------------------------|
        // Drop derived wavelength sampling, forward-miss, and profile spectroscopy caches together. These                |
        // caches are keyed from the same spectral/instrument/prepared state and must not drift independently.            |
        // ---------------------------------------------------------------------------------------------------------------|

        self.wavelength_sampling.deinit(allocator);
        self.forward_miss_plan.deinit(allocator);
        allocator.free(self.profile_spectroscopy_caches);
        self.wavelength_sampling = .{};
        self.forward_miss_plan = .{};
        self.profile_spectroscopy_caches = &.{};
        self.wavelength_plan_key = 0;
        self.wavelength_plan_valid = false;
        self.forward_miss_plan_valid = false;
        self.profile_spectroscopy_cache_key = 0;
        self.profile_spectroscopy_cache_valid = false;
    }

    pub fn spectralCache(self: *ProductStorage, allocator: Allocator) Error!*Cache.SpectralEvaluationCache {
        // ProductStorage.spectralCache ----------------------------------------------------------------------------------|
        // Return the reusable irradiance cache for this run. The cache keeps capacity but clears values so               |
        // a previous spectrum cannot affect the next spectrum.                                                           |
        // ---------------------------------------------------------------------------------------------------------------|

        if (self.evaluation_cache == null) {
            self.evaluation_cache = Cache.SpectralEvaluationCache.init(allocator);
        }
        self.evaluation_cache.?.reset();
        return &(self.evaluation_cache.?);
    }

    pub fn forwardResultBuffer(
        self: *ProductStorage,
        allocator: Allocator,
        capacity: usize,
    ) Error![]Types.ForwardIntegratedSample {
        // ProductStorage.forwardResultBuffer ----------------------------------------------------------------------------|
        // Return the dense staging array used for high-resolution LABOS miss results. Reusing this buffer                |
        // avoids repeated allocation across retrieval iterations with similar wavelength plans.                          |
        // ---------------------------------------------------------------------------------------------------------------|

        try ensureForwardResultCapacity(allocator, &self.forward_results, capacity);
        return self.forward_results[0..capacity];
    }

    pub fn buffers(
        self: *ProductStorage,
        allocator: Allocator,
        scene: *const Scene,
        rtm_config: common.SolveConfig,
    ) Error!Buffers {
        // ProductStorage.buffers ----------------------------------------------------------------------------------------|
        // Ensure all output and transport buffers are large enough for one simulation, then return trimmed               |
        // views for the active sample/layer counts.                                                                      |
        //                                                                                                                |
        // allocation rule                                                                                                |
        //   Buffers grow when needed and keep capacity across runs. Buffers for disabled RTM features are                |
        //   freed so stale source-interface, quadrature, or pseudo-spherical data cannot be reused.                      |
        //                                                                                                                |
        // Jacobian layout                                                                                                |
        //   Workspace Jacobians are state-major over active states only: [active_state][sample].                         |
        // ---------------------------------------------------------------------------------------------------------------|

        const requirements_request = BufferHintRequest{
            .scene = scene,
            .rtm_config = &rtm_config,
        };
        const requirements = BufferRequirements.fromSceneHint(&requirements_request);

        const product_buffers = ProductSampleBufferOwners{
            .wavelengths = &self.wavelengths,
            .radiance = &self.radiance,
            .irradiance = &self.irradiance,
            .reflectance = &self.reflectance,
            .scratch = &self.scratch,
            .scratch_aux = &self.scratch_aux,
        };
        const transport_buffers = TransportBufferOwners{
            .layer_inputs = &self.layer_inputs,
            .source_interfaces = &self.source_interfaces,
            .rtm_quadrature_levels = &self.rtm_quadrature_levels,
        };
        const pseudo_spherical_buffers = PseudoSphericalBufferOwners{
            .samples = &self.pseudo_spherical_samples,
            .level_starts = &self.pseudo_spherical_level_starts,
            .level_altitudes = &self.pseudo_spherical_level_altitudes,
        };
        const jacobian_buffers = JacobianBufferOwners{
            .values = &self.jacobian,
        };

        try ensureProductSampleBuffers(allocator, &product_buffers, requirements.sample_count);
        try ensureTransportBuffers(allocator, &transport_buffers, requirements);
        try ensurePseudoSphericalBuffers(allocator, &pseudo_spherical_buffers, requirements);
        try ensureJacobianBuffers(allocator, &jacobian_buffers, requirements);

        const source_interface_view: []common.SourceInterfaceInput = if (requirements.source_interface_count != 0)
            transport_buffers.source_interfaces.*[0..requirements.source_interface_count]
        else
            @constCast(&[_]common.SourceInterfaceInput{});
        const rtm_quadrature_view: []common.RtmQuadratureLevel = if (requirements.rtm_quadrature_level_count != 0)
            transport_buffers.rtm_quadrature_levels.*[0..requirements.rtm_quadrature_level_count]
        else
            @constCast(&[_]common.RtmQuadratureLevel{});

        var pseudo_spherical_samples_view: []common.PseudoSphericalSample =
            @constCast(&[_]common.PseudoSphericalSample{});
        var pseudo_spherical_starts_view: []usize = @constCast(&[_]usize{});
        var pseudo_spherical_altitudes_view: []f64 = @constCast(&[_]f64{});
        if (requirements.pseudo_spherical_level_count != 0) {
            pseudo_spherical_samples_view =
                pseudo_spherical_buffers.samples.*[0..requirements.pseudo_spherical_sample_count];
            pseudo_spherical_starts_view =
                pseudo_spherical_buffers.level_starts.*[0..requirements.pseudo_spherical_level_count];
            pseudo_spherical_altitudes_view =
                pseudo_spherical_buffers.level_altitudes.*[0..requirements.pseudo_spherical_level_count];
        }

        const jacobian_view = if (requirements.active_jacobian_count != 0)
            jacobian_buffers.values.*[0 .. requirements.sample_count * requirements.active_jacobian_count]
        else
            null;

        return .{
            .wavelengths = product_buffers.wavelengths.*[0..requirements.sample_count],
            .radiance = product_buffers.radiance.*[0..requirements.sample_count],
            .irradiance = product_buffers.irradiance.*[0..requirements.sample_count],
            .reflectance = product_buffers.reflectance.*[0..requirements.sample_count],
            .scratch = product_buffers.scratch.*[0..requirements.sample_count],
            .scratch_aux = product_buffers.scratch_aux.*[0..requirements.sample_count],
            .layer_inputs = transport_buffers.layer_inputs.*[0..requirements.layer_count],
            .source_interfaces = source_interface_view,
            .rtm_quadrature_levels = rtm_quadrature_view,
            .pseudo_spherical_samples = pseudo_spherical_samples_view,
            .pseudo_spherical_level_starts = pseudo_spherical_starts_view,
            .pseudo_spherical_level_altitudes = pseudo_spherical_altitudes_view,
            .jacobian = jacobian_view,
            .jacobian_state_mask = requirements.jacobian_state_mask,
        };
    }
};

fn ensureProductSampleBuffers(
    allocator: Allocator,
    owners: *const ProductSampleBufferOwners,
    sample_count: usize,
) Error!void {
    // ensureProductSampleBuffers ----------------------------------------------------------------------------------------|
    // Grow the sample-sized product rows together. All values are scratch/output rows and old contents are               |
    // discarded whenever capacity grows.                                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    try ensureBufferCapacity(allocator, owners.wavelengths, sample_count);
    try ensureBufferCapacity(allocator, owners.radiance, sample_count);
    try ensureBufferCapacity(allocator, owners.irradiance, sample_count);
    try ensureBufferCapacity(allocator, owners.reflectance, sample_count);
    try ensureBufferCapacity(allocator, owners.scratch, sample_count);
    try ensureBufferCapacity(allocator, owners.scratch_aux, sample_count);
}

fn ensureTransportBuffers(
    allocator: Allocator,
    owners: *const TransportBufferOwners,
    requirements: BufferRequirements,
) Error!void {
    // ensureTransportBuffers --------------------------------------------------------------------------------------------|
    // Grow transport-route buffers from the requirements row. Disabled feature buffers are freed immediately             |
    // so stale rows cannot be observed by a later route.                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    try ensureLayerBufferCapacity(allocator, owners.layer_inputs, requirements.layer_count);
    if (requirements.source_interface_count != 0) {
        try ensureSourceInterfaceBufferCapacity(
            allocator,
            owners.source_interfaces,
            requirements.source_interface_count,
        );
    } else {
        freeSourceInterfaceBuffer(allocator, owners.source_interfaces.*);
        owners.source_interfaces.* = &.{};
    }
    if (requirements.rtm_quadrature_level_count != 0) {
        try ensureRtmQuadratureBufferCapacity(
            allocator,
            owners.rtm_quadrature_levels,
            requirements.rtm_quadrature_level_count,
        );
    } else {
        freeRtmQuadratureBuffer(allocator, owners.rtm_quadrature_levels.*);
        owners.rtm_quadrature_levels.* = &.{};
    }
}

fn ensurePseudoSphericalBuffers(
    allocator: Allocator,
    owners: *const PseudoSphericalBufferOwners,
    requirements: BufferRequirements,
) Error!void {
    // ensurePseudoSphericalBuffers --------------------------------------------------------------------------------------|
    // Grow or release geometric-correction support rows as one group. The sample, start-index, and altitude              |
    // arrays describe the same pseudo-spherical grid and must not drift independently.                                   |
    // -------------------------------------------------------------------------------------------------------------------|

    if (requirements.pseudo_spherical_level_count != 0) {
        try ensurePseudoSphericalSampleBufferCapacity(
            allocator,
            owners.samples,
            requirements.pseudo_spherical_sample_count,
        );
        try ensureIndexBufferCapacity(
            allocator,
            owners.level_starts,
            requirements.pseudo_spherical_level_count,
        );
        try ensureBufferCapacity(
            allocator,
            owners.level_altitudes,
            requirements.pseudo_spherical_level_count,
        );
    } else {
        freePseudoSphericalSampleBuffer(allocator, owners.samples.*);
        freeIndexBuffer(allocator, owners.level_starts.*);
        freeBuffer(allocator, owners.level_altitudes.*);
        owners.samples.* = &.{};
        owners.level_starts.* = &.{};
        owners.level_altitudes.* = &.{};
    }
}

fn ensureJacobianBuffers(
    allocator: Allocator,
    owners: *const JacobianBufferOwners,
    requirements: BufferRequirements,
) Error!void {
    // ensureJacobianBuffers ---------------------------------------------------------------------------------------------|
    // Grow the optional state-major Jacobian output row when derivative states are active. Disabled runs keep            |
    // capacity for reuse but return a null Jacobian view.                                                                |
    // -------------------------------------------------------------------------------------------------------------------|

    if (requirements.active_jacobian_count == 0) return;
    try ensureBufferCapacity(
        allocator,
        owners.values,
        requirements.sample_count * requirements.active_jacobian_count,
    );
}

pub fn transportLayerCountHint(scene: *const Scene, rtm_config: common.SolveConfig) usize {
    // transportLayerCountHint -------------------------------------------------------------------------------------------|
    // Estimate layer-buffer capacity before wavelength-specific preparation. Explicit interval grids use the             |
    // interval division contract; ordinary scenes use layer_count * sublayer_divisions.                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    _ = rtm_config;

    if (scene.atmosphere.interval_grid.enabled()) {
        const uses_disamar_shared_rtm_grid =
            scene.observation_model.resolvedChannelControls(.radiance).response.integration_mode == .disamar_hr_grid or
            scene.observation_model.resolvedChannelControls(.irradiance).response.integration_mode == .disamar_hr_grid;

        var total_count: usize = 0;
        for (scene.atmosphere.interval_grid.intervals) |interval| {
            total_count += if (uses_disamar_shared_rtm_grid)
                @as(usize, interval.altitude_divisions) + 1
            else
                @max(@as(usize, interval.altitude_divisions), 1);
        }

        return @max(total_count, 1);
    }

    const layer_count = @max(@as(usize, @intCast(scene.atmosphere.layer_count)), 1);
    return layer_count * @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn pseudoSphericalSampleCountHint(scene: *const Scene, rtm_config: common.SolveConfig) usize {
    // pseudoSphericalSampleCountHint ------------------------------------------------------------------------------------|
    // Over-allocate enough pseudo-spherical support samples for the unresolved scene hint. The resolved path             |
    // below may use fewer samples once PreparedOpticalState has the exact RTM grid.                                      |
    // -------------------------------------------------------------------------------------------------------------------|

    const layer_count = transportLayerCountHint(scene, rtm_config);
    return layer_count * (pseudoSphericalSubgridDivisions(scene) + 2);
}

pub fn resolvedTransportLayerCount(
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    // resolvedTransportLayerCount ---------------------------------------------------------------------------------------|
    // Return the exact transport-layer count from PreparedOpticalState after interval/sublayer preparation.              |
    // -------------------------------------------------------------------------------------------------------------------|

    _ = rtm_config;
    return prepared.transportLayerCount();
}

pub fn resolvedPseudoSphericalSampleCount(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
) usize {
    // resolvedPseudoSphericalSampleCount --------------------------------------------------------------------------------|
    // Return the exact pseudo-spherical support count for worker scratch buffers. Shared RTM geometry carries            |
    // explicit per-layer support counts; the fallback uses the subgrid count for every resolved layer.                   |
    // -------------------------------------------------------------------------------------------------------------------|

    if (prepared.intervalSemanticsUseReducedSharedRtmLayers() and
        prepared.shared_rtm_geometry.isValidFor(resolvedTransportLayerCount(rtm_config, prepared)))
    {
        var sample_count: usize = 0;
        for (prepared.shared_rtm_geometry.layers) |layer| {
            const support_count: usize = @intCast(layer.support_count);
            if (support_count > 2) sample_count += support_count - 2;
        }
        return sample_count;
    }
    return resolvedTransportLayerCount(rtm_config, prepared) * pseudoSphericalSubgridDivisions(scene);
}

fn pseudoSphericalSubgridDivisions(scene: *const Scene) usize {
    // pseudoSphericalSubgridDivisions -----------------------------------------------------------------------------------|
    // Clamp the scene sublayer division count to at least one so support buffers are never sized to zero                 |
    // for a geometric-correction route.                                                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    return @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
}

pub fn validateBuffers(
    requirements: BufferRequirements,
    buffers: Buffers,
) Error!void {
    // validateBuffers ---------------------------------------------------------------------------------------------------|
    // Check that a Buffers view is internally coherent for one spectral sweep and the requested RTM route.               |
    // This catches stale workspace slices before simulation writes into them.                                            |
    // -------------------------------------------------------------------------------------------------------------------|

    // The always-active summary buffers and the rtm_config-selected transport
    // carriers must stay shape-compatible for a single sweep.
    const summary_buffers_match =
        requirements.sample_count != 0 and
        buffers.wavelengths.len == requirements.sample_count and
        buffers.radiance.len == requirements.sample_count and
        buffers.irradiance.len == requirements.sample_count and
        buffers.reflectance.len == requirements.sample_count and
        buffers.scratch.len == requirements.sample_count and
        buffers.scratch_aux.len == requirements.sample_count and
        buffers.layer_inputs.len >= requirements.layer_count;
    if (!summary_buffers_match) {
        return error.ShapeMismatch;
    }

    const source_interfaces_match =
        requirements.source_interface_count == 0 or
        buffers.source_interfaces.len >= requirements.source_interface_count;
    if (!source_interfaces_match) {
        return error.ShapeMismatch;
    }

    const rtm_quadrature_matches =
        requirements.rtm_quadrature_level_count == 0 or
        buffers.rtm_quadrature_levels.len >= requirements.rtm_quadrature_level_count;
    if (!rtm_quadrature_matches) {
        return error.ShapeMismatch;
    }

    const pseudo_spherical_grid_matches =
        requirements.pseudo_spherical_level_count == 0 or
        (buffers.pseudo_spherical_samples.len >= requirements.pseudo_spherical_sample_count and
            buffers.pseudo_spherical_level_starts.len >= requirements.pseudo_spherical_level_count and
            buffers.pseudo_spherical_level_altitudes.len >= requirements.pseudo_spherical_level_count);
    if (!pseudo_spherical_grid_matches) {
        return error.ShapeMismatch;
    }

    if (buffers.jacobian) |values| {
        if (requirements.active_jacobian_count == 0 or
            buffers.jacobian_state_mask != requirements.jacobian_state_mask or
            values.len != requirements.sample_count * requirements.active_jacobian_count)
        {
            return error.ShapeMismatch;
        }
    } else if (requirements.active_jacobian_count != 0 or buffers.jacobian_state_mask != 0) {
        return error.ShapeMismatch;
    }
}

pub fn ensureBufferCapacity(allocator: Allocator, buffer: *[]f64, capacity: usize) Error!void {
    // ensureBufferCapacity ----------------------------------------------------------------------------------------------|
    // Grow an f64 scratch/output buffer without preserving old values. Simulation fills the returned view                |
    // before reading it.                                                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(f64, capacity);
    freeBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureLayerBufferCapacity(allocator: Allocator, buffer: *[]common.LayerInput, capacity: usize) Error!void {
    // ensureLayerBufferCapacity -----------------------------------------------------------------------------------------|
    // Grow the wavelength-specific LayerInput buffer. Existing contents are scratch data and are discarded.              |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.LayerInput, capacity);
    freeLayerBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureForwardResultCapacity(
    allocator: Allocator,
    buffer: *[]Types.ForwardIntegratedSample,
    capacity: usize,
) Error!void {
    // ensureForwardResultCapacity ---------------------------------------------------------------------------------------|
    // Grow the dense forward-result staging buffer used between prefetch and nominal integration.                        |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(Types.ForwardIntegratedSample, capacity);
    freeForwardResultBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureSourceInterfaceBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.SourceInterfaceInput,
    capacity: usize,
) Error!void {
    // ensureSourceInterfaceBufferCapacity -------------------------------------------------------------------------------|
    // Grow the coarse source-interface buffer used by the integrated-source fallback route.                              |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.SourceInterfaceInput, capacity);
    freeSourceInterfaceBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureRtmQuadratureBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.RtmQuadratureLevel,
    capacity: usize,
) Error!void {
    // ensureRtmQuadratureBufferCapacity ---------------------------------------------------------------------------------|
    // Grow the RTM-native quadrature buffer used by integrated-source evaluation.                                        |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.RtmQuadratureLevel, capacity);
    freeRtmQuadratureBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensurePseudoSphericalSampleBufferCapacity(
    allocator: Allocator,
    buffer: *[]common.PseudoSphericalSample,
    capacity: usize,
) Error!void {
    // ensurePseudoSphericalSampleBufferCapacity -------------------------------------------------------------------------|
    // Grow the pseudo-spherical support sample buffer used by geometric-correction attenuation.                          |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(common.PseudoSphericalSample, capacity);
    freePseudoSphericalSampleBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn ensureIndexBufferCapacity(allocator: Allocator, buffer: *[]usize, capacity: usize) Error!void {
    // ensureIndexBufferCapacity -----------------------------------------------------------------------------------------|
    // Grow a usize index buffer, currently used for pseudo-spherical level starts.                                       |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.*.len >= capacity) return;
    const replacement = try allocator.alloc(usize, capacity);
    freeIndexBuffer(allocator, buffer.*);
    buffer.* = replacement;
}

fn freeBuffer(allocator: Allocator, buffer: []f64) void {
    // freeBuffer --------------------------------------------------------------------------------------------------------|
    // Free a possibly empty f64 buffer. Empty slice sentinels are not allocator-owned.                                   |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freeLayerBuffer(allocator: Allocator, buffer: []common.LayerInput) void {
    // freeLayerBuffer ---------------------------------------------------------------------------------------------------|
    // Free a possibly empty LayerInput buffer.                                                                           |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freeForwardResultBuffer(allocator: Allocator, buffer: []Types.ForwardIntegratedSample) void {
    // freeForwardResultBuffer -------------------------------------------------------------------------------------------|
    // Free a possibly empty forward-result staging buffer.                                                               |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freeSourceInterfaceBuffer(allocator: Allocator, buffer: []common.SourceInterfaceInput) void {
    // freeSourceInterfaceBuffer -----------------------------------------------------------------------------------------|
    // Free a possibly empty source-interface buffer.                                                                     |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freeRtmQuadratureBuffer(allocator: Allocator, buffer: []common.RtmQuadratureLevel) void {
    // freeRtmQuadratureBuffer -------------------------------------------------------------------------------------------|
    // Free a possibly empty RTM quadrature buffer.                                                                       |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freePseudoSphericalSampleBuffer(allocator: Allocator, buffer: []common.PseudoSphericalSample) void {
    // freePseudoSphericalSampleBuffer -----------------------------------------------------------------------------------|
    // Free a possibly empty pseudo-spherical sample buffer.                                                              |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}

fn freeIndexBuffer(allocator: Allocator, buffer: []usize) void {
    // freeIndexBuffer ---------------------------------------------------------------------------------------------------|
    // Free a possibly empty usize index buffer.                                                                          |
    // -------------------------------------------------------------------------------------------------------------------|

    if (buffer.len != 0) allocator.free(buffer);
}
