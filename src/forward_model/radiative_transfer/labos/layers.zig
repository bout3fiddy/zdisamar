const std = @import("std");
const math = std.math;
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../root.zig");

pub const LayerRT = basis.LayerRT;

pub const Profile = struct {
    mutex: std.Thread.Mutex = .{},
    zero_rt_ns: i128 = 0,
    fill_phase_ns: i128 = 0,
    max_beta_ns: i128 = 0,
    exponent_ns: i128 = 0,
    single_scatter_ns: i128 = 0,
    renorm_ns: i128 = 0,
    doubling_ns: i128 = 0,
    double_qseries_ns: i128 = 0,
    double_zero_check_ns: i128 = 0,
    double_qt_ns: i128 = 0,
    double_d_ns: i128 = 0,
    double_rd_ns: i128 = 0,
    double_u_ns: i128 = 0,
    double_tu_ns: i128 = 0,
    double_r_new_ns: i128 = 0,
    double_td_ns: i128 = 0,
    double_t_new_ns: i128 = 0,
    double_exponent_ns: i128 = 0,
    store_ns: i128 = 0,
    layer_count: usize = 0,
    doubling_count: usize = 0,
    double_step_count: usize = 0,

    pub const Sample = struct {
        zero_rt_ns: i128 = 0,
        fill_phase_ns: i128 = 0,
        max_beta_ns: i128 = 0,
        exponent_ns: i128 = 0,
        single_scatter_ns: i128 = 0,
        renorm_ns: i128 = 0,
        doubling_ns: i128 = 0,
        double_qseries_ns: i128 = 0,
        double_zero_check_ns: i128 = 0,
        double_qt_ns: i128 = 0,
        double_d_ns: i128 = 0,
        double_rd_ns: i128 = 0,
        double_u_ns: i128 = 0,
        double_tu_ns: i128 = 0,
        double_r_new_ns: i128 = 0,
        double_td_ns: i128 = 0,
        double_t_new_ns: i128 = 0,
        double_exponent_ns: i128 = 0,
        store_ns: i128 = 0,
        layer_count: usize = 0,
        doubling_count: usize = 0,
        double_step_count: usize = 0,
    };

    pub fn addSample(self: *Profile, sample: Sample) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.zero_rt_ns += sample.zero_rt_ns;
        self.fill_phase_ns += sample.fill_phase_ns;
        self.max_beta_ns += sample.max_beta_ns;
        self.exponent_ns += sample.exponent_ns;
        self.single_scatter_ns += sample.single_scatter_ns;
        self.renorm_ns += sample.renorm_ns;
        self.doubling_ns += sample.doubling_ns;
        self.double_qseries_ns += sample.double_qseries_ns;
        self.double_zero_check_ns += sample.double_zero_check_ns;
        self.double_qt_ns += sample.double_qt_ns;
        self.double_d_ns += sample.double_d_ns;
        self.double_rd_ns += sample.double_rd_ns;
        self.double_u_ns += sample.double_u_ns;
        self.double_tu_ns += sample.double_tu_ns;
        self.double_r_new_ns += sample.double_r_new_ns;
        self.double_td_ns += sample.double_td_ns;
        self.double_t_new_ns += sample.double_t_new_ns;
        self.double_exponent_ns += sample.double_exponent_ns;
        self.store_ns += sample.store_ns;
        self.layer_count += sample.layer_count;
        self.doubling_count += sample.doubling_count;
        self.double_step_count += sample.double_step_count;
    }

    pub fn print(self: *Profile) void {
        const layer_denom = @max(@as(f64, @floatFromInt(self.layer_count)), 1.0);
        std.debug.print(
            "[zds-profile] labos_layers={} doubled_layers={} double_steps={} zero_rt={d:.3}ms fill_phase={d:.3}ms max_beta={d:.3}ms exponent={d:.3}ms single_scatter={d:.3}ms renorm={d:.3}ms doubling={d:.3}ms double_qseries={d:.3}ms double_zero_check={d:.3}ms double_qt={d:.3}ms double_d={d:.3}ms double_rd={d:.3}ms double_u={d:.3}ms double_tu={d:.3}ms double_r_new={d:.3}ms double_td={d:.3}ms double_t_new={d:.3}ms double_exponent={d:.3}ms store={d:.3}ms fill_phase_mean={d:.6}ms/layer doubling_mean={d:.6}ms/layer\n",
            .{
                self.layer_count,
                self.doubling_count,
                self.double_step_count,
                nsToMs(self.zero_rt_ns),
                nsToMs(self.fill_phase_ns),
                nsToMs(self.max_beta_ns),
                nsToMs(self.exponent_ns),
                nsToMs(self.single_scatter_ns),
                nsToMs(self.renorm_ns),
                nsToMs(self.doubling_ns),
                nsToMs(self.double_qseries_ns),
                nsToMs(self.double_zero_check_ns),
                nsToMs(self.double_qt_ns),
                nsToMs(self.double_d_ns),
                nsToMs(self.double_rd_ns),
                nsToMs(self.double_u_ns),
                nsToMs(self.double_tu_ns),
                nsToMs(self.double_r_new_ns),
                nsToMs(self.double_td_ns),
                nsToMs(self.double_t_new_ns),
                nsToMs(self.double_exponent_ns),
                nsToMs(self.store_ns),
                nsToMs(self.fill_phase_ns) / layer_denom,
                nsToMs(self.doubling_ns) / layer_denom,
            },
        );
    }
};

threadlocal var active_profile: ?*Profile = null;

pub fn setProfile(profile: ?*Profile) ?*Profile {
    const previous = active_profile;
    active_profile = profile;
    return previous;
}

fn nsToMs(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / 1.0e6;
}

fn locateLowerIndex(values: []const f64, target: f64) usize {
    if (values.len <= 1) return 0;
    var index: usize = 0;
    while (index + 1 < values.len and values[index + 1] < target) : (index += 1) {}
    return index;
}

// PUB FOR TEST: re-exported via labos/internal.zig.
pub fn zeroFourierIntegral(
    zplus: *const basis.Mat,
    zmin: *const basis.Mat,
    geo: *const basis.Geometry,
    column_index: usize,
) f64 {
    const column_weight = @max(geo.w[column_index], 1.0e-30);
    var integral: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        const row_weight = @max(geo.w[imu], 1.0e-30);
        integral += geo.wg[imu] *
            ((zplus.get(imu, column_index) + zmin.get(imu, column_index)) /
                (row_weight * column_weight));
    }
    return integral;
}

// PUB FOR TEST: re-exported via labos/internal.zig.
pub fn renormalizeZeroFourierPhaseKernel(
    geo: *const basis.Geometry,
    zplus: *basis.Mat,
    zmin: *basis.Mat,
) void {
    if (geo.n_gauss == 0 or geo.nmutot == 0) return;

    var zp = [_][basis.max_nmutot]f64{.{0.0} ** basis.max_nmutot} ** basis.max_nmutot;
    for (0..geo.nmutot) |imu0| {
        const column_weight = @max(geo.w[imu0], 1.0e-30);
        for (0..geo.nmutot) |imu| {
            const row_weight = @max(geo.w[imu], 1.0e-30);
            zp[imu][imu0] = zplus.data[imu * zplus.n + imu0] / (row_weight * column_weight);
        }
    }

    for (0..geo.n_gauss) |imu0| {
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.data[imu * zmin.n + imu0] / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const denominator = zp[imu0][imu0] * geo.wg[imu0];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = (2.0 - integral) / denominator;
        zp[imu0][imu0] *= 1.0 + fraction;
    }

    for (geo.n_gauss..geo.nmutot) |imu0| {
        const target_mu = geo.u[imu0];
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.data[imu * zmin.n + imu0] / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const delta = 2.0 - integral;

        if (target_mu > geo.ug[0] and target_mu < geo.ug[geo.n_gauss - 1]) {
            const low = @min(locateLowerIndex(geo.ug[0..geo.n_gauss], target_mu), geo.n_gauss - 2);
            const high = low + 1;
            const span = geo.ug[high] - geo.ug[low];
            if (span <= 0.0) continue;
            const low_weight = (target_mu - geo.ug[low]) / span;
            const high_weight = (geo.ug[high] - target_mu) / span;
            const low_denominator = zp[imu0][low] * geo.wg[low];
            const high_denominator = zp[imu0][high] * geo.wg[high];
            if (@abs(low_denominator) > 1.0e-30) {
                const fraction = low_weight * delta / low_denominator;
                zp[imu0][low] *= 1.0 + fraction;
                zp[low][imu0] = zp[imu0][low];
            }
            if (@abs(high_denominator) > 1.0e-30) {
                const fraction = high_weight * delta / high_denominator;
                zp[imu0][high] *= 1.0 + fraction;
                zp[high][imu0] = zp[imu0][high];
            }
            continue;
        }

        const edge = if (target_mu < geo.ug[0]) 0 else geo.n_gauss - 1;
        const denominator = zp[imu0][edge] * geo.wg[edge];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = delta / denominator;
        zp[imu0][edge] *= 1.0 + fraction;
        zp[edge][imu0] = zp[imu0][edge];
    }

    for (0..geo.nmutot) |imu0| {
        const column_weight = geo.w[imu0];
        for (0..geo.nmutot) |imu| {
            zplus.data[imu * zplus.n + imu0] = zp[imu][imu0] * geo.w[imu] * column_weight;
        }
    }
}

// Rsingle: single-scattering reflection for a homogeneous layer.
fn singleScatterR(
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    if (n == 12) return singleScatterR12(a, E, Zmin, geo);
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;
        for (0..n) |i| {
            const eer = E.data[i] * ej;
            result.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += n;
        }
    }
    return result;
}

fn singleScatterR12(
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    var result = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;
        inline for (0..12) |i| {
            const eer = E.data[i] * ej;
            result.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += 12;
        }
    }
    return result;
}

// Tsingle: single-scattering transmission for a homogeneous layer.
fn singleScatterT(
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    if (n == 12) return singleScatterT12(a, b, E, Zplus, geo);
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;
        for (0..n) |i| {
            var eet: f64 = undefined;
            if (geo.dmu_same[idx]) {
                eet = b * E.data[i];
            } else {
                eet = E.data[i] - ej;
            }
            result.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += n;
        }
    }
    return result;
}

fn singleScatterT12(
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    var result = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;
        inline for (0..12) |i| {
            var eet: f64 = undefined;
            if (geo.dmu_same[idx]) {
                eet = b * E.data[i];
            } else {
                eet = E.data[i] - ej;
            }
            result.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += 12;
        }
    }
    return result;
}

fn gaussTrace(n: usize, n_gauss: usize, mat: *const basis.Mat) f64 {
    if (n == 12 and n_gauss == 10) {
        var trace = mat.data[0];
        trace += mat.data[13];
        trace += mat.data[26];
        trace += mat.data[39];
        trace += mat.data[52];
        trace += mat.data[65];
        trace += mat.data[78];
        trace += mat.data[91];
        trace += mat.data[104];
        trace += mat.data[117];
        return trace;
    }
    var trace: f64 = 0.0;
    for (0..n_gauss) |k| trace += mat.data[k * n + k];
    return trace;
}

// Perform ndouble doubling steps on R, T, E for a layer.
fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    geo: *const basis.Geometry,
    b_start: f64,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
    profile_sample: ?*Profile.Sample,
) void {
    var b = b_start;
    for (0..ndouble) |_| {
        if (profile_sample) |sample| sample.double_step_count += 1;

        const zero_check_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        const trace_r = gaussTrace(n, n_gauss, R);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;
        if (profile_sample) |sample| sample.double_zero_check_ns += std.time.nanoTimestamp() - zero_check_start;

        const D = if (q_is_zero) blk: {
            break :blk T.*;
        } else blk: {
            const q_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
            const Q = basis.qseries(n, n_gauss, threshold_mul, R, R);
            if (profile_sample) |sample| sample.double_qseries_ns += std.time.nanoTimestamp() - q_start;

            const smul_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
            var qt: basis.Mat = undefined;
            basis.smulInto(&qt, n, n_gauss, threshold_mul, &Q, T);
            if (profile_sample) |sample| sample.double_qt_ns += std.time.nanoTimestamp() - smul_start;

            const combine_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
            const combined = basis.matAddSemul3(n, T, &Q, E, &qt);
            if (profile_sample) |sample| sample.double_d_ns += std.time.nanoTimestamp() - combine_start;
            break :blk combined;
        };

        const rd_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        var rd: basis.Mat = undefined;
        basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);
        if (profile_sample) |sample| sample.double_rd_ns += std.time.nanoTimestamp() - rd_start;

        const u_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        const U = basis.semulAdd(n, R, E, &rd);
        if (profile_sample) |sample| sample.double_u_ns += std.time.nanoTimestamp() - u_start;

        const tu_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        var tu: basis.Mat = undefined;
        basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);
        if (profile_sample) |sample| sample.double_tu_ns += std.time.nanoTimestamp() - tu_start;

        const r_new_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);
        if (profile_sample) |sample| sample.double_r_new_ns += std.time.nanoTimestamp() - r_new_start;

        const td_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        var td: basis.Mat = undefined;
        basis.smulInto(&td, n, n_gauss, threshold_mul, T, &D);
        if (profile_sample) |sample| sample.double_td_ns += std.time.nanoTimestamp() - td_start;

        const t_new_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        const T_new = basis.esmulSemulAdd(n, E, &D, T, &td);
        if (profile_sample) |sample| sample.double_t_new_ns += std.time.nanoTimestamp() - t_new_start;

        // PARITY: DISAMAR's whole-array assignments evaluate both RHS values
        // from the pre-step operators before storing the doubled layer state.
        R.* = R_new;
        T.* = T_new;

        b *= 2.0;
        const exponent_start = if (profile_sample != null) std.time.nanoTimestamp() else 0;
        if (b < 0.001) {
            for (0..geo.nmutot) |imu| {
                E.data[imu] = math.exp(-b / @max(geo.u[imu], 1.0e-12));
            }
        } else {
            for (0..geo.nmutot) |imu| {
                const e = E.data[imu];
                E.data[imu] = e * e;
            }
        }
        if (profile_sample) |sample| sample.double_exponent_ns += std.time.nanoTimestamp() - exponent_start;
    }
}

fn maxLayerPhaseCoefficientIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |layer| {
        max_index = @max(max_index, phase_functions.maxPhaseCoefficientIndex(layer.phase_coefficients));
    }
    return max_index;
}

pub fn fillLayerPhaseMaxIndices(
    layer_phase_max_indices: []usize,
    layers: []const common.LayerInput,
) void {
    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    for (layers, layer_phase_max_indices[0..layers.len]) |layer, *max_index| {
        max_index.* = phase_functions.maxPhaseCoefficientIndex(layer.phase_coefficients);
    }
}

pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_max_indices: ?[]const usize,
    phase_kernel_cache: ?[]basis.PhaseKernel,
    phase_kernel_valid: ?[]bool,
    rt_active: ?[]bool,
) void {
    const nlayer = layers.len;
    const profile_enabled = active_profile != null;
    var profile_sample = Profile.Sample{};

    const zero_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
    rt[0] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[0] = false;
    if (phase_kernel_valid) |valid| @memset(valid, false);
    if (profile_enabled) profile_sample.zero_rt_ns += std.time.nanoTimestamp() - zero_start;

    for (0..nlayer) |layer_idx| {
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];
        profile_sample.layer_count += 1;
        if (i_fourier >= basis.max_phase_coef) {
            const zero_layer_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            if (profile_enabled) profile_sample.zero_rt_ns += std.time.nanoTimestamp() - zero_layer_start;
            continue;
        }

        const phase_coefs = layer.phase_coefficients;
        const max_phase_index = if (layer_phase_max_indices) |indices|
            indices[layer_idx]
        else
            phase_functions.maxPhaseCoefficientIndex(phase_coefs);
        if (i_fourier > max_phase_index) {
            const zero_layer_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            if (profile_enabled) profile_sample.zero_rt_ns += std.time.nanoTimestamp() - zero_layer_start;
            continue;
        }
        if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0 or layer.single_scatter_albedo <= 0.0) {
            const zero_layer_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            if (profile_enabled) profile_sample.zero_rt_ns += std.time.nanoTimestamp() - zero_layer_start;
            continue;
        }

        const fill_phase_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var z = basis.fillZplusZminFromBasisLimited(
            i_fourier,
            phase_coefs,
            max_phase_index,
            geo,
            plm_basis,
        );
        if (profile_enabled) profile_sample.fill_phase_ns += std.time.nanoTimestamp() - fill_phase_start;
        if (phase_kernel_cache) |cache| {
            cache[rt_idx] = z;
            if (phase_kernel_valid) |valid| valid[rt_idx] = true;
        }
        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        const max_beta_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var max_beta_eff: f64 = 0.0;
        for (i_fourier..max_phase_index + 1) |ic| {
            const icf: f64 = @floatFromInt(ic);
            const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
            if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
        }
        const a_eff = a * max_beta_eff;
        if (profile_enabled) profile_sample.max_beta_ns += std.time.nanoTimestamp() - max_beta_start;

        var use_doubling = false;
        var b_start = b;
        var ndouble: usize = 0;

        if (controls.scattering == .multiple and a_eff * b > controls.threshold_doubl) {
            // DECISION:
            //   Trigger doubling only when the scaled optical thickness crosses
            //   the configured threshold.
            use_doubling = true;
            var bd = b;
            for (0..60) |_| {
                bd /= 2.0;
                ndouble += 1;
                if (a_eff * bd < controls.threshold_doubl) break;
            }
            b_start = bd;
        }

        const exponent_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var E = basis.Vec.zero(geo.nmutot);
        for (0..geo.nmutot) |imu| {
            E.data[imu] = math.exp(-b_start / @max(geo.u[imu], 1.0e-12));
        }
        if (profile_enabled) profile_sample.exponent_ns += std.time.nanoTimestamp() - exponent_start;

        const single_scatter_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        var R = singleScatterR(a, &E, &z.Zmin, geo);
        var T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
        if (profile_enabled) profile_sample.single_scatter_ns += std.time.nanoTimestamp() - single_scatter_start;

        if (use_doubling) {
            profile_sample.doubling_count += 1;
            if (i_fourier == 0 and controls.renorm_phase_function) {
                const renorm_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
                renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
                if (profile_enabled) profile_sample.renorm_ns += std.time.nanoTimestamp() - renorm_start;
                const renorm_scatter_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
                R = singleScatterR(a, &E, &z.Zmin, geo);
                T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
                if (profile_enabled) profile_sample.single_scatter_ns += std.time.nanoTimestamp() - renorm_scatter_start;
            }
            const doubling_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
            doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E, if (profile_enabled) &profile_sample else null);
            if (profile_enabled) profile_sample.doubling_ns += std.time.nanoTimestamp() - doubling_start;
        }

        const store_start = if (profile_enabled) std.time.nanoTimestamp() else 0;
        rt[rt_idx].R = R;
        rt[rt_idx].T = T;
        if (rt_active) |active| active[rt_idx] = a != 0.0;
        if (profile_enabled) profile_sample.store_ns += std.time.nanoTimestamp() - store_start;
    }

    if (active_profile) |profiler| profiler.addSample(profile_sample);
}

fn zeroLayerRt(n: usize) LayerRT {
    return .{
        .R = basis.Mat.zero(n),
        .T = basis.Mat.zero(n),
    };
}

pub fn calcRTlayersInto(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
) void {
    const plm_basis = basis.FourierPlmBasis.init(
        i_fourier,
        maxLayerPhaseCoefficientIndex(layers),
        geo,
    );
    calcRTlayersIntoWithBasis(
        rt,
        layers,
        i_fourier,
        geo,
        controls,
        &plm_basis,
        null,
        null,
        null,
        null,
    );
}

pub fn calcRTlayers(
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
) [attenuation.AttenArray.max_levels]LayerRT {
    var rt: [attenuation.AttenArray.max_levels]LayerRT = undefined;
    calcRTlayersInto(rt[0 .. layers.len + 1], layers, i_fourier, geo, controls);
    return rt;
}

pub fn fillSurface(
    i_fourier: usize,
    albedo: f64,
    geo: *const basis.Geometry,
) LayerRT {
    const n = geo.nmutot;
    var result: LayerRT = .{
        .R = basis.Mat.zero(n),
        .T = basis.Mat.zero(n),
    };

    if (i_fourier == 0) {
        for (0..n) |j| {
            for (0..n) |i| {
                result.R.set(i, j, geo.w[i] * albedo * geo.w[j]);
            }
        }
    }

    return result;
}
