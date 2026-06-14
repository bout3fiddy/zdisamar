const std = @import("std");

const algebra = @import("algebra.zig");
const jacobian_states = @import("../rtm/jacobian_states.zig");

const Allocator = std.mem.Allocator;
const Matrix = algebra.Matrix;
const Vector = algebra.Vector;

pub const max_state_count = algebra.max_state_count;
pub const max_iteration_count: usize = 1000;
pub const StateVector = Vector;
pub const StateMatrix = Matrix;
pub const no_lower_bound = -std.math.inf(f64);
pub const no_upper_bound = std.math.inf(f64);

// root.zig ---------------------------------------------------------------------------------------------------|
// Retrieval value layer, fixed state-space scratch, and retained result owners for O2 A O2 A release.         |
//                                                                                                             |
// route map                                                                                                   |
//   api/c.zig converts Python/C request rows into StateSpec, MeasuredReflectanceRows, and result owners.      |
//   Future O2 A solver slices mutate these retrieval values and call root.zig forward functions with updated  |
//   aerosol/scalar state, while session memory stays warm.                                                    |
//                                                                                                             |
// primary paths                                                                                               |
//   buildPressureProfile/freePressureProfile build the pressure-to-altitude spline side data used by the      |
//   aerosol-layer pressure state. MeasuredReflectanceRows copies caller measurement arrays into dense SoA     |
//   buffers. Result, BatchResult, and FastmodeBatchResult retain contiguous arrays borrowed by C/Python.      |
//                                                                                                             |
// state-space storage                                                                                         |
//   Retrieval state math is capped at max_state_count = 2. Vector and Matrix live in algebra.zig and are      |
//   stack values; no heap-backed linalg or generic owner object sits in the iteration path.                   |
// ------------------------------------------------------------------------------------------------------------|

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

// StateSpec --------------------------------------------------------------------------------------------------|
// Scalar retrieval variable description passed from Python and C into native OE.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] initial                  : f64                                                                   |
// [  8.. 15] prior                    : f64                                                                   |
// [ 16.. 23] variance                 : f64                                                                   |
// [ 24.. 31] lower_bound              : f64                                                                   |
// [ 32.. 39] upper_bound              : f64                                                                   |
// [ 40.. 47] thickness_hpa            : f64                                                                   |
// [ 48.. 95] pressure_altitude_profile: PressureAltitudeProfile                                               |
// [ 96.. 99] interval_index_1based    : u32                                                                   |
// [100..100] state                    : jacobian_states.State                                                 |
// [101..103] trailing padding         : 3 B                                                                   |
//                                                                                                             |
// encoded fields                                                                                              |
//   bounds use +/-inf for absence. An empty pressure profile means no pressure-state metadata.                |
//                                                                                                             |
// unused bits: 24 padding + 0 bool-storage slack = 24 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 104 B (0.102 KiB); total = per instance * state count                             |
pub const StateSpec = struct {
    state: jacobian_states.State,
    initial: f64,
    prior: f64,
    variance: f64,
    lower_bound: f64 = no_lower_bound,
    upper_bound: f64 = no_upper_bound,
    thickness_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    pressure_altitude_profile: PressureAltitudeProfile = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// PressureAltitudeProfile ------------------------------------------------------------------------------------|
// Pressure-altitude table uses convert native altitude tangents to hPa tangents.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] altitude_km : []const f64                                                                          |
// [16..31] pressure_hpa: []const f64                                                                          |
// [32..47] second      : []const f64                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   altitude_km and pressure_hpa borrow caller arrays. second owns the spline curvature array returned by     |
//   buildPressureProfile and must be freed with freePressureProfile.                                          |
//                                                                                                             |
// math                                                                                                        |
//   second stores curvature for log(pressure_hpa), not pressure_hpa. pressureAtAltitude exponentiates the     |
//   spline sample before pressure-state derivative code uses it.                                              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 48 B (0.047 KiB); total also includes second-derivative storage                   |
pub const PressureAltitudeProfile = struct {
    altitude_km: []const f64 = &.{},
    pressure_hpa: []const f64 = &.{},
    second: []const f64 = &.{},

    pub fn hasSamples(self: PressureAltitudeProfile) bool {
        // PressureAltitudeProfile.hasSamples -----------------------------------------------------------------|
        // Report whether any borrowed or owned profile storage is attached.                                   |
        // ----------------------------------------------------------------------------------------------------|
        return self.altitude_km.len != 0 or self.pressure_hpa.len != 0 or self.second.len != 0;
    }

    pub fn altitudeDerivativeAtPressure(self: PressureAltitudeProfile, pressure_hpa: f64) !f64 {
        // PressureAltitudeProfile.altitudeDerivativeAtPressure -----------------------------------------------|
        //                                                                                                     |
        // math                                                                                                |
        //   step_hpa = max(abs(pressure_hpa) * 1.0e-4, 1.0e-3)                                                |
        //                                                                                                     |
        //                   altitude(upper_pressure) - altitude(lower_pressure)                               |
        //   derivative = ------------------------------------------------------------------                   |
        //                         upper_pressure - lower_pressure                                             |
        //                                                                                                     |
        // ----------------------------------------------------------------------------------------------------|
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
        // PressureAltitudeProfile.altitudeAtPressure ---------------------------------------------------------|
        // Invert the monotonic pressure-altitude spline with the 80-step bisection route.                     |
        // ----------------------------------------------------------------------------------------------------|
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
        // PressureAltitudeProfile.pressureAtAltitude ---------------------------------------------------------|
        // Sample log-pressure curvature at altitude and return pressure in hPa.                               |
        // ----------------------------------------------------------------------------------------------------|
        const log_pressure = try cubicSplineSample(
            self.altitude_km,
            self.pressure_hpa,
            self.second,
            altitude_km,
        );
        return @exp(log_pressure);
    }
};
// ------------------------------------------------------------------------------------------------------------|

// MeasuredReflectanceRows ------------------------------------------------------------------------------------|
// Long-lived measurement buffers for one retrieval.                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm: []f64                                                                               |
// [16..31] reflectance   : []f64                                                                              |
// [32..47] inv_variance  : []f64                                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   Owns three dense f64 SoA buffers copied from caller input. Struct size excludes backing arrays.           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 48 B (0.047 KiB); total also includes 3 * sample_count * 8 B                      |
pub const MeasuredReflectanceRows = struct {
    wavelength_nm: []f64 = &.{},
    reflectance: []f64 = &.{},
    inv_variance: []f64 = &.{},

    pub fn init(
        allocator: Allocator,
        wavelength_nm: []const f64,
        reflectance: []const f64,
        variance: []const f64,
    ) !MeasuredReflectanceRows {
        // MeasuredReflectanceRows.init -----------------------------------------------------------------------|
        // Copy caller measurement arrays and store inverse variance for one streaming normal-system pass.     |
        //                                                                                                     |
        // guard                                                                                               |
        //   Wavelengths must be strictly increasing, all values finite, and variance positive.                |
        // ----------------------------------------------------------------------------------------------------|
        if (wavelength_nm.len == 0) return error.EmptyMeasurement;
        if (wavelength_nm.len != reflectance.len or wavelength_nm.len != variance.len) {
            return error.InvalidMeasurement;
        }

        var measurements: MeasuredReflectanceRows = .{};
        errdefer measurements.deinit(allocator);
        measurements.wavelength_nm = try allocator.dupe(f64, wavelength_nm);
        measurements.reflectance = try allocator.dupe(f64, reflectance);
        measurements.inv_variance = try allocator.alloc(f64, variance.len);

        for (
            measurements.wavelength_nm,
            measurements.reflectance,
            variance,
            measurements.inv_variance,
            0..,
        ) |wavelength, y, var_value, *inv, index| {
            if (!std.math.isFinite(wavelength) or
                !std.math.isFinite(y) or
                !std.math.isFinite(var_value) or
                var_value <= 0.0)
            {
                return error.InvalidMeasurement;
            }
            if (index != 0 and wavelength <= measurements.wavelength_nm[index - 1]) {
                return error.InvalidMeasurement;
            }
            inv.* = 1.0 / var_value;
        }

        return measurements;
    }

    pub fn deinit(self: *MeasuredReflectanceRows, allocator: Allocator) void {
        // MeasuredReflectanceRows.deinit ---------------------------------------------------------------------|
        // Release dense measurement SoA buffers owned by this retrieval.                                      |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wavelength_nm);
        allocator.free(self.reflectance);
        allocator.free(self.inv_variance);
        self.* = .{};
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RetrievalIterationScratch ----------------------------------------------------------------------------------|
// Reused fixed-size state-space scratch. The spectral dimension is never stored here.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 256 B (0.250 KiB), align: 8                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] sqrt_sa            : Vector                                                                      |
// [ 16.. 31] sqrt_inv_sa        : Vector                                                                      |
// [ 32.. 47] dx_white           : Vector                                                                      |
// [ 48.. 63] b                  : Vector                                                                      |
// [ 64.. 79] dx_trans           : Vector                                                                      |
// [ 80.. 95] rhs_trans          : Vector                                                                      |
// [ 96..111] dx_trans_new       : Vector                                                                      |
// [112..127] dx_physical        : Vector                                                                      |
// [128..159] g                  : Matrix                                                                      |
// [160..191] jt_invse_j         : Matrix                                                                      |
// [192..223] eigenvectors       : Matrix                                                                      |
// [224..255] posterior_precision: Matrix                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 256 B (0.250 KiB); one stack value per active retrieval                           |
pub const RetrievalIterationScratch = struct {
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
// ------------------------------------------------------------------------------------------------------------|

// Result -----------------------------------------------------------------------------------------------------|
// Native result storage retained behind the C result handle.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 184 B (0.180 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] state_ids                       : []jacobian_states.State                                        |
// [ 16.. 31] state                           : []f64                                                          |
// [ 32.. 47] initial_state                   : []f64                                                          |
// [ 48.. 63] posterior_covariance            : []f64                                                          |
// [ 64.. 79] averaging_kernel                : []f64                                                          |
// [ 80.. 95] history_state                   : []f64                                                          |
// [ 96..111] history_chi2                    : []f64                                                          |
// [112..127] history_chi2_reflectance        : []f64                                                          |
// [128..143] history_chi2_state_vector       : []f64                                                          |
// [144..159] history_state_vector_convergence: []f64                                                          |
// [160..175] history_snr_normal              : []u8                                                           |
// [176..177] iteration_count                 : u16                                                            |
// [178..178] state_count                     : u8                                                             |
// [179..179] converged                       : bool                                                           |
// [180..183] trailing padding                : 4 B                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   Owns state, posterior, averaging-kernel, and history arrays. Struct size excludes those buffers.          |
//                                                                                                             |
// unused bits: 32 padding + 7 bool-storage slack = 39 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 184 B (0.180 KiB); total also includes referenced result buffers                  |
pub const Result = struct {
    state_count: u8 = 0,
    iteration_count: u16 = 0,
    converged: bool = false,
    state_ids: []jacobian_states.State = &.{},
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
        // Result.init ----------------------------------------------------------------------------------------|
        // Allocate C/Python-borrowable result arrays for one retrieval run.                                   |
        // ----------------------------------------------------------------------------------------------------|
        if (state_count > max_state_count) return error.InvalidStateCount;
        if (max_iterations > max_iteration_count) return error.InvalidStateSpec;

        var result: Result = .{ .state_count = @intCast(state_count) };
        errdefer result.deinit(allocator);
        result.state_ids = try allocator.alloc(jacobian_states.State, state_count);
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
        // Result.deinit --------------------------------------------------------------------------------------|
        // Release single-run arrays retained behind the external result handle.                               |
        // ----------------------------------------------------------------------------------------------------|
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
// ------------------------------------------------------------------------------------------------------------|

// BatchResult ------------------------------------------------------------------------------------------------|
// Batch output owner for repeated full-physics starts.                                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] run_count       : usize                                                                          |
// [  8.. 15] state_count     : usize                                                                          |
// [ 16.. 23] history_capacity: usize                                                                          |
// [ 24.. 39] iteration_count : []usize                                                                        |
// [ 40.. 55] converged       : []u8                                                                           |
// [ 56.. 71] status          : []u8                                                                           |
// [ 72.. 87] state           : []f64                                                                          |
// [ 88..103] history_state   : []f64                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   Owns SoA result buffers sized by run_count, state_count, and history_capacity.                            |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 104 B (0.102 KiB); total also includes owned result buffers                       |
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
        // BatchResult.init -----------------------------------------------------------------------------------|
        // Allocate run-major SoA arrays for a full-physics retrieval batch.                                   |
        // ----------------------------------------------------------------------------------------------------|
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

        const batch = result.output();
        for (0..batch.run_count) |run_index| resetBatchRun(batch, run_index, .pending);
        return result;
    }

    pub fn deinit(self: *BatchResult, allocator: Allocator) void {
        // BatchResult.deinit ---------------------------------------------------------------------------------|
        // Release full-physics batch arrays retained behind the external batch handle.                        |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.iteration_count);
        allocator.free(self.converged);
        allocator.free(self.status);
        allocator.free(self.state);
        allocator.free(self.history_state);
        self.* = .{};
    }

    pub fn output(self: *BatchResult) BatchOutput {
        // BatchResult.output ---------------------------------------------------------------------------------|
        // Borrow this owner as the common batch writer view used by single-worker and parallel runners.       |
        // ----------------------------------------------------------------------------------------------------|
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
// ------------------------------------------------------------------------------------------------------------|

pub const BatchRunStatus = enum(u8) {
    pending = 0,
    ok = 1,
    failed = 2,
};

// BatchOutput ------------------------------------------------------------------------------------------------|
// Borrowed view used by batch initializers and workers.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 120 B (0.117 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] run_count           : usize                                                                      |
// [  8.. 15] state_count         : usize                                                                      |
// [ 16.. 23] history_capacity    : usize                                                                      |
// [ 24.. 31] history_stride      : usize                                                                      |
// [ 32.. 39] history_start_offset: usize                                                                      |
// [ 40.. 55] iteration_count     : []usize                                                                    |
// [ 56.. 71] converged           : []u8                                                                       |
// [ 72.. 87] status              : []u8                                                                       |
// [ 88..103] state               : []f64                                                                      |
// [104..119] history_state       : []f64                                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   Borrows storage from BatchResult or a fastmode stage view. No backing arrays are owned here.              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 120 B (0.117 KiB); total storage lives in the owner                               |
pub const BatchOutput = struct {
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
// ------------------------------------------------------------------------------------------------------------|

// FastmodeBatchResult ----------------------------------------------------------------------------------------|
// Batch output owner for fast-stage starts plus full-correction metadata.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 168 B (0.164 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] run_count                      : usize                                                           |
// [  8.. 15] state_count                    : usize                                                           |
// [ 16.. 23] history_capacity               : usize                                                           |
// [ 24.. 39] iteration_count                : []usize                                                         |
// [ 40.. 55] converged                      : []u8                                                            |
// [ 56.. 71] status                         : []u8                                                            |
// [ 72.. 87] state                          : []f64                                                           |
// [ 88..103] history_state                  : []f64                                                           |
// [104..119] fast_stage_iteration_count     : []usize                                                         |
// [120..135] fast_stage_converged           : []u8                                                            |
// [136..151] full_correction_iteration_count: []usize                                                         |
// [152..167] full_correction_converged      : []u8                                                            |
//                                                                                                             |
// referenced storage                                                                                          |
//   Owns SoA buffers for final state, combined history, and per-stage convergence metadata.                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 168 B (0.164 KiB); total also includes owned result buffers                       |
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
        // FastmodeBatchResult.init ---------------------------------------------------------------------------|
        // Allocate final, fast-stage, and exact-correction result arrays for a fastmode batch.                |
        // ----------------------------------------------------------------------------------------------------|
        if (run_count == 0) return error.InvalidStateSpec;

        if (state_count == 0 or state_count > max_state_count) return error.InvalidStateCount;

        if (history_capacity == 0 or history_capacity > max_iteration_count * 2) {
            return error.InvalidStateSpec;
        }

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
        // FastmodeBatchResult.deinit -------------------------------------------------------------------------|
        // Release fastmode batch arrays retained behind the external fastmode handle.                         |
        // ----------------------------------------------------------------------------------------------------|
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
// ------------------------------------------------------------------------------------------------------------|

// Controls ---------------------------------------------------------------------------------------------------|
// OE iteration limits and convergence thresholds supplied by the API boundary.                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] max_iterations                    : usize                                                          |
// [ 8..15] state_vector_convergence_threshold: f64                                                            |
// [16..23] max_change_transformed_state      : f64                                                            |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 24 B (0.023 KiB); usually passed by value                                         |
pub const Controls = struct {
    max_iterations: usize = 10,
    state_vector_convergence_threshold: f64 = 1.0,
    max_change_transformed_state: f64 = 1.0,
};
// ------------------------------------------------------------------------------------------------------------|

// StateSpace -------------------------------------------------------------------------------------------------|
// Dense state-space vectors derived once before an OE run or correction step.                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 88 B (0.086 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] state                : Vector                                                                      |
// [16..31] prior                : Vector                                                                      |
// [32..47] variance             : Vector                                                                      |
// [48..63] lower                : Vector                                                                      |
// [64..79] upper                : Vector                                                                      |
// [80..80] derivative_state_mask: jacobian_states.StateMask                                                   |
// [81..87] trailing padding     : 7 B                                                                         |
//                                                                                                             |
// ownership                                                                                                   |
//   No heap references. Copied by value so correction paths reuse prepared scalar state without aliases.      |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 88 B (0.086 KiB); one stack value per active retrieval or correction              |
pub const StateSpace = struct {
    state: Vector,
    prior: Vector,
    variance: Vector,
    lower: Vector,
    upper: Vector,
    derivative_state_mask: jacobian_states.StateMask,
};
// ------------------------------------------------------------------------------------------------------------|

// ReflectanceEvaluationRows --------------------------------------------------------------------------------- |
// Borrowed product-grid rows consumed immediately by the retrieval accumulator.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm: []const f64                                                                         |
// [16..31] reflectance   : []const f64                                                                        |
// [32..47] jacobian      : []const jacobian_states.Vector                                                     |
//                                                                                                             |
// referenced storage                                                                                          |
//   All slices borrow the forward spectrum result. Jacobian rows are reflectance-space fixed vectors, not the |
//   active-column radiance buffer.                                                                            |
pub const ReflectanceEvaluationRows = struct {
    wavelength_nm: []const f64,
    reflectance: []const f64,
    jacobian: []const jacobian_states.Vector,
};
// ------------------------------------------------------------------------------------------------------------|

// Accumulation -----------------------------------------------------------------------------------------------|
// Normal-system contribution returned from one measurement stream pass.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] chi2_reflectance: f64                                                                              |
// [ 8..39] jt_invse_j      : Matrix                                                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 40 B (0.039 KiB); one stack return per OE iteration                               |
pub const Accumulation = struct {
    chi2_reflectance: f64,
    jt_invse_j: Matrix,
};
// ------------------------------------------------------------------------------------------------------------|

// JacobianProjection -----------------------------------------------------------------------------------------|
// Per-iteration projection from fixed RTM Jacobian lanes into the active OE state vector.                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 1] source_index: [max_state_count]u8                                                                  |
// [ 2..15] padding     : 14 B                                                                                 |
// [16..31] state_scale : Vector                                                                               |
//                                                                                                             |
// unused bits: 112 padding + 0 bool-storage slack = 112 bits                                                  |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 32 B (0.031 KiB); one stack value per OE iteration                                |
const JacobianProjection = struct {
    source_index: [max_state_count]u8 = [_]u8{0} ** max_state_count,
    state_scale: Vector = algebra.zeroVector(),
};
// ------------------------------------------------------------------------------------------------------------|

// Step -------------------------------------------------------------------------------------------------------|
// Solver output for one OE iteration.                                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] state              : Vector                                                                        |
// [16..47] posterior_precision: Matrix                                                                        |
// [48..48] snr_normal         : bool                                                                          |
// [49..55] trailing padding   : 7 B                                                                           |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 56 B (0.055 KiB); one stack return per OE iteration                               |
pub const Step = struct {
    state: Vector,
    posterior_precision: Matrix,
    snr_normal: bool,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn initializeStateSpace(state_specs: []const StateSpec, result: ?*Result) Error!StateSpace {
    // initializeStateSpace ---------------------------------------------------------------------------------- |
    // Convert validated state-spec rows into fixed two-lane vectors used by the Rodgers update.               |
    //                                                                                                         |
    //   removed from the state vector.                                                                        |
    // --------------------------------------------------------------------------------------------------------|
    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;

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
        state_space.derivative_state_mask |= jacobian_states.stateMask(spec.state);
        if (result) |full_result| {
            full_result.state_ids[index] = spec.state;
            full_result.initial_state[index] = spec.initial;
        }
    }
    return state_space;
}

pub fn preparePriorScales(
    state_space: StateSpace,
    state_count: usize,
    scratch: *RetrievalIterationScratch,
) Error!void {
    // preparePriorScales ------------------------------------------------------------------------------------ |
    // Fill sqrt(Sa) and sqrt(Sa)^-1 scratch lanes from the diagonal prior covariance.                         |
    // --------------------------------------------------------------------------------------------------------|
    try algebra.choleskyLowerDiagonal(state_space.variance[0..state_count], &scratch.sqrt_sa, &scratch.sqrt_inv_sa);
}

pub fn accumulateNormalSystem(
    measurement: MeasuredReflectanceRows,
    evaluation: ReflectanceEvaluationRows,
    state_specs: []const StateSpec,
    previous: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    scratch: *RetrievalIterationScratch,
) Error!Accumulation {
    // accumulateNormalSystem -------------------------------------------------------------------------------- |
    // Stream product-grid reflectance samples into the OE normal system for one forward/Jacobian evaluation.  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once per OE iteration                                                                      |
    //   stream   : wavelength sample -> residual -> projected Jacobian lanes -> b and G accumulation          |
    //   shape    : max_state_count=2 keeps the state loops fixed while the wavelength loop carries the        |
    //              spectral dimension                                                                         |
    //   memory   : evaluation.jacobian is one fixed two-lane reflectance vector per product sample            |
    //                                                                                                         |
    // math                                                                                                    |
    //   G += sqrt(Sa) * Jt * Se^-1 * J * sqrt(Sa)                                                             |
    //   b += sqrt(Sa) * Jt * Se^-1 * residual                                                                 |
    //                                                                                                         |
    // units                                                                                                   |
    //   from `Spectrum`, so no radiance-to-reflectance scale is applied here. The pressure lane still         |
    //   follows the aerosol-layer pressure-shift projection through altitudeDerivativeAtPressure.             |
    // --------------------------------------------------------------------------------------------------------|
    if (evaluation.wavelength_nm.len != measurement.wavelength_nm.len or
        evaluation.reflectance.len != measurement.wavelength_nm.len or
        evaluation.jacobian.len != measurement.wavelength_nm.len)
    {
        return error.WavelengthGridMismatch;
    }
    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;

    scratch.b = algebra.zeroVector();
    scratch.g = algebra.zeroMatrix();
    scratch.jt_invse_j = algebra.zeroMatrix();

    var projection: JacobianProjection = .{};
    for (state_specs, 0..) |spec, index| {
        scratch.dx_white[index] = (previous[index] - prior[index]) / sqrt_sa[index];
        projection.source_index[index] = @intCast(jacobian_states.stateIndex(spec.state));
        projection.state_scale[index] = if (spec.state == .aerosol_layer_mid_pressure_hpa)
            try spec.pressure_altitude_profile.altitudeDerivativeAtPressure(previous[index])
        else
            1.0;
    }

    var chi2_reflectance: f64 = 0.0;
    var column_values = algebra.zeroVector();
    for (measurement.wavelength_nm, 0..) |wavelength_nm, sample_index| {
        if (evaluation.wavelength_nm[sample_index] != wavelength_nm) return error.WavelengthGridMismatch;

        const residual = measurement.reflectance[sample_index] - evaluation.reflectance[sample_index];
        const inv_variance = measurement.inv_variance[sample_index];
        chi2_reflectance += residual * residual * inv_variance;

        for (0..state_specs.len) |state_index| {
            column_values[state_index] =
                evaluation.jacobian[sample_index][projection.source_index[state_index]] *
                projection.state_scale[state_index];
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

pub fn solveStep(
    state_count: usize,
    g: Matrix,
    b: Vector,
    prior: Vector,
    sqrt_sa: Vector,
    sqrt_inv_sa: Vector,
    max_change_transformed_state: f64,
    scratch: *RetrievalIterationScratch,
) Error!Step {
    // solveStep --------------------------------------------------------------------------------------------- |
    // Solve one Rodgers transformed-state update using the fixed two-lane eigensystem.                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   G = sqrt(Sa) * Jt * Se^-1 * J * sqrt(Sa)                                                              |
    //   b = sqrt(Sa) * Jt * Se^-1 * residual                                                                  |
    //                                                                                                         |
    //   dx_new_k = (lambda_scale * rhs_k + lambda_k * dx_k) / (lambda_k + 1)                                  |
    //   state   = prior + sqrt(Sa) * eigenvectors * dx_new                                                    |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
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

pub fn quadraticForm(matrix: Matrix, vector: Vector, state_count: usize) f64 {
    // quadraticForm ----------------------------------------------------------------------------------------- |
    // Return vector^T * matrix * vector over the active leading state lanes.                                  |
    // --------------------------------------------------------------------------------------------------------|
    var value: f64 = 0.0;
    for (0..state_count) |row| {
        var row_value: f64 = 0.0;
        for (0..state_count) |col| row_value += matrix[row][col] * vector[col];
        value += vector[row] * row_value;
    }
    return value;
}

fn computeTransformedUpdate(
    eigenvalues: Vector,
    rhs_trans: Vector,
    dx_trans: Vector,
    state_count: usize,
    lambda_scale: f64,
    out: *Vector,
) void {
    // computeTransformedUpdate ------------------------------------------------------------------------------ |
    // Build the damped transformed-state update for the current eigenvalue scale.                             |
    // --------------------------------------------------------------------------------------------------------|
    for (0..state_count) |index| {
        const lambda = lambda_scale * eigenvalues[index];
        out[index] = (lambda_scale * rhs_trans[index] + lambda * dx_trans[index]) / (lambda + 1.0);
    }
}

fn transformedChange(next: Vector, previous: Vector, state_count: usize) f64 {
    // transformedChange ------------------------------------------------------------------------------------- |
    // Return the largest absolute transformed-state lane change.                                              |
    // --------------------------------------------------------------------------------------------------------|
    var change: f64 = 0.0;
    for (0..state_count) |index| change = @max(change, @abs(next[index] - previous[index]));
    return change;
}

pub fn validateStateSpecs(state_specs: []const StateSpec) Error!void {
    // validateStateSpecs -------------------------------------------------------------------------------------|
    // Validate one C/Python OE state vector before the solver mutates the O2 A case.                          |
    //                                                                                                         |
    // guard                                                                                                   |
    //   fixed state count     : 1..2                                                                          |
    //   covariance lanes      : finite and positive                                                           |
    //   pressure-state lanes  : carry interval placement, thickness, and pressure-to-altitude profile rows    |
    //   non-pressure lanes    : carry no pressure-placement side data                                         |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
    if (state_specs.len == 0 or state_specs.len > max_state_count) return error.InvalidStateCount;
    for (state_specs) |spec| try validateStateSpec(spec);
}

pub fn buildPressureProfile(
    allocator: Allocator,
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) !PressureAltitudeProfile {
    // buildPressureProfile -----------------------------------------------------------------------------------|
    // Build pressure-profile curvature for aerosol-layer pressure-state tangent conversion.                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   The current route splines log(pressure_hpa) over altitude_km. A two-point profile is valid and keeps  |
    //   zero curvature, giving linear interpolation in log-pressure.                                          |
    //                                                                                                         |
    // --------------------------------------------------------------------------------------------------------|
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
    // freePressureProfile ------------------------------------------------------------------------------------|
    // Release only the curvature array allocated by buildPressureProfile; sample arrays are borrowed.         |
    // --------------------------------------------------------------------------------------------------------|
    if (profile.second.len == 0) return;
    allocator.free(profile.second);
}

fn validateStateSpec(spec: StateSpec) Error!void {
    // validateStateSpec --------------------------------------------------------------------------------------|
    // Validate scalar values and side-data shape for one retrieval state.                                     |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.isFinite(spec.initial) or
        !std.math.isFinite(spec.prior) or
        !std.math.isFinite(spec.variance) or
        spec.variance <= 0.0)
    {
        return error.InvalidStateSpec;
    }

    if (std.math.isNan(spec.lower_bound) or std.math.isNan(spec.upper_bound)) return error.InvalidStateSpec;
    if (spec.lower_bound != no_lower_bound and !std.math.isFinite(spec.lower_bound)) {
        return error.InvalidStateSpec;
    }
    if (spec.upper_bound != no_upper_bound and !std.math.isFinite(spec.upper_bound)) {
        return error.InvalidStateSpec;
    }
    if (spec.lower_bound > spec.upper_bound) return error.InvalidStateSpec;

    switch (spec.state) {
        .aerosol_layer_mid_pressure_hpa => {
            if (spec.thickness_hpa <= 0.0 or
                spec.interval_index_1based == 0 or
                !spec.pressure_altitude_profile.hasSamples())
            {
                return error.InvalidStateSpec;
            }
        },
        .aerosol_optical_depth => {
            if (spec.thickness_hpa != 0.0 or
                spec.interval_index_1based != 0 or
                spec.pressure_altitude_profile.hasSamples())
            {
                return error.InvalidStateSpec;
            }
        },
    }
}

fn initializeFastmodeBatchResult(result: *FastmodeBatchResult) void {
    // initializeFastmodeBatchResult --------------------------------------------------------------------------|
    // Fill every fastmode run slot with pending status and NaN payload values before worker writes.           |
    // --------------------------------------------------------------------------------------------------------|
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

fn resetBatchRun(batch: BatchOutput, run_index: usize, status: BatchRunStatus) void {
    // resetBatchRun ------------------------------------------------------------------------------------------|
    // Reset one run-major batch slot before a worker attempts the retrieval start.                            |
    // --------------------------------------------------------------------------------------------------------|
    batch.iteration_count[run_index] = 0;
    batch.converged[run_index] = 0;
    batch.status[run_index] = @intFromEnum(status);

    const state_offset = run_index * batch.state_count;
    for (0..batch.state_count) |state_index| {
        batch.state[state_offset + state_index] = std.math.nan(f64);
    }
    clearBatchRunHistory(batch, run_index);
}

fn clearBatchRunHistory(batch: BatchOutput, run_index: usize) void {
    // clearBatchRunHistory -----------------------------------------------------------------------------------|
    // Fill the selected history slot range with NaN while preserving other fastmode stage slots.              |
    // --------------------------------------------------------------------------------------------------------|
    const history_offset = (run_index * batch.history_stride + batch.history_start_offset) *
        batch.state_count;
    for (0..batch.history_capacity * batch.state_count) |history_index| {
        batch.history_state[history_offset + history_index] = std.math.nan(f64);
    }
}

fn validatePressureProfileSamples(
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) !void {
    // validatePressureProfileSamples -------------------------------------------------------------------------|
    // Reject non-finite, non-monotonic, or non-positive pressure-profile samples before spline setup.         |
    // --------------------------------------------------------------------------------------------------------|
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
    // endpointSplineSecondDerivatives ------------------------------------------------------------------------|
    // Solve clamped endpoint equations for log-pressure spline curvature.                                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   Interior rhs rows use the log-pressure slope jump:                                                    |
    //                                                                                                         |
    //     rhs_i = 6 * (slope_right - slope_left)                                                              |
    //                                                                                                         |
    //   pressure profiles use a temporary tridiagonal solve.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    const count = x.len;
    if (count != pressure_hpa.len or count != second.len or count < 2) {
        return error.InvalidPressureProfile;
    }
    try validatePressureProfileSamples(x, pressure_hpa);

    if (count == 2) {
        second[0] = 0.0;
        second[1] = 0.0;
        return;
    }
    if (count > max_state_count) {
        return endpointSplineSecondDerivativesDynamic(allocator, x, pressure_hpa, second);
    }

    var matrix = algebra.zeroMatrix();
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
    // endpointSplineSecondDerivativesDynamic -----------------------------------------------------------------|
    // Solve the same log-pressure spline equations for profiles too large for fixed two-state storage.        |
    // --------------------------------------------------------------------------------------------------------|
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
    // cubicSplineSample --------------------------------------------------------------------------------------|
    // Sample log(pressure_hpa) with caller-prepared pressure-profile curvature.                               |
    // --------------------------------------------------------------------------------------------------------|
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
