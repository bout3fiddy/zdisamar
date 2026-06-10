const std = @import("std");
const InstrumentGrid = @import("../forward_model/instrument_grid/root.zig");
const OpticsPrepare = @import("../forward_model/optical_properties/root.zig");
const jacobian = @import("../forward_model/jacobian/root.zig");
const o2a_runtime = @import("../input/o2a_reference/run.zig");
const o2a_types = @import("../input/o2a_reference/types.zig");
const o2a_prepared = @import("../input/o2a_reference/root.zig");
const ReferenceData = @import("../input/ReferenceData.zig");
const Telemetry = @import("../forward_model/instrumentation/telemetry.zig");
const Trace = @import("../forward_model/instrumentation/trace.zig");
const work_partition = @import("../forward_model/work_partition.zig");
const algebra = @import("algebra.zig");

const Allocator = std.mem.Allocator;
const Matrix = algebra.Matrix;
const Vector = algebra.Vector;
const VerticalInterval = @import("../input/Atmosphere.zig").VerticalInterval;
const Scene = @import("../input/Scene.zig").Scene;

pub const max_state_count = algebra.max_state_count;
pub const max_iteration_count: usize = 1000;
pub const no_lower_bound = -std.math.inf(f64);
pub const no_upper_bound = std.math.inf(f64);

// retrieval.zig ---------------------------------------------------------------------------------------------|
// Native O2 A optimal-estimation workflow and retained result owners.                                        |
//                                                                                                            |
// called by                                                                                                  |
//   src/root.zig exposes this file as zdisamar.optimal_estimation.                                           |
//   src/api/c.zig is the external C/Python boundary: it normalizes measurement slices, builds StateSpec      |
//   rows, creates pressure-profile spline scratch, and stores returned Result/BatchResult handles.           |
//   src/internal.zig imports this file for focused tests without widening the public facade.                 |
//                                                                                                            |
// public routes                                                                                              |
//   runO2A              : one full solve from a resolved O2 A case to an owned Result.                       |
//   runO2ABatch         : repeated starts over one state template, writing run-major SoA batch outputs.      |
//   runO2AFastmodeBatch : fast-stage batch solve, then a full-correction batch seeded from fast states.      |
//   correctPreparedO2A  : one retained correction solve against an already prepared O2 A forward case.       |
//   buildPressureProfile/freePressureProfile build the spline side data used by pressure-state retrievals.   |
//                                                                                                            |
// input and preparation flow                                                                                 |
//   StateSpec rows describe the OE state vector. RetrievalPreparedCase copies the resolved O2 A input into   |
//   mutable scene/interval storage, owns the measurement workspace, captures reusable spectroscopy profile   |
//   arrays after the first preparation, and borrows the caller-owned ProductStorage used for RTM products.   |
//                                                                                                            |
// iteration flow                                                                                             |
//   runPreparedO2ACore initializes StateSpace, enables semi-analytical Jacobians, evaluates RTM/Jacobian,    |
//   streams samples into Jt * Se^-1 * J and Jt * Se^-1 * residual, solves the Rodgers transformed update,    |
//   clamps physical bounds, records history, and converts posterior precision to covariance and              |
//   averaging-kernel output.                                                                                 |
//                                                                                                            |
// memory layout model                                                                                        |
//   Small state-space values live in fixed [max_state_count=3] vectors and matrices from algebra.zig.        |
//   Spectral-length data stays in MeasurementWorkspace, ProductStorage, and retained output slices.          |
//   BatchResult and FastmodeBatchResult are run-major SoA owners so C/Python views can borrow contiguous     |
//   status, state, iteration, convergence, and history arrays until the native handle is freed.              |
//                                                                                                            |
// hot path                                                                                                   |
//   Batches reuse one RetrievalPreparedCase per worker. The per-start loop mutates only state-dependent      |
//   scene rows, then accumulateNormalSystem walks the wavelength grid once while projecting active native    |
//   Jacobian columns into the <=3 OE state columns. Keep allocation and text/API handling outside this loop. |
// -----------------------------------------------------------------------------------------------------------|

pub const Error = error{
    EmptyMeasurement,
    InvalidMeasurement,
    InvalidStateCount,
    InvalidStateSpec,
    InvalidPressureProfile,
    WavelengthGridMismatch,
    MissingJacobian,
    UnsupportedState,
    OutOfMemory,
    SingularMatrix,
    InvalidPriorCovariance,
};

// StateSpec -------------------------------------------------------------------------------------------------|
// Scalar retrieval variable description passed from Python and C into native OE.                             |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 104 B (0.102 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..  7] initial                  : f64                                                                  |
// [  8.. 15] prior                    : f64                                                                  |
// [ 16.. 23] variance                 : f64                                                                  |
// [ 24.. 31] lower_bound              : f64                                                                  |
// [ 32.. 39] upper_bound              : f64                                                                  |
// [ 40.. 47] thickness_hpa            : f64                                                                  |
// [ 48.. 95] pressure_altitude_profile: PressureAltitudeProfile                                              |
// [ 96.. 99] interval_index_1based    : u32                                                                  |
// [100..100] state                    : jacobian.State                                                       |
// [101..103] trailing padding         : 3 B                                                                  |
//                                                                                                            |
// encoded fields                                                                                             |
//   bounds use +/-inf for absence. An empty pressure profile means no pressure-state metadata.               |
//                                                                                                            |
// unused bits: 24 padding + 0 bool-storage slack = 24 bits                                                   |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 104 B (0.102 KiB); total = per instance * state count                            |
pub const StateSpec = struct {
    state: jacobian.State,
    initial: f64,
    prior: f64,
    variance: f64,
    lower_bound: f64 = no_lower_bound,
    upper_bound: f64 = no_upper_bound,
    thickness_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    pressure_altitude_profile: PressureAltitudeProfile = .{},
};
// -----------------------------------------------------------------------------------------------------------|

// PressureAltitudeProfile -----------------------------------------------------------------------------------|
// Pressure-altitude table used to convert native altitude tangents to hPa tangents.                          |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 48 B (0.047 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..15] altitude_km : []const f64                                                                         |
// [16..31] pressure_hpa: []const f64                                                                         |
// [32..47] second      : []const f64                                                                         |
//                                                                                                            |
// referenced storage                                                                                         |
//   Slices borrow caller/workspace arrays. Referenced altitude, pressure, and spline storage is out-of-line. |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 48 B (0.047 KiB); total also includes second-derivative storage                  |
pub const PressureAltitudeProfile = struct {
    altitude_km: []const f64 = &.{},
    pressure_hpa: []const f64 = &.{},
    second: []const f64 = &.{},

    pub fn hasSamples(self: PressureAltitudeProfile) bool {
        return self.altitude_km.len != 0 or self.pressure_hpa.len != 0 or self.second.len != 0;
    }

    pub fn altitudeDerivativeAtPressure(self: PressureAltitudeProfile, pressure_hpa: f64) !f64 {
        if (self.altitude_km.len < 2 or
            self.altitude_km.len != self.pressure_hpa.len or
            self.second.len != self.altitude_km.len)
        {
            return error.InvalidPressureProfile;
        }
        const step_hpa = @max(@abs(pressure_hpa) * 1.0e-4, 1.0e-3);
        const lower_pressure = @max(self.pressure_hpa[self.pressure_hpa.len - 1], pressure_hpa - step_hpa);
        const upper_pressure = @min(self.pressure_hpa[0], pressure_hpa + step_hpa);
        if (upper_pressure <= lower_pressure) return error.InvalidPressureProfile;
        const altitude_span =
            try self.altitudeAtPressure(upper_pressure) -
            try self.altitudeAtPressure(lower_pressure);
        return altitude_span / (upper_pressure - lower_pressure);
    }

    fn altitudeAtPressure(self: PressureAltitudeProfile, pressure_hpa: f64) !f64 {
        if (!std.math.isFinite(pressure_hpa)) return error.InvalidPressureProfile;
        const lower_pressure = self.pressure_hpa[self.pressure_hpa.len - 1];
        const upper_pressure = self.pressure_hpa[0];
        if (pressure_hpa < lower_pressure or pressure_hpa > upper_pressure) return error.InvalidPressureProfile;

        var lower_altitude = self.altitude_km[0];
        var upper_altitude = self.altitude_km[self.altitude_km.len - 1];
        for (0..80) |_| {
            const mid_altitude = 0.5 * (lower_altitude + upper_altitude);
            const mid_pressure = try self.pressureAtAltitude(mid_altitude);
            if (mid_pressure > pressure_hpa) {
                lower_altitude = mid_altitude;
            } else {
                upper_altitude = mid_altitude;
            }
        }
        return 0.5 * (lower_altitude + upper_altitude);
    }

    fn pressureAtAltitude(self: PressureAltitudeProfile, altitude_km: f64) !f64 {
        const log_pressure = try cubicSplineSample(
            self.altitude_km,
            self.pressure_hpa,
            self.second,
            altitude_km,
        );
        return @exp(log_pressure);
    }
};
// -----------------------------------------------------------------------------------------------------------|

// MeasurementWorkspace --------------------------------------------------------------------------------------|
// Long-lived measurement buffers for one retrieval.                                                          |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 48 B (0.047 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..15] wavelength_nm: []f64                                                                              |
// [16..31] reflectance   : []f64                                                                             |
// [32..47] inv_variance  : []f64                                                                             |
//                                                                                                            |
// referenced storage                                                                                         |
//   Owns three dense f64 SoA buffers copied from caller input. Struct size excludes backing arrays.          |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 48 B (0.047 KiB); total also includes 3 * sample_count * 8 B                     |
pub const MeasurementWorkspace = struct {
    wavelength_nm: []f64 = &.{},
    reflectance: []f64 = &.{},
    inv_variance: []f64 = &.{},

    pub fn init(
        allocator: Allocator,
        wavelength_nm: []const f64,
        reflectance: []const f64,
        variance: []const f64,
    ) !MeasurementWorkspace {
        if (wavelength_nm.len == 0) return error.EmptyMeasurement;

        if (wavelength_nm.len != reflectance.len or wavelength_nm.len != variance.len) return error.InvalidMeasurement;
        var workspace: MeasurementWorkspace = .{};
        errdefer workspace.deinit(allocator);
        workspace.wavelength_nm = try allocator.dupe(f64, wavelength_nm);
        workspace.reflectance = try allocator.dupe(f64, reflectance);
        workspace.inv_variance = try allocator.alloc(f64, variance.len);

        for (
            workspace.wavelength_nm,
            workspace.reflectance,
            variance,

            workspace.inv_variance,
            0..,
        ) |wavelength, y, var_value, *inv, index| {
            if (!std.math.isFinite(wavelength) or
                !std.math.isFinite(y) or
                !std.math.isFinite(var_value) or
                var_value <= 0.0)
            {
                return error.InvalidMeasurement;
            }
            if (index != 0 and wavelength <= workspace.wavelength_nm[index - 1]) return error.InvalidMeasurement;
            inv.* = 1.0 / var_value;
        }

        return workspace;
    }

    pub fn deinit(self: *MeasurementWorkspace, allocator: Allocator) void {
        allocator.free(self.wavelength_nm);
        allocator.free(self.reflectance);
        allocator.free(self.inv_variance);
        self.* = .{};
    }
};
// -----------------------------------------------------------------------------------------------------------|

// IterationWorkspace ----------------------------------------------------------------------------------------|
// Reused fixed-size state-space scratch. The spectral dimension is never stored here.                        |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 480 B (0.469 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 23] sqrt_sa            : Vector                                                                     |
// [ 24.. 47] sqrt_inv_sa        : Vector                                                                     |
// [ 48.. 71] dx_white           : Vector                                                                     |
// [ 72.. 95] b                  : Vector                                                                     |
// [ 96..119] dx_trans           : Vector                                                                     |
// [120..143] rhs_trans          : Vector                                                                     |
// [144..167] dx_trans_new       : Vector                                                                     |
// [168..191] dx_physical        : Vector                                                                     |
// [192..263] g                  : Matrix                                                                     |
// [264..335] jt_invse_j         : Matrix                                                                     |
// [336..407] eigenvectors       : Matrix                                                                     |
// [408..479] posterior_precision: Matrix                                                                     |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 8 cache lines at 64 B per line                                                                 |
// footprint: per instance = 480 B (0.469 KiB); one stack value per active retrieval                          |
pub const IterationWorkspace = struct {
    sqrt_sa: Vector = algebra.zeroVector(),
    sqrt_inv_sa: Vector = algebra.zeroVector(),
    dx_white: Vector = algebra.zeroVector(),
    b: Vector = algebra.zeroVector(),
    dx_trans: Vector = algebra.zeroVector(),
    rhs_trans: Vector = algebra.zeroVector(),
    dx_trans_new: Vector = algebra.zeroVector(),
    dx_physical: Vector = algebra.zeroVector(),
    g: Matrix = algebra.zeroMatrix(),
    jt_invse_j: Matrix = algebra.zeroMatrix(),
    eigenvectors: Matrix = algebra.zeroMatrix(),
    posterior_precision: Matrix = algebra.zeroMatrix(),
};
// -----------------------------------------------------------------------------------------------------------|

// Result ----------------------------------------------------------------------------------------------------|
// Native result storage retained behind the C result handle.                                                 |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 184 B (0.180 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 15] state_ids                       : []jacobian.State                                              |
// [ 16.. 31] state                           : []f64                                                         |
// [ 32.. 47] initial_state                   : []f64                                                         |
// [ 48.. 63] posterior_covariance            : []f64                                                         |
// [ 64.. 79] averaging_kernel                : []f64                                                         |
// [ 80.. 95] history_state                   : []f64                                                         |
// [ 96..111] history_chi2                    : []f64                                                         |
// [112..127] history_chi2_reflectance        : []f64                                                         |
// [128..143] history_chi2_state_vector       : []f64                                                         |
// [144..159] history_state_vector_convergence: []f64                                                         |
// [160..175] history_snr_normal              : []u8                                                          |
// [176..177] iteration_count                 : u16                                                           |
// [178..178] state_count                     : u8                                                            |
// [179..179] converged                       : bool                                                          |
// [180..183] trailing padding                : 4 B                                                           |
//                                                                                                            |
// referenced storage                                                                                         |
//   Owns state, posterior, averaging-kernel, and history arrays. Struct size excludes those buffers.         |
//                                                                                                            |
// unused bits: 32 padding + 7 bool-storage slack = 39 bits                                                   |
// cache span: 3 cache lines at 64 B per line                                                                 |
// footprint: per instance = 184 B (0.180 KiB); total also includes referenced result buffers                 |
pub const Result = struct {
    state_count: u8 = 0,
    iteration_count: u16 = 0,
    converged: bool = false,
    state_ids: []jacobian.State = &.{},
    state: []f64 = &.{},
    initial_state: []f64 = &.{},
    posterior_covariance: []f64 = &.{},
    averaging_kernel: []f64 = &.{},
    history_state: []f64 = &.{},
    history_chi2: []f64 = &.{},
    history_chi2_reflectance: []f64 = &.{},
    history_chi2_state_vector: []f64 = &.{},
    history_state_vector_convergence: []f64 = &.{},
    history_snr_normal: []u8 = &.{},

    pub fn init(allocator: Allocator, state_count: usize, max_iterations: usize) !Result {
        if (state_count > max_state_count) return error.InvalidStateCount;
        if (max_iterations > max_iteration_count) return error.InvalidStateSpec;
        var result: Result = .{ .state_count = @intCast(state_count) };
        errdefer result.deinit(allocator);
        result.state_ids = try allocator.alloc(jacobian.State, state_count);

        result.state = try allocator.alloc(f64, state_count);
        result.initial_state = try allocator.alloc(f64, state_count);
        result.posterior_covariance = try allocator.alloc(f64, state_count * state_count);
        result.averaging_kernel = try allocator.alloc(f64, state_count * state_count);
        result.history_state = try allocator.alloc(f64, max_iterations * state_count);
        result.history_chi2 = try allocator.alloc(f64, max_iterations);

        result.history_chi2_reflectance = try allocator.alloc(f64, max_iterations);
        result.history_chi2_state_vector = try allocator.alloc(f64, max_iterations);
        result.history_state_vector_convergence = try allocator.alloc(f64, max_iterations);
        result.history_snr_normal = try allocator.alloc(u8, max_iterations);
        return result;
    }

    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.state_ids);
        allocator.free(self.state);
        allocator.free(self.initial_state);
        allocator.free(self.posterior_covariance);
        allocator.free(self.averaging_kernel);
        allocator.free(self.history_state);
        allocator.free(self.history_chi2);
        allocator.free(self.history_chi2_reflectance);
        allocator.free(self.history_chi2_state_vector);
        allocator.free(self.history_state_vector_convergence);
        allocator.free(self.history_snr_normal);
        self.* = .{};
    }
};
// -----------------------------------------------------------------------------------------------------------|

// BatchResult -----------------------------------------------------------------------------------------------|
// Batch output owner for repeated full-physics starts.                                                       |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 104 B (0.102 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..  7] run_count       : usize                                                                         |
// [  8.. 15] state_count     : usize                                                                         |
// [ 16.. 23] history_capacity: usize                                                                         |
// [ 24.. 39] iteration_count : []usize                                                                       |
// [ 40.. 55] converged       : []u8                                                                          |
// [ 56.. 71] status          : []u8                                                                          |
// [ 72.. 87] state           : []f64                                                                         |
// [ 88..103] history_state   : []f64                                                                         |
//                                                                                                            |
// referenced storage                                                                                         |
//   Owns SoA result buffers sized by run_count, state_count, and history_capacity.                           |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 104 B (0.102 KiB); total also includes owned result buffers                      |
pub const BatchResult = struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: []usize = &.{},
    converged: []u8 = &.{},
    status: []u8 = &.{},
    state: []f64 = &.{},
    history_state: []f64 = &.{},

    pub fn init(allocator: Allocator, run_count: usize, state_count: usize, history_capacity: usize) !BatchResult {
        if (run_count == 0) return error.InvalidStateSpec;
        if (state_count == 0 or state_count > max_state_count) return error.InvalidStateCount;
        if (history_capacity == 0 or history_capacity > max_iteration_count) return error.InvalidStateSpec;
        var result: BatchResult = .{
            .run_count = run_count,
            .state_count = state_count,
            .history_capacity = history_capacity,
        };

        errdefer result.deinit(allocator);
        result.iteration_count = try allocator.alloc(usize, run_count);
        result.converged = try allocator.alloc(u8, run_count);
        result.status = try allocator.alloc(u8, run_count);
        result.state = try allocator.alloc(f64, run_count * state_count);
        result.history_state = try allocator.alloc(f64, run_count * history_capacity * state_count);

        initializeBatchOutput(result.output());
        return result;
    }

    pub fn deinit(self: *BatchResult, allocator: Allocator) void {
        allocator.free(self.iteration_count);
        allocator.free(self.converged);
        allocator.free(self.status);
        allocator.free(self.state);
        allocator.free(self.history_state);
        self.* = .{};
    }

    fn output(self: *BatchResult) BatchOutput {
        return .{
            .run_count = self.run_count,
            .state_count = self.state_count,
            .history_capacity = self.history_capacity,
            .history_stride = self.history_capacity,
            .history_start_offset = 0,
            .iteration_count = self.iteration_count,
            .converged = self.converged,
            .status = self.status,
            .state = self.state,
            .history_state = self.history_state,
        };
    }
};
// -----------------------------------------------------------------------------------------------------------|

pub const BatchRunStatus = enum(u8) {
    pending = 0,
    ok = 1,
    failed = 2,
};

// BatchOutput -----------------------------------------------------------------------------------------------|
// Borrowed view used by batch initializers and workers.                                                      |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 120 B (0.117 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..  7] run_count           : usize                                                                     |
// [  8.. 15] state_count         : usize                                                                     |
// [ 16.. 23] history_capacity    : usize                                                                     |
// [ 24.. 31] history_stride      : usize                                                                     |
// [ 32.. 39] history_start_offset: usize                                                                     |
// [ 40.. 55] iteration_count     : []usize                                                                   |
// [ 56.. 71] converged           : []u8                                                                      |
// [ 72.. 87] status              : []u8                                                                      |
// [ 88..103] state               : []f64                                                                     |
// [104..119] history_state       : []f64                                                                     |
//                                                                                                            |
// referenced storage                                                                                         |
//   Borrows storage from BatchResult or a fastmode stage view. No backing arrays are owned here.             |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 120 B (0.117 KiB); total storage lives in the owner                              |
const BatchOutput = struct {
    run_count: usize,
    state_count: usize,
    history_capacity: usize,
    history_stride: usize,
    history_start_offset: usize,
    iteration_count: []usize,
    converged: []u8,
    status: []u8,
    state: []f64,
    history_state: []f64,
};
// -----------------------------------------------------------------------------------------------------------|

fn initializeBatchOutput(batch: BatchOutput) void {
    for (0..batch.run_count) |run_index| {
        markBatchRunPending(batch, run_index);
    }
}

fn initializeFastmodeBatchResult(result: *FastmodeBatchResult) void {
    for (0..result.run_count) |run_index| {
        result.iteration_count[run_index] = 0;
        result.converged[run_index] = 0;
        result.status[run_index] = @intFromEnum(BatchRunStatus.pending);
        result.fast_stage_iteration_count[run_index] = 0;
        result.fast_stage_converged[run_index] = 0;
        result.full_correction_iteration_count[run_index] = 0;
        result.full_correction_converged[run_index] = 0;
        const state_offset = run_index * result.state_count;
        for (0..result.state_count) |state_index| {
            result.state[state_offset + state_index] = std.math.nan(f64);
        }
        const history_offset = run_index * result.history_capacity * result.state_count;
        for (0..result.history_capacity * result.state_count) |history_index| {
            result.history_state[history_offset + history_index] = std.math.nan(f64);
        }
    }
}

fn markBatchRunPending(batch: BatchOutput, run_index: usize) void {
    batch.iteration_count[run_index] = 0;
    batch.converged[run_index] = 0;
    batch.status[run_index] = @intFromEnum(BatchRunStatus.pending);
    const state_offset = run_index * batch.state_count;
    for (0..batch.state_count) |state_index| {
        batch.state[state_offset + state_index] = std.math.nan(f64);
    }
    clearBatchRunHistory(batch, run_index);
}

fn markBatchRunFailure(batch: BatchOutput, run_index: usize) void {
    batch.iteration_count[run_index] = 0;
    batch.converged[run_index] = 0;
    batch.status[run_index] = @intFromEnum(BatchRunStatus.failed);
    const state_offset = run_index * batch.state_count;
    for (0..batch.state_count) |state_index| {
        batch.state[state_offset + state_index] = std.math.nan(f64);
    }
    clearBatchRunHistory(batch, run_index);
}

fn clearBatchRunHistory(batch: BatchOutput, run_index: usize) void {
    const history_offset = (run_index * batch.history_stride + batch.history_start_offset) *
        batch.state_count;
    for (0..batch.history_capacity * batch.state_count) |history_index| {
        batch.history_state[history_offset + history_index] = std.math.nan(f64);
    }
}

// FastmodeBatchResult ---------------------------------------------------------------------------------------|
// Batch output owner for fast-stage starts plus full-correction metadata.                                    |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 168 B (0.164 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..  7] run_count                      : usize                                                          |
// [  8.. 15] state_count                    : usize                                                          |
// [ 16.. 23] history_capacity               : usize                                                          |
// [ 24.. 39] iteration_count                : []usize                                                        |
// [ 40.. 55] converged                      : []u8                                                           |
// [ 56.. 71] status                         : []u8                                                           |
// [ 72.. 87] state                          : []f64                                                          |
// [ 88..103] history_state                  : []f64                                                          |
// [104..119] fast_stage_iteration_count     : []usize                                                        |
// [120..135] fast_stage_converged           : []u8                                                           |
// [136..151] full_correction_iteration_count: []usize                                                        |
// [152..167] full_correction_converged      : []u8                                                           |
//                                                                                                            |
// referenced storage                                                                                         |
//   Owns SoA buffers for final state, combined history, and per-stage convergence metadata.                  |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 3 cache lines at 64 B per line                                                                 |
// footprint: per instance = 168 B (0.164 KiB); total also includes owned result buffers                      |
pub const FastmodeBatchResult = struct {
    run_count: usize = 0,
    state_count: usize = 0,
    history_capacity: usize = 0,
    iteration_count: []usize = &.{},
    converged: []u8 = &.{},
    status: []u8 = &.{},
    state: []f64 = &.{},
    history_state: []f64 = &.{},
    fast_stage_iteration_count: []usize = &.{},
    fast_stage_converged: []u8 = &.{},
    full_correction_iteration_count: []usize = &.{},
    full_correction_converged: []u8 = &.{},

    pub fn init(
        allocator: Allocator,
        run_count: usize,
        state_count: usize,
        history_capacity: usize,
    ) !FastmodeBatchResult {
        if (run_count == 0) return error.InvalidStateSpec;
        if (state_count == 0 or state_count > max_state_count) return error.InvalidStateCount;

        if (history_capacity == 0 or history_capacity > max_iteration_count * 2) return error.InvalidStateSpec;
        var result: FastmodeBatchResult = .{
            .run_count = run_count,
            .state_count = state_count,

            .history_capacity = history_capacity,
        };

        errdefer result.deinit(allocator);
        result.iteration_count = try allocator.alloc(usize, run_count);
        result.converged = try allocator.alloc(u8, run_count);
        result.status = try allocator.alloc(u8, run_count);
        result.state = try allocator.alloc(f64, run_count * state_count);
        result.history_state = try allocator.alloc(f64, run_count * history_capacity * state_count);

        result.fast_stage_iteration_count = try allocator.alloc(usize, run_count);
        result.fast_stage_converged = try allocator.alloc(u8, run_count);
        result.full_correction_iteration_count = try allocator.alloc(usize, run_count);
        result.full_correction_converged = try allocator.alloc(u8, run_count);
        initializeFastmodeBatchResult(&result);
        return result;
    }

    pub fn deinit(self: *FastmodeBatchResult, allocator: Allocator) void {
        allocator.free(self.iteration_count);
        allocator.free(self.converged);
        allocator.free(self.status);
        allocator.free(self.state);
        allocator.free(self.history_state);
        allocator.free(self.fast_stage_iteration_count);
        allocator.free(self.fast_stage_converged);
        allocator.free(self.full_correction_iteration_count);
        allocator.free(self.full_correction_converged);
        self.* = .{};
    }
};
// -----------------------------------------------------------------------------------------------------------|

// Controls --------------------------------------------------------------------------------------------------|
// OE iteration limits and convergence thresholds supplied by the API boundary.                               |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 24 B (0.023 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] max_iterations                    : usize                                                         |
// [ 8..15] state_vector_convergence_threshold: f64                                                           |
// [16..23] max_change_transformed_state      : f64                                                           |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 24 B (0.023 KiB); usually passed by value                                        |
pub const Controls = struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};
// -----------------------------------------------------------------------------------------------------------|

// StateSpace ------------------------------------------------------------------------------------------------|
// Dense state-space vectors derived once before an OE run or correction step.                                |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 128 B (0.125 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 23] state                : Vector                                                                   |
// [ 24.. 47] prior                : Vector                                                                   |
// [ 48.. 71] variance             : Vector                                                                   |
// [ 72.. 95] lower                : Vector                                                                   |
// [ 96..119] upper                : Vector                                                                   |
// [120..120] derivative_state_mask: jacobian.StateMask                                                       |
// [121..127] trailing padding    : 7 B                                                                       |
//                                                                                                            |
// ownership                                                                                                  |
//   No heap references. Copied by value so correction paths reuse prepared scalar state without aliases.     |
//                                                                                                            |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                   |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 128 B (0.125 KiB); one stack value per active retrieval or correction            |
const StateSpace = struct {
    state: Vector,
    prior: Vector,
    variance: Vector,
    lower: Vector,
    upper: Vector,
    derivative_state_mask: jacobian.StateMask,
};
// -----------------------------------------------------------------------------------------------------------|

// ProfilePreparationSession ---------------------------------------------------------------------------------|
// Retrieval-session cache for profile spectroscopy support.                                                  |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 104 B (0.102 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 95] borrowed        : OpticsPrepare.BorrowedProfilePreparation                                       |
// [96.. 96] captured        : bool                                                                           |
// [97..103] trailing padding: 7 B                                                                            |
//                                                                                                            |
// referenced storage                                                                                         |
//   Captures first-iteration profile arrays and prepared line-state arrays from PreparedOpticalState.        |
//   Pressure-placement updates rebuild vertical-grid rows, not these invariant spectroscopy profile rows.    |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 104 B (0.102 KiB); total also includes captured referenced arrays                |
const ProfilePreparationSession = struct {
    borrowed: OpticsPrepare.BorrowedProfilePreparation = .{},
    captured: bool = false,

    fn borrowedPreparation(self: *const ProfilePreparationSession) ?*const OpticsPrepare.BorrowedProfilePreparation {
        if (!self.captured) return null;
        return &self.borrowed;
    }

    fn captureFromPrepared(
        self: *ProfilePreparationSession,
        prepared: *OpticsPrepare.PreparedOpticalState,
    ) void {
        if (self.captured or prepared.spectroscopy_profile_altitudes_km.len == 0) return;
        if (!prepared.owns_spectroscopy_profile_arrays) return;

        self.borrowed.altitudes_km = prepared.spectroscopy_profile_altitudes_km;
        self.borrowed.pressures_hpa = prepared.spectroscopy_profile_pressures_hpa;
        self.borrowed.temperatures_k = prepared.spectroscopy_profile_temperatures_k;
        prepared.spectroscopy_profile_altitudes_km = &.{};
        prepared.spectroscopy_profile_pressures_hpa = &.{};
        prepared.spectroscopy_profile_temperatures_k = &.{};
        prepared.owns_spectroscopy_profile_arrays = false;

        if (prepared.owns_spectroscopy_profile_strong_line_states) {
            self.borrowed.strong_line_states = prepared.spectroscopy_profile_strong_line_states;
            prepared.spectroscopy_profile_strong_line_states = null;
            prepared.owns_spectroscopy_profile_strong_line_states = false;
        }
        if (prepared.owns_spectroscopy_profile_weak_line_states) {
            self.borrowed.weak_line_states = prepared.spectroscopy_profile_weak_line_states;
            prepared.spectroscopy_profile_weak_line_states = null;
            prepared.owns_spectroscopy_profile_weak_line_states = false;
        }
        self.borrowed.spectroscopy_plan_key = prepared.spectroscopy_plan_key;
        self.borrowed.spectroscopy_profile_cache_inputs_key = prepared.spectroscopy_profile_cache_inputs_key;
        self.captured = true;
    }

    fn deinit(self: *ProfilePreparationSession, allocator: Allocator) void {
        if (self.borrowed.strong_line_states) |states| {
            for (states) |*state| state.deinit(allocator);
            allocator.free(states);
        }
        if (self.borrowed.weak_line_states) |states| {
            for (states) |*state| state.deinit(allocator);

            allocator.free(states);
        }
        if (self.borrowed.altitudes_km.len != 0) allocator.free(self.borrowed.altitudes_km);
        if (self.borrowed.pressures_hpa.len != 0) allocator.free(self.borrowed.pressures_hpa);
        if (self.borrowed.temperatures_k.len != 0) allocator.free(self.borrowed.temperatures_k);
        self.* = undefined;
    }
};
// -----------------------------------------------------------------------------------------------------------|

// RetrievalPreparedCase -------------------------------------------------------------------------------------|
// Retrieval-owned preparation for one inverse problem.                                                       |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 2200 B (2.148 KiB), align: 8 B                                                                       |
//                                                                                                            |
// memory                                                                                                     |
// [   0..  15] state_specs        : []const StateSpec                                                        |
// [  16..  23] forward_storage    : *InstrumentGrid.ProductStorage                                           |
// [  24..  71] measurement        : MeasurementWorkspace                                                     |
// [  72.. 407] loaded_inputs      : o2a_types.LoadedVendorO2AInputs                                          |
// [ 408..1287] mutable_input      : o2a_types.ResolvedVendorO2ACase                                          |
// [1288..1303] mutable_intervals  : []VerticalInterval                                                       |
// [1304..1975] scene              : Scene                                                                    |
// [1976..2007] weak_cutoff_grid   : o2a_runtime.WeakCutoffGridCache                                          |
// [2008..2111] profile_preparation: ProfilePreparationSession                                                |
// [2112..2191] rtm_config         : o2a_types.SolveConfig                                                    |
// [2192..2192] solar_rewindowed   : bool                                                                     |
// [2193..2199] trailing padding   : 7 B                                                                      |
//                                                                                                            |
// hot path                                                                                                   |
//   State evaluations rebuild state-dependent scene/optical rows, while rtm_config selection and measurement |
//   ownership stay outside the iteration loop.                                                               |
//                                                                                                            |
// referenced storage                                                                                         |
//   Owns mutable case copies, scene buffers, weak-cutoff cache, captured profile arrays, and measurement     |
//   SoA buffers. state_specs and forward_storage are borrowed from the caller.                               |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 35 cache lines at 64 B per line                                                                |
// footprint: per instance = 2200 B (2.148 KiB); total also includes owned referenced storage                 |
const RetrievalPreparedCase = struct {
    state_specs: []const StateSpec,
    forward_storage: *InstrumentGrid.ProductStorage,
    measurement: MeasurementWorkspace,
    loaded_inputs: o2a_types.LoadedVendorO2AInputs,
    mutable_input: o2a_types.ResolvedVendorO2ACase,
    mutable_intervals: []VerticalInterval,
    scene: Scene,
    weak_cutoff_grid: o2a_runtime.WeakCutoffGridCache = .{},
    solar_rewindowed: bool = false,
    profile_preparation: ProfilePreparationSession = .{},
    rtm_config: o2a_types.SolveConfig,

    fn init(
        allocator: Allocator,
        base_input: *const o2a_types.ResolvedVendorO2ACase,
        measurement_wavelength_nm: []const f64,
        measurement_reflectance: []const f64,
        measurement_variance: []const f64,
        state_specs: []const StateSpec,
        forward_storage: *InstrumentGrid.ProductStorage,
    ) !RetrievalPreparedCase {
        var measurement = try MeasurementWorkspace.init(
            allocator,
            measurement_wavelength_nm,
            measurement_reflectance,
            measurement_variance,
        );
        errdefer measurement.deinit(allocator);

        var loaded_inputs = try o2a_runtime.loadResolvedVendorO2AInputs(allocator, base_input);
        errdefer loaded_inputs.deinit(allocator);

        const mutable_intervals = try allocator.alloc(VerticalInterval, base_input.intervals.len);
        errdefer allocator.free(mutable_intervals);
        @memcpy(mutable_intervals, base_input.intervals);

        var mutable_input = base_input.*;
        mutable_input.intervals = mutable_intervals;

        var scene = try o2a_runtime.buildResolvedVendorO2AScene(
            allocator,
            &mutable_input,
            loaded_inputs.raw_solar_spectrum,
        );
        errdefer scene.deinitOwned(allocator);

        return .{
            .state_specs = state_specs,
            .forward_storage = forward_storage,
            .measurement = measurement,
            .loaded_inputs = loaded_inputs,
            .mutable_input = mutable_input,
            .mutable_intervals = mutable_intervals,
            .scene = scene,
            .rtm_config = try o2a_runtime.prepareResolvedVendorO2ASolveConfigFromResolved(base_input),
        };
    }

    fn deinit(self: *RetrievalPreparedCase, allocator: Allocator) void {
        self.profile_preparation.deinit(allocator);
        self.weak_cutoff_grid.deinit(allocator);
        self.scene.deinitOwned(allocator);
        allocator.free(self.mutable_intervals);
        self.loaded_inputs.deinit(allocator);
        self.measurement.deinit(allocator);
        self.* = undefined;
    }
};
// -----------------------------------------------------------------------------------------------------------|

pub fn runO2A(
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const StateSpec,
    forward_storage: *InstrumentGrid.ProductStorage,
    controls: Controls,
) !Result {
    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;

    if (controls.max_iterations == 0 or controls.max_iterations > max_iteration_count) return error.InvalidStateSpec;
    if (base_input.aerosol.profile.len > 1) return error.MultiLayerAerosolProfileUnsupportedForRetrieval;

    var prepared_case = try RetrievalPreparedCase.init(
        allocator,
        base_input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        state_specs,
        forward_storage,
    );
    defer prepared_case.deinit(allocator);

    return runPreparedO2A(allocator, &prepared_case, state_specs, controls);
}

pub fn runO2ABatch(
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    forward_storage: *InstrumentGrid.ProductStorage,
    controls: Controls,
    batch_worker_count: usize,
) !BatchResult {
    const run_count = try validateBatchInputs(base_input, state_template, initial_states, prior_states, controls);
    var batch = try BatchResult.init(allocator, run_count, state_template.len, controls.max_iterations);
    errdefer batch.deinit(allocator);
    var output = batch.output();

    try runO2ABatchInto(
        allocator,
        base_input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        state_template,
        initial_states,
        prior_states,
        forward_storage,
        controls,
        batch_worker_count,
        &output,
    );
    return batch;
}

fn runO2ABatchInto(
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    forward_storage: *InstrumentGrid.ProductStorage,
    controls: Controls,
    batch_worker_count: usize,
    batch: *BatchOutput,
) !void {
    const run_count = try validateBatchInputs(base_input, state_template, initial_states, prior_states, controls);

    if (batch.run_count != run_count or batch.state_count != state_template.len) return error.InvalidStateSpec;

    if (batch.iteration_count.len != run_count or
        batch.converged.len != run_count or
        batch.status.len != run_count)
    {
        return error.InvalidStateSpec;
    }

    if (batch.state.len != run_count * state_template.len) return error.InvalidStateSpec;

    if (batch.history_capacity < controls.max_iterations or
        batch.history_start_offset + batch.history_capacity > batch.history_stride)
    {
        return error.InvalidStateSpec;
    }

    if (batch.history_state.len != run_count * batch.history_stride * state_template.len) return error.InvalidStateSpec;

    const previous_context = Telemetry.currentContext();
    Telemetry.setContext(telemetryContextWithScene(previous_context, base_input.scene_id));
    defer Telemetry.setContext(previous_context);

    const effective_worker_count = @min(run_count, @max(@as(usize, 1), batch_worker_count));
    if (effective_worker_count == 1) {
        var prepared_case = try RetrievalPreparedCase.init(
            allocator,
            base_input,
            measurement_wavelength_nm,
            measurement_reflectance,
            measurement_variance,
            state_template,
            forward_storage,
        );
        defer prepared_case.deinit(allocator);
        try runO2ABatchRange(
            allocator,
            &prepared_case,
            state_template,
            initial_states,
            prior_states,
            controls,
            batch,
            0,
            run_count,
        );
        return;
    }

    try runO2ABatchParallel(
        allocator,
        base_input,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
        state_template,
        initial_states,
        prior_states,
        controls,
        batch,
        effective_worker_count,
    );
}

fn telemetryContextWithScene(context: Telemetry.Context, scene_id: []const u8) Telemetry.Context {
    if (comptime !Telemetry.enabled) return context;
    var resolved = context;
    if (resolved.scene_hash == -1) resolved.scene_hash = telemetryHashBytes(scene_id);
    return resolved;
}

fn telemetryContextWithStage(context: Telemetry.Context, stage: Telemetry.Stage) Telemetry.Context {
    if (comptime !Telemetry.enabled) return context;
    var resolved = context;
    resolved.stage = stage;
    return resolved;
}

fn telemetryContextWithStartState(
    context: Telemetry.Context,
    start_index: usize,
    state: []const f64,
) Telemetry.Context {
    if (comptime !Telemetry.enabled) return context;
    var resolved = telemetryContextWithState(context, state);
    resolved.start_index = telemetryIndex(start_index);
    return resolved;
}

fn telemetryContextWithEvaluationState(
    context: Telemetry.Context,
    iteration_index: usize,
    state: []const f64,
) Telemetry.Context {
    if (comptime !Telemetry.enabled) return context;
    var resolved = telemetryContextWithState(context, state);
    resolved.iteration_index = telemetryIndex(iteration_index);
    resolved.forward_evaluation_index = telemetryIndex(iteration_index);
    return resolved;
}

fn telemetryContextWithState(context: Telemetry.Context, state: []const f64) Telemetry.Context {
    if (comptime !Telemetry.enabled) return context;
    var resolved = context;
    resolved.state_hash = telemetryHashFloats(state);
    for (0..resolved.state_values.len) |index| {
        resolved.state_values[index] = if (index < state.len) state[index] else std.math.nan(f64);
    }
    return resolved;
}

fn telemetryHashBytes(bytes: []const u8) i64 {
    if (comptime !Telemetry.enabled) return 0;
    var hasher = std.hash.Wyhash.init(0x6f65_5f6d_7374_6172);
    hasher.update(bytes);
    return signedTelemetryHash(hasher.final());
}

fn telemetryHashFloats(values: []const f64) i64 {
    if (comptime !Telemetry.enabled) return 0;
    var hasher = std.hash.Wyhash.init(0x6f65_5f73_7461_7465);
    for (values) |value| {
        var bits = @as(u64, @bitCast(value));
        hasher.update(std.mem.asBytes(&bits));
    }
    return signedTelemetryHash(hasher.final());
}

fn signedTelemetryHash(hash: u64) i64 {
    if (comptime !Telemetry.enabled) return 0;
    return @as(i64, @bitCast(hash));
}

fn telemetryIndex(value: usize) i64 {
    if (comptime !Telemetry.enabled) return 0;
    return std.math.cast(i64, value) orelse std.math.maxInt(i64);
}

fn validateBatchInputs(
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    controls: Controls,
) !usize {
    if (state_template.len == 0 or state_template.len > max_state_count) return error.InvalidStateCount;

    if (controls.max_iterations == 0 or controls.max_iterations > max_iteration_count) return error.InvalidStateSpec;
    if (base_input.aerosol.profile.len > 1) return error.MultiLayerAerosolProfileUnsupportedForRetrieval;
    if (initial_states.len != prior_states.len) return error.InvalidStateSpec;
    if (initial_states.len % state_template.len != 0) return error.InvalidStateSpec;
    const run_count = initial_states.len / state_template.len;
    if (run_count == 0) return error.InvalidStateSpec;

    return run_count;
}

pub fn runO2AFastmodeBatch(
    allocator: Allocator,
    fast_input: *const o2a_types.ResolvedVendorO2ACase,
    fast_measurement_wavelength_nm: []const f64,
    fast_measurement_reflectance: []const f64,
    fast_measurement_variance: []const f64,
    fast_state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    fast_forward_storage: *InstrumentGrid.ProductStorage,
    fast_controls: Controls,
    correction_input: *const o2a_types.ResolvedVendorO2ACase,
    correction_measurement_wavelength_nm: []const f64,
    correction_measurement_reflectance: []const f64,
    correction_measurement_variance: []const f64,
    correction_state_template: []const StateSpec,
    correction_prior_states: []const f64,
    correction_forward_storage: *InstrumentGrid.ProductStorage,
    correction_controls: Controls,
    batch_worker_count: usize,
) !FastmodeBatchResult {
    if (fast_state_template.len != correction_state_template.len) return error.InvalidStateSpec;
    const run_count = try validateBatchInputs(
        fast_input,
        fast_state_template,
        initial_states,
        prior_states,
        fast_controls,
    );
    if (correction_prior_states.len != run_count * correction_state_template.len) return error.InvalidStateSpec;

    const fast_history_capacity = fast_controls.max_iterations;
    const correction_history_capacity = correction_controls.max_iterations;
    const total_history_capacity = fast_history_capacity + correction_history_capacity;
    var result = try FastmodeBatchResult.init(allocator, run_count, fast_state_template.len, total_history_capacity);
    errdefer result.deinit(allocator);

    var fast_output = BatchOutput{
        .run_count = run_count,
        .state_count = fast_state_template.len,
        .history_capacity = fast_history_capacity,
        .history_stride = result.history_capacity,
        .history_start_offset = 0,
        .iteration_count = result.fast_stage_iteration_count,
        .converged = result.fast_stage_converged,
        .status = result.status,
        .state = result.state,
        .history_state = result.history_state,
    };
    const fastmode_context = Telemetry.currentContext();
    {
        Telemetry.setContext(telemetryContextWithStage(fastmode_context, .fast));
        defer Telemetry.setContext(fastmode_context);
        try runO2ABatchInto(
            allocator,
            fast_input,
            fast_measurement_wavelength_nm,
            fast_measurement_reflectance,
            fast_measurement_variance,
            fast_state_template,
            initial_states,
            prior_states,
            fast_forward_storage,
            fast_controls,
            batch_worker_count,
            &fast_output,
        );
    }

    var correction_output = BatchOutput{
        .run_count = run_count,
        .state_count = correction_state_template.len,
        .history_capacity = correction_history_capacity,
        .history_stride = result.history_capacity,
        .history_start_offset = fast_history_capacity,
        .iteration_count = result.full_correction_iteration_count,
        .converged = result.full_correction_converged,
        .status = result.status,
        .state = result.state,
        .history_state = result.history_state,
    };
    for (0..run_count) |run_index| {
        if (result.status[run_index] == @intFromEnum(BatchRunStatus.ok)) {
            result.status[run_index] = @intFromEnum(BatchRunStatus.pending);
        }
    }
    {
        Telemetry.setContext(telemetryContextWithStage(fastmode_context, .correction));
        defer Telemetry.setContext(fastmode_context);
        try runO2ABatchInto(
            allocator,
            correction_input,
            correction_measurement_wavelength_nm,
            correction_measurement_reflectance,
            correction_measurement_variance,
            correction_state_template,
            result.state,
            correction_prior_states,
            correction_forward_storage,
            correction_controls,
            batch_worker_count,
            &correction_output,
        );
    }

    for (0..run_count) |run_index| {
        result.iteration_count[run_index] =
            result.fast_stage_iteration_count[run_index] + result.full_correction_iteration_count[run_index];
        result.converged[run_index] = if (result.status[run_index] == @intFromEnum(BatchRunStatus.ok))
            result.fast_stage_converged[run_index]
        else
            0;
        compactFastmodeBatchHistory(&result, run_index, fast_history_capacity);
    }
    return result;
}

fn compactFastmodeBatchHistory(
    result: *FastmodeBatchResult,
    run_index: usize,
    fast_history_capacity: usize,
) void {
    const fast_count = result.fast_stage_iteration_count[run_index];
    const correction_count = result.full_correction_iteration_count[run_index];
    if (correction_count == 0 or fast_count == fast_history_capacity) return;

    const state_count = result.state_count;
    const run_history_offset = run_index * result.history_capacity * state_count;
    const source_offset = run_history_offset + fast_history_capacity * state_count;
    const target_offset = run_history_offset + fast_count * state_count;
    const value_count = correction_count * state_count;
    std.mem.copyForwards(
        f64,
        result.history_state[target_offset .. target_offset + value_count],
        result.history_state[source_offset .. source_offset + value_count],
    );
}

fn runO2ABatchRange(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    controls: Controls,
    batch: *BatchOutput,
    start_run: usize,
    end_run: usize,
) !void {
    const range_context = Telemetry.currentContext();
    for (start_run..end_run) |run_index| {
        if (batch.status[run_index] != @intFromEnum(BatchRunStatus.pending)) continue;

        const state_offset = run_index * state_template.len;
        const summary = runPreparedO2AStartSummary(
            allocator,
            prepared_case,
            state_template,
            initial_states[state_offset .. state_offset + state_template.len],
            prior_states[state_offset .. state_offset + state_template.len],
            controls,
            run_index + 1,
            range_context,
            batchHistoryState(batch.*, run_index),
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                markBatchRunFailure(batch.*, run_index);
                continue;
            },
        };

        batch.iteration_count[run_index] = summary.iteration_count;
        batch.converged[run_index] = if (summary.converged) 1 else 0;
        batch.status[run_index] = @intFromEnum(BatchRunStatus.ok);
        for (0..state_template.len) |state_index| {
            batch.state[state_offset + state_index] = summary.state[state_index];
        }
    }
}

fn runPreparedO2AStartSummary(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state_template: []const StateSpec,
    initial_state: []const f64,
    prior_state: []const f64,
    controls: Controls,
    start_index: usize,
    base_context: Telemetry.Context,
    history_state: []f64,
) !RunSummary {
    std.debug.assert(initial_state.len == state_template.len);
    std.debug.assert(prior_state.len == state_template.len);
    var run_specs_buffer: [max_state_count]StateSpec = undefined;
    for (state_template, 0..) |template, state_index| {
        var spec = template;
        spec.initial = initial_state[state_index];
        spec.prior = prior_state[state_index];
        run_specs_buffer[state_index] = spec;
    }

    const previous_context = Telemetry.currentContext();
    const start_context = telemetryContextWithStartState(
        base_context,
        start_index,
        initial_state,
    );
    Telemetry.setContext(start_context);
    defer Telemetry.setContext(previous_context);
    return runPreparedO2ASummary(
        allocator,
        prepared_case,
        run_specs_buffer[0..state_template.len],
        controls,
        history_state,
    );
}

fn batchHistoryState(batch: BatchOutput, run_index: usize) []f64 {
    const history_offset = (run_index * batch.history_stride + batch.history_start_offset) *
        batch.state_count;
    return batch.history_state[history_offset .. history_offset + batch.history_capacity * batch.state_count];
}

// Worker descriptor for one contiguous slice of a native OE start batch.
// layout(product 64-bit):
//   size: 224 B, align: 8 B
//   field storage: 216 B across 15 product fields; largest: slice descriptors=128 B across 8 slices; padding: 8 B
//   unused bits: 64 padding + 0 bool-storage slack = 64 bits
//   out-of-line: all input slices borrow the batch request; batch points at caller-owned result buffers
//   cache span: 4 cache line(s) at 64 B per line
//   count: native batch worker count, usually CPU-core bounded for multi-start diagnosis
//   footprint: per instance = 224 B (0.219 KiB); each worker owns its prepared case and product storage while running
// telemetry: telemetry_context is zero-size in product builds and stores row attribution only in the validation
// telemetry executable
const BatchWorker = struct {
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    controls: Controls,
    batch: *BatchOutput,
    queue: *work_partition.ChunkQueue,
    shared_forward_prefetch_pool: ?*std.Thread.Pool,
    telemetry_context: Telemetry.Context,
    err: ?anyerror = null,
};

fn runO2ABatchParallel(
    allocator: Allocator,
    base_input: *const o2a_types.ResolvedVendorO2ACase,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_template: []const StateSpec,
    initial_states: []const f64,
    prior_states: []const f64,
    controls: Controls,
    batch: *BatchOutput,
    worker_count: usize,
) !void {
    const workers = try allocator.alloc(BatchWorker, worker_count);
    defer allocator.free(workers);
    const threads = try allocator.alloc(std.Thread, worker_count - 1);
    defer allocator.free(threads);
    var shared_forward_prefetch_pool_storage: std.Thread.Pool = undefined;
    var shared_forward_prefetch_pool_valid = false;
    const shared_forward_prefetch_pool = choose_shared_forward_prefetch_pool: {
        break :choose_shared_forward_prefetch_pool if (worker_count > 1)
            initSharedForwardPrefetchPool(
                allocator,
                &shared_forward_prefetch_pool_storage,
                &shared_forward_prefetch_pool_valid,
            )
        else
            null;
    };
    defer if (shared_forward_prefetch_pool_valid) shared_forward_prefetch_pool_storage.deinit();

    // One-iteration correction batches are uniform enough that wider queue
    // chunks reduce scheduling traffic; multi-iteration basin sweeps keep
    // one-start chunks so hard starts do not pin the tail.
    const batch_chunk_size: usize = if (controls.max_iterations == 1) 4 else 1;
    var queue = work_partition.ChunkQueue.init(batch.run_count, batch_chunk_size);
    const telemetry_context = Telemetry.currentContext();
    var started_thread_count: usize = 0;
    for (0..worker_count) |worker_index| {
        workers[worker_index] = .{
            .allocator = allocator,
            .base_input = base_input,
            .measurement_wavelength_nm = measurement_wavelength_nm,
            .measurement_reflectance = measurement_reflectance,
            .measurement_variance = measurement_variance,
            .state_template = state_template,
            .initial_states = initial_states,
            .prior_states = prior_states,
            .controls = controls,
            .batch = batch,
            .queue = &queue,
            .shared_forward_prefetch_pool = shared_forward_prefetch_pool,
            .telemetry_context = telemetry_context,
        };

        if (worker_index + 1 < worker_count) {
            threads[started_thread_count] = std.Thread.spawn(
                .{},
                runO2ABatchWorker,
                .{&workers[worker_index]},
            ) catch {
                runO2ABatchWorker(&workers[worker_index]);
                continue;
            };
            started_thread_count += 1;
        }
    }

    runO2ABatchWorker(&workers[worker_count - 1]);
    for (threads[0..started_thread_count]) |thread| thread.join();
    for (workers) |worker| {
        if (worker.err) |err| return err;
    }
}

fn runO2ABatchWorker(worker: *BatchWorker) void {
    runO2ABatchWorkerFallible(worker) catch |err| {
        worker.err = err;
    };
}

fn runO2ABatchWorkerFallible(worker: *BatchWorker) !void {
    const previous_context = Telemetry.currentContext();
    Telemetry.setContext(worker.telemetry_context);
    defer Telemetry.setContext(previous_context);

    var forward_storage: InstrumentGrid.ProductStorage = .{};
    forward_storage.shared_forward_prefetch_pool = worker.shared_forward_prefetch_pool;
    defer forward_storage.deinit(worker.allocator);
    var prepared_case = try RetrievalPreparedCase.init(
        worker.allocator,
        worker.base_input,
        worker.measurement_wavelength_nm,
        worker.measurement_reflectance,
        worker.measurement_variance,
        worker.state_template,
        &forward_storage,
    );
    defer prepared_case.deinit(worker.allocator);

    // Broad basin sweeps have variable iteration counts by start. Claim one
    // start at a time so a hard region does not pin the final worker tail.
    while (worker.queue.next()) |chunk| {
        try runO2ABatchRange(
            worker.allocator,
            &prepared_case,
            worker.state_template,
            worker.initial_states,
            worker.prior_states,
            worker.controls,
            worker.batch,
            chunk.start,
            chunk.end,
        );
    }
}

fn initSharedForwardPrefetchPool(
    allocator: Allocator,
    pool: *std.Thread.Pool,
    valid: *bool,
) ?*std.Thread.Pool {
    const worker_count = work_partition.preferredWorkerCount(std.math.maxInt(usize), 1);
    if (worker_count <= 1) return null;
    pool.init(.{
        .allocator = allocator,
        .n_jobs = worker_count - 1,
    }) catch return null;
    valid.* = true;
    return pool;
}

fn runPreparedO2A(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state_specs: []const StateSpec,
    controls: Controls,
) !Result {
    var result = try Result.init(allocator, state_specs.len, controls.max_iterations);
    errdefer result.deinit(allocator);

    var empty_history: [0]f64 = .{};
    _ = try runPreparedO2ACore(
        allocator,
        prepared_case,
        state_specs,
        controls,
        &result,
        empty_history[0..],
    );
    return result;
}

fn runPreparedO2ASummary(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state_specs: []const StateSpec,
    controls: Controls,
    history_state: []f64,
) !RunSummary {
    return runPreparedO2ACore(allocator, prepared_case, state_specs, controls, null, history_state);
}

fn runPreparedO2ACore(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state_specs: []const StateSpec,
    controls: Controls,
    full_result: ?*Result,
    history_state: []f64,
) !RunSummary {
    // runPreparedO2ACore ------------------------------------------------------------------------------------|
    // Runs one optimal-estimation solve over a prepared mutable O2 A case.                                   |
    //                                                                                                        |
    // hot path                                                                                               |
    //   repeated : once per retrieval start, and once per batch start in batch mode                          |
    //   inner    : every OE iteration evaluates RTM/Jacobian, streams samples into Jt * Se^-1 * J, then      |
    //              solves a max_state_count=3 linearized update                                              |
    //   memory   : IterationWorkspace keeps fixed-size vectors/matrices on the stack; spectral arrays stay   |
    //              in MeasurementWorkspace and ProductStorage                                                |
    //                                                                                                        |
    // instrumentation                                                                                        |
    //   trace zones split total retrieval, iteration, RTM/Jacobian, normal-system, and solver-update costs.  |
    // -------------------------------------------------------------------------------------------------------|

    // instrumentation: trace zone
    // captures: full optimal-estimation retrieval wall time
    // why: anchor setup, iteration, forward/Jacobian, and solver phases to one inversion.
    const retrieval_zone = Trace.staticZone(@src(), "optimal_estimation.run");
    defer retrieval_zone.end();

    // instrumentation: trace counter
    // captures: active retrieval state count
    // why: normalize iteration and solver timing by inverse-problem dimension.
    Trace.plotU("optimal_estimation_state_count", @intCast(state_specs.len));

    // instrumentation: trace counter
    // captures: configured maximum OE iterations
    // why: make trace comparisons robust when controls change.
    Trace.plotU("optimal_estimation_max_iterations", @intCast(controls.max_iterations));

    prepared_case.state_specs = state_specs;

    const state_space = try initializeStateSpace(state_specs, full_result);
    var state = state_space.state;
    prepared_case.rtm_config.derivative_mode = .semi_analytical;
    prepared_case.rtm_config.derivative_state_mask = state_space.derivative_state_mask;

    var scratch: IterationWorkspace = .{};
    try algebra.choleskyLowerDiagonal(state_space.variance[0..state_specs.len], &scratch.sqrt_sa, &scratch.sqrt_inv_sa);

    var final_posterior_precision: Matrix = undefined;

    var converged = false;
    var iteration_count: usize = 0;
    for (0..controls.max_iterations) |iteration_offset| {

        // instrumentation: trace zone
        // captures: one OE iteration wall time and iteration index
        // why: compare convergence cost across forward/Jacobian, normal-system, and solver phases.
        const iteration_zone = Trace.staticZone(@src(), "optimal_estimation.iteration");
        defer iteration_zone.end();
        iteration_zone.value(@intCast(iteration_offset + 1));

        const previous = state;
        const evaluation = traced_evaluation: {
            const previous_context = Telemetry.currentContext();
            Telemetry.setContext(telemetryContextWithEvaluationState(
                previous_context,
                iteration_offset + 1,
                previous[0..state_specs.len],
            ));
            defer Telemetry.setContext(previous_context);

            // instrumentation: trace zone
            // captures: RTM product and Jacobian evaluation wall time
            // why: keep forward-model cost separate from inverse-method linear algebra.
            const zone = Trace.staticZone(@src(), "optimal_estimation.rtm_jacobian");
            defer zone.end();
            break :traced_evaluation try evaluateO2AState(
                allocator,
                prepared_case,
                previous,
            );
        };

        const accumulation = traced_normal_system: {

            // instrumentation: trace zone
            // captures: normal-system accumulation wall time
            // why: measure residual/Jacobian reduction independently from RTM solves.
            const zone = Trace.staticZone(@src(), "optimal_estimation.normal_system");
            defer zone.end();
            break :traced_normal_system try accumulateNormalSystem(
                prepared_case.measurement,
                evaluation.view,
                state_specs,
                previous,
                state_space.prior,
                scratch.sqrt_sa,
                evaluation.solar_mu0,
                &scratch,
            );
        };

        const step = traced_solver_update: {

            // instrumentation: trace zone
            // captures: solver update wall time
            // why: isolate state-step computation from forward model and accumulation.
            const zone = Trace.staticZone(@src(), "optimal_estimation.solver_update");
            defer zone.end();
            break :traced_solver_update try solveStep(
                state_specs.len,
                scratch.g,
                scratch.b,
                state_space.prior,
                scratch.sqrt_sa,
                scratch.sqrt_inv_sa,
                controls.max_change_transformed_state,
                &scratch,
            );
        };
        state = step.state;
        for (0..state_specs.len) |index| {
            state[index] = @min(state_space.upper[index], @max(state_space.lower[index], state[index]));
        }

        var dx_iter = algebra.zeroVector();
        for (0..state_specs.len) |index| dx_iter[index] = state[index] - previous[index];
        var chi2_state: f64 = 0.0;
        for (0..state_specs.len) |index| chi2_state += dx_iter[index] * dx_iter[index] / state_space.variance[index];
        const state_conv = quadraticForm(step.posterior_precision, dx_iter, state_specs.len) /
            @as(f64, @floatFromInt(state_specs.len));
        converged = state_conv < controls.state_vector_convergence_threshold and step.snr_normal;

        if (full_result) |result| {
            const history_offset = iteration_offset * state_specs.len;
            for (0..state_specs.len) |index| result.history_state[history_offset + index] = state[index];
            result.history_chi2[iteration_offset] = accumulation.chi2_reflectance + chi2_state;
            result.history_chi2_reflectance[iteration_offset] = accumulation.chi2_reflectance;
            result.history_chi2_state_vector[iteration_offset] = chi2_state;

            result.history_state_vector_convergence[iteration_offset] = state_conv;
            result.history_snr_normal[iteration_offset] = if (step.snr_normal) 1 else 0;
            final_posterior_precision = step.posterior_precision;
            scratch.jt_invse_j = accumulation.jt_invse_j;
        }
        if (history_state.len > 0) {
            const history_offset = iteration_offset * state_specs.len;

            for (0..state_specs.len) |index| history_state[history_offset + index] = state[index];
        }
        iteration_count = iteration_offset + 1;
        if (converged) break;
    }

    if (full_result) |result| {
        const posterior_covariance = try algebra.invertSymmetric(final_posterior_precision, state_specs.len);
        const averaging_kernel = algebra.multiply(posterior_covariance, scratch.jt_invse_j, state_specs.len);
        result.iteration_count = @intCast(iteration_count);
        result.converged = converged;
        for (0..state_specs.len) |row| {
            result.state[row] = state[row];
            for (0..state_specs.len) |col| {
                result.posterior_covariance[row * state_specs.len + col] = posterior_covariance[row][col];
                result.averaging_kernel[row * state_specs.len + col] = averaging_kernel[row][col];
            }
        }
    }
    return .{
        .state = state,
        .iteration_count = iteration_count,
        .converged = converged,
    };
}

pub fn correctPreparedO2A(
    allocator: Allocator,
    prepared_case: *const o2a_prepared.PreparedO2A,
    measurement_wavelength_nm: []const f64,
    measurement_reflectance: []const f64,
    measurement_variance: []const f64,
    state_specs: []const StateSpec,
    forward_storage: *InstrumentGrid.ProductStorage,
    controls: Controls,
) !Result {
    const correction_zone = Trace.staticZone(@src(), "optimal_estimation.prepared_correction");
    defer correction_zone.end();

    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;

    var measurement = try MeasurementWorkspace.init(
        allocator,
        measurement_wavelength_nm,
        measurement_reflectance,
        measurement_variance,
    );
    defer measurement.deinit(allocator);

    var result = try Result.init(allocator, state_specs.len, 1);
    errdefer result.deinit(allocator);

    const state_space = try initializeStateSpace(state_specs, &result);
    var prepared = prepared_case.*;
    prepared.rtm_config.derivative_mode = .semi_analytical;
    prepared.rtm_config.derivative_state_mask = state_space.derivative_state_mask;

    var scratch: IterationWorkspace = .{};
    try algebra.choleskyLowerDiagonal(state_space.variance[0..state_specs.len], &scratch.sqrt_sa, &scratch.sqrt_inv_sa);

    const evaluation = traced_evaluation: {
        const zone = Trace.staticZone(@src(), "optimal_estimation.prepared_correction_rtm_jacobian");
        defer zone.end();
        const view = try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            forward_storage,
            &prepared.scene,
            prepared.rtm_config,
            &prepared.prepared,
        );
        break :traced_evaluation ForwardEvaluation{
            .view = view,
            .solar_mu0 = prepared.scene.geometry.solarCosineAtAltitude(0.0),
        };
    };

    const accumulation = try accumulateNormalSystem(
        measurement,
        evaluation.view,
        state_specs,
        state_space.state,
        state_space.prior,
        scratch.sqrt_sa,
        evaluation.solar_mu0,
        &scratch,
    );

    const step = try solveStep(
        state_specs.len,
        scratch.g,
        scratch.b,
        state_space.prior,
        scratch.sqrt_sa,
        scratch.sqrt_inv_sa,
        controls.max_change_transformed_state,
        &scratch,
    );

    var state = step.state;
    for (0..state_specs.len) |index| {
        state[index] = @min(state_space.upper[index], @max(state_space.lower[index], state[index]));
    }

    var dx_iter = algebra.zeroVector();
    for (0..state_specs.len) |index| dx_iter[index] = state[index] - state_space.state[index];
    var chi2_state: f64 = 0.0;
    for (0..state_specs.len) |index| {
        chi2_state += dx_iter[index] * dx_iter[index] / state_space.variance[index];
    }
    const state_conv = quadraticForm(step.posterior_precision, dx_iter, state_specs.len) /
        @as(f64, @floatFromInt(state_specs.len));
    const converged = state_conv < controls.state_vector_convergence_threshold and step.snr_normal;

    for (0..state_specs.len) |index| result.history_state[index] = state[index];
    result.history_chi2[0] = accumulation.chi2_reflectance + chi2_state;
    result.history_chi2_reflectance[0] = accumulation.chi2_reflectance;
    result.history_chi2_state_vector[0] = chi2_state;
    result.history_state_vector_convergence[0] = state_conv;
    result.history_snr_normal[0] = if (step.snr_normal) 1 else 0;

    const posterior_covariance = try algebra.invertSymmetric(step.posterior_precision, state_specs.len);
    const averaging_kernel = algebra.multiply(posterior_covariance, accumulation.jt_invse_j, state_specs.len);
    result.iteration_count = 1;
    result.converged = converged;
    for (0..state_specs.len) |row| {
        result.state[row] = state[row];
        for (0..state_specs.len) |col| {
            result.posterior_covariance[row * state_specs.len + col] = posterior_covariance[row][col];
            result.averaging_kernel[row * state_specs.len + col] = averaging_kernel[row][col];
        }
    }
    return result;
}

fn initializeStateSpace(state_specs: []const StateSpec, result: ?*Result) !StateSpace {
    var state_space: StateSpace = .{
        .state = algebra.zeroVector(),
        .prior = algebra.zeroVector(),
        .variance = algebra.zeroVector(),
        .lower = algebra.zeroVector(),
        .upper = algebra.zeroVector(),
        .derivative_state_mask = 0,
    };

    for (state_specs, 0..) |spec, index| {
        try validateStateSpec(spec);
        state_space.state[index] = spec.initial;
        state_space.prior[index] = spec.prior;
        state_space.variance[index] = spec.variance;
        state_space.lower[index] = spec.lower_bound;
        state_space.upper[index] = spec.upper_bound;
        state_space.derivative_state_mask |= jacobian.stateMask(spec.state);
        if (result) |full_result| {
            full_result.state_ids[index] = spec.state;
            full_result.initial_state[index] = spec.initial;
        }
    }
    return state_space;
}

fn validateStateSpec(spec: StateSpec) !void {
    if (!std.math.isFinite(spec.initial) or
        !std.math.isFinite(spec.prior) or
        !std.math.isFinite(spec.variance) or
        spec.variance <= 0.0)
    {
        return error.InvalidStateSpec;
    }

    if (std.math.isNan(spec.lower_bound) or std.math.isNan(spec.upper_bound)) return error.InvalidStateSpec;
    if (spec.lower_bound != no_lower_bound and !std.math.isFinite(spec.lower_bound)) return error.InvalidStateSpec;
    if (spec.upper_bound != no_upper_bound and !std.math.isFinite(spec.upper_bound)) return error.InvalidStateSpec;

    if (spec.lower_bound > spec.upper_bound) return error.InvalidStateSpec;

    if (spec.state == .aerosol_layer_mid_pressure_hpa) {
        if (spec.thickness_hpa <= 0.0 or
            spec.interval_index_1based == 0 or
            !spec.pressure_altitude_profile.hasSamples())
        {
            return error.InvalidStateSpec;
        }
    } else if (spec.thickness_hpa != 0.0 or
        spec.interval_index_1based != 0 or
        spec.pressure_altitude_profile.hasSamples())
    {
        return error.InvalidStateSpec;
    }
}

// ForwardEvaluation -----------------------------------------------------------------------------------------|
// Borrowed forward evaluation consumed immediately by the OE accumulation loop.                              |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 256 B (0.250 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0..247] view     : InstrumentGrid.InstrumentGridProductView                                             |
// [248..255] solar_mu0: f64                                                                                  |
//                                                                                                            |
// referenced storage                                                                                         |
//   view borrows ProductStorage arrays. Runtime case storage is consumed before return.                      |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 4 cache lines at 64 B per line                                                                 |
// footprint: per instance = 256 B (0.250 KiB); borrowed product buffers live in ProductStorage               |
const ForwardEvaluation = struct {
    view: InstrumentGrid.InstrumentGridProductView,
    solar_mu0: f64,
};
// -----------------------------------------------------------------------------------------------------------|

// RunSummary ------------------------------------------------------------------------------------------------|
// Batch-only final-state output for one start.                                                               |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 40 B (0.039 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..23] state           : Vector                                                                          |
// [24..31] iteration_count : usize                                                                           |
// [32..32] converged       : bool                                                                            |
// [33..39] trailing padding: 7 B                                                                             |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 40 B (0.039 KiB); one stack value per completed batch start                      |
const RunSummary = struct {
    state: Vector,
    iteration_count: usize,
    converged: bool,
};
// -----------------------------------------------------------------------------------------------------------|

fn evaluateO2AState(
    allocator: Allocator,
    prepared_case: *RetrievalPreparedCase,
    state: Vector,
) !ForwardEvaluation {
    {

        // instrumentation: trace zone
        // captures: retrieval-state application wall time
        // why: separate mutable scene/control updates from optical and RTM recomputation.
        const zone = Trace.staticZone(@src(), "optimal_estimation.state_application");
        defer zone.end();

        // The mutable case starts as the base case once. Each evaluation overwrites
        // every retrieval-owned field, so the iteration path avoids recopying the
        // full resolved case and interval grid before the RTM preparation.
        try writeStateToInput(
            &prepared_case.mutable_input,
            prepared_case.mutable_intervals,
            prepared_case.state_specs,
            state,
        );
        writeStateToScene(&prepared_case.scene, &prepared_case.mutable_input);
    }

    var prepared_optics = prepared_runtime_optics: {

        // instrumentation: trace zone
        // captures: per-iteration optical preparation wall time
        // why: measure setup rebuilt after aerosol and pressure-state changes.
        const zone = Trace.staticZone(@src(), "optimal_estimation.prepare_evaluation");
        defer zone.end();

        // OE state updates do not change the adaptive weak-line cutoff grid.
        // Cache that support once per retrieval while rebuilding the optical
        // layers that depend on aerosol amount and pressure placement.

        // The mutable scene is retrieval-owned. Solar rewindow support is
        // derived from the instrument grid and line-list plan, so it is
        // installed once and then reused while optical state is refreshed.
        break :prepared_runtime_optics try o2a_runtime.prepareResolvedVendorO2AOpticalStateWithSceneSessionCaches(
            allocator,
            &prepared_case.scene,
            &prepared_case.loaded_inputs,
            &prepared_case.weak_cutoff_grid,
            &prepared_case.solar_rewindowed,
            prepared_case.profile_preparation.borrowedPreparation(),
        );
    };
    defer prepared_optics.deinit(allocator);
    const view = simulated_forward_view: {

        // instrumentation: trace zone
        // captures: per-iteration forward product plus Jacobian wall time
        // why: isolate the model evaluation consumed by the OE residual step.
        const zone = Trace.staticZone(@src(), "optimal_estimation.forward_jacobian_product");
        defer zone.end();
        break :simulated_forward_view try InstrumentGrid.simulateProductWithWorkspace(
            allocator,
            prepared_case.forward_storage,
            &prepared_case.scene,
            prepared_case.rtm_config,
            &prepared_optics,
        );
    };
    prepared_case.profile_preparation.captureFromPrepared(&prepared_optics);
    return .{
        .view = view,
        .solar_mu0 = prepared_case.scene.geometry.solarCosineAtAltitude(0.0),
    };
}

fn writeStateToScene(
    scene: *Scene,
    input: *const o2a_types.ResolvedVendorO2ACase,
) void {
    scene.surface.albedo = input.surface_albedo;
    scene.aerosol.optical_depth = input.aerosol.optical_depth;
    scene.aerosol.placement = input.aerosol.placement;
    if (input.intervals.len != 0) {
        scene.atmosphere.interval_grid.intervals = input.intervals;
    }
}

fn writeStateToInput(
    input: *o2a_types.ResolvedVendorO2ACase,
    intervals: []VerticalInterval,
    state_specs: []const StateSpec,
    state: Vector,
) !void {
    for (state_specs, 0..) |spec, index| {
        const value = state[index];

        switch (spec.state) {
            .surface_albedo => input.surface_albedo = value,
            .aerosol_optical_depth => input.aerosol.optical_depth = value,
            .aerosol_layer_mid_pressure_hpa => {
                const fit_interval_index = @as(u64, spec.interval_index_1based);
                const half_thickness = 0.5 * spec.thickness_hpa;

                const top_pressure = value - half_thickness;
                const bottom_pressure = value + half_thickness;
                input.aerosol.placement.top_pressure_hpa = top_pressure;
                input.aerosol.placement.bottom_pressure_hpa = bottom_pressure;
                var updated = false;
                for (intervals) |*interval| {
                    const interval_index = @as(u64, interval.index_1based);

                    if (interval_index == fit_interval_index) {
                        interval.top_pressure_hpa = top_pressure;
                        interval.bottom_pressure_hpa = bottom_pressure;
                        updated = true;
                    } else if (interval_index + 1 == fit_interval_index) {
                        interval.bottom_pressure_hpa = top_pressure;
                    } else if (interval_index == fit_interval_index + 1) {
                        interval.top_pressure_hpa = bottom_pressure;
                    }
                }

                if (!updated) return error.InvalidStateSpec;
            },
        }
    }
}

// Accumulation ----------------------------------------------------------------------------------------------|
// Normal-system contribution returned from one measurement stream pass.                                      |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 80 B (0.078 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0.. 7] chi2_reflectance: f64                                                                             |
// [ 8..79] jt_invse_j      : Matrix                                                                          |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 80 B (0.078 KiB); one stack return per OE iteration                              |
const Accumulation = struct {
    chi2_reflectance: f64,
    jt_invse_j: Matrix,
};
// -----------------------------------------------------------------------------------------------------------|

// JacobianProjection ----------------------------------------------------------------------------------------|
// Per-iteration projection from active native RTM Jacobian columns into the OE state vector.                 |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 48 B (0.047 KiB), align: 8 B                                                                         |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..23] source_offset: [max_state_count]usize                                                             |
// [24..47] state_scale  : Vector                                                                             |
//                                                                                                            |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                     |
// cache span: 1 cache line at 64 B per line                                                                  |
// footprint: per instance = 48 B (0.047 KiB); one stack value per OE iteration                               |
const JacobianProjection = struct {
    source_offset: [max_state_count]usize = [_]usize{0} ** max_state_count,
    state_scale: Vector = algebra.zeroVector(),
};
// -----------------------------------------------------------------------------------------------------------|

fn accumulateNormalSystem(
    measurement: MeasurementWorkspace,
    view: InstrumentGrid.InstrumentGridProductView,
    state_specs: []const StateSpec,
    previous: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    solar_mu0: f64,
    scratch: *IterationWorkspace,
) !Accumulation {
    // accumulateNormalSystem --------------------------------------------------------------------------------|
    // Streams measurement samples into the OE normal system for one RTM/Jacobian evaluation.                 |
    //                                                                                                        |
    // hot path                                                                                               |
    //   repeated : once per OE iteration                                                                     |
    //   stream   : wavelength sample -> residual -> projected Jacobian columns -> b and G accumulation       |
    //   shape    : max_state_count=3 keeps the state loops fixed and small while the wavelength loop carries |
    //              the spectral dimension                                                                    |
    //   memory   : raw_jacobian is column-major by active native Jacobian state; JacobianProjection stores   |
    //              each active column offset plus pressure-state scaling for this iteration                  |
    //                                                                                                        |
    // math                                                                                                   |
    //   G += sqrt(Sa) * Jt * Se^-1 * J * sqrt(Sa)                                                            |
    //   b += sqrt(Sa) * Jt * Se^-1 * residual                                                                |
    // -------------------------------------------------------------------------------------------------------|

    if (view.wavelengths.len != measurement.wavelength_nm.len) return error.WavelengthGridMismatch;

    const raw_jacobian = view.jacobian orelse return error.MissingJacobian;
    const active_jacobian_count = jacobian.activeStateCount(view.jacobian_state_mask);
    if (active_jacobian_count == 0 or raw_jacobian.len != measurement.wavelength_nm.len * active_jacobian_count) {
        return error.MissingJacobian;
    }
    scratch.b = algebra.zeroVector();

    scratch.g = algebra.zeroMatrix();
    scratch.jt_invse_j = algebra.zeroMatrix();
    var projection: JacobianProjection = .{};
    for (0..state_specs.len) |index| {
        scratch.dx_white[index] = (previous[index] - prior[index]) / sqrt_sa[index];
        const spec = state_specs[index];

        const active_index = jacobian.activeStateIndex(view.jacobian_state_mask, spec.state) orelse
            return error.MissingJacobian;
        projection.source_offset[index] = active_index * measurement.wavelength_nm.len;
        projection.state_scale[index] = if (spec.state == .aerosol_layer_mid_pressure_hpa)
            try spec.pressure_altitude_profile.altitudeDerivativeAtPressure(previous[index])
        else
            1.0;
    }

    var chi2_reflectance: f64 = 0.0;
    var column_values = algebra.zeroVector();
    const reflectance_scale_numerator = std.math.pi / solar_mu0;
    for (measurement.wavelength_nm, 0..) |wavelength_nm, sample_index| {
        if (view.wavelengths[sample_index] != wavelength_nm) return error.WavelengthGridMismatch;
        const residual = measurement.reflectance[sample_index] - view.reflectance[sample_index];

        const inv_variance = measurement.inv_variance[sample_index];
        chi2_reflectance += residual * residual * inv_variance;
        const reflectance_scale = reflectance_scale_numerator / @max(view.irradiance[sample_index], 1.0e-300);
        for (0..state_specs.len) |state_index| {
            const source_index = projection.source_offset[state_index] + sample_index;
            column_values[state_index] =
                raw_jacobian[source_index] * reflectance_scale * projection.state_scale[state_index];
        }
        for (0..state_specs.len) |row| {
            const weighted_row = column_values[row] * inv_variance;
            scratch.b[row] += sqrt_sa[row] * weighted_row * residual;
            for (0..state_specs.len) |col| {
                const normal = weighted_row * column_values[col];

                scratch.jt_invse_j[row][col] += normal;
                scratch.g[row][col] += sqrt_sa[row] * normal * sqrt_sa[col];
            }
        }
    }
    return .{
        .chi2_reflectance = chi2_reflectance,
        .jt_invse_j = scratch.jt_invse_j,
    };
}

// Step ------------------------------------------------------------------------------------------------------|
// Solver output for one OE iteration.                                                                        |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 104 B (0.102 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [ 0..23] state              : Vector                                                                       |
// [24..95] posterior_precision: Matrix                                                                       |
// [96..96] snr_normal         : bool                                                                         |
// [97..103] trailing padding  : 7 B                                                                          |
//                                                                                                            |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                   |
// cache span: 2 cache lines at 64 B per line                                                                 |
// footprint: per instance = 104 B (0.102 KiB); one stack return per OE iteration                             |
const Step = struct {
    state: Vector,
    posterior_precision: Matrix,
    snr_normal: bool,
};
// -----------------------------------------------------------------------------------------------------------|

fn solveStep(
    state_count: usize,
    g: Matrix,
    b: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    sqrt_inv_sa: Vector,
    max_change_transformed_state: f64,
    scratch: *IterationWorkspace,
) !Step {
    const eig = algebra.jacobiEigenSymmetric(g, state_count);
    scratch.eigenvectors = eig.vectors;
    scratch.dx_trans = algebra.transposeMatrixVector(eig.vectors, scratch.dx_white, state_count);
    scratch.rhs_trans = algebra.transposeMatrixVector(eig.vectors, b, state_count);

    var max_dx_trans: f64 = 0.0;
    for (0..state_count) |index| max_dx_trans = @max(max_dx_trans, @abs(scratch.dx_trans[index]));
    const max_change = @max(max_change_transformed_state, max_dx_trans);
    var lambda_scale: f64 = 1.0;
    var snr_normal = true;
    computeTransformedUpdate(
        eig.values,
        scratch.rhs_trans,
        scratch.dx_trans,
        state_count,
        lambda_scale,
        &scratch.dx_trans_new,
    );
    var change = transformedChange(scratch.dx_trans_new, scratch.dx_trans, state_count);
    if (change > 1.01 * max_change) {
        snr_normal = false;
        var factor_total: f64 = 1.0;
        for (0..10) |_| {
            factor_total *= 0.75;
            const scale2 = factor_total * factor_total;
            computeTransformedUpdate(
                eig.values,
                scratch.rhs_trans,
                scratch.dx_trans,
                state_count,
                scale2,
                &scratch.dx_trans_new,
            );
            change = transformedChange(scratch.dx_trans_new, scratch.dx_trans, state_count);
            if (change < max_change) {
                lambda_scale = scale2;
                break;
            }
        }
    }

    const rotated = algebra.matrixVector(eig.vectors, scratch.dx_trans_new, state_count);
    var state = algebra.zeroVector();
    for (0..state_count) |index| {
        scratch.dx_physical[index] = sqrt_sa[index] * rotated[index];
        state[index] = prior[index] + scratch.dx_physical[index];
    }

    var posterior_white = algebra.identityMatrix(state_count);
    for (0..state_count) |row| {
        for (0..state_count) |col| {
            var value: f64 = 0.0;
            for (0..state_count) |k| {
                value += eig.vectors[row][k] * (lambda_scale * eig.values[k]) * eig.vectors[col][k];
            }
            posterior_white[row][col] += value;
        }
    }

    var posterior_precision = algebra.zeroMatrix();
    for (0..state_count) |row| {
        for (0..state_count) |col| {
            posterior_precision[row][col] = sqrt_inv_sa[row] * posterior_white[row][col] * sqrt_inv_sa[col];
        }
    }
    return .{
        .state = state,
        .posterior_precision = posterior_precision,
        .snr_normal = snr_normal,
    };
}

fn computeTransformedUpdate(
    eigenvalues: Vector,
    rhs_trans: Vector,
    dx_trans: Vector,
    state_count: usize,
    lambda_scale: f64,
    out: *Vector,
) void {
    for (0..state_count) |index| {
        const lambda = lambda_scale * eigenvalues[index];
        out[index] = (lambda_scale * rhs_trans[index] + lambda * dx_trans[index]) / (lambda + 1.0);
    }
}

fn transformedChange(next: Vector, previous: Vector, state_count: usize) f64 {
    var change: f64 = 0.0;
    for (0..state_count) |index| change = @max(change, @abs(next[index] - previous[index]));
    return change;
}

fn quadraticForm(matrix: Matrix, vector: Vector, state_count: usize) f64 {
    var value: f64 = 0.0;
    for (0..state_count) |row| {
        var row_value: f64 = 0.0;
        for (0..state_count) |col| row_value += matrix[row][col] * vector[col];
        value += vector[row] * row_value;
    }
    return value;
}

pub fn buildPressureProfile(
    allocator: Allocator,
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) !PressureAltitudeProfile {
    if (altitude_km.len < 2 or altitude_km.len != pressure_hpa.len) return error.InvalidPressureProfile;
    const second = try allocator.alloc(f64, altitude_km.len);
    errdefer allocator.free(second);
    try endpointSplineSecondDerivatives(allocator, altitude_km, pressure_hpa, second);
    return .{
        .altitude_km = altitude_km,
        .pressure_hpa = pressure_hpa,
        .second = second,
    };
}

pub fn freePressureProfile(allocator: Allocator, profile: PressureAltitudeProfile) void {
    if (profile.second.len == 0) return;
    allocator.free(profile.second);
}

fn validatePressureProfileSamples(
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) !void {
    if (altitude_km.len < 2 or altitude_km.len != pressure_hpa.len) return error.InvalidPressureProfile;

    for (0..altitude_km.len) |index| {
        if (!std.math.isFinite(altitude_km[index]) or
            !std.math.isFinite(pressure_hpa[index]) or
            pressure_hpa[index] <= 0.0)
        {
            return error.InvalidPressureProfile;
        }
        if (index != 0 and
            (altitude_km[index] <= altitude_km[index - 1] or
                pressure_hpa[index] >= pressure_hpa[index - 1]))
        {
            return error.InvalidPressureProfile;
        }
    }
}

fn endpointSplineSecondDerivatives(
    allocator: Allocator,
    x: []const f64,
    pressure_hpa: []const f64,
    second: []f64,
) !void {
    const count = x.len;
    if (count != pressure_hpa.len or count != second.len or count < 2) return error.InvalidPressureProfile;
    try validatePressureProfileSamples(x, pressure_hpa);
    if (count == 2) {
        second[0] = 0.0;

        second[1] = 0.0;
        return;
    }
    var matrix = algebra.zeroMatrix();
    if (count > max_state_count) {
        return endpointSplineSecondDerivativesDynamic(allocator, x, pressure_hpa, second);
    }
    var rhs = algebra.zeroVector();
    const width0 = x[1] - x[0];
    matrix[0][0] = 2.0 * width0;
    matrix[0][1] = width0;
    rhs[0] = 0.0;

    for (1..count - 1) |index| {
        const width_left = x[index] - x[index - 1];
        const width_right = x[index + 1] - x[index];
        const slope_left = (@log(pressure_hpa[index]) - @log(pressure_hpa[index - 1])) / width_left;
        const slope_right = (@log(pressure_hpa[index + 1]) - @log(pressure_hpa[index])) / width_right;
        matrix[index][index - 1] = width_left;

        matrix[index][index] = 2.0 * (width_left + width_right);
        matrix[index][index + 1] = width_right;
        rhs[index] = 6.0 * (slope_right - slope_left);
    }
    const last = count - 1;
    const width_last = x[last] - x[last - 1];

    matrix[last][last - 1] = width_last;
    matrix[last][last] = 2.0 * width_last;
    const inverse = try algebra.invertSymmetric(matrix, count);
    const solved = algebra.matrixVector(inverse, rhs, count);
    for (0..count) |index| second[index] = solved[index];
}

fn endpointSplineSecondDerivativesDynamic(
    allocator: Allocator,
    x: []const f64,
    pressure_hpa: []const f64,
    second: []f64,
) !void {
    const count = x.len;
    var lower = try allocator.alloc(f64, count);
    defer allocator.free(lower);
    var diag = try allocator.alloc(f64, count);
    defer allocator.free(diag);
    var upper = try allocator.alloc(f64, count);
    defer allocator.free(upper);
    var rhs = try allocator.alloc(f64, count);
    defer allocator.free(rhs);
    @memset(lower, 0.0);
    @memset(diag, 0.0);
    @memset(upper, 0.0);
    @memset(rhs, 0.0);
    const width0 = x[1] - x[0];
    diag[0] = 2.0 * width0;
    upper[0] = width0;
    for (1..count - 1) |index| {
        const width_left = x[index] - x[index - 1];
        const width_right = x[index + 1] - x[index];
        const slope_left = (@log(pressure_hpa[index]) - @log(pressure_hpa[index - 1])) / width_left;
        const slope_right = (@log(pressure_hpa[index + 1]) - @log(pressure_hpa[index])) / width_right;
        lower[index] = width_left;
        diag[index] = 2.0 * (width_left + width_right);
        upper[index] = width_right;
        rhs[index] = 6.0 * (slope_right - slope_left);
    }
    const last = count - 1;
    const width_last = x[last] - x[last - 1];
    lower[last] = width_last;
    diag[last] = 2.0 * width_last;
    for (1..count) |index| {
        const factor = lower[index] / diag[index - 1];
        diag[index] -= factor * upper[index - 1];
        rhs[index] -= factor * rhs[index - 1];
    }
    second[last] = rhs[last] / diag[last];
    var reverse_index = last;
    while (reverse_index > 0) {
        reverse_index -= 1;
        const numerator = rhs[reverse_index] -
            upper[reverse_index] * second[reverse_index + 1];
        second[reverse_index] = numerator / diag[reverse_index];
    }
}

fn cubicSplineSample(x: []const f64, pressure_hpa: []const f64, second: []const f64, value: f64) !f64 {
    var lower_index: usize = 0;
    while (lower_index + 1 < x.len and x[lower_index + 1] < value) : (lower_index += 1) {}
    lower_index = @min(lower_index, x.len - 2);
    const upper_index = lower_index + 1;
    const width = x[upper_index] - x[lower_index];
    if (width <= 0.0) return error.InvalidPressureProfile;
    const upper_weight = (x[upper_index] - value) / width;
    const lower_weight = (value - x[lower_index]) / width;
    const y0 = @log(pressure_hpa[lower_index]);
    const y1 = @log(pressure_hpa[upper_index]);
    var interpolated = upper_weight * y0 + lower_weight * y1;
    interpolated += ((upper_weight * upper_weight * upper_weight - upper_weight) * second[lower_index] +
        (lower_weight * lower_weight * lower_weight - lower_weight) * second[upper_index]) * width * width / 6.0;
    return interpolated;
}
