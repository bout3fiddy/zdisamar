const std = @import("std");
const zdisamar = @import("zdisamar");

const allocator = std.heap.smp_allocator;

// c.zig ------------------------------------------------------------------------------------------------------|
// C ABI boundary for Python bindings and other callers that cannot hold native Zig owners directly.           |
//                                                                                                             |
// called from                                                                                                 |
//   build.zig builds this file as the C shared-library root.                                                  |
//   python/zdisamar/bindings/signatures.py binds every zds_* export with ctypes-compatible signatures.        |
//   python/zdisamar/bindings/handles.py owns the high-level Python handle lifecycle and calls the matching    |
//   zds_*_free function for every borrowed result view.                                                       |
//   src/root.zig, input/o2a_reference/root.zig, and optimal_estimation/retrieval.zig are the native Zig       |
//   surfaces this boundary converts into and out of.                                                          |
//                                                                                                             |
// exports                                                                                                     |
//   context       : create/destroy, last_error, parsed/default O2 A preparation, session warmup               |
//   spectra       : run spectrum, run Jacobian spectrum, choose Jacobian states by external state id          |
//   retrieval     : single, batch, fastmode batch, and prepared-correction optimal-estimation runs            |
//   diagnostics   : spectrum summary, atmospheric budget, O2 lines, instrument response, O2-O2 CIA, RT rows   |
//   cleanup       : zds_*_free functions remove Context-owned native handles or copied diagnostic row tables  |
//                                                                                                             |
// call path                                                                                                   |
//   C request structs borrow caller buffers long enough to validate and convert into native Zig slices.       |
//   Context owns prepared O2 A state, parsed JSON storage, session storage, native output handles, copied     |
//   diagnostic row buffers, and the fixed last_error string.                                                  |
//   Run functions allocate native outputs, store those pointers in Context lists, and return extern structs   |
//   containing borrowed array pointers plus an opaque result_handle.                                          |
//   Diagnostic functions copy native rows into Context-owned C row arrays so C/Python callers can read stable |
//   tables until the matching free call.                                                                      |
//                                                                                                             |
// ownership                                                                                                   |
//   Input arrays and JSON buffers are borrowed from the caller. Result and diagnostic pointers are borrowed   |
//   from Context. C callers must call the matching zds_*_free function before destroying the context, or let  |
//   zds_context_destroy clear any still-retained handles.                                                     |
//                                                                                                             |
// runtime shape                                                                                               |
//   This file does no file I/O, CLI parsing, or reference-data loading itself. It validates raw pointers and  |
//   counts, translates errors into c_int status plus last_error, and forwards work to the public Zig facade.  |
//                                                                                                             |
// memory                                                                                                      |
//   Public structs below are extern ABI rows. Field order is part of the C contract, so layout comments show  |
//   source order plus explicit padding measured with @sizeOf, @alignOf, and @offsetOf on the current target.  |
//   Pointer fields are one-word C pointers here; referenced arrays, JSON storage, and native result buffers   |
//   live out of line and are not counted in the ABI row size.                                                 |
// ------------------------------------------------------------------------------------------------------------|

pub const ZdsStatus = enum(c_int) {
    ok = 0,
    failure = 1,
};

// ZdsSpectrum ------------------------------------------------------------------------------------------------|
// Borrowed spectrum arrays returned by run calls. result_handle owns the backing native Output.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len                  : usize                                                                       |
// [ 8..15] wavelength_nm        : [*]const f64                                                                |
// [16..23] radiance             : [*]const f64                                                                |
// [24..31] irradiance           : [*]const f64                                                                |
// [32..39] reflectance          : [*]const f64                                                                |
// [40..47] jacobian             : ?[*]const f64                                                               |
// [48..55] jacobian_state_count : usize                                                                       |
// [56..63] result_handle        : ?*anyopaque                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   array pointers borrow result_handle storage until the matching zds_spectrum_free call.                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B (0.062 KiB); total also includes referenced storage above                    |
pub const ZdsSpectrum = extern struct {
    len: usize = 0,
    wavelength_nm: [*]const f64 = undefined,
    radiance: [*]const f64 = undefined,
    irradiance: [*]const f64 = undefined,
    reflectance: [*]const f64 = undefined,
    jacobian: ?[*]const f64 = null,
    jacobian_state_count: usize = 0,
    result_handle: ?*anyopaque = null,
};

// ZdsDiagnosticReport ----------------------------------------------------------------------------------------|
// Small scalar summary for one spectrum.                                                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 3] sample_count        : u32                                                                          |
// [ 4.. 7] padding             : 4 B                                                                          |
// [ 8..15] wavelength_start_nm : f64                                                                          |
// [16..23] wavelength_end_nm   : f64                                                                          |
// [24..31] mean_radiance       : f64                                                                          |
// [32..39] mean_irradiance     : f64                                                                          |
// [40..47] mean_reflectance    : f64                                                                          |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 48 B (0.047 KiB); stack or caller-owned row                                       |
pub const ZdsDiagnosticReport = extern struct {
    sample_count: u32 = 0,
    wavelength_start_nm: f64 = 0.0,
    wavelength_end_nm: f64 = 0.0,
    mean_radiance: f64 = 0.0,
    mean_irradiance: f64 = 0.0,
    mean_reflectance: f64 = 0.0,
};

// ZdsOptimalEstimationStateSpec ------------------------------------------------------------------------------|
// One C-facing retrieval-state control row. Optional pressure profile pointers borrow caller buffers.         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 0] state_id                      : u8                                                                 |
// [ 1.. 1] has_lower                     : u8                                                                 |
// [ 2.. 2] has_upper                     : u8                                                                 |
// [ 3.. 3] padding                       : 1 B                                                                |
// [ 4.. 7] interval_index_1based         : u32                                                                |
// [ 8..15] initial                       : f64                                                                |
// [16..23] prior                         : f64                                                                |
// [24..31] variance                      : f64                                                                |
// [32..39] lower                         : f64                                                                |
// [40..47] upper                         : f64                                                                |
// [48..55] thickness_hpa                 : f64                                                                |
// [56..63] pressure_profile_count        : usize                                                              |
// [64..71] pressure_profile_altitude_km  : ?[*]const f64                                                      |
// [72..79] pressure_profile_pressure_hpa : ?[*]const f64                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   pressure profile arrays are borrowed only while the request is converted into native state specs.         |
//                                                                                                             |
// unused bits: 8 padding + 0 bool-storage slack = 8 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B (0.078 KiB); total also includes borrowed profile arrays                     |
pub const ZdsOptimalEstimationStateSpec = extern struct {
    state_id: u8 = 0,
    has_lower: u8 = 0,
    has_upper: u8 = 0,
    interval_index_1based: u32 = 0,
    initial: f64 = 0.0,
    prior: f64 = 0.0,
    variance: f64 = 0.0,
    lower: f64 = 0.0,
    upper: f64 = 0.0,
    thickness_hpa: f64 = 0.0,
    pressure_profile_count: usize = 0,
    pressure_profile_altitude_km: ?[*]const f64 = null,
    pressure_profile_pressure_hpa: ?[*]const f64 = null,
};

// ZdsOptimalEstimationControls -------------------------------------------------------------------------------|
// Iteration and convergence controls copied into the native retrieval request.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] max_iterations                     : usize                                                         |
// [ 8..15] state_vector_convergence_threshold : f64                                                           |
// [16..23] max_change_transformed_state       : f64                                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B (0.023 KiB); embedded in request rows                                        |
pub const ZdsOptimalEstimationControls = extern struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};

// ZdsOptimalEstimationRequest --------------------------------------------------------------------------------|
// Single-run retrieval request with borrowed measurement arrays and state rows.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] sample_count  : usize                                                                              |
// [ 8..15] wavelength_nm : ?[*]const f64                                                                      |
// [16..23] reflectance   : ?[*]const f64                                                                      |
// [24..31] variance      : ?[*]const f64                                                                      |
// [32..39] state_count   : usize                                                                              |
// [40..47] states        : ?[*]const ZdsOptimalEstimationStateSpec                                            |
// [48..71] controls      : ZdsOptimalEstimationControls                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   measurement arrays and state specs borrow caller buffers for the duration of the call.                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 72 B (0.070 KiB); total also includes borrowed buffers                            |
pub const ZdsOptimalEstimationRequest = extern struct {
    sample_count: usize = 0,
    wavelength_nm: ?[*]const f64 = null,
    reflectance: ?[*]const f64 = null,
    variance: ?[*]const f64 = null,
    state_count: usize = 0,
    states: ?[*]const ZdsOptimalEstimationStateSpec = null,
    controls: ZdsOptimalEstimationControls = .{},
};

// ZdsOptimalEstimationResult ---------------------------------------------------------------------------------|
// Borrowed single-run retrieval output. result_handle owns all pointed-to result arrays.                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 120 B (0.117 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] state_count                      : usize                                                         |
// [  8.. 15] iteration_count                  : usize                                                         |
// [ 16.. 16] converged                        : u8                                                            |
// [ 17.. 23] padding                          : 7 B                                                           |
// [ 24.. 31] state_ids                        : ?[*]const u8                                                  |
// [ 32.. 39] state                            : ?[*]const f64                                                 |
// [ 40.. 47] initial_state                    : ?[*]const f64                                                 |
// [ 48.. 55] posterior_covariance             : ?[*]const f64                                                 |
// [ 56.. 63] averaging_kernel                 : ?[*]const f64                                                 |
// [ 64.. 71] history_state                    : ?[*]const f64                                                 |
// [ 72.. 79] history_chi2                     : ?[*]const f64                                                 |
// [ 80.. 87] history_chi2_reflectance         : ?[*]const f64                                                 |
// [ 88.. 95] history_chi2_state_vector        : ?[*]const f64                                                 |
// [ 96..103] history_state_vector_convergence : ?[*]const f64                                                 |
// [104..111] history_snr_normal               : ?[*]const u8                                                  |
// [112..119] result_handle                    : ?*anyopaque                                                   |
//                                                                                                             |
// referenced storage                                                                                          |
//   all pointer fields borrow native result arrays until zds_optimal_estimation_result_free.                  |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 120 B (0.117 KiB); total also includes native result arrays                       |
pub const ZdsOptimalEstimationResult = extern struct {
    state_count: usize = 0,
    iteration_count: usize = 0,
    converged: u8 = 0,
    state_ids: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    initial_state: ?[*]const f64 = null,
    posterior_covariance: ?[*]const f64 = null,
    averaging_kernel: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    history_chi2: ?[*]const f64 = null,
    history_chi2_reflectance: ?[*]const f64 = null,
    history_chi2_state_vector: ?[*]const f64 = null,
    history_state_vector_convergence: ?[*]const f64 = null,
    history_snr_normal: ?[*]const u8 = null,
    result_handle: ?*anyopaque = null,
};

// ZdsOptimalEstimationBatchRequest ---------------------------------------------------------------------------|
// Multi-run retrieval request sharing one measurement grid and one state template across run-specific priors. |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] sample_count       : usize                                                                       |
// [  8.. 15] wavelength_nm      : ?[*]const f64                                                               |
// [ 16.. 23] reflectance        : ?[*]const f64                                                               |
// [ 24.. 31] variance           : ?[*]const f64                                                               |
// [ 32.. 39] state_count        : usize                                                                       |
// [ 40.. 47] state_template     : ?[*]const ZdsOptimalEstimationStateSpec                                     |
// [ 48.. 55] run_count          : usize                                                                       |
// [ 56.. 63] initial            : ?[*]const f64                                                               |
// [ 64.. 71] prior              : ?[*]const f64                                                               |
// [ 72.. 95] controls           : ZdsOptimalEstimationControls                                                |
// [ 96..103] batch_worker_count : usize                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   measurement arrays, template state rows, and run initial/prior arrays borrow caller buffers.              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 104 B (0.102 KiB); total also includes borrowed buffers                           |
pub const ZdsOptimalEstimationBatchRequest = extern struct {
    sample_count: usize = 0,
    wavelength_nm: ?[*]const f64 = null,
    reflectance: ?[*]const f64 = null,
    variance: ?[*]const f64 = null,
    state_count: usize = 0,
    state_template: ?[*]const ZdsOptimalEstimationStateSpec = null,
    run_count: usize = 0,
    initial: ?[*]const f64 = null,
    prior: ?[*]const f64 = null,
    controls: ZdsOptimalEstimationControls = .{},
    batch_worker_count: usize = 1,
};

// ZdsOptimalEstimationBatchResult ----------------------------------------------------------------------------|
// Borrowed batch retrieval output backed by a native BatchResult handle.                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] run_count        : usize                                                                           |
// [ 8..15] state_count      : usize                                                                           |
// [16..23] history_capacity : usize                                                                           |
// [24..31] iteration_count  : ?[*]const usize                                                                 |
// [32..39] converged        : ?[*]const u8                                                                    |
// [40..47] status           : ?[*]const u8                                                                    |
// [48..55] state            : ?[*]const f64                                                                   |
// [56..63] history_state    : ?[*]const f64                                                                   |
// [64..71] result_handle    : ?*anyopaque                                                                     |
//                                                                                                             |
// referenced storage                                                                                          |
//   pointer fields borrow native batch result arrays until zds_optimal_estimation_batch_result_free.          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 72 B (0.070 KiB); total also includes native result arrays                        |
pub const ZdsOptimalEstimationBatchResult = extern struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: ?[*]const usize = null,
    converged: ?[*]const u8 = null,
    status: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    result_handle: ?*anyopaque = null,
};

// ZdsOptimalEstimationFastmodeBatchResult --------------------------------------------------------------------|
// Borrowed fastmode batch output with per-stage iteration and convergence arrays.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] run_count                       : usize                                                          |
// [  8.. 15] state_count                     : usize                                                          |
// [ 16.. 23] history_capacity                : usize                                                          |
// [ 24.. 31] iteration_count                 : ?[*]const usize                                                |
// [ 32.. 39] converged                       : ?[*]const u8                                                   |
// [ 40.. 47] status                          : ?[*]const u8                                                   |
// [ 48.. 55] state                           : ?[*]const f64                                                  |
// [ 56.. 63] history_state                   : ?[*]const f64                                                  |
// [ 64.. 71] fast_stage_iteration_count      : ?[*]const usize                                                |
// [ 72.. 79] fast_stage_converged            : ?[*]const u8                                                   |
// [ 80.. 87] full_correction_iteration_count : ?[*]const usize                                                |
// [ 88.. 95] full_correction_converged       : ?[*]const u8                                                   |
// [ 96..103] result_handle                   : ?*anyopaque                                                    |
//                                                                                                             |
// referenced storage                                                                                          |
//   pointer fields borrow native fastmode arrays until the matching fastmode result free call.                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 104 B (0.102 KiB); total also includes native result arrays                       |
pub const ZdsOptimalEstimationFastmodeBatchResult = extern struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: ?[*]const usize = null,
    converged: ?[*]const u8 = null,
    status: ?[*]const u8 = null,
    state: ?[*]const f64 = null,
    history_state: ?[*]const f64 = null,
    fast_stage_iteration_count: ?[*]const usize = null,
    fast_stage_converged: ?[*]const u8 = null,
    full_correction_iteration_count: ?[*]const usize = null,
    full_correction_converged: ?[*]const u8 = null,
    result_handle: ?*anyopaque = null,
};

// ZdsAtmosphericBudgetRow ------------------------------------------------------------------------------------|
// One atmospheric budget row copied from a native diagnostic row.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                    : f64                                                           |
// [  8.. 11] layer_index                      : u32                                                           |
// [ 12.. 15] sublayer_index                   : u32                                                           |
// [ 16.. 19] global_sublayer_index            : u32                                                           |
// [ 20.. 23] interval_index_1based            : u32                                                           |
// [ 24.. 27] support_row_kind                 : u32                                                           |
// [ 28.. 31] padding                          : 4 B                                                           |
// [ 32.. 39] altitude_km                      : f64                                                           |
// [ 40.. 47] top_altitude_km                  : f64                                                           |
// [ 48.. 55] bottom_altitude_km               : f64                                                           |
// [ 56.. 63] pressure_hpa                     : f64                                                           |
// [ 64.. 71] top_pressure_hpa                 : f64                                                           |
// [ 72.. 79] bottom_pressure_hpa              : f64                                                           |
// [ 80.. 87] temperature_k                    : f64                                                           |
// [ 88.. 95] number_density_cm3               : f64                                                           |
// [ 96..103] oxygen_number_density_cm3        : f64                                                           |
// [104..111] absorber_number_density_cm3      : f64                                                           |
// [112..119] path_length_cm                   : f64                                                           |
// [120..127] aerosol_fraction                 : f64                                                           |
// [128..135] gas_absorption_optical_depth     : f64                                                           |
// [136..143] gas_scattering_optical_depth     : f64                                                           |
// [144..151] cia_optical_depth                : f64                                                           |
// [152..159] aerosol_optical_depth            : f64                                                           |
// [160..167] aerosol_scattering_optical_depth : f64                                                           |
// [168..175] aerosol_absorption_optical_depth : f64                                                           |
// [176..183] total_absorption_optical_depth   : f64                                                           |
// [184..191] total_scattering_optical_depth   : f64                                                           |
// [192..199] total_optical_depth              : f64                                                           |
// [200..207] single_scatter_albedo            : f64                                                           |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 208 B (0.203 KiB); total = per instance * live row count                          |
pub const ZdsAtmosphericBudgetRow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    support_row_kind: u32 = 0,
    altitude_km: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    temperature_k: f64 = 0.0,
    number_density_cm3: f64 = 0.0,
    oxygen_number_density_cm3: f64 = 0.0,
    absorber_number_density_cm3: f64 = 0.0,
    path_length_cm: f64 = 0.0,
    aerosol_fraction: f64 = 0.0,
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    aerosol_absorption_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
};

// ZdsAtmosphericBudget ---------------------------------------------------------------------------------------|
// Borrowed atmospheric budget table. rows is owned by Context until released.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len  : usize                                                                                       |
// [ 8..15] rows : [*]const ZdsAtmosphericBudgetRow                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows points at a Context-owned copied row buffer.                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above                    |
pub const ZdsAtmosphericBudget = extern struct {
    len: usize = 0,
    rows: [*]const ZdsAtmosphericBudgetRow = undefined,
};

// ZdsO2LineContributionRow -----------------------------------------------------------------------------------|
// One O2 line-contribution diagnostic row copied from native spectroscopy diagnostics.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 168 B (0.164 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                    : f64                                                           |
// [  8.. 11] profile_node_index               : u32                                                           |
// [ 12.. 15] padding                          : 4 B                                                           |
// [ 16.. 23] altitude_km                      : f64                                                           |
// [ 24.. 27] row_kind                         : u32                                                           |
// [ 28.. 31] status                           : u32                                                           |
// [ 32.. 35] line_index                       : u32                                                           |
// [ 36.. 39] strong_line_index                : u32                                                           |
// [ 40.. 43] matched_strong_line_index        : u32                                                           |
// [ 44.. 45] gas_index                        : u16                                                           |
// [ 46.. 46] isotope_number                   : u8                                                            |
// [ 47.. 47] padding                          : 1 B                                                           |
// [ 48.. 51] isotopologue_code                : i32                                                           |
// [ 52.. 55] padding                          : 4 B                                                           |
// [ 56.. 63] center_wavelength_nm             : f64                                                           |
// [ 64.. 71] center_wavenumber_cm1            : f64                                                           |
// [ 72.. 79] shifted_center_wavenumber_cm1    : f64                                                           |
// [ 80.. 87] line_strength_cm2_per_molecule   : f64                                                           |
// [ 88.. 95] air_half_width_cm1               : f64                                                           |
// [ 96..103] pressure_shift_cm1               : f64                                                           |
// [104..111] lower_state_energy_cm1           : f64                                                           |
// [112..119] temperature_k                    : f64                                                           |
// [120..127] pressure_hpa                     : f64                                                           |
// [128..135] weak_line_sigma_cm2_per_molecule : f64                                                           |
// [136..143] strong_line_sigma_cm2_per_molecule : f64                                                         |
// [144..151] line_mixing_sigma_cm2_per_molecule : f64                                                         |
// [152..159] total_sigma_cm2_per_molecule     : f64                                                           |
// [160..167] abs_total_sigma_cm2_per_molecule : f64                                                           |
//                                                                                                             |
// unused bits: 72 padding + 0 bool-storage slack = 72 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 168 B (0.164 KiB); total = per instance * live row count                          |
pub const ZdsO2LineContributionRow = extern struct {
    wavelength_nm: f64 = 0.0,
    profile_node_index: u32 = 0,
    altitude_km: f64 = 0.0,
    row_kind: u32 = 0,
    status: u32 = 0,
    line_index: u32 = 0,
    strong_line_index: u32 = 0,
    matched_strong_line_index: u32 = 0,
    gas_index: u16 = 0,
    isotope_number: u8 = 0,
    isotopologue_code: i32 = 0,
    center_wavelength_nm: f64 = 0.0,
    center_wavenumber_cm1: f64 = 0.0,
    shifted_center_wavenumber_cm1: f64 = 0.0,
    line_strength_cm2_per_molecule: f64 = 0.0,
    air_half_width_cm1: f64 = 0.0,
    pressure_shift_cm1: f64 = 0.0,
    lower_state_energy_cm1: f64 = 0.0,
    temperature_k: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    weak_line_sigma_cm2_per_molecule: f64 = 0.0,
    strong_line_sigma_cm2_per_molecule: f64 = 0.0,
    line_mixing_sigma_cm2_per_molecule: f64 = 0.0,
    total_sigma_cm2_per_molecule: f64 = 0.0,
    abs_total_sigma_cm2_per_molecule: f64 = 0.0,
};

// ZdsO2LineContributions -------------------------------------------------------------------------------------|
// Borrowed O2 line-contribution table plus total available row count before truncation.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len             : usize                                                                            |
// [ 8..15] total_row_count : usize                                                                            |
// [16..16] truncated       : u8                                                                               |
// [17..23] padding         : 7 B                                                                              |
// [24..31] rows            : [*]const ZdsO2LineContributionRow                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows points at a Context-owned copied row buffer.                                                         |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above                    |
pub const ZdsO2LineContributions = extern struct {
    len: usize = 0,
    total_row_count: usize = 0,
    truncated: u8 = 0,
    rows: [*]const ZdsO2LineContributionRow = undefined,
};

// ZdsInstrumentResponseRow -----------------------------------------------------------------------------------|
// One instrument-response support sample copied from native diagnostics.                                      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 3] nominal_index                 : i32                                                                |
// [ 4.. 7] padding                       : 4 B                                                                |
// [ 8..15] nominal_wavelength_nm         : f64                                                                |
// [16..19] channel                       : u32                                                                |
// [20..23] sample_index                  : u32                                                                |
// [24..27] support_count                 : u32                                                                |
// [28..31] padding                       : 4 B                                                                |
// [32..39] offset_nm                     : f64                                                                |
// [40..47] support_wavelength_nm         : f64                                                                |
// [48..55] weight                        : f64                                                                |
// [56..63] support_width_nm              : f64                                                                |
// [64..71] instrument_fwhm_nm            : f64                                                                |
// [72..79] high_resolution_step_nm       : f64                                                                |
// [80..87] high_resolution_half_span_nm  : f64                                                                |
// [88..91] integration_mode              : u32                                                                |
// [92..92] response_enabled              : u8                                                                 |
// [93..95] padding                       : 3 B                                                                |
//                                                                                                             |
// unused bits: 88 padding + 0 bool-storage slack = 88 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B (0.094 KiB); total = per instance * live row count                           |
pub const ZdsInstrumentResponseRow = extern struct {
    nominal_index: i32 = 0,
    nominal_wavelength_nm: f64 = 0.0,
    channel: u32 = 0,
    sample_index: u32 = 0,
    support_count: u32 = 0,
    offset_nm: f64 = 0.0,
    support_wavelength_nm: f64 = 0.0,
    weight: f64 = 0.0,
    support_width_nm: f64 = 0.0,
    instrument_fwhm_nm: f64 = 0.0,
    high_resolution_step_nm: f64 = 0.0,
    high_resolution_half_span_nm: f64 = 0.0,
    integration_mode: u32 = 0,
    response_enabled: u8 = 0,
};

// ZdsInstrumentResponse --------------------------------------------------------------------------------------|
// Borrowed instrument-response diagnostic table.                                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len  : usize                                                                                       |
// [ 8..15] rows : [*]const ZdsInstrumentResponseRow                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows points at a Context-owned copied row buffer.                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above                    |
pub const ZdsInstrumentResponse = extern struct {
    len: usize = 0,
    rows: [*]const ZdsInstrumentResponseRow = undefined,
};

// ZdsO2O2CIARow ----------------------------------------------------------------------------------------------|
// One O2-O2 CIA diagnostic row copied from native optical-depth diagnostics.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                     : f64                                                          |
// [  8.. 11] layer_index                       : u32                                                          |
// [ 12.. 15] sublayer_index                    : u32                                                          |
// [ 16.. 19] global_sublayer_index             : u32                                                          |
// [ 20.. 23] interval_index_1based             : u32                                                          |
// [ 24.. 31] altitude_km                       : f64                                                          |
// [ 32.. 39] pressure_hpa                      : f64                                                          |
// [ 40.. 47] temperature_k                     : f64                                                          |
// [ 48.. 55] oxygen_number_density_cm3         : f64                                                          |
// [ 56.. 63] path_length_cm                    : f64                                                          |
// [ 64.. 71] cia_cross_section_cm5_per_molecule2 : f64                                                        |
// [ 72.. 79] cia_optical_depth                 : f64                                                          |
// [ 80.. 87] total_absorption_optical_depth    : f64                                                          |
// [ 88.. 95] total_optical_depth               : f64                                                          |
// [ 96..103] cia_share_of_total_absorption     : f64                                                          |
// [104..111] cia_share_of_total_optical_depth  : f64                                                          |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 112 B (0.109 KiB); total = per instance * live row count                          |
pub const ZdsO2O2CIARow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    altitude_km: f64 = 0.0,
    pressure_hpa: f64 = 0.0,
    temperature_k: f64 = 0.0,
    oxygen_number_density_cm3: f64 = 0.0,
    path_length_cm: f64 = 0.0,
    cia_cross_section_cm5_per_molecule2: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    cia_share_of_total_absorption: f64 = 0.0,
    cia_share_of_total_optical_depth: f64 = 0.0,
};

// ZdsO2O2CIADiagnostics --------------------------------------------------------------------------------------|
// Borrowed O2-O2 CIA diagnostic table.                                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len  : usize                                                                                       |
// [ 8..15] rows : [*]const ZdsO2O2CIARow                                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows points at a Context-owned copied row buffer.                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above                    |
pub const ZdsO2O2CIADiagnostics = extern struct {
    len: usize = 0,
    rows: [*]const ZdsO2O2CIARow = undefined,
};

// ZdsRadiativeTransferDiagnosticRow --------------------------------------------------------------------------|
// One radiative-transfer diagnostic row copied from the native RT diagnostic table.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 136 B (0.133 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] wavelength_nm                      : f64                                                         |
// [  8.. 11] layer_index                        : u32                                                         |
// [ 12.. 15] sublayer_index                     : u32                                                         |
// [ 16.. 19] global_sublayer_index              : u32                                                         |
// [ 20.. 23] interval_index_1based              : u32                                                         |
// [ 24.. 31] altitude_km                        : f64                                                         |
// [ 32.. 39] total_optical_depth                : f64                                                         |
// [ 40.. 47] total_absorption_optical_depth     : f64                                                         |
// [ 48.. 55] total_scattering_optical_depth     : f64                                                         |
// [ 56.. 63] single_scatter_albedo              : f64                                                         |
// [ 64.. 71] cumulative_optical_depth_above     : f64                                                         |
// [ 72.. 79] mid_layer_transmission_proxy       : f64                                                         |
// [ 80.. 87] direct_surface_transmission_proxy  : f64                                                         |
// [ 88.. 95] atmospheric_scattering_source_proxy : f64                                                        |
// [ 96..103] absorption_loss_proxy              : f64                                                         |
// [104..111] pseudo_spherical_airmass_factor    : f64                                                         |
// [112..115] n_streams                          : u32                                                         |
// [116..116] integrate_source_function          : u8                                                          |
// [117..119] padding                            : 3 B                                                         |
// [120..127] final_reflectance                  : f64                                                         |
// [128..135] final_radiance                     : f64                                                         |
//                                                                                                             |
// unused bits: 24 padding + 0 bool-storage slack = 24 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 136 B (0.133 KiB); total = per instance * live row count                          |
pub const ZdsRadiativeTransferDiagnosticRow = extern struct {
    wavelength_nm: f64 = 0.0,
    layer_index: u32 = 0,
    sublayer_index: u32 = 0,
    global_sublayer_index: u32 = 0,
    interval_index_1based: u32 = 0,
    altitude_km: f64 = 0.0,
    total_optical_depth: f64 = 0.0,
    total_absorption_optical_depth: f64 = 0.0,
    total_scattering_optical_depth: f64 = 0.0,
    single_scatter_albedo: f64 = 0.0,
    cumulative_optical_depth_above: f64 = 0.0,
    mid_layer_transmission_proxy: f64 = 0.0,
    direct_surface_transmission_proxy: f64 = 0.0,
    atmospheric_scattering_source_proxy: f64 = 0.0,
    absorption_loss_proxy: f64 = 0.0,
    pseudo_spherical_airmass_factor: f64 = 0.0,
    n_streams: u32 = 0,
    integrate_source_function: u8 = 0,
    final_reflectance: f64 = 0.0,
    final_radiance: f64 = 0.0,
};

// ZdsRadiativeTransferDiagnostics ----------------------------------------------------------------------------|
// Borrowed radiative-transfer diagnostic table.                                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] len  : usize                                                                                       |
// [ 8..15] rows : [*]const ZdsRadiativeTransferDiagnosticRow                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows points at a Context-owned copied row buffer.                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); total also includes referenced storage above                    |
pub const ZdsRadiativeTransferDiagnostics = extern struct {
    len: usize = 0,
    rows: [*]const ZdsRadiativeTransferDiagnosticRow = undefined,
};

// Context ----------------------------------------------------------------------------------------------------|
// Native owner behind the opaque C context pointer. It owns prepared state, JSON storage, results, and        |
// copied diagnostic rows exposed through borrowed C views.                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 4840 B (4.727 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..2911] prepared                       : ?PreparedO2A                                                  |
// [2912..3807] parsed_input                   : ?std.json.Parsed(O2AInput)                                    |
// [3808..4359] o2a_session_storage            : O2ASessionStorage                                             |
// [4360..4383] results                        : ArrayList(*Output)                                            |
// [4384..4407] oe_results                     : ArrayList(*Result)                                            |
// [4408..4431] oe_batch_results               : ArrayList(*BatchResult)                                       |
// [4432..4455] oe_fastmode_batch_results      : ArrayList(*FastmodeBatchResult)                               |
// [4456..4479] atmospheric_budgets            : ArrayList([]ZdsAtmosphericBudgetRow)                          |
// [4480..4503] o2_line_contribution_tables    : ArrayList([]ZdsO2LineContributionRow)                         |
// [4504..4527] instrument_response_tables     : ArrayList([]ZdsInstrumentResponseRow)                         |
// [4528..4551] o2_o2_cia_tables               : ArrayList([]ZdsO2O2CIARow)                                    |
// [4552..4575] radiative_transfer_tables      : ArrayList([]ZdsRadiativeTransferDiagnosticRow)                |
// [4576..4832] last_error                     : [256:0]u8                                                     |
// [4833..4839] trailing padding               : 7 B                                                           |
//                                                                                                             |
// referenced storage                                                                                          |
//   array lists retain native result pointers and copied diagnostic row buffers until cleared or released.    |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 76 cache lines at 64 B per line                                                                 |
// footprint: per instance = 4840 B (4.727 KiB); total also includes referenced storage above                  |
const Context = struct {
    prepared: ?zdisamar.PreparedO2A = null,
    parsed_input: ?std.json.Parsed(zdisamar.O2AInput) = null,
    o2a_session_storage: zdisamar.O2ASessionStorage = .{},
    results: std.ArrayList(*zdisamar.Output) = .empty,
    oe_results: std.ArrayList(*zdisamar.optimal_estimation.Result) = .empty,
    oe_batch_results: std.ArrayList(*zdisamar.optimal_estimation.BatchResult) = .empty,
    oe_fastmode_batch_results: std.ArrayList(*zdisamar.optimal_estimation.FastmodeBatchResult) = .empty,
    atmospheric_budgets: std.ArrayList([]ZdsAtmosphericBudgetRow) = .empty,
    o2_line_contribution_tables: std.ArrayList([]ZdsO2LineContributionRow) = .empty,
    instrument_response_tables: std.ArrayList([]ZdsInstrumentResponseRow) = .empty,
    o2_o2_cia_tables: std.ArrayList([]ZdsO2O2CIARow) = .empty,
    radiative_transfer_tables: std.ArrayList([]ZdsRadiativeTransferDiagnosticRow) = .empty,
    last_error: [256:0]u8 = [_:0]u8{0} ** 256,

    fn clearResults(self: *Context) void {
        for (self.results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.results.clearAndFree(allocator);
    }

    fn clearOptimalEstimationResults(self: *Context) void {
        for (self.oe_results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.oe_results.clearAndFree(allocator);
    }

    fn clearOptimalEstimationBatchResults(self: *Context) void {
        for (self.oe_batch_results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.oe_batch_results.clearAndFree(allocator);
    }

    fn clearOptimalEstimationFastmodeBatchResults(self: *Context) void {
        for (self.oe_fastmode_batch_results.items) |result| {
            result.deinit(allocator);
            allocator.destroy(result);
        }
        self.oe_fastmode_batch_results.clearAndFree(allocator);
    }

    fn clearAtmosphericBudgets(self: *Context) void {
        clearStoredRows(ZdsAtmosphericBudgetRow, &self.atmospheric_budgets);
    }

    fn clearO2LineContributionTables(self: *Context) void {
        clearStoredRows(ZdsO2LineContributionRow, &self.o2_line_contribution_tables);
    }

    fn clearInstrumentResponseTables(self: *Context) void {
        clearStoredRows(ZdsInstrumentResponseRow, &self.instrument_response_tables);
    }

    fn clearO2O2CIATables(self: *Context) void {
        clearStoredRows(ZdsO2O2CIARow, &self.o2_o2_cia_tables);
    }

    fn clearRadiativeTransferTables(self: *Context) void {
        clearStoredRows(ZdsRadiativeTransferDiagnosticRow, &self.radiative_transfer_tables);
    }

    fn removeResult(self: *Context, result: *zdisamar.Output) bool {
        for (self.results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeOptimalEstimationResult(self: *Context, result: *zdisamar.optimal_estimation.Result) bool {
        for (self.oe_results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.oe_results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeOptimalEstimationBatchResult(self: *Context, result: *zdisamar.optimal_estimation.BatchResult) bool {
        for (self.oe_batch_results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.oe_batch_results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeOptimalEstimationFastmodeBatchResult(
        self: *Context,
        result: *zdisamar.optimal_estimation.FastmodeBatchResult,
    ) bool {
        for (self.oe_fastmode_batch_results.items, 0..) |stored, index| {
            if (stored == result) {
                _ = self.oe_fastmode_batch_results.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    fn removeAtmosphericBudget(self: *Context, rows_ptr: [*]const ZdsAtmosphericBudgetRow) ?[]ZdsAtmosphericBudgetRow {
        return removeStoredRows(ZdsAtmosphericBudgetRow, &self.atmospheric_budgets, rows_ptr);
    }

    fn removeO2LineContributionTable(
        self: *Context,
        rows_ptr: [*]const ZdsO2LineContributionRow,
    ) ?[]ZdsO2LineContributionRow {
        return removeStoredRows(ZdsO2LineContributionRow, &self.o2_line_contribution_tables, rows_ptr);
    }

    fn removeInstrumentResponseTable(
        self: *Context,
        rows_ptr: [*]const ZdsInstrumentResponseRow,
    ) ?[]ZdsInstrumentResponseRow {
        return removeStoredRows(ZdsInstrumentResponseRow, &self.instrument_response_tables, rows_ptr);
    }

    fn removeO2O2CIATable(self: *Context, rows_ptr: [*]const ZdsO2O2CIARow) ?[]ZdsO2O2CIARow {
        return removeStoredRows(ZdsO2O2CIARow, &self.o2_o2_cia_tables, rows_ptr);
    }

    fn removeRadiativeTransferTable(
        self: *Context,
        rows_ptr: [*]const ZdsRadiativeTransferDiagnosticRow,
    ) ?[]ZdsRadiativeTransferDiagnosticRow {
        return removeStoredRows(ZdsRadiativeTransferDiagnosticRow, &self.radiative_transfer_tables, rows_ptr);
    }

    fn ownsResult(self: *const Context, result: *const zdisamar.Output) bool {
        for (self.results.items) |stored| {
            if (stored == result) return true;
        }
        return false;
    }

    fn clearPrepared(self: *Context) void {
        if (self.prepared) |*prepared| prepared.deinit(allocator);
        self.prepared = null;
        if (self.parsed_input) |*parsed| parsed.deinit();
        self.parsed_input = null;
    }

    fn setError(self: *Context, message: []const u8) void {
        @memset(self.last_error[0..], 0);
        const n = @min(message.len, self.last_error.len - 1);
        @memcpy(self.last_error[0..n], message[0..n]);
    }
};

// PreparedWavelengthRequest ----------------------------------------------------------------------------------|
// Zig-only checked view of a prepared context plus caller-provided wavelength slice.                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] prepared    : *PreparedO2A                                                                         |
// [ 8..23] wavelengths : []const f64                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   prepared lives in Context; wavelengths borrows the caller buffer.                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B (0.023 KiB); stack-local request view                                        |
const PreparedWavelengthRequest = struct {
    prepared: *zdisamar.PreparedO2A,
    wavelengths: []const f64,
};

fn clearStoredRows(comptime Row: type, list: *std.ArrayList([]Row)) void {
    for (list.items) |rows| allocator.free(rows);
    list.clearAndFree(allocator);
}

fn removeStoredRows(comptime Row: type, list: *std.ArrayList([]Row), rows_ptr: [*]const Row) ?[]Row {
    for (list.items, 0..) |stored, index| {
        if (stored.ptr == rows_ptr) {
            return list.swapRemove(index);
        }
    }
    return null;
}

fn checkedWavelengthRequest(
    resolved: *Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
) ?PreparedWavelengthRequest {
    const wavelengths = wavelengths_ptr orelse {
        resolved.setError("null wavelengths");

        return null;
    };
    if (wavelength_count == 0) {
        resolved.setError("empty wavelengths");
        return null;
    }
    if (resolved.prepared == null) {
        resolved.setError("not prepared");

        return null;
    }
    return .{
        .prepared = &resolved.prepared.?,
        .wavelengths = wavelengths[0..wavelength_count],
    };
}

fn storeCopiedRows(
    comptime NativeRow: type,
    comptime ApiRow: type,
    resolved: *Context,
    list: *std.ArrayList([]ApiRow),
    native_rows: []const NativeRow,
    comptime copyRow: fn (NativeRow) ApiRow,
) ?[]ApiRow {
    const rows = allocator.alloc(ApiRow, native_rows.len) catch |err| {
        resolved.setError(@errorName(err));
        return null;
    };
    errdefer allocator.free(rows);
    for (native_rows, rows) |native, *row| row.* = copyRow(native);

    list.append(allocator, rows) catch |err| {
        allocator.free(rows);
        resolved.setError(@errorName(err));
        return null;
    };
    return rows;
}

export fn zds_context_create() ?*Context {
    const ctx = allocator.create(Context) catch return null;
    ctx.* = .{};
    return ctx;
}

export fn zds_context_destroy(ctx: ?*Context) void {
    const resolved = ctx orelse return;
    resolved.clearResults();
    resolved.clearOptimalEstimationResults();
    resolved.clearOptimalEstimationBatchResults();
    resolved.clearOptimalEstimationFastmodeBatchResults();
    resolved.clearAtmosphericBudgets();
    resolved.clearO2LineContributionTables();
    resolved.clearInstrumentResponseTables();
    resolved.clearO2O2CIATables();
    resolved.clearRadiativeTransferTables();
    resolved.clearPrepared();
    resolved.o2a_session_storage.deinit(allocator);
    allocator.destroy(resolved);
}

export fn zds_prepare_default_o2a(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    resolved.clearPrepared();
    const input = zdisamar.defaultO2AInput();
    resolved.prepared = zdisamar.prepareO2A(allocator, &input) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_prepare_o2a_json(ctx: ?*Context, json_ptr: ?[*]const u8, json_len: usize) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const ptr = json_ptr orelse {
        resolved.setError("null input JSON");
        return @intFromEnum(ZdsStatus.failure);
    };
    if (json_len == 0) {
        resolved.setError("empty input JSON");
        return @intFromEnum(ZdsStatus.failure);
    }

    var parsed = zdisamar.parseO2AInputJson(allocator, ptr[0..json_len]) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer parsed.deinit();

    var prepared = zdisamar.prepareO2A(allocator, &parsed.value) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    errdefer prepared.deinit(allocator);

    resolved.clearPrepared();
    resolved.parsed_input = parsed;
    resolved.prepared = prepared;
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_warm_o2a_session(ctx: ?*Context) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }
    zdisamar.warmO2ASessionStorage(
        allocator,
        &resolved.o2a_session_storage,
        &resolved.prepared.?,
    ) catch |err| {
        resolved.setError(@errorName(err));

        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_warm_o2a_optimal_estimation(
    ctx: ?*Context,
    state_ids: ?[*]const u8,
    requested_state_count: usize,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const loaded_prepared = resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    };

    const state_slice = if (state_ids) |ids| ids[0..requested_state_count] else &.{};
    const selection = jacobianStateSelection(state_slice) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    var prepared = loaded_prepared;
    prepared.rtm_config.derivative_mode = .semi_analytical;
    prepared.rtm_config.derivative_state_mask = selection.mask;

    zdisamar.warmO2ASessionStorage(
        allocator,
        &resolved.o2a_session_storage,
        &prepared,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_default_o2a_input_json(ctx: ?*Context, out: ?[*]u8, capacity: usize, out_len: ?*usize) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const json = zdisamar.renderDefaultO2AInputJson(allocator) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(json);

    if (out_len) |slot| slot.* = json.len;
    if (out) |buffer| {
        if (capacity < json.len + 1) {
            resolved.setError("buffer too small");
            return @intFromEnum(ZdsStatus.failure);
        }
        @memcpy(buffer[0..json.len], json);
        buffer[json.len] = 0;
    }
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const output = out orelse return @intFromEnum(ZdsStatus.failure);
    if (resolved.prepared == null) {
        resolved.setError("not prepared");

        return @intFromEnum(ZdsStatus.failure);
    }
    const prepared = &resolved.prepared.?;
    const result = allocator.create(zdisamar.Output) catch |err| {
        resolved.setError(@errorName(err));

        return @intFromEnum(ZdsStatus.failure);
    };

    result.* = zdisamar.runO2AWithSessionStorage(allocator, &resolved.o2a_session_storage, prepared) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);

        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .jacobian = null,
        .jacobian_state_count = 0,
        .result_handle = @ptrCast(result),
    };

    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_spectrum_jacobian(ctx: ?*Context, out: ?*ZdsSpectrum) c_int {
    return runSpectrumJacobianForStateIds(ctx, out, null, 0);
}

export fn zds_run_spectrum_jacobian_for_states(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    state_count: usize,
) c_int {
    if (state_count != 0 and state_ids == null) return @intFromEnum(ZdsStatus.failure);
    return runSpectrumJacobianForStateIds(ctx, out, state_ids, state_count);
}

// OptimalEstimationMeasurementSlices -------------------------------------------------------------------------|
// Zig-only checked view of caller-owned measurement arrays. Never passed across the C boundary.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm : []const f64                                                                        |
// [16..31] reflectance   : []const f64                                                                        |
// [32..47] variance      : []const f64                                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   all slices borrow caller-owned C buffers after null and length validation.                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B (0.047 KiB); stack-local request view                                        |
const OptimalEstimationMeasurementSlices = struct {
    wavelength_nm: []const f64,
    reflectance: []const f64,
    variance: []const f64,
};

// OptimalEstimationStateSpecs --------------------------------------------------------------------------------|
// Zig-only normalized state specs plus request-scoped pressure-profile spline scratch.                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 464 B (0.453 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..143] profiles    : [max_state_count]PressureAltitudeProfile                                           |
// [144..455] state_specs : [max_state_count]StateSpec                                                         |
// [456..463] state_count : usize                                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   pressure-profile second-derivative arrays are owned until the C call returns and deinit frees them.       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 8 cache lines at 64 B per line                                                                  |
// footprint: per instance = 464 B (0.453 KiB); total also includes pressure-profile spline storage            |
const OptimalEstimationStateSpecs = struct {
    profiles: [zdisamar.optimal_estimation.max_state_count]zdisamar.optimal_estimation.PressureAltitudeProfile =
        [_]zdisamar.optimal_estimation.PressureAltitudeProfile{.{}} ** zdisamar.optimal_estimation.max_state_count,
    state_specs: [zdisamar.optimal_estimation.max_state_count]zdisamar.optimal_estimation.StateSpec = undefined,
    state_count: usize = 0,

    fn deinit(self: *OptimalEstimationStateSpecs) void {
        for (&self.profiles) |*profile| {
            if (profile.hasSamples()) {
                zdisamar.optimal_estimation.freePressureProfile(allocator, profile.*);
                profile.* = .{};
            }
        }
    }

    fn slice(self: *const OptimalEstimationStateSpecs) []const zdisamar.optimal_estimation.StateSpec {
        return self.state_specs[0..self.state_count];
    }
};

fn optimalEstimationMeasurementSlices(
    resolved: *Context,
    request: anytype,
) ?OptimalEstimationMeasurementSlices {
    const wavelengths_ptr = request.wavelength_nm orelse {
        resolved.setError("null measurement wavelengths");

        return null;
    };
    const reflectance_ptr = request.reflectance orelse {
        resolved.setError("null measurement reflectance");
        return null;
    };

    const variance_ptr = request.variance orelse {
        resolved.setError("null measurement variance");
        return null;
    };
    if (request.sample_count == 0) {
        resolved.setError("empty measurement");

        return null;
    }
    return .{
        .wavelength_nm = wavelengths_ptr[0..request.sample_count],
        .reflectance = reflectance_ptr[0..request.sample_count],
        .variance = variance_ptr[0..request.sample_count],
    };
}

fn optimalEstimationControls(
    resolved: *Context,
    request: anytype,
) ?zdisamar.optimal_estimation.Controls {
    if (request.controls.max_iterations == 0 or
        request.controls.max_iterations > zdisamar.optimal_estimation.max_iteration_count)
    {
        resolved.setError("invalid optimal-estimation max_iterations");
        return null;
    }
    return .{
        .max_iterations = request.controls.max_iterations,
        .state_vector_convergence_threshold = request.controls.state_vector_convergence_threshold,
        .max_change_transformed_state = request.controls.max_change_transformed_state,
    };
}

fn optimalEstimationStateSpecs(
    resolved: *Context,
    request: *const ZdsOptimalEstimationRequest,
) !OptimalEstimationStateSpecs {
    const state_specs_ptr = request.states orelse {
        resolved.setError("null state specs");
        return error.InvalidStateSpec;
    };
    return optimalEstimationStateSpecsFromRaw(resolved, request.state_count, state_specs_ptr);
}

fn optimalEstimationStateSpecsFromRaw(
    resolved: *Context,
    state_count: usize,
    state_specs_ptr: [*]const ZdsOptimalEstimationStateSpec,
) !OptimalEstimationStateSpecs {
    if (state_count == 0 or state_count > zdisamar.optimal_estimation.max_state_count) {
        resolved.setError("invalid state count");
        return error.InvalidStateCount;
    }

    var parsed: OptimalEstimationStateSpecs = .{ .state_count = state_count };
    errdefer parsed.deinit();

    const raw_states = state_specs_ptr[0..state_count];
    for (raw_states, 0..) |raw, index| {
        const state = std.meta.intToEnum(zdisamar.RadiativeTransferJacobian.State, raw.state_id) catch |err| {
            resolved.setError(@errorName(err));
            return err;
        };

        if (state == .aerosol_layer_mid_pressure_hpa) {
            const altitude_ptr = raw.pressure_profile_altitude_km orelse {
                resolved.setError("missing pressure profile altitude");
                return error.InvalidPressureProfile;
            };
            const pressure_ptr = raw.pressure_profile_pressure_hpa orelse {
                resolved.setError("missing pressure profile pressure");

                return error.InvalidPressureProfile;
            };
            parsed.profiles[index] = zdisamar.optimal_estimation.buildPressureProfile(
                allocator,
                altitude_ptr[0..raw.pressure_profile_count],
                pressure_ptr[0..raw.pressure_profile_count],
            ) catch |err| {
                resolved.setError(@errorName(err));

                return err;
            };
        }
        if (raw.has_lower != 0 and !std.math.isFinite(raw.lower)) {
            resolved.setError("invalid optimal-estimation lower bound");

            return error.InvalidStateSpec;
        }
        if (raw.has_upper != 0 and !std.math.isFinite(raw.upper)) {
            resolved.setError("invalid optimal-estimation upper bound");

            return error.InvalidStateSpec;
        }
        const lower_bound = if (raw.has_lower != 0) raw.lower else zdisamar.optimal_estimation.no_lower_bound;
        const upper_bound = if (raw.has_upper != 0) raw.upper else zdisamar.optimal_estimation.no_upper_bound;

        parsed.state_specs[index] = .{
            .state = state,
            .initial = raw.initial,
            .prior = raw.prior,
            .variance = raw.variance,
            .lower_bound = lower_bound,
            .upper_bound = upper_bound,
            .thickness_hpa = raw.thickness_hpa,
            .interval_index_1based = raw.interval_index_1based,
            .pressure_altitude_profile = parsed.profiles[index],
        };
    }
    return parsed;
}

export fn zds_run_o2a_optimal_estimation(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationRequest,
    out: ?*ZdsOptimalEstimationResult,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation request");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_out = out orelse {
        resolved.setError("null optimal-estimation result");

        return @intFromEnum(ZdsStatus.failure);
    };
    var default_input: zdisamar.O2AInput = undefined;
    const input = choose_input: {
        if (resolved.parsed_input) |*parsed| {
            break :choose_input &parsed.value;
        }
        if (resolved.prepared == null) {
            resolved.setError("not prepared");

            return @intFromEnum(ZdsStatus.failure);
        }
        default_input = zdisamar.defaultO2AInput();
        break :choose_input &default_input;
    };
    zdisamar.o2a.requireRetrievalCompatibleAerosol(input) catch {
        resolved.setError("multi-layer aerosol profiles are forward-simulation only");

        return @intFromEnum(ZdsStatus.failure);
    };
    const measurement = optimalEstimationMeasurementSlices(
        resolved,

        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    const controls = optimalEstimationControls(
        resolved,

        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    var state_specs = optimalEstimationStateSpecs(
        resolved,

        resolved_request,
    ) catch return @intFromEnum(ZdsStatus.failure);
    defer state_specs.deinit();

    const native = allocator.create(zdisamar.optimal_estimation.Result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    native.* = zdisamar.optimal_estimation.runO2A(
        allocator,
        input,
        measurement.wavelength_nm,
        measurement.reflectance,
        measurement.variance,
        state_specs.slice(),
        &resolved.o2a_session_storage,
        controls,
    ) catch |err| {
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.oe_results.append(allocator, native) catch |err| {
        native.deinit(allocator);
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved_out.* = optimalEstimationResultView(native);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_o2a_optimal_estimation_batch(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationBatchRequest,
    out: ?*ZdsOptimalEstimationBatchResult,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation batch request");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_out = out orelse {
        resolved.setError("null optimal-estimation batch result");

        return @intFromEnum(ZdsStatus.failure);
    };
    var default_input: zdisamar.O2AInput = undefined;
    const input = choose_input: {
        if (resolved.parsed_input) |*parsed| {
            break :choose_input &parsed.value;
        }
        if (resolved.prepared == null) {
            resolved.setError("not prepared");

            return @intFromEnum(ZdsStatus.failure);
        }
        default_input = zdisamar.defaultO2AInput();
        break :choose_input &default_input;
    };
    zdisamar.o2a.requireRetrievalCompatibleAerosol(input) catch {
        resolved.setError("multi-layer aerosol profiles are forward-simulation only");

        return @intFromEnum(ZdsStatus.failure);
    };
    const measurement = optimalEstimationMeasurementSlices(
        resolved,
        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    const controls = optimalEstimationControls(
        resolved,
        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    const state_template_ptr = resolved_request.state_template orelse {
        resolved.setError("null state template");

        return @intFromEnum(ZdsStatus.failure);
    };
    const run_count = resolved_request.run_count;
    const state_count = resolved_request.state_count;
    if (run_count == 0) {
        resolved.setError("empty optimal-estimation batch");

        return @intFromEnum(ZdsStatus.failure);
    }
    const batch_worker_count = resolved_request.batch_worker_count;
    if (batch_worker_count == 0) {
        resolved.setError("invalid optimal-estimation batch_worker_count");
        return @intFromEnum(ZdsStatus.failure);
    }
    const total_state_count = std.math.mul(usize, run_count, state_count) catch {
        resolved.setError("optimal-estimation batch is too large");
        return @intFromEnum(ZdsStatus.failure);
    };
    const initial_ptr = resolved_request.initial orelse {
        resolved.setError("null batch initial states");

        return @intFromEnum(ZdsStatus.failure);
    };
    const prior_ptr = resolved_request.prior orelse {
        resolved.setError("null batch prior states");
        return @intFromEnum(ZdsStatus.failure);
    };

    var state_template = optimalEstimationStateSpecsFromRaw(
        resolved,
        state_count,
        state_template_ptr,
    ) catch return @intFromEnum(ZdsStatus.failure);
    defer state_template.deinit();

    const native = allocator.create(zdisamar.optimal_estimation.BatchResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    native.* = zdisamar.optimal_estimation.runO2ABatch(
        allocator,
        input,
        measurement.wavelength_nm,
        measurement.reflectance,
        measurement.variance,
        state_template.slice(),
        initial_ptr[0..total_state_count],
        prior_ptr[0..total_state_count],
        &resolved.o2a_session_storage,
        controls,
        batch_worker_count,
    ) catch |err| {
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.oe_batch_results.append(allocator, native) catch |err| {
        native.deinit(allocator);
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved_out.* = optimalEstimationBatchResultView(native);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_o2a_fastmode_optimal_estimation_batch(
    fast_ctx: ?*Context,
    correction_ctx: ?*Context,
    fast_request: ?*const ZdsOptimalEstimationBatchRequest,
    correction_request: ?*const ZdsOptimalEstimationBatchRequest,
    out: ?*ZdsOptimalEstimationFastmodeBatchResult,
) c_int {
    const resolved = fast_ctx orelse return @intFromEnum(ZdsStatus.failure);

    const correction_resolved = correction_ctx orelse {
        resolved.setError("null correction context");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_fast_request = fast_request orelse {
        resolved.setError("null fastmode batch request");

        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_correction_request = correction_request orelse {
        resolved.setError("null fastmode correction batch request");
        return @intFromEnum(ZdsStatus.failure);
    };

    const resolved_out = out orelse {
        resolved.setError("null fastmode batch result");
        return @intFromEnum(ZdsStatus.failure);
    };

    var default_fast_input: zdisamar.O2AInput = undefined;
    const fast_input = choose_fast_input: {
        if (resolved.parsed_input) |*parsed| {
            break :choose_fast_input &parsed.value;
        }
        if (resolved.prepared == null) {
            resolved.setError("fast context not prepared");

            return @intFromEnum(ZdsStatus.failure);
        }
        default_fast_input = zdisamar.defaultO2AInput();
        break :choose_fast_input &default_fast_input;
    };
    var default_correction_input: zdisamar.O2AInput = undefined;

    const correction_input = choose_correction_input: {
        if (correction_resolved.parsed_input) |*parsed| {
            break :choose_correction_input &parsed.value;
        }
        if (correction_resolved.prepared == null) {
            resolved.setError("correction context not prepared");
            return @intFromEnum(ZdsStatus.failure);
        }
        default_correction_input = zdisamar.defaultO2AInput();
        break :choose_correction_input &default_correction_input;
    };
    zdisamar.o2a.requireRetrievalCompatibleAerosol(fast_input) catch {
        resolved.setError("multi-layer aerosol profiles are forward-simulation only");

        return @intFromEnum(ZdsStatus.failure);
    };
    zdisamar.o2a.requireRetrievalCompatibleAerosol(correction_input) catch {
        resolved.setError("multi-layer aerosol profiles are forward-simulation only");
        return @intFromEnum(ZdsStatus.failure);
    };

    const fast_measurement = optimalEstimationMeasurementSlices(
        resolved,
        resolved_fast_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    const correction_measurement = optimalEstimationMeasurementSlices(
        correction_resolved,
        resolved_correction_request,
    ) orelse {
        resolved.setError("invalid fastmode correction measurement");
        return @intFromEnum(ZdsStatus.failure);
    };
    const fast_controls = optimalEstimationControls(
        resolved,
        resolved_fast_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);

    const correction_controls = optimalEstimationControls(correction_resolved, resolved_correction_request) orelse {
        resolved.setError("invalid fastmode correction controls");
        return @intFromEnum(ZdsStatus.failure);
    };
    const fast_template_ptr = resolved_fast_request.state_template orelse {
        resolved.setError("null fast state template");

        return @intFromEnum(ZdsStatus.failure);
    };
    const correction_template_ptr = resolved_correction_request.state_template orelse {
        resolved.setError("null correction state template");
        return @intFromEnum(ZdsStatus.failure);
    };

    const run_count = resolved_fast_request.run_count;
    const state_count = resolved_fast_request.state_count;
    if (run_count == 0 or resolved_correction_request.run_count != run_count) {
        resolved.setError("invalid fastmode batch run count");
        return @intFromEnum(ZdsStatus.failure);
    }
    if (state_count == 0 or resolved_correction_request.state_count != state_count) {
        resolved.setError("invalid fastmode batch state count");

        return @intFromEnum(ZdsStatus.failure);
    }
    const batch_worker_count = resolved_fast_request.batch_worker_count;
    if (batch_worker_count == 0) {
        resolved.setError("invalid fastmode batch_worker_count");
        return @intFromEnum(ZdsStatus.failure);
    }
    const total_state_count = std.math.mul(usize, run_count, state_count) catch {
        resolved.setError("fastmode batch is too large");
        return @intFromEnum(ZdsStatus.failure);
    };
    const initial_ptr = resolved_fast_request.initial orelse {
        resolved.setError("null fastmode batch initial states");

        return @intFromEnum(ZdsStatus.failure);
    };
    const prior_ptr = resolved_fast_request.prior orelse {
        resolved.setError("null fastmode batch prior states");
        return @intFromEnum(ZdsStatus.failure);
    };

    const correction_prior_ptr = resolved_correction_request.prior orelse {
        resolved.setError("null fastmode correction prior states");
        return @intFromEnum(ZdsStatus.failure);
    };

    var fast_state_template = optimalEstimationStateSpecsFromRaw(
        resolved,
        state_count,
        fast_template_ptr,
    ) catch return @intFromEnum(ZdsStatus.failure);
    defer fast_state_template.deinit();
    var correction_state_template = optimalEstimationStateSpecsFromRaw(
        correction_resolved,
        state_count,
        correction_template_ptr,
    ) catch {
        resolved.setError("invalid fastmode correction state template");
        return @intFromEnum(ZdsStatus.failure);
    };
    defer correction_state_template.deinit();

    const native = allocator.create(zdisamar.optimal_estimation.FastmodeBatchResult) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    native.* = zdisamar.optimal_estimation.runO2AFastmodeBatch(
        allocator,
        fast_input,
        fast_measurement.wavelength_nm,
        fast_measurement.reflectance,
        fast_measurement.variance,
        fast_state_template.slice(),
        initial_ptr[0..total_state_count],
        prior_ptr[0..total_state_count],
        &resolved.o2a_session_storage,
        fast_controls,
        correction_input,
        correction_measurement.wavelength_nm,
        correction_measurement.reflectance,
        correction_measurement.variance,
        correction_state_template.slice(),
        correction_prior_ptr[0..total_state_count],
        &correction_resolved.o2a_session_storage,
        correction_controls,
        batch_worker_count,
    ) catch |err| {
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.oe_fastmode_batch_results.append(allocator, native) catch |err| {
        native.deinit(allocator);
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved_out.* = optimalEstimationFastmodeBatchResultView(native);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_run_o2a_optimal_estimation_correction(
    ctx: ?*Context,
    request: ?*const ZdsOptimalEstimationRequest,
    out: ?*ZdsOptimalEstimationResult,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const resolved_request = request orelse {
        resolved.setError("null optimal-estimation request");
        return @intFromEnum(ZdsStatus.failure);
    };
    const resolved_out = out orelse {
        resolved.setError("null optimal-estimation result");

        return @intFromEnum(ZdsStatus.failure);
    };
    const loaded_prepared = resolved.prepared orelse {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    };

    if (resolved.parsed_input) |*parsed| {
        zdisamar.o2a.requireRetrievalCompatibleAerosol(&parsed.value) catch {
            resolved.setError("multi-layer aerosol profiles are forward-simulation only");
            return @intFromEnum(ZdsStatus.failure);
        };
    }
    const measurement = optimalEstimationMeasurementSlices(
        resolved,
        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);

    const controls = optimalEstimationControls(
        resolved,
        resolved_request,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    var state_specs = optimalEstimationStateSpecs(
        resolved,
        resolved_request,
    ) catch return @intFromEnum(ZdsStatus.failure);
    defer state_specs.deinit();

    const native = allocator.create(zdisamar.optimal_estimation.Result) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    native.* = zdisamar.optimal_estimation.correctPreparedO2A(
        allocator,
        &loaded_prepared,
        measurement.wavelength_nm,
        measurement.reflectance,
        measurement.variance,
        state_specs.slice(),
        &resolved.o2a_session_storage,
        controls,
    ) catch |err| {
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    resolved.oe_results.append(allocator, native) catch |err| {
        native.deinit(allocator);
        allocator.destroy(native);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved_out.* = optimalEstimationResultView(native);
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

fn runSpectrumJacobianForStateIds(
    ctx: ?*Context,
    out: ?*ZdsSpectrum,
    state_ids: ?[*]const u8,
    requested_state_count: usize,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const output = out orelse return @intFromEnum(ZdsStatus.failure);

    if (resolved.prepared == null) {
        resolved.setError("not prepared");
        return @intFromEnum(ZdsStatus.failure);
    }

    const state_slice = if (state_ids) |ids| ids[0..requested_state_count] else &.{};
    const selection = jacobianStateSelection(state_slice) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    var prepared = resolved.prepared.?;
    prepared.rtm_config.derivative_mode = .semi_analytical;
    prepared.rtm_config.derivative_state_mask = selection.mask;

    const result = allocator.create(zdisamar.Output) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    result.* = (if (selection.count == 0)
        zdisamar.runO2AWithSessionStorage(allocator, &resolved.o2a_session_storage, &prepared)
    else
        zdisamar.o2a.runO2AWithSessionStorageJacobianStates(
            allocator,
            &resolved.o2a_session_storage,
            &prepared,
            selection.slice(),
        )) catch |err| {
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    resolved.results.append(allocator, result) catch |err| {
        result.deinit(allocator);
        allocator.destroy(result);
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    const output_state_count = if (selection.count == 0)
        zdisamar.RadiativeTransferJacobian.state_count
    else
        selection.count;

    output.* = .{
        .len = result.wavelengths.len,
        .wavelength_nm = result.wavelengths.ptr,
        .radiance = result.radiance.ptr,
        .irradiance = result.irradiance.ptr,
        .reflectance = result.reflectance.ptr,
        .jacobian = if (result.jacobian) |values| values.ptr else null,
        .jacobian_state_count = output_state_count,
        .result_handle = @ptrCast(result),
    };

    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_report(ctx: ?*Context, spectrum: ?*const ZdsSpectrum, out: ?*ZdsDiagnosticReport) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_spectrum = spectrum orelse {
        resolved.setError("null spectrum");
        return @intFromEnum(ZdsStatus.failure);
    };

    const resolved_out = out orelse {
        resolved.setError("null diagnostic report");
        return @intFromEnum(ZdsStatus.failure);
    };
    const handle = resolved_spectrum.result_handle orelse {
        resolved.setError("spectrum is closed");

        return @intFromEnum(ZdsStatus.failure);
    };
    const result: *zdisamar.Output = @ptrCast(@alignCast(handle));
    if (!resolved.ownsResult(result)) {
        resolved.setError("unknown spectrum result");
        return @intFromEnum(ZdsStatus.failure);
    }

    const report = zdisamar.report.summaryReportFromProduct(result);
    resolved_out.* = .{
        .sample_count = report.sample_count,
        .wavelength_start_nm = report.wavelength_start_nm,
        .wavelength_end_nm = report.wavelength_end_nm,
        .mean_radiance = report.mean_radiance,
        .mean_irradiance = report.mean_irradiance,
        .mean_reflectance = report.mean_reflectance,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_atmospheric_budget(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsAtmosphericBudget,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null atmospheric budget");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildAtmosphericBudget(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.AtmosphericBudgetRow,
        ZdsAtmosphericBudgetRow,
        resolved,
        &resolved.atmospheric_budgets,
        native_rows,
        copyAtmosphericBudgetRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_o2_line_contributions(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    max_rows: usize,
    out: ?*ZdsO2LineContributions,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const resolved_out = out orelse {
        resolved.setError("null O2 line contribution table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    if (max_rows == 0) {
        resolved.setError("invalid row limit");
        return @intFromEnum(ZdsStatus.failure);
    }

    var native_table = zdisamar.buildO2LineContributions(
        allocator,
        &request.prepared.prepared,
        request.wavelengths,
        max_rows,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer native_table.deinit(allocator);

    const rows = storeCopiedRows(
        zdisamar.O2LineContributionRow,
        ZdsO2LineContributionRow,
        resolved,
        &resolved.o2_line_contribution_tables,
        native_table.rows,
        copyO2LineContributionRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);

    resolved_out.* = .{
        .len = rows.len,
        .total_row_count = native_table.total_row_count,
        .truncated = if (native_table.truncated) 1 else 0,
        .rows = rows.ptr,
    };

    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_instrument_response_sampling(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    channel_mask: u32,
    out: ?*ZdsInstrumentResponse,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null instrument response table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildInstrumentResponse(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
        channel_mask,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.InstrumentResponseRow,
        ZdsInstrumentResponseRow,
        resolved,
        &resolved.instrument_response_tables,
        native_rows,
        copyInstrumentResponseRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_o2_o2_cia_diagnostics(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    out: ?*ZdsO2O2CIADiagnostics,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);
    const resolved_out = out orelse {
        resolved.setError("null O2-O2 CIA table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const native_rows = zdisamar.buildO2O2CIADiagnostics(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.wavelengths,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.O2O2CIARow,
        ZdsO2O2CIARow,
        resolved,
        &resolved.o2_o2_cia_tables,
        native_rows,
        copyO2O2CIARow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_radiative_transfer_diagnostics(
    ctx: ?*Context,
    wavelengths_ptr: ?[*]const f64,
    wavelength_count: usize,
    spectrum: ?*const ZdsSpectrum,
    out: ?*ZdsRadiativeTransferDiagnostics,
) c_int {
    const resolved = ctx orelse return @intFromEnum(ZdsStatus.failure);

    const resolved_out = out orelse {
        resolved.setError("null radiative-transfer table");
        return @intFromEnum(ZdsStatus.failure);
    };
    const request = checkedWavelengthRequest(resolved, wavelengths_ptr, wavelength_count) orelse
        return @intFromEnum(ZdsStatus.failure);

    const spectrum_view = spectrumView(resolved, spectrum) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };

    const native_rows = zdisamar.buildRadiativeTransferDiagnostics(
        allocator,
        &request.prepared.scene,
        &request.prepared.prepared,
        request.prepared.rtm_config,
        request.wavelengths,
        spectrum_view,
    ) catch |err| {
        resolved.setError(@errorName(err));
        return @intFromEnum(ZdsStatus.failure);
    };
    defer allocator.free(native_rows);

    const rows = storeCopiedRows(
        zdisamar.RadiativeTransferDiagnosticRow,
        ZdsRadiativeTransferDiagnosticRow,
        resolved,
        &resolved.radiative_transfer_tables,
        native_rows,
        copyRadiativeTransferDiagnosticRow,
    ) orelse return @intFromEnum(ZdsStatus.failure);
    resolved_out.* = .{
        .len = rows.len,
        .rows = rows.ptr,
    };
    resolved.setError("");
    return @intFromEnum(ZdsStatus.ok);
}

export fn zds_spectrum_free(ctx: ?*Context, out: ?*ZdsSpectrum) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.Output = @ptrCast(@alignCast(handle));
        if (resolved.removeResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_optimal_estimation_result_free(ctx: ?*Context, out: ?*ZdsOptimalEstimationResult) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.optimal_estimation.Result = @ptrCast(@alignCast(handle));
        if (resolved.removeOptimalEstimationResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_optimal_estimation_batch_result_free(ctx: ?*Context, out: ?*ZdsOptimalEstimationBatchResult) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.optimal_estimation.BatchResult = @ptrCast(@alignCast(handle));
        if (resolved.removeOptimalEstimationBatchResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_optimal_estimation_fastmode_batch_result_free(
    ctx: ?*Context,
    out: ?*ZdsOptimalEstimationFastmodeBatchResult,
) void {
    const resolved = ctx orelse return;
    const output = out orelse return;
    if (output.result_handle) |handle| {
        const result: *zdisamar.optimal_estimation.FastmodeBatchResult = @ptrCast(@alignCast(handle));
        if (resolved.removeOptimalEstimationFastmodeBatchResult(result)) {
            result.deinit(allocator);
            allocator.destroy(result);
        }
    }
    output.* = .{};
}

export fn zds_atmospheric_budget_free(ctx: ?*Context, out: ?*ZdsAtmosphericBudget) void {
    const resolved = ctx orelse return;
    const budget = out orelse return;
    if (budget.len != 0) {
        if (resolved.removeAtmosphericBudget(budget.rows)) |rows| allocator.free(rows);
    }
    budget.* = .{};
}

export fn zds_o2_line_contributions_free(ctx: ?*Context, out: ?*ZdsO2LineContributions) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeO2LineContributionTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_instrument_response_free(ctx: ?*Context, out: ?*ZdsInstrumentResponse) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeInstrumentResponseTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_o2_o2_cia_diagnostics_free(ctx: ?*Context, out: ?*ZdsO2O2CIADiagnostics) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeO2O2CIATable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_radiative_transfer_diagnostics_free(ctx: ?*Context, out: ?*ZdsRadiativeTransferDiagnostics) void {
    const resolved = ctx orelse return;
    const table = out orelse return;
    if (table.len != 0) {
        if (resolved.removeRadiativeTransferTable(table.rows)) |rows| allocator.free(rows);
    }
    table.* = .{};
}

export fn zds_last_error(ctx: ?*Context) [*:0]const u8 {
    const resolved = ctx orelse return "null context";
    return @ptrCast(&resolved.last_error);
}

fn spectrumView(resolved: *const Context, spectrum: ?*const ZdsSpectrum) !?zdisamar.RadiativeTransferSpectrumView {
    const raw = spectrum orelse return null;
    const handle = raw.result_handle orelse return error.SpectrumClosed;
    const result: *zdisamar.Output = @ptrCast(@alignCast(handle));

    if (!resolved.ownsResult(result)) return error.UnknownSpectrumResult;
    return .{
        .wavelength_nm = raw.wavelength_nm[0..raw.len],
        .reflectance = raw.reflectance[0..raw.len],

        .radiance = raw.radiance[0..raw.len],
    };
}

fn optimalEstimationResultView(native: *zdisamar.optimal_estimation.Result) ZdsOptimalEstimationResult {
    const converged: u8 = if (native.converged) 1 else 0;

    return .{
        .state_count = @intCast(native.state_count),
        .iteration_count = @intCast(native.iteration_count),
        .converged = converged,
        .state_ids = @ptrCast(native.state_ids.ptr),
        .state = native.state.ptr,
        .initial_state = native.initial_state.ptr,
        .posterior_covariance = native.posterior_covariance.ptr,
        .averaging_kernel = native.averaging_kernel.ptr,
        .history_state = native.history_state.ptr,
        .history_chi2 = native.history_chi2.ptr,
        .history_chi2_reflectance = native.history_chi2_reflectance.ptr,
        .history_chi2_state_vector = native.history_chi2_state_vector.ptr,
        .history_state_vector_convergence = native.history_state_vector_convergence.ptr,
        .history_snr_normal = native.history_snr_normal.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn optimalEstimationBatchResultView(native: *zdisamar.optimal_estimation.BatchResult) ZdsOptimalEstimationBatchResult {
    return .{
        .run_count = native.run_count,
        .state_count = native.state_count,
        .history_capacity = native.history_capacity,
        .iteration_count = native.iteration_count.ptr,
        .converged = native.converged.ptr,
        .status = native.status.ptr,
        .state = native.state.ptr,
        .history_state = native.history_state.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn optimalEstimationFastmodeBatchResultView(
    native: *zdisamar.optimal_estimation.FastmodeBatchResult,
) ZdsOptimalEstimationFastmodeBatchResult {
    return .{
        .run_count = native.run_count,
        .state_count = native.state_count,
        .history_capacity = native.history_capacity,
        .iteration_count = native.iteration_count.ptr,
        .converged = native.converged.ptr,
        .status = native.status.ptr,
        .state = native.state.ptr,
        .history_state = native.history_state.ptr,
        .fast_stage_iteration_count = native.fast_stage_iteration_count.ptr,
        .fast_stage_converged = native.fast_stage_converged.ptr,
        .full_correction_iteration_count = native.full_correction_iteration_count.ptr,
        .full_correction_converged = native.full_correction_converged.ptr,
        .result_handle = @ptrCast(native),
    };
}

fn copyAtmosphericBudgetRow(row: zdisamar.AtmosphericBudgetRow) ZdsAtmosphericBudgetRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .support_row_kind = @intFromEnum(row.support_row_kind),
        .altitude_km = row.altitude_km,
        .top_altitude_km = row.top_altitude_km,
        .bottom_altitude_km = row.bottom_altitude_km,
        .pressure_hpa = row.pressure_hpa,
        .top_pressure_hpa = row.top_pressure_hpa,
        .bottom_pressure_hpa = row.bottom_pressure_hpa,
        .temperature_k = row.temperature_k,
        .number_density_cm3 = row.number_density_cm3,
        .oxygen_number_density_cm3 = row.oxygen_number_density_cm3,
        .absorber_number_density_cm3 = row.absorber_number_density_cm3,
        .path_length_cm = row.path_length_cm,
        .aerosol_fraction = row.aerosol_fraction,
        .gas_absorption_optical_depth = row.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = row.gas_scattering_optical_depth,
        .cia_optical_depth = row.cia_optical_depth,
        .aerosol_optical_depth = row.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = row.aerosol_scattering_optical_depth,
        .aerosol_absorption_optical_depth = row.aerosol_absorption_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_scattering_optical_depth = row.total_scattering_optical_depth,
        .total_optical_depth = row.total_optical_depth,
        .single_scatter_albedo = row.single_scatter_albedo,
    };
}

fn copyO2LineContributionRow(row: zdisamar.O2LineContributionRow) ZdsO2LineContributionRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .profile_node_index = row.profile_node_index,
        .altitude_km = row.altitude_km,
        .row_kind = @intFromEnum(row.row_kind),
        .status = @intFromEnum(row.status),
        .line_index = row.line_index,
        .strong_line_index = row.strong_line_index,
        .matched_strong_line_index = row.matched_strong_line_index,
        .gas_index = row.gas_index,
        .isotope_number = row.isotope_number,
        .isotopologue_code = row.isotopologue_code,
        .center_wavelength_nm = row.center_wavelength_nm,
        .center_wavenumber_cm1 = row.center_wavenumber_cm1,
        .shifted_center_wavenumber_cm1 = row.shifted_center_wavenumber_cm1,
        .line_strength_cm2_per_molecule = row.line_strength_cm2_per_molecule,
        .air_half_width_cm1 = row.air_half_width_cm1,
        .pressure_shift_cm1 = row.pressure_shift_cm1,
        .lower_state_energy_cm1 = row.lower_state_energy_cm1,
        .temperature_k = row.temperature_k,
        .pressure_hpa = row.pressure_hpa,
        .weak_line_sigma_cm2_per_molecule = row.weak_line_sigma_cm2_per_molecule,
        .strong_line_sigma_cm2_per_molecule = row.strong_line_sigma_cm2_per_molecule,
        .line_mixing_sigma_cm2_per_molecule = row.line_mixing_sigma_cm2_per_molecule,
        .total_sigma_cm2_per_molecule = row.total_sigma_cm2_per_molecule,
        .abs_total_sigma_cm2_per_molecule = row.abs_total_sigma_cm2_per_molecule,
    };
}

fn copyInstrumentResponseRow(row: zdisamar.InstrumentResponseRow) ZdsInstrumentResponseRow {
    return .{
        .nominal_index = row.nominal_index,
        .nominal_wavelength_nm = row.nominal_wavelength_nm,
        .channel = row.channel,
        .sample_index = row.sample_index,
        .support_count = row.support_count,
        .offset_nm = row.offset_nm,
        .support_wavelength_nm = row.support_wavelength_nm,
        .weight = row.weight,
        .support_width_nm = row.support_width_nm,
        .instrument_fwhm_nm = row.instrument_fwhm_nm,
        .high_resolution_step_nm = row.high_resolution_step_nm,
        .high_resolution_half_span_nm = row.high_resolution_half_span_nm,
        .integration_mode = row.integration_mode,
        .response_enabled = row.response_enabled,
    };
}

fn copyO2O2CIARow(row: zdisamar.O2O2CIARow) ZdsO2O2CIARow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .altitude_km = row.altitude_km,
        .pressure_hpa = row.pressure_hpa,
        .temperature_k = row.temperature_k,
        .oxygen_number_density_cm3 = row.oxygen_number_density_cm3,
        .path_length_cm = row.path_length_cm,
        .cia_cross_section_cm5_per_molecule2 = row.cia_cross_section_cm5_per_molecule2,
        .cia_optical_depth = row.cia_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_optical_depth = row.total_optical_depth,
        .cia_share_of_total_absorption = row.cia_share_of_total_absorption,
        .cia_share_of_total_optical_depth = row.cia_share_of_total_optical_depth,
    };
}

fn copyRadiativeTransferDiagnosticRow(
    row: zdisamar.RadiativeTransferDiagnosticRow,
) ZdsRadiativeTransferDiagnosticRow {
    return .{
        .wavelength_nm = row.wavelength_nm,
        .layer_index = row.layer_index,
        .sublayer_index = row.sublayer_index,
        .global_sublayer_index = row.global_sublayer_index,
        .interval_index_1based = row.interval_index_1based,
        .altitude_km = row.altitude_km,
        .total_optical_depth = row.total_optical_depth,
        .total_absorption_optical_depth = row.total_absorption_optical_depth,
        .total_scattering_optical_depth = row.total_scattering_optical_depth,
        .single_scatter_albedo = row.single_scatter_albedo,
        .cumulative_optical_depth_above = row.cumulative_optical_depth_above,
        .mid_layer_transmission_proxy = row.mid_layer_transmission_proxy,
        .direct_surface_transmission_proxy = row.direct_surface_transmission_proxy,
        .atmospheric_scattering_source_proxy = row.atmospheric_scattering_source_proxy,
        .absorption_loss_proxy = row.absorption_loss_proxy,
        .pseudo_spherical_airmass_factor = row.pseudo_spherical_airmass_factor,
        .n_streams = row.n_streams,
        .integrate_source_function = row.integrate_source_function,
        .final_reflectance = row.final_reflectance,
        .final_radiance = row.final_radiance,
    };
}

fn jacobianStateFromId(state_id: u8) !zdisamar.RadiativeTransferJacobian.State {
    return switch (state_id) {
        @intFromEnum(zdisamar.RadiativeTransferJacobian.State.surface_albedo) => .surface_albedo,
        @intFromEnum(zdisamar.RadiativeTransferJacobian.State.aerosol_optical_depth) => .aerosol_optical_depth,
        @intFromEnum(
            zdisamar.RadiativeTransferJacobian.State.aerosol_layer_mid_pressure_hpa,
        ) => .aerosol_layer_mid_pressure_hpa,
        else => error.UnsupportedJacobianState,
    };
}

const JacobianStateSelection = struct {
    states: [zdisamar.RadiativeTransferJacobian.state_count]zdisamar.RadiativeTransferJacobian.State = undefined,
    count: usize = 0,
    mask: zdisamar.RadiativeTransferJacobian.StateMask = zdisamar.RadiativeTransferJacobian.all_states_mask,

    fn slice(self: *const JacobianStateSelection) []const zdisamar.RadiativeTransferJacobian.State {
        return self.states[0..self.count];
    }
};

fn jacobianStateSelection(state_ids: []const u8) !JacobianStateSelection {
    if (state_ids.len == 0) return .{};
    if (state_ids.len > zdisamar.RadiativeTransferJacobian.state_count) return error.TooManyJacobianStates;

    var selection: JacobianStateSelection = .{
        .mask = 0,
    };
    for (state_ids) |state_id| {
        const state = try jacobianStateFromId(state_id);
        selection.states[selection.count] = state;
        selection.count += 1;
        selection.mask |= zdisamar.RadiativeTransferJacobian.stateMask(state);
    }
    selection.mask = zdisamar.RadiativeTransferJacobian.sanitizedMask(selection.mask);
    return selection;
}
