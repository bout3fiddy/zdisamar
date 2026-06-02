const std = @import("std");
const math = std.math;
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../root.zig");
const Telemetry = @import("../../calculation_telemetry.zig");
const Perturbation = @import("../../perturbation_sensitivity.zig");
const Trace = @import("../../performance_trace.zig");

// layers.zig -------------------------------------------------------------------------------------------------|
// LABOS layer matrix builder. Layer optical properties and phase coefficients become RT_fc R/T matrices.      |
//                                                                                                             |
// called by                                                                                                   |
//   execute.zig builds RT_fc once per retained Fourier term before scattering-order transport                 |
//                                                                                                             |
// main paths                                                                                                  |
//   calcRTlayersIntoWithBasis                                                                                 |
//     -> skip inactive Fourier/layer combinations                                                             |
//     -> build Zplus/Zmin phase matrices                                                                      |
//     -> classify layer doubling                                                                              |
//     -> fill single-scatter R/T                                                                              |
//     -> optional layer doubling                                                                              |
//                                                                                                             |
//   doDouble / doDouble12x10                                                                                  |
//     -> repeated two-sublayer doubling with q-series gates and matrix products                               |
//                                                                                                             |
//   calcRTlayersTangentIntoWithBasis                                                                          |
//     -> central-difference RT layer derivative for one Jacobian state                                        |
//                                                                                                             |
// DISAMAR names                                                                                               |
//   RT_fc : layer reflection/transmission matrices for one Fourier term                                       |
//   R     : layer reflection matrix                                                                           |
//   T     : layer transmission matrix                                                                         |
//   E     : direct attenuation through the current layer                                                      |
//   Zplus/Zmin : phase kernels used by transmission/reflection single scatter                                 |
//                                                                                                             |
// numbers                                                                                                     |
//   phase_normalization_floor keeps phase normalization divisions finite                                      |
//   empty_layer_optical_depth_floor treats vanishing optical depth as inactive                                |
//   layer_direction_cosine_floor keeps exp(-tau / mu) finite for grazing directions                           |
//   tangent_step is the central-difference step for layer RT derivatives                                      |
// ------------------------------------------------------------------------------------------------------------|

const phase_normalization_floor: f64 = 1.0e-30;
const empty_layer_optical_depth_floor: f64 = 1.0e-20;
const layer_direction_cosine_floor: f64 = 1.0e-12;
const tangent_step: f64 = 1.0e-5;

const phase_odd_reciprocal = build_phase_odd_reciprocal: {
    var values: [basis.max_phase_coef]f64 = undefined;
    for (&values, 0..) |*value, idx| {
        const idx_f: f64 = @floatFromInt(idx);
        value.* = 1.0 / (2.0 * idx_f + 1.0);
    }
    break :build_phase_odd_reciprocal values;
};

pub const LayerRT = basis.LayerRT;

fn locateLowerIndex(values: []const f64, target: f64) usize {
    // locateLowerIndex ---------------------------------------------------------------------------------------|
    // Return the largest index whose next value is still below target.                                        |
    // Used to place viewing/solar directions between neighboring Gaussian directions.                         |
    // --------------------------------------------------------------------------------------------------------|

    if (values.len <= 1) return 0;

    var index: usize = 0;
    while (index + 1 < values.len and values[index + 1] < target) : (index += 1) {}

    return index;
}

pub fn zeroFourierIntegral(
    zplus: *const basis.Mat,
    zmin: *const basis.Mat,
    geo: *const basis.Geometry,
    column_index: usize,
) f64 {
    // zeroFourierIntegral ------------------------------------------------------------------------------------|
    // Integrate one zero-Fourier phase column over the Gaussian streams.                                      |
    // Re-exported via labos/internal.zig for tests.                                                           |
    //                                                                                                         |
    // The phase rows are stored with stream weights folded in. Divide by the row and column weights before    |
    // summing with Gaussian quadrature weights.                                                               |
    //                                                                                                         |
    // math                                                                                                    |
    //   integral += wg_mu * (Zplus[mu,col] + Zmin[mu,col]) / (w_mu * w_col)                                   |
    // --------------------------------------------------------------------------------------------------------|

    const column_weight = @max(geo.w[column_index], phase_normalization_floor);
    var integral: f64 = 0.0;

    for (0..geo.n_gauss) |imu| {
        const row_weight = @max(geo.w[imu], phase_normalization_floor);

        integral += geo.wg[imu] *
            ((zplus.get(imu, column_index) + zmin.get(imu, column_index)) /
                (row_weight * column_weight));
    }

    return integral;
}

pub fn renormalizeZeroFourierPhaseKernel(
    geo: *const basis.Geometry,
    zplus: *basis.Mat,
    zmin: *basis.Mat,
) void {
    // renormalizeZeroFourierPhaseKernel ----------------------------------------------------------------------|
    // Adjust zero-Fourier phase rows so their Gaussian integral is 2.                                         |
    // Re-exported via labos/internal.zig for tests.                                                           |
    //                                                                                                         |
    // Steps:                                                                                                  |
    //   1. copy Zplus into a weight-normalized work table                                                     |
    //   2. fix Gaussian columns directly on their diagonal                                                    |
    //   3. fix viewing/solar columns by interpolating between neighboring Gaussian directions                 |
    //   4. write the weight factors back into Zplus                                                           |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : optional zero-Fourier phase preparation before RT layer construction                       |
    //   memory   : stack work table sized by max_nmutot                                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   integral_mu (Zplus + Zmin) = 2                                                                        |
    // --------------------------------------------------------------------------------------------------------|

    if (geo.n_gauss == 0 or geo.nmutot == 0) return;

    var zp = [_][basis.max_nmutot]f64{.{0.0} ** basis.max_nmutot} ** basis.max_nmutot;

    for (0..geo.nmutot) |imu0| {
        const column_weight = @max(geo.w[imu0], phase_normalization_floor);
        for (0..geo.nmutot) |imu| {
            const row_weight = @max(geo.w[imu], phase_normalization_floor);
            zp[imu][imu0] = zplus.data[imu * zplus.n + imu0] / (row_weight * column_weight);
        }
    }

    for (0..geo.n_gauss) |imu0| {
        var integral: f64 = 0.0;

        for (0..geo.n_gauss) |imu| {
            const row_weight = @max(geo.w[imu], phase_normalization_floor);
            const column_weight = @max(geo.w[imu0], phase_normalization_floor);
            const zmin_weighted = zmin.data[imu * zmin.n + imu0] / (row_weight * column_weight);
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin_weighted);
        }

        const denominator = zp[imu0][imu0] * geo.wg[imu0];
        if (@abs(denominator) <= phase_normalization_floor) continue;

        const fraction = (2.0 - integral) / denominator;
        zp[imu0][imu0] *= 1.0 + fraction;
    }

    for (geo.n_gauss..geo.nmutot) |imu0| {
        const target_mu = geo.u[imu0];
        var integral: f64 = 0.0;

        for (0..geo.n_gauss) |imu| {
            const row_weight = @max(geo.w[imu], phase_normalization_floor);
            const column_weight = @max(geo.w[imu0], phase_normalization_floor);
            const zmin_weighted = zmin.data[imu * zmin.n + imu0] / (row_weight * column_weight);
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin_weighted);
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

            if (@abs(low_denominator) > phase_normalization_floor) {
                const fraction = low_weight * delta / low_denominator;
                zp[imu0][low] *= 1.0 + fraction;
                zp[low][imu0] = zp[imu0][low];
            }

            if (@abs(high_denominator) > phase_normalization_floor) {
                const fraction = high_weight * delta / high_denominator;
                zp[imu0][high] *= 1.0 + fraction;
                zp[high][imu0] = zp[imu0][high];
            }
            continue;
        }

        const edge = if (target_mu < geo.ug[0]) 0 else geo.n_gauss - 1;
        const denominator = zp[imu0][edge] * geo.wg[edge];
        if (@abs(denominator) <= phase_normalization_floor) continue;

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

fn fillSingleScatterR(
    out: *basis.Mat,
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // fillSingleScatterR -------------------------------------------------------------------------------------|
    // Single-scattering reflection for one homogeneous layer.                                                 |
    //                                                                                                         |
    // Fixed n=12 uses the unrolled helper below. Other stream counts use the same row-major formula.          |
    //                                                                                                         |
    // math                                                                                                    |
    //   R[i,j] = omega * Zmin[i,j] * (1 - E[i] * E[j]) * dmu_plus[i,j]                                        |
    //                                                                                                         |
    // omega : single-scatter albedo                                                                           |
    // E     : direct attenuation through the layer                                                            |
    // --------------------------------------------------------------------------------------------------------|

    const n = geo.nmutot;
    if (n == 12) return fillSingleScatterR12(out, a, E, Zmin, geo);

    out.* = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;

        for (0..n) |i| {
            const eer = E.data[i] * ej;
            out.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += n;
        }
    }
}

fn fillSingleScatterR12(
    out: *basis.Mat,
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // fillSingleScatterR12 -----------------------------------------------------------------------------------|
    // Fixed 12x12 reflection fill.                                                                            |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;

        inline for (0..12) |i| {
            const eer = E.data[i] * ej;
            out.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += 12;
        }
    }
}

fn fillSingleScatterT(
    out: *basis.Mat,
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // fillSingleScatterT -------------------------------------------------------------------------------------|
    // Single-scattering transmission for one homogeneous layer.                                               |
    //                                                                                                         |
    // Fixed n=12 uses the unrolled helper below. Other stream counts use the same row-major formula.          |
    //                                                                                                         |
    // math                                                                                                    |
    //   T[i,j] = omega * Zplus[i,j] * eet[i,j] * dmu_min[i,j]                                                 |
    //                                                                                                         |
    //   eet[i,j] = tau_start * E[i]     when mu_i and mu_j are effectively the same                           |
    //            = E[i] - E[j]          otherwise                                                             |
    // --------------------------------------------------------------------------------------------------------|

    const n = geo.nmutot;
    if (n == 12) return fillSingleScatterT12(out, a, b, E, Zplus, geo);

    out.* = basis.Mat.zero(n);

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
            out.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += n;
        }
    }
}

fn fillSingleScatterT12(
    out: *basis.Mat,
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // fillSingleScatterT12 -----------------------------------------------------------------------------------|
    // Fixed 12x12 transmission fill.                                                                          |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = basis.Mat{ .data = undefined, .n = 12 };

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
            out.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += 12;
        }
    }
}

fn gaussTrace(n: usize, n_gauss: usize, mat: *const basis.Mat) f64 {
    // gaussTrace ---------------------------------------------------------------------------------------------|
    // Sum the diagonal of the Gaussian block.                                                                 |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 uses literal row-major diagonal indexes: k*12 + k = 13*k.                        |
    // Generic stream counts use k*n + k.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

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

inline fn squareAttenuation(n: usize, E: *basis.Vec) void {
    // squareAttenuation --------------------------------------------------------------------------------------|
    // One doubling step turns half-layer attenuation into full-layer attenuation: E <- E * E.                 |
    // --------------------------------------------------------------------------------------------------------|

    if (n == basis.max_nmutot) return squareAttenuation12(E);

    for (0..n) |imu| {
        const e = E.data[imu];
        E.data[imu] = e * e;
    }
}

inline fn squareAttenuation12(E: *basis.Vec) void {
    // squareAttenuation12 ------------------------------------------------------------------------------------|
    // Fixed 12-direction attenuation square for the LABOS O2 A route.                                         |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..basis.max_nmutot) |imu| {
        const e = E.data[imu];
        E.data[imu] = e * e;
    }
}

fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    thresholds: common.RadiativeTransferPerformanceThresholds,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
) void {
    // doDouble -----------------------------------------------------------------------------------------------|
    // Dynamic-shape LABOS layer doubling for one layer and Fourier term. Steps:                               |
    //                                                                                                         |
    //   1. choose whether Q = inverse(I - R*R) - I is needed                                                  |
    //   2. build D from Q/E/T, or reuse T when Q is skipped                                                   |
    //   3. build U from R/E/D                                                                                 |
    //   4. update R and T through thresholded matrix products                                                 |
    //   5. square E for the next doubling step                                                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every selected layer-doubling step                                                         |
    //   costly   : q-series solve                                                                             |
    //              small matrix products                                                                      |
    //              R/T scratch swaps                                                                          |
    //   memory   : two scratch matrices for next R/T plus one temporary D                                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   each step combines two identical sublayers into one thicker layer                                     |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   traces which doubling steps keep Q/R-D/T-U/T-D matrix products and which steps use cheaper paths      |
    //   telemetry records the threshold margins behind those skip decisions                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (n == basis.max_nmutot and n_gauss == basis.max_gauss) {
        doDouble12x10(ndouble, thresholds, R, T, E, i_fourier, layer_index, phase_max_index);
        return;
    }

    const threshold_mul = thresholds.threshold_mul;

    var r_storage: basis.Mat = undefined;
    var t_storage: basis.Mat = undefined;
    var current_r = R;
    var current_t = T;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..ndouble) |doubling_step_index| {

        // instrumentation: trace counter: doubling steps -----------------------------------------------------|
        // captures: layer-doubling iterations                                                                 |
        // why: count the repeated matrix squaring work per layer/Fourier term.                                |
        Trace.plotU("doubling_steps", 1);
        // end instrumentation: trace counter: doubling steps -------------------------------------------------|

        const trace_r = gaussTrace(n, n_gauss, current_r);
        const trace_t = gaussTrace(n, n_gauss, current_t);

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: q-series feedback cutoff                                                                  |
        // Treat Q as zero when trace(R)^2 is below threshold_mul.                                             |
        // ----------------------------------------------------------------------------------------------------|
        // Q = inverse(I - R*R) - I is the feedback correction for repeated reflection inside the doubled      |
        // layer. Building Q costs matrix products and a q-series solve. If trace(R)^2 is tiny, this branch    |
        // reuses T as D and drops that small feedback term for this step.                                     |
        //                                                                                                     |
        // threshold_mul = 1.0e-12 by generic default and 1.0e-8 in the O2 A route. Lower values keep more     |
        // Q work; higher values skip more. Research note 10 measured this early check moving forward time     |
        // from 2.224609 s to 2.136820 s by avoiding q-series work before the expensive solve.                 |

        // instrumentation: telemetry and perturbation: q-series skip -----------------------------------------|
        // captures: q-series skip decision from trace(R)^2                                                    |
        // why: test whether Q work is negligible at this layer/Fourier/step.                                  |
        const coord = Perturbation.Coord{
            .layer_index = @intCast(layer_index),
            .fourier_index = @intCast(i_fourier),
            .order_index = @intCast(doubling_step_index),
        };
        const q_is_zero = Perturbation.decision(
            .qseries_skip,
            coord,
            @abs(trace_r * trace_r) <= threshold_mul,
        );
        // end instrumentation: telemetry and perturbation: q-series skip -------------------------------------|

        // instrumentation: calculation telemetry: q-series skip ----------------------------------------------|
        // captures: q-series skip inputs and decision                                                         |
        // why: record the trace-based threshold margin behind avoidable Q products.                           |
        Telemetry.labosDoublingStep(
            i_fourier,
            layer_index,
            phase_max_index,
            doubling_step_index,
            trace_r,
            trace_t,
            threshold_mul,
            q_is_zero,
        );
        // end instrumentation: calculation telemetry: q-series skip ------------------------------------------|

        var d_storage: basis.Mat = undefined;
        const D = choose_doubling_d: {
            if (q_is_zero) {

                // instrumentation: trace counter: q-series skipped -------------------------------------------|
                // captures: q-series products skipped by threshold                                            |
                // why: quantify actual savings from the q-zero path.                                          |
                Trace.plotU("doubling_qseries_skipped", 1);
                // end instrumentation: trace counter: q-series skipped ---------------------------------------|

                break :choose_doubling_d current_t;
            }

            // instrumentation: trace counters: q-series retained ---------------------------------------------|
            // captures: nonzero q-series and matrix-product work                                              |
            // why: connect q-series decisions to retained arithmetic volume.                                  |
            Trace.plotU("doubling_qseries_nonzero", 1);
            Trace.plotU("matrix_qseries", 1);
            Trace.plotU("matrix_smul_q_product", 1);
            Trace.plotU("matrix_smul_add_semul3", 1);
            // end instrumentation: trace counters: q-series retained -----------------------------------------|

            var Q: basis.Mat = undefined;
            basis.qseriesKnownNonzeroProductInto(&Q, n, n_gauss, current_r, current_r);
            basis.smulAddSemul3KnownRightTraceInto(&d_storage, n, n_gauss, threshold_mul, &Q, E, current_t, trace_t);
            break :choose_doubling_d &d_storage;
        };
        // end tradeoff: q-series feedback cutoff -------------------------------------------------------------|

        const trace_d = if (q_is_zero) trace_t else gaussTrace(n, n_gauss, D);

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: R-D product cutoff                                                                        |
        // Skip the R-D product when its trace estimate is below threshold_mul.                                |
        // ----------------------------------------------------------------------------------------------------|
        // U normally receives a product term from R, E, and D. The trace test is a cheap proxy for whether    |
        // that product can change the layer update. If it is too small, the code uses the cheaper semul path  |
        // and leaves out the tiny R-D product.                                                                |
        //                                                                                                     |
        // The gate is abs(trace(R) * trace(D)) > threshold_mul. threshold_mul is 1.0e-12 by generic default   |
        // and 1.0e-8 in O2 A. qzero_rd_product_suppression defaults to false; the perturbation report         |
        // forced this q-zero skip in 563,874 / 24,518,833 hits and measured max reflectance delta 1.050e-06.  |

        // instrumentation: trace counter: R-D gate -----------------------------------------------------------|
        // captures: R-D product gate evaluations                                                              |
        // why: count downstream product checks after q-series handling.                                       |
        Trace.plotU("matrix_smul_rd", 1);
        // end instrumentation: trace counter: R-D gate -------------------------------------------------------|

        // instrumentation: perturbation context: downstream gates --------------------------------------------|
        // captures: layer/Fourier/doubling coordinate shared by R-D, T-U, and T-D gates                       |
        // why: keep the three downstream product experiments on the same coordinate.                          |
        const downstream_coord = Perturbation.Coord{
            .layer_index = @intCast(layer_index),
            .fourier_index = @intCast(i_fourier),
            .order_index = @intCast(doubling_step_index),
            .branch = if (q_is_zero) 1 else 0,
        };
        // end instrumentation: perturbation context: downstream gates ----------------------------------------|

        // instrumentation: perturbation: R-D product gate ----------------------------------------------------|
        // captures: R-D product retention decision                                                            |
        // why: test whether q-zero branches can skip this product without meaningful output movement.         |
        const rd_nonzero = Perturbation.decision(
            .qseries_rd_product,
            downstream_coord,
            !(q_is_zero and thresholds.qzero_rd_product_suppression) and
                @abs(trace_r * trace_d) > threshold_mul,
        );
        // end instrumentation: perturbation: R-D product gate ------------------------------------------------|

        var U: basis.Mat = undefined;
        if (rd_nonzero) {

            // instrumentation: trace counters: R-D retained --------------------------------------------------|
            // captures: retained R-D product and semul-add work                                               |
            // why: measure matrix products not skipped by downstream gates.                                   |
            Trace.plotU("matrix_smul_rd_nonzero", 1);
            Trace.plotU("matrix_semul_add", 1);
            // end instrumentation: trace counters: R-D retained ----------------------------------------------|

            basis.semulAddProductKnownNonzeroInto(&U, n, n_gauss, current_r, E, D);
        } else {

            // instrumentation: trace counter: R-D skipped ----------------------------------------------------|
            // captures: simplified semul path                                                                 |
            // why: count cheaper fallback operations when R-D is negligible.                                  |
            Trace.plotU("matrix_semul", 1);
            // end instrumentation: trace counter: R-D skipped ------------------------------------------------|

            basis.semulInto(&U, n, current_r, E);
        }
        // end tradeoff: R-D product cutoff -------------------------------------------------------------------|

        const trace_u = gaussTrace(n, n_gauss, &U);

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: T-U product cutoff                                                                        |
        // Skip the expensive R update product when the T-U trace estimate is below threshold_mul.             |
        // ----------------------------------------------------------------------------------------------------|
        // This update feeds reflected light after the new U field has been built. If trace(T) * trace(U) is   |
        // tiny, the code uses a scale/add update and drops the small T-U product.                             |
        //                                                                                                     |
        // The gate is abs(trace(T) * trace(U)) > threshold_mul. threshold_mul is 1.0e-12 by generic default   |
        // and 1.0e-8 in O2 A. qzero_tu_product_suppression defaults to false; the perturbation report         |
        // forced this q-zero skip in 396,775 / 24,518,833 hits and measured max reflectance delta 1.002e-06.  |

        // instrumentation: trace counter: T-U gate -----------------------------------------------------------|
        // captures: T-U product gate evaluations                                                              |
        // why: count reflectance-update product checks after U construction.                                  |
        Trace.plotU("matrix_smul_tu", 1);
        // end instrumentation: trace counter: T-U gate -------------------------------------------------------|

        // instrumentation: perturbation: T-U product gate ----------------------------------------------------|
        // captures: T-U product retention decision                                                            |
        // why: test whether q-zero branches can skip this reflectance update product.                         |
        const tu_nonzero = Perturbation.decision(
            .qseries_tu_product,
            downstream_coord,
            !(q_is_zero and thresholds.qzero_tu_product_suppression) and
                @abs(trace_t * trace_u) > threshold_mul,
        );
        // end instrumentation: perturbation: T-U product gate ------------------------------------------------|

        if (tu_nonzero) {

            // instrumentation: trace counters: T-U retained --------------------------------------------------|
            // captures: retained T-U product and full R update work                                           |
            // why: measure when reflectance doubling needs the expensive update.                              |
            Trace.plotU("matrix_smul_tu_nonzero", 1);
            Trace.plotU("matrix_mat_add_esmul3", 1);
            // end instrumentation: trace counters: T-U retained ----------------------------------------------|

            basis.matAddEsmul3ProductKnownNonzeroInto(next_r, n, n_gauss, current_r, E, &U, current_t);
        } else {

            // instrumentation: trace counter: T-U skipped ----------------------------------------------------|
            // captures: simplified R update path                                                              |
            // why: count cheaper reflectance updates when T-U is negligible.                                  |
            Trace.plotU("matrix_mat_add_esmul", 1);
            // end instrumentation: trace counter: T-U skipped ------------------------------------------------|

            basis.matAddEsmulInto(next_r, n, current_r, E, &U);
        }
        // end tradeoff: T-U product cutoff -------------------------------------------------------------------|

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: T-D product cutoff                                                                        |
        // Skip the expensive T update product when the T-D trace estimate is below threshold_mul.             |
        // ----------------------------------------------------------------------------------------------------|
        // This update feeds transmission through the doubled layer. If trace(T) * trace(D) is tiny, the code  |
        // uses the cheaper transmission update and drops the small T-D product.                               |
        //                                                                                                     |
        // The gate is abs(trace(T) * trace(D)) > threshold_mul. threshold_mul is 1.0e-12 by generic default   |
        // and 1.0e-8 in O2 A. qzero_td_product_suppression defaults to false; the perturbation report         |
        // forced this q-zero skip in 1,143,287 / 24,518,666 hits and measured max reflectance delta           |
        // 3.540e-06.                                                                                          |

        // instrumentation: trace counter: T-D gate -----------------------------------------------------------|
        // captures: T-D product gate evaluations                                                              |
        // why: count transmission-update product checks after q-series handling.                              |
        Trace.plotU("matrix_smul_td", 1);
        // end instrumentation: trace counter: T-D gate -------------------------------------------------------|

        // instrumentation: perturbation: T-D product gate ----------------------------------------------------|
        // captures: T-D product retention decision                                                            |
        // why: test whether q-zero branches can skip this transmission update product.                        |
        const td_nonzero = Perturbation.decision(
            .qseries_td_product,
            downstream_coord,
            !(q_is_zero and thresholds.qzero_td_product_suppression) and
                @abs(trace_t * trace_d) > threshold_mul,
        );
        // end instrumentation: perturbation: T-D product gate ------------------------------------------------|

        // instrumentation: calculation telemetry: downstream gates -------------------------------------------|
        // captures: downstream R-D/T-U/T-D threshold margins                                                  |
        // why: record which matrix products were retained after q-zero decisions.                             |
        Telemetry.labosDoublingDownstreamGates(
            i_fourier,
            layer_index,
            phase_max_index,
            doubling_step_index,
            q_is_zero,
            trace_r,
            trace_t,
            trace_d,
            trace_u,
            threshold_mul,
            rd_nonzero,
            tu_nonzero,
            td_nonzero,
        );
        // end instrumentation: calculation telemetry: downstream gates ---------------------------------------|

        if (q_is_zero) {
            if (td_nonzero) {

                // instrumentation: trace counters: self transmission retained --------------------------------|
                // captures: retained self transmission update under q-zero                                    |
                // why: measure remaining matrix work when Q itself was skipped.                               |
                Trace.plotU("matrix_smul_td_nonzero", 1);
                Trace.plotU("matrix_esmul_semul_add", 1);
                // end instrumentation: trace counters: self transmission retained ----------------------------|

                basis.esmulSemulSelfAddProductKnownNonzeroInto(next_t, n, n_gauss, E, current_t);
            } else {

                // instrumentation: trace counter: self transmission skipped ----------------------------------|
                // captures: simplified self transmission update under q-zero                                  |
                // why: count cheaper transmission updates when T-D is negligible.                             |
                Trace.plotU("matrix_esmul_semul", 1);
                // end instrumentation: trace counter: self transmission skipped ------------------------------|

                basis.esmulSemulSelfInto(next_t, n, E, current_t);
            }
        } else {
            if (td_nonzero) {

                // instrumentation: trace counters: transmission retained -------------------------------------|
                // captures: retained transmission update with D product                                       |
                // why: measure matrix work when both Q and T-D are nonzero.                                   |
                Trace.plotU("matrix_smul_td_nonzero", 1);
                Trace.plotU("matrix_esmul_semul_add", 1);
                // end instrumentation: trace counters: transmission retained ---------------------------------|

                basis.esmulSemulAddProductKnownNonzeroInto(next_t, n, n_gauss, E, D, current_t);
            } else {

                // instrumentation: trace counter: transmission skipped ---------------------------------------|
                // captures: simplified transmission update with D                                             |
                // why: count cheaper updates when the final product is negligible.                            |
                Trace.plotU("matrix_esmul_semul", 1);
                // end instrumentation: trace counter: transmission skipped -----------------------------------|

                basis.esmulSemulInto(next_t, n, E, D, current_t);
            }
        }
        // end tradeoff: T-D product cutoff -------------------------------------------------------------------|

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        // instrumentation: trace counter: attenuation square -------------------------------------------------|
        // captures: attenuation squaring width                                                                |
        // why: tie doubling cost to stream dimension.                                                         |
        Trace.plotU("doubling_square_evals", @intCast(n));
        // end instrumentation: trace counter: attenuation square ---------------------------------------------|

        squareAttenuation(n, E);
    }

    if (final_in_scratch) {
        R.* = current_r.*;
        T.* = current_t.*;
    }
}

fn doDouble12x10(
    ndouble: usize,
    thresholds: common.RadiativeTransferPerformanceThresholds,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
) void {
    // doDouble12x10 ------------------------------------------------------------------------------------------|
    // Fixed 12x10 layer doubling for the O2 A LABOS route. Steps:                                             |
    //                                                                                                         |
    //   1. run one fixed-shape doubling step                                                                  |
    //   2. swap current and next R/T scratch matrices                                                         |
    //   3. square E for the next doubling step                                                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : selected layer-doubling steps in the fixed O2 A route                                      |
    //   costly   : q-series products and fixed-shape matrix kernels                                           |
    //   memory   : two scratch matrices reused by pointer swapping                                            |
    //                                                                                                         |
    // calls                                                                                                   |
    //   doDouble12x10Step                                                                                     |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   counts fixed-shape doubling steps and the attenuation squaring done between steps                     |
    // --------------------------------------------------------------------------------------------------------|

    var r_storage: basis.Mat = undefined;
    var t_storage: basis.Mat = undefined;
    var current_r = R;
    var current_t = T;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..ndouble) |doubling_step_index| {

        // instrumentation: trace counter: fixed doubling steps -----------------------------------------------|
        // captures: fixed 12x10 layer-doubling iterations                                                     |
        // why: count matrix squaring work in the specialized hot path.                                        |
        Trace.plotU("doubling_steps", 1);
        // end instrumentation: trace counter: fixed doubling steps -------------------------------------------|

        doDouble12x10Step(
            thresholds,
            current_r,
            current_t,
            E,
            next_r,
            next_t,
            i_fourier,
            layer_index,
            phase_max_index,
            doubling_step_index,
        );

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        // instrumentation: trace counter: fixed attenuation square -------------------------------------------|
        // captures: fixed 12x10 attenuation square evaluations                                                |
        // why: tie specialized doubling cost to the full stream width.                                        |
        Trace.plotU("doubling_square_evals", basis.max_nmutot);
        // end instrumentation: trace counter: fixed attenuation square ---------------------------------------|

        squareAttenuation12(E);
    }

    if (final_in_scratch) {
        R.* = current_r.*;
        T.* = current_t.*;
    }
}

inline fn doDouble12x10Step(
    thresholds: common.RadiativeTransferPerformanceThresholds,
    current_r: *const basis.Mat,
    current_t: *const basis.Mat,
    E: *const basis.Vec,
    next_r: *basis.Mat,
    next_t: *basis.Mat,
    i_fourier: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
) void {
    // doDouble12x10Step --------------------------------------------------------------------------------------|
    // One fixed 12x10 doubling step.                                                                          |
    //                                                                                                         |
    // This mirrors doDouble, but every matrix call goes through the fixed-shape LABOS kernels.                |
    // The trace gates decide whether each expensive product is retained or replaced by a cheaper scale/add.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   Q = inverse(I - R*R) - I                                                                              |
    //   D = Q*E*T + T                 when Q is retained                                                      |
    //   D = T                         when Q is skipped                                                       |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   traces the same skip decisions as doDouble, but on the fixed 12x10 hot path                           |
    //   telemetry keeps the threshold margins beside the branch decisions                                     |
    // --------------------------------------------------------------------------------------------------------|

    const threshold_mul = thresholds.threshold_mul;
    const trace_r = gaussTrace(basis.max_nmutot, basis.max_gauss, current_r);
    const trace_t = gaussTrace(basis.max_nmutot, basis.max_gauss, current_t);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: fixed q-series feedback cutoff                                                                |
    // Treat Q as zero when trace(R)^2 is below threshold_mul in the fixed 12x10 path.                         |
    // --------------------------------------------------------------------------------------------------------|
    // This is the same cutoff used by doDouble, but the retained path calls fixed-shape matrix kernels.       |
    // Skipping Q avoids the q-series solve and later products for this hot O2 A shape. The cost is the same:  |
    // a very small repeated-reflection feedback term is left out for this doubling step.                      |
    //                                                                                                         |
    // threshold_mul = 1.0e-12 by generic default and 1.0e-8 in the O2 A route. Research note 10 measured the  |
    // same early q-series check moving forward time from 2.224609 s to 2.136820 s.                            |

    // instrumentation: telemetry and perturbation: fixed q-series skip ---------------------------------------|
    // captures: fixed-size q-series skip decision                                                             |
    // why: test the hot 12x10 doubling path without copying matrix payloads.                                  |
    const coord = Perturbation.Coord{
        .layer_index = @intCast(layer_index),
        .fourier_index = @intCast(i_fourier),
        .order_index = @intCast(doubling_step_index),
    };
    const q_is_zero = Perturbation.decision(
        .qseries_skip,
        coord,
        @abs(trace_r * trace_r) <= threshold_mul,
    );
    // end instrumentation: telemetry and perturbation: fixed q-series skip -----------------------------------|

    // instrumentation: calculation telemetry: fixed q-series skip --------------------------------------------|
    // captures: fixed-size q-series skip inputs and decision                                                  |
    // why: record threshold margins in the specialized hot path.                                              |
    Telemetry.labosDoublingStep(
        i_fourier,
        layer_index,
        phase_max_index,
        doubling_step_index,
        trace_r,
        trace_t,
        threshold_mul,
        q_is_zero,
    );
    // end instrumentation: calculation telemetry: fixed q-series skip ----------------------------------------|

    var d_storage: basis.Mat = undefined;
    const D = choose_fixed_doubling_d: {
        if (q_is_zero) {

            // instrumentation: trace counter: fixed q-series skipped -----------------------------------------|
            // captures: fixed-size q-series products skipped by threshold                                     |
            // why: quantify savings from q-zero specialization.                                               |
            Trace.plotU("doubling_qseries_skipped", 1);
            // end instrumentation: trace counter: fixed q-series skipped -------------------------------------|

            break :choose_fixed_doubling_d current_t;
        }

        // instrumentation: trace counters: fixed q-series retained -------------------------------------------|
        // captures: fixed-size nonzero q-series and matrix-product work                                       |
        // why: connect q-series decisions to retained arithmetic volume.                                      |
        Trace.plotU("doubling_qseries_nonzero", 1);
        Trace.plotU("matrix_qseries", 1);
        Trace.plotU("matrix_smul_q_product", 1);
        Trace.plotU("matrix_smul_add_semul3", 1);
        // end instrumentation: trace counters: fixed q-series retained ---------------------------------------|

        var Q: basis.Mat = undefined;
        basis.qseriesKnownNonzeroProductInto(&Q, basis.max_nmutot, basis.max_gauss, current_r, current_r);
        basis.smulAddSemul3KnownRightTraceInto(
            &d_storage,
            basis.max_nmutot,
            basis.max_gauss,
            threshold_mul,
            &Q,
            E,
            current_t,
            trace_t,
        );
        break :choose_fixed_doubling_d &d_storage;
    };
    // end tradeoff: fixed q-series feedback cutoff -----------------------------------------------------------|

    const trace_d = if (q_is_zero) trace_t else gaussTrace(basis.max_nmutot, basis.max_gauss, D);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: fixed R-D product cutoff                                                                      |
    // Skip the fixed-shape R-D product when its trace estimate is below threshold_mul.                        |
    // --------------------------------------------------------------------------------------------------------|
    // The fixed kernel is fast, but it is still a full 12x10 matrix operation. If the estimated product is    |
    // below the cutoff, the code uses the cheaper semul path and drops the tiny R-D contribution.             |
    //                                                                                                         |
    // The gate is abs(trace(R) * trace(D)) > threshold_mul. threshold_mul is 1.0e-12 by generic default and   |
    // 1.0e-8 in O2 A. qzero_rd_product_suppression defaults to false; the perturbation report forced this     |
    // q-zero skip in 563,874 / 24,518,833 hits and measured max reflectance delta 1.050e-06.                  |

    // instrumentation: trace counter: fixed R-D gate ---------------------------------------------------------|
    // captures: fixed-size R-D product gate evaluations                                                       |
    // why: count downstream product checks after q-series handling.                                           |
    Trace.plotU("matrix_smul_rd", 1);
    // end instrumentation: trace counter: fixed R-D gate -----------------------------------------------------|

    // instrumentation: perturbation context: fixed downstream gates ------------------------------------------|
    // captures: layer/Fourier/doubling coordinate shared by fixed R-D, T-U, and T-D gates                     |
    // why: keep the three fixed-product experiments on the same coordinate.                                   |
    const downstream_coord = Perturbation.Coord{
        .layer_index = @intCast(layer_index),
        .fourier_index = @intCast(i_fourier),
        .order_index = @intCast(doubling_step_index),
        .branch = if (q_is_zero) 1 else 0,
    };
    // end instrumentation: perturbation context: fixed downstream gates --------------------------------------|

    // instrumentation: perturbation: fixed R-D product gate --------------------------------------------------|
    // captures: fixed R-D product retention decision                                                          |
    // why: test whether q-zero branches can skip this hot-path product.                                       |
    const rd_nonzero = Perturbation.decision(
        .qseries_rd_product,
        downstream_coord,
        !(q_is_zero and thresholds.qzero_rd_product_suppression) and
            @abs(trace_r * trace_d) > threshold_mul,
    );
    // end instrumentation: perturbation: fixed R-D product gate ----------------------------------------------|

    var U: basis.Mat = undefined;
    if (rd_nonzero) {

        // instrumentation: trace counters: fixed R-D retained ------------------------------------------------|
        // captures: retained fixed-size R-D product and semul-add work                                        |
        // why: measure matrix products not skipped by downstream gates.                                       |
        Trace.plotU("matrix_smul_rd_nonzero", 1);
        Trace.plotU("matrix_semul_add", 1);
        // end instrumentation: trace counters: fixed R-D retained --------------------------------------------|

        basis.semulAddProductKnownNonzeroInto(&U, basis.max_nmutot, basis.max_gauss, current_r, E, D);
    } else {

        // instrumentation: trace counter: fixed R-D skipped --------------------------------------------------|
        // captures: simplified fixed-size semul path                                                          |
        // why: count cheaper fallback operations when R-D is negligible.                                      |
        Trace.plotU("matrix_semul", 1);
        // end instrumentation: trace counter: fixed R-D skipped ----------------------------------------------|

        basis.semulInto(&U, basis.max_nmutot, current_r, E);
    }
    // end tradeoff: fixed R-D product cutoff -----------------------------------------------------------------|

    const trace_u = gaussTrace(basis.max_nmutot, basis.max_gauss, &U);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: fixed T-U product cutoff                                                                      |
    // Skip the fixed-shape R update product when the T-U trace estimate is below threshold_mul.               |
    // --------------------------------------------------------------------------------------------------------|
    // This keeps the O2 A hot path on the cheaper update when the retained reflected-light product is too     |
    // small to matter at the configured cutoff. The cost is that the small T-U contribution is not added.     |
    //                                                                                                         |
    // The gate is abs(trace(T) * trace(U)) > threshold_mul. threshold_mul is 1.0e-12 by generic default and   |
    // 1.0e-8 in O2 A. qzero_tu_product_suppression defaults to false; the perturbation report forced this     |
    // q-zero skip in 396,775 / 24,518,833 hits and measured max reflectance delta 1.002e-06.                  |

    // instrumentation: trace counter: fixed T-U gate ---------------------------------------------------------|
    // captures: fixed-size T-U product gate evaluations                                                       |
    // why: count reflectance-update product checks after U construction.                                      |
    Trace.plotU("matrix_smul_tu", 1);
    // end instrumentation: trace counter: fixed T-U gate -----------------------------------------------------|

    // instrumentation: perturbation: fixed T-U product gate --------------------------------------------------|
    // captures: fixed T-U product retention decision                                                          |
    // why: test whether q-zero branches can skip this reflectance update product.                             |
    const tu_nonzero = Perturbation.decision(
        .qseries_tu_product,
        downstream_coord,
        !(q_is_zero and thresholds.qzero_tu_product_suppression) and
            @abs(trace_t * trace_u) > threshold_mul,
    );
    // end instrumentation: perturbation: fixed T-U product gate ----------------------------------------------|

    if (tu_nonzero) {

        // instrumentation: trace counters: fixed T-U retained ------------------------------------------------|
        // captures: retained fixed-size T-U product and R update work                                         |
        // why: measure when reflectance doubling needs the expensive update.                                  |
        Trace.plotU("matrix_smul_tu_nonzero", 1);
        Trace.plotU("matrix_mat_add_esmul3", 1);
        // end instrumentation: trace counters: fixed T-U retained --------------------------------------------|

        basis.matAddEsmul3ProductKnownNonzeroInto(
            next_r,
            basis.max_nmutot,
            basis.max_gauss,
            current_r,
            E,
            &U,
            current_t,
        );
    } else {

        // instrumentation: trace counter: fixed T-U skipped --------------------------------------------------|
        // captures: simplified fixed-size R update path                                                       |
        // why: count cheaper reflectance updates when T-U is negligible.                                      |
        Trace.plotU("matrix_mat_add_esmul", 1);
        // end instrumentation: trace counter: fixed T-U skipped ----------------------------------------------|

        basis.matAddEsmulInto(next_r, basis.max_nmutot, current_r, E, &U);
    }
    // end tradeoff: fixed T-U product cutoff -----------------------------------------------------------------|

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: fixed T-D product cutoff                                                                      |
    // Skip the fixed-shape T update product when the T-D trace estimate is below threshold_mul.               |
    // --------------------------------------------------------------------------------------------------------|
    // This keeps the transmission update on the cheaper path when the D-coupled product is below the cutoff.  |
    // The cost is that a tiny transmission contribution is not added for this doubled sublayer.               |
    //                                                                                                         |
    // The gate is abs(trace(T) * trace(D)) > threshold_mul. threshold_mul is 1.0e-12 by generic default and   |
    // 1.0e-8 in O2 A. qzero_td_product_suppression defaults to false; the perturbation report forced this     |
    // q-zero skip in 1,143,287 / 24,518,666 hits and measured max reflectance delta 3.540e-06.                |

    // instrumentation: trace counter: fixed T-D gate ---------------------------------------------------------|
    // captures: fixed-size T-D product gate evaluations                                                       |
    // why: count transmission-update product checks after q-series handling.                                  |
    Trace.plotU("matrix_smul_td", 1);
    // end instrumentation: trace counter: fixed T-D gate -----------------------------------------------------|

    // instrumentation: perturbation: fixed T-D product gate --------------------------------------------------|
    // captures: fixed T-D product retention decision                                                          |
    // why: test whether q-zero branches can skip this transmission update product.                            |
    const td_nonzero = Perturbation.decision(
        .qseries_td_product,
        downstream_coord,
        !(q_is_zero and thresholds.qzero_td_product_suppression) and
            @abs(trace_t * trace_d) > threshold_mul,
    );
    // end instrumentation: perturbation: fixed T-D product gate ----------------------------------------------|

    // instrumentation: calculation telemetry: fixed downstream gates -----------------------------------------|
    // captures: fixed-size downstream product threshold margins                                               |
    // why: record which matrix products were retained after q-zero decisions.                                 |
    Telemetry.labosDoublingDownstreamGates(
        i_fourier,
        layer_index,
        phase_max_index,
        doubling_step_index,
        q_is_zero,
        trace_r,
        trace_t,
        trace_d,
        trace_u,
        threshold_mul,
        rd_nonzero,
        tu_nonzero,
        td_nonzero,
    );
    // end instrumentation: calculation telemetry: fixed downstream gates -------------------------------------|

    if (q_is_zero) {
        if (td_nonzero) {

            // instrumentation: trace counters: fixed self transmission retained ------------------------------|
            // captures: retained fixed-size self transmission update under q-zero                             |
            // why: measure remaining matrix work when Q itself was skipped.                                   |
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            // end instrumentation: trace counters: fixed self transmission retained --------------------------|

            basis.esmulSemulSelfAddProductKnownNonzeroInto(next_t, basis.max_nmutot, basis.max_gauss, E, current_t);
        } else {

            // instrumentation: trace counter: fixed self transmission skipped --------------------------------|
            // captures: simplified fixed-size self transmission update under q-zero                           |
            // why: count cheaper transmission updates when T-D is negligible.                                 |
            Trace.plotU("matrix_esmul_semul", 1);
            // end instrumentation: trace counter: fixed self transmission skipped ----------------------------|

            basis.esmulSemulSelfInto(next_t, basis.max_nmutot, E, current_t);
        }
    } else {
        if (td_nonzero) {

            // instrumentation: trace counters: fixed transmission retained -----------------------------------|
            // captures: retained fixed-size transmission update with D product                                |
            // why: measure matrix work when both Q and T-D are nonzero.                                       |
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            // end instrumentation: trace counters: fixed transmission retained -------------------------------|

            basis.esmulSemulAddProductKnownNonzeroInto(next_t, basis.max_nmutot, basis.max_gauss, E, D, current_t);
        } else {

            // instrumentation: trace counter: fixed transmission skipped -------------------------------------|
            // captures: simplified fixed-size transmission update with D                                      |
            // why: count cheaper updates when the final product is negligible.                                |
            Trace.plotU("matrix_esmul_semul", 1);
            // end instrumentation: trace counter: fixed transmission skipped ---------------------------------|

            basis.esmulSemulInto(next_t, basis.max_nmutot, E, D, current_t);
        }
    }
    // end tradeoff: fixed T-D product cutoff -----------------------------------------------------------------|

}

fn maxLayerPhaseCoefficientIndex(layers: []const common.LayerInput) usize {
    // maxLayerPhaseCoefficientIndex --------------------------------------------------------------------------|
    // Highest phase coefficient used by any layer.                                                            |
    // --------------------------------------------------------------------------------------------------------|

    var max_index: usize = 0;

    for (layers) |*layer| {
        max_index = @max(max_index, layer.phase.maxIndex());
    }

    return max_index;
}

pub fn fillLayerPhaseMaxIndices(
    layer_phase_max_indices: []usize,
    layers: []const common.LayerInput,
) void {
    // fillLayerPhaseMaxIndices -------------------------------------------------------------------------------|
    // Store the highest active phase coefficient for each layer.                                              |
    //                                                                                                         |
    // Used by calcRTlayersIntoWithBasis to skip Fourier terms that a layer cannot support.                    |
    // --------------------------------------------------------------------------------------------------------|

    std.debug.assert(layer_phase_max_indices.len >= layers.len);

    for (layers, layer_phase_max_indices[0..layers.len]) |*layer, *max_index| {
        max_index.* = layer.phase.maxIndex();
    }
}

pub fn fillLayerEffectiveScatteringSuffixes(
    suffixes: []f64,
    layers: []const common.LayerInput,
    layer_phase_max_indices: []const usize,
    phase_stride: usize,
) void {
    // fillLayerEffectiveScatteringSuffixes -------------------------------------------------------------------|
    // Precompute effective scattering strength for each layer and Fourier order.                              |
    //                                                                                                         |
    // math                                                                                                    |
    //   suffix[m] = max over l>=m of abs(beta_l) / (2 * l + 1)                                                |
    //                                                                                                         |
    // beta_l : phase coefficient at order l                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    std.debug.assert(phase_stride > 0 and phase_stride <= basis.max_phase_coef);
    std.debug.assert(suffixes.len >= layers.len * phase_stride);

    for (layers, layer_phase_max_indices[0..layers.len], 0..) |*layer, max_phase_index, layer_idx| {
        const layer_suffixes = suffixes[layer_idx * phase_stride ..][0..phase_stride];
        @memset(layer_suffixes, 0.0);

        var suffix: f64 = 0.0;
        var reverse_index = max_phase_index + 1;

        while (reverse_index > 0) {
            reverse_index -= 1;

            const beta_eff = @abs(layer.phase.coefficient(reverse_index)) * phase_odd_reciprocal[reverse_index];
            suffix = @max(suffix, beta_eff);
            if (reverse_index < phase_stride) layer_suffixes[reverse_index] = suffix;
        }
    }
}

pub const LayerDoublingDecision = struct {
    start_optical_depth: f64,
    doubling_count: usize,
    uses_doubling: bool,
};

pub fn classifyLayerDoubling(
    scattering: common.ScatteringMode,
    threshold_doubl: f64,
    optical_depth: f64,
    effective_scattering_coefficient: f64,
    effective_scattering_depth: f64,
) LayerDoublingDecision {
    // classifyLayerDoubling ----------------------------------------------------------------------------------|
    // Choose whether a layer needs doubling, and how thin the starting layer should be.                       |
    //                                                                                                         |
    // No doubling is needed unless multiple scattering is enabled and effective scattering depth crosses the  |
    // configured threshold. The starting layer is then thinned until one doubling chain lands back at the     |
    // original optical depth.                                                                                 |
    // --------------------------------------------------------------------------------------------------------|

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: layer doubling threshold                                                                      |
    // Skip layer doubling when the scaled scattering thickness is below threshold_doubl.                      |
    // --------------------------------------------------------------------------------------------------------|
    // Doubling is the expensive multiple-scattering correction inside one layer. For weakly scattering        |
    // layers, this branch keeps the single-scatter layer and avoids the repeated matrix squaring.             |
    // The cost is that very small intra-layer multiple-scattering feedback is not added.                      |
    //                                                                                                         |
    // threshold_doubl = 0.1 by generic default and 1.0e-6 in O2 A. The fastmode research example uses         |
    // 3.0e-5. Lower values double more layers. The current forward trace recorded 1,075,939 doubled layers    |
    // and 8,389,666 doubling steps, so this threshold controls a large amount of work.                        |
    if (scattering != .multiple or !(effective_scattering_depth > threshold_doubl)) {
        return .{
            .start_optical_depth = optical_depth,
            .doubling_count = 0,
            .uses_doubling = false,
        };
    }
    // end tradeoff: layer doubling threshold -----------------------------------------------------------------|

    const ratio = effective_scattering_depth / threshold_doubl;
    const exponent = math.ilogb(ratio);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: maximum doubling depth                                                                        |
    // Cap the number of layer splits at 60 so extreme inputs cannot create an unbounded doubling chain.       |
    // --------------------------------------------------------------------------------------------------------|
    // Each extra split halves the starting optical depth and adds another matrix-squaring step. The hard cap  |
    // is 60 splits. It is far beyond normal LABOS layers, but still matters as a hard stop for pathological   |
    // inputs. If an extreme layer still fails threshold_doubl after 60 splits, the solver uses the best       |
    // capped split count instead of spending unbounded time chasing a thinner starting layer.                 |
    var count_i32: i32 = if (exponent >= 60) 60 else @max(1, exponent + 1);
    var count: usize = @intCast(count_i32);
    var start = math.ldexp(optical_depth, -count_i32);

    // Try one fewer split while the previous starting layer is still below the threshold.
    while (count > 1) {
        const previous_count_i32 = count_i32 - 1;
        const previous_start = math.ldexp(optical_depth, -previous_count_i32);
        if (effective_scattering_coefficient * previous_start >= threshold_doubl) break;
        count_i32 = previous_count_i32;
        count -= 1;
        start = previous_start;
    }

    // Add splits until the starting layer is safely below the threshold.
    while (count < 60 and effective_scattering_coefficient * start >= threshold_doubl) {
        start *= 0.5;
        count += 1;
    }
    // end tradeoff: maximum doubling depth -------------------------------------------------------------------|

    return .{
        .start_optical_depth = start,
        .doubling_count = count,
        .uses_doubling = true,
    };
}

pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_max_indices: ?[]const usize,
    layer_effective_scattering_suffixes: ?[]const f64,
    layer_effective_scattering_suffix_stride: usize,
    phase_row_cache: ?[]basis.PhaseKernelRow,
    phase_row_valid: ?[]bool,
    rt_active: ?[]bool,
) void {
    // calcRTlayersIntoWithBasis ------------------------------------------------------------------------------|
    // Build LABOS RT_fc layer matrices for one Fourier term. Steps:                                           |
    //                                                                                                         |
    //   1. skip layers that cannot contribute to this Fourier term                                            |
    //   2. build Zplus/Zmin phase matrices                                                                    |
    //   3. choose the effective scattering strength used for layer doubling                                   |
    //   4. fill single-scatter R/T matrices                                                                   |
    //   5. run layer doubling when the threshold says it is needed                                            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every layer inside every retained Fourier term                                             |
    //   costly   : phase matrix build                                                                         |
    //              effective scattering scan                                                                  |
    //              single-scatter R/T fill                                                                    |
    //              optional doubling                                                                          |
    //   memory   : optional workspace caches for phase rows and activity masks                                |
    //                                                                                                         |
    // math                                                                                                    |
    //   layer RT maps tau, omega, and phase_l into reflection R and transmission T                            |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   traces layer pruning, phase-matrix setup, single-scatter setup, and optional doubling                 |
    //   telemetry records why each layer does or does not enter expensive doubling                            |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    if (rt_active) |active| active[0] = false;
    if (phase_row_valid) |valid| valid[0] = false;

    for (0..nlayer) |layer_idx| {

        // instrumentation: trace counter: layer visits -------------------------------------------------------|
        // captures: layer visits in one Fourier RT-layer build                                                |
        // why: compare active and skipped layer counts during pre-partitioning work.                          |
        Trace.plotU("layer_visits", 1);
        // end instrumentation: trace counter: layer visits ---------------------------------------------------|

        const rt_idx = layer_idx + 1;
        const layer = &layers[layer_idx];

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: fixed phase-order storage cap                                                             |
        // Skip layer RT work when the Fourier order is outside the fixed phase-coefficient storage.           |
        // ----------------------------------------------------------------------------------------------------|
        // LABOS keeps phase arrays fixed-size so phase kernels and workspaces stay bounded and stack-friendly.|
        // basis.max_phase_coef is 151: vendor HG phase index 0..150. If a caller asks for a Fourier order     |
        // beyond that cap, this file cannot build a valid phase matrix for it, so the layer is marked         |
        // inactive for that order. Upstream normally caps the retained Fourier range before this point.       |
        if (i_fourier >= basis.max_phase_coef) {

            // instrumentation: trace counter: Fourier storage skip -------------------------------------------|
            // captures: layers skipped because the Fourier index exceeds storage                              |
            // why: quantify phase-order pruning before any matrix setup.                                      |
            Trace.plotU("layer_skipped_fourier_out_of_range", 1);
            // end instrumentation: trace counter: Fourier storage skip ---------------------------------------|

            markInactiveLayer(rt, phase_row_valid, rt_active, rt_idx, geo.nmutot);
            continue;
        }
        // end tradeoff: fixed phase-order storage cap --------------------------------------------------------|

        const phase = layer.phase;
        const max_phase_index = if (layer_phase_max_indices) |indices|
            indices[layer_idx]
        else
            phase.maxIndex();

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: phase-support cutoff                                                                      |
        // Skip this layer for Fourier orders above its active phase support.                                  |
        // ----------------------------------------------------------------------------------------------------|
        // max_phase_index comes from the prepared phase support. Phase coefficients and Rayleigh/aerosol      |
        // weights at or below 1.0e-12 are treated as absent there, so higher Fourier orders can be skipped    |
        // here without building Zplus/Zmin or RT_fc. Prepared HG rows use the route truncation threshold      |
        // 1.0e-8 in O2 A. The cost is that coefficients below the support floor do not contribute here.       |
        if (i_fourier > max_phase_index) {

            // instrumentation: trace counter: Fourier support skip -------------------------------------------|
            // captures: layers skipped by per-layer Fourier phase support                                     |
            // why: quantify savings from layer phase pre-partitioning.                                        |
            Trace.plotU("layer_skipped_fourier_out_of_range", 1);
            // end instrumentation: trace counter: Fourier support skip ---------------------------------------|

            markInactiveLayer(rt, phase_row_valid, rt_active, rt_idx, geo.nmutot);
            continue;
        }
        // end tradeoff: phase-support cutoff -----------------------------------------------------------------|

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: empty layer cutoff                                                                        |
        // Treat a layer with vanishing optical depth as inactive for RT_fc construction.                      |
        // ----------------------------------------------------------------------------------------------------|
        // empty_layer_optical_depth_floor = 1.0e-20. The floor avoids building phase matrices and R/T         |
        // matrices for a layer that cannot materially change scattering. The cost is that optical depths      |
        // below that floor are rounded down to an inactive scattering layer here. The zero                    |
        // scattering-optical-depth and zero single-scatter-albedo checks are exact no-scatter cases.          |
        if (layer.optical_depth < empty_layer_optical_depth_floor or
            layer.scattering_optical_depth <= 0.0 or
            layer.single_scatter_albedo <= 0.0)
        {

            // instrumentation: trace counter: empty optics skip ----------------------------------------------|
            // captures: layers skipped because optical/scattering terms are empty                             |
            // why: quantify no-op RT layers that can be omitted safely.                                       |
            Trace.plotU("layer_skipped_empty_optics", 1);
            // end instrumentation: trace counter: empty optics skip ------------------------------------------|

            markInactiveLayer(rt, phase_row_valid, rt_active, rt_idx, geo.nmutot);
            continue;
        }
        // end tradeoff: empty layer cutoff -------------------------------------------------------------------|

        var z = z: {

            // instrumentation: trace zone: phase matrix ------------------------------------------------------|
            // captures: phase matrix construction wall time                                                   |
            // why: isolate PLM/phase-kernel work before layer scattering decisions.                           |
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.phase_matrix");
            defer zone.end();
            const built_phase_matrix = basis.fillZplusZminFromWeightedPhaseLimited(
                i_fourier,
                phase.aerosol_weight,
                phase.rayleigh2_weight,
                phase.aerosol_phase_coefficients,
                max_phase_index,
                geo,
                plm_basis,
            );
            // end instrumentation: trace zone: phase matrix --------------------------------------------------|

            break :z built_phase_matrix;
        };

        // instrumentation: trace counter: phase matrix builds ------------------------------------------------|
        // captures: phase matrix builds                                                                       |
        // why: count expensive phase-kernel construction after Fourier/layer pruning.                         |
        Trace.plotU("phase_matrix_builds", 1);
        // end instrumentation: trace counter: phase matrix builds --------------------------------------------|

        if (phase_row_cache) |cache| {
            cachePhaseKernelViewRow(cache, rt_idx, &z, geo.viewIdx());
            if (phase_row_valid) |valid| valid[rt_idx] = true;
        } else if (phase_row_valid) |valid| {
            valid[rt_idx] = false;
        }
        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        const max_beta_eff = max_beta_eff: {

            // instrumentation: trace zone: effective scattering ----------------------------------------------|
            // captures: effective scattering suffix computation wall time                                     |
            // why: measure threshold input preparation for layer doubling.                                    |
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.effective_scattering");
            defer zone.end();
            if (layer_effective_scattering_suffixes) |suffixes| {
                std.debug.assert(layer_effective_scattering_suffix_stride > i_fourier);
                std.debug.assert(suffixes.len >= layers.len * layer_effective_scattering_suffix_stride);
                const cached_suffix = suffixes[layer_idx * layer_effective_scattering_suffix_stride + i_fourier];
                // end instrumentation: trace zone: effective scattering --------------------------------------|

                break :max_beta_eff cached_suffix;
            }

            var suffix: f64 = 0.0;
            var scanned_terms: usize = 0;
            var nonzero_terms: usize = 0;

            for (i_fourier..max_phase_index + 1) |ic| {
                scanned_terms += 1;
                const phase_coefficient = phase.coefficient(ic);
                if (phase_coefficient != 0.0) nonzero_terms += 1;
                const beta_eff = @abs(phase_coefficient) * phase_odd_reciprocal[ic];
                if (beta_eff > suffix) suffix = beta_eff;
            }

            // instrumentation: trace counters: phase coefficient scan ----------------------------------------|
            // captures: scanned and nonzero phase coefficient terms                                           |
            // why: expose how much phase-support work feeds the doubling threshold.                           |
            Trace.plotU("phase_coeff_terms_scanned", @intCast(scanned_terms));
            Trace.plotU("phase_coeff_terms_nonzero", @intCast(nonzero_terms));
            // end instrumentation: trace counters: phase coefficient scan ------------------------------------|

            // end instrumentation: trace zone: effective scattering ------------------------------------------|

            break :max_beta_eff suffix;
        };
        const effective_scattering_coefficient = a * max_beta_eff;
        const effective_scattering_depth = effective_scattering_coefficient * b;

        // Doubling is only used when tau_eff crosses threshold_doubl: 0.1 generic, 1.0e-6 in O2 A.
        const doubling_decision = classifyLayerDoubling(
            controls.scattering,
            controls.performance_thresholds.threshold_doubl,
            b,
            effective_scattering_coefficient,
            effective_scattering_depth,
        );

        // instrumentation: calculation telemetry: layer doubling decision ------------------------------------|
        // captures: layer-doubling threshold inputs                                                           |
        // why: explain which layers enter expensive doubling and by how much.                                 |
        Telemetry.labosLayerDecision(
            i_fourier,
            layer_idx,
            max_phase_index,
            b,
            a,
            max_beta_eff,
            effective_scattering_depth,
            controls.performance_thresholds.threshold_doubl,
            doubling_decision.start_optical_depth,
            doubling_decision.doubling_count,
            doubling_decision.uses_doubling,
        );
        // end instrumentation: calculation telemetry: layer doubling decision --------------------------------|

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: optional phase renormalization                                                            |
        // Run the zero-Fourier phase normalization pass only when the route asks for it.                      |
        // ----------------------------------------------------------------------------------------------------|
        // controls.renorm_phase_function defaults to true. This correction improves DISAMAR parity for        |
        // doubled zero-Fourier phase kernels. It costs an extra pass over Zplus/Zmin. If the control is       |
        // false, the solver keeps the faster raw phase kernel and skips that normalization correction.        |
        const needs_renormalized_phase =
            doubling_decision.uses_doubling and i_fourier == 0 and controls.renorm_phase_function;

        var E = basis.Vec.zero(geo.nmutot);
        {

            // instrumentation: trace zone: initial attenuation -----------------------------------------------|
            // captures: initial attenuation exponential fill                                                  |
            // why: separate exp(-tau/mu) work from scattering matrix setup.                                   |
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.initial_exponential");
            defer zone.end();

            for (0..geo.nmutot) |imu| {
                const mu = @max(geo.u[imu], layer_direction_cosine_floor);
                E.data[imu] = math.exp(-doubling_decision.start_optical_depth / mu);
            }
            // end instrumentation: trace zone: initial attenuation -------------------------------------------|

        }

        // instrumentation: trace counter: initial attenuation ------------------------------------------------|
        // captures: number of initial attenuation exponential evaluations                                     |
        // why: tie layer setup cost to stream count.                                                          |
        Trace.plotU("initial_exp_evals", @intCast(geo.nmutot));
        // end instrumentation: trace counter: initial attenuation --------------------------------------------|

        if (needs_renormalized_phase) {
            {

                // instrumentation: trace zone: phase renormalization -----------------------------------------|
                // captures: zero-Fourier phase renormalization wall time                                      |
                // why: make this optional DISAMAR-parity correction visible.                                  |
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.phase_renormalization");
                defer zone.end();
                renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
                // end instrumentation: trace zone: phase renormalization -------------------------------------|

            }

            // instrumentation: trace counter: phase renormalization ------------------------------------------|
            // captures: phase renormalization executions                                                      |
            // why: confirm when the optional correction affects layer setup.                                  |
            Trace.plotU("phase_renormalizations", 1);
            // end instrumentation: trace counter: phase renormalization --------------------------------------|

        }
        // end tradeoff: optional phase renormalization -------------------------------------------------------|

        const layer_rt = &rt[rt_idx];
        {

            // instrumentation: trace zone: single scatter ----------------------------------------------------|
            // captures: single-scatter R/T construction wall time                                             |
            // why: isolate base layer matrices before optional doubling.                                      |
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.single_scatter");
            defer zone.end();
            fillSingleScatterR(&layer_rt.R, a, &E, &z.Zmin, geo);
            fillSingleScatterT(&layer_rt.T, a, doubling_decision.start_optical_depth, &E, &z.Zplus, geo);
            // end instrumentation: trace zone: single scatter ------------------------------------------------|

        }

        // instrumentation: trace counters: single scatter ----------------------------------------------------|
        // captures: single-scatter reflection and transmission matrix builds                                  |
        // why: count base layer matrix work before doubling is applied.                                       |
        Trace.plotU("single_scatter_r", 1);
        Trace.plotU("single_scatter_t", 1);
        // end instrumentation: trace counters: single scatter ------------------------------------------------|

        if (doubling_decision.uses_doubling) {

            // instrumentation: trace counter: doubled layers -------------------------------------------------|
            // captures: layers entering doubling                                                              |
            // why: quantify threshold-selected expensive layer work.                                          |
            Trace.plotU("doubled_layers", 1);
            // end instrumentation: trace counter: doubled layers ---------------------------------------------|

            {

                // instrumentation: trace zone: layer doubling ------------------------------------------------|
                // captures: layer doubling wall time                                                          |
                // why: isolate repeated matrix squaring from base single scatter setup.                       |
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.doubling");
                defer zone.end();
                doDouble(
                    doubling_decision.doubling_count,
                    geo.nmutot,
                    geo.n_gauss,
                    controls.performance_thresholds,
                    &layer_rt.R,
                    &layer_rt.T,
                    &E,
                    i_fourier,
                    layer_idx,
                    max_phase_index,
                );
                // end instrumentation: trace zone: layer doubling --------------------------------------------|

            }
        }

        if (rt_active) |active| active[rt_idx] = a != 0.0;
    }
}

inline fn markInactiveLayer(
    rt: []LayerRT,
    phase_row_valid: ?[]bool,
    rt_active: ?[]bool,
    rt_idx: usize,
    nmutot: usize,
) void {
    // markInactiveLayer --------------------------------------------------------------------------------------|
    // Mark a skipped layer as inactive for this Fourier term.                                                 |
    //                                                                                                         |
    // If an active mask exists, orders.zig can skip the layer without clearing the 2.3 KiB LayerRT payload.   |
    // Callers without that mask still receive an explicit zero RT layer.                                      |
    // --------------------------------------------------------------------------------------------------------|

    if (phase_row_valid) |valid| valid[rt_idx] = false;

    if (rt_active) |active| {
        active[rt_idx] = false;
    } else {
        rt[rt_idx] = zeroLayerRt(nmutot);
    }
}

fn cachePhaseKernelViewRow(
    phase_row_cache: []basis.PhaseKernelRow,
    rt_idx: usize,
    z: *const basis.PhaseKernel,
    row_index: usize,
) void {
    // cachePhaseKernelViewRow --------------------------------------------------------------------------------|
    // Cache the phase-kernel row needed by the viewing direction.                                             |
    //                                                                                                         |
    // Integrated-source reflectance can reuse this row instead of rereading the full Zplus/Zmin matrices.     |
    // --------------------------------------------------------------------------------------------------------|

    const n = z.Zplus.n;
    const row_offset = row_index * n;
    var row = basis.PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = n,
    };

    for (0..n) |col| {
        row.zplus[col] = z.Zplus.data[row_offset + col];
        row.zmin[col] = z.Zmin.data[row_offset + col];
    }

    phase_row_cache[rt_idx] = row;
}

pub fn calcRTlayersTangentIntoWithBasis(
    rt_tangent: []LayerRT,
    layers: []const common.LayerInput,
    state: common.Jacobian.State,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
) void {
    // calcRTlayersTangentIntoWithBasis -----------------------------------------------------------------------|
    // Build derivative RT layers for one Jacobian state. Steps:                                               |
    //                                                                                                         |
    //   1. skip layers whose derivative state is zero                                                         |
    //   2. build plus and minus layer inputs                                                                  |
    //   3. run the ordinary RT layer builder on each perturbed layer                                          |
    //   4. store the central difference into rt_tangent                                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   tangent RT = (RT(x + eps * dx) - RT(x - eps * dx)) / (2 * eps)                                        |
    //                                                                                                         |
    // eps : tangent_step                                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    const nlevel = layers.len + 1;
    std.debug.assert(rt_tangent.len >= nlevel);

    for (rt_tangent[0..nlevel]) |*layer_rt| layer_rt.* = zeroLayerRt(geo.nmutot);

    const eps = tangent_step;
    const inv_span = 0.5 / eps;

    for (layers, 0..) |layer, layer_idx| {
        const d_optical_depth = common.Jacobian.get(layer.optical_depth_jacobian, state);
        const d_scattering_optical_depth = common.Jacobian.get(layer.scattering_optical_depth_jacobian, state);
        const d_single_scatter_albedo = common.Jacobian.get(layer.single_scatter_albedo_jacobian, state);
        if (d_optical_depth == 0.0 and d_scattering_optical_depth == 0.0 and d_single_scatter_albedo == 0.0) continue;

        var plus_layer = layer;
        plus_layer.optical_depth = @max(layer.optical_depth + eps * d_optical_depth, 0.0);
        plus_layer.scattering_optical_depth = @max(
            layer.scattering_optical_depth + eps * d_scattering_optical_depth,
            0.0,
        );
        plus_layer.single_scatter_albedo = std.math.clamp(
            layer.single_scatter_albedo + eps * d_single_scatter_albedo,
            0.0,
            1.0,
        );

        var minus_layer = layer;
        minus_layer.optical_depth = @max(layer.optical_depth - eps * d_optical_depth, 0.0);
        minus_layer.scattering_optical_depth = @max(
            layer.scattering_optical_depth - eps * d_scattering_optical_depth,
            0.0,
        );
        minus_layer.single_scatter_albedo = std.math.clamp(
            layer.single_scatter_albedo - eps * d_single_scatter_albedo,
            0.0,
            1.0,
        );

        const plus_layers = [_]common.LayerInput{plus_layer};
        const minus_layers = [_]common.LayerInput{minus_layer};
        var plus_rt: [2]LayerRT = undefined;
        var minus_rt: [2]LayerRT = undefined;

        calcRTlayersIntoWithBasis(
            &plus_rt,
            &plus_layers,
            i_fourier,
            geo,
            controls,
            plm_basis,
            null,
            null,
            0,
            null,
            null,
            null,
        );

        calcRTlayersIntoWithBasis(
            &minus_rt,
            &minus_layers,
            i_fourier,
            geo,
            controls,
            plm_basis,
            null,
            null,
            0,
            null,
            null,
            null,
        );

        rt_tangent[layer_idx + 1] = layerRtDifferenceScaled(plus_rt[1], minus_rt[1], inv_span);
    }
}

fn layerRtDifferenceScaled(plus: LayerRT, minus: LayerRT, scale: f64) LayerRT {
    // layerRtDifferenceScaled --------------------------------------------------------------------------------|
    // Difference two RT layers and multiply by the central-difference scale.                                  |
    // --------------------------------------------------------------------------------------------------------|

    return .{
        .R = matDifferenceScaled(plus.R, minus.R, scale),
        .T = matDifferenceScaled(plus.T, minus.T, scale),
    };
}

fn matDifferenceScaled(plus: basis.Mat, minus: basis.Mat, scale: f64) basis.Mat {
    // matDifferenceScaled ------------------------------------------------------------------------------------|
    // Elementwise scaled matrix difference.                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    var result = basis.Mat{ .data = undefined, .n = plus.n };

    for (0..plus.n * plus.n) |index| {
        result.data[index] = (plus.data[index] - minus.data[index]) * scale;
    }

    return result;
}

fn zeroLayerRt(n: usize) LayerRT {
    // zeroLayerRt --------------------------------------------------------------------------------------------|
    // Empty layer reflection/transmission pair.                                                               |
    // --------------------------------------------------------------------------------------------------------|

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
    // calcRTlayersInto ---------------------------------------------------------------------------------------|
    // Build RT layers when the caller has not already prepared a Plm basis.                                   |
    // --------------------------------------------------------------------------------------------------------|

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
        0,
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
) [attenuation.max_levels]LayerRT {
    // calcRTlayers -------------------------------------------------------------------------------------------|
    // Returning wrapper around calcRTlayersInto.                                                              |
    // --------------------------------------------------------------------------------------------------------|

    var rt: [attenuation.max_levels]LayerRT = undefined;
    calcRTlayersInto(rt[0 .. layers.len + 1], layers, i_fourier, geo, controls);
    return rt;
}

pub fn fillSurface(
    i_fourier: usize,
    albedo: f64,
    geo: *const basis.Geometry,
) LayerRT {
    // fillSurface --------------------------------------------------------------------------------------------|
    // Build the surface boundary as RT layer 0.                                                               |
    //                                                                                                         |
    // Only the zero Fourier term carries Lambertian surface reflection. Higher Fourier terms return zero R/T. |
    //                                                                                                         |
    // math                                                                                                    |
    //   R[i,j] = w[i] * albedo * w[j]                                                                         |
    // --------------------------------------------------------------------------------------------------------|

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
