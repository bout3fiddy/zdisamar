const rows = @import("rows.zig");

const Mat = rows.Mat;
const Vec = rows.Vec;

const threshold_q: f64 = 1.0e-3;
const lu_diagonal_floor: f64 = 1.0e-30;

// matrix_12x10.zig -----------------------------------------------------------------------------------------  |
// Small LABOS matrix multiply kernels used by layer-doubling and q-series transport.                          |
//                                                                                                             |
// provenance                                                                                                  |
//   Trace gates, generic multiply/q-series shape, and the fixed 12x10 loops are ported from main:             |
//   `src/forward_model/radiative_transfer/labos/matrix.zig` `smul`, `smulInto`, `qseries`,                    |
//   `qseriesFromProduct`, `smul12x10Into`, and `qseriesFromProduct12x10Into`.                                 |
//                                                                                                             |
// math                                                                                                        |
//   C[i,j] = sum over Gaussian k of A[i,k] * B[k,j].                                                          |
//   Q(AB) uses the LABOS repeated-scattering transform:                                                       |
//     Q_gg = inverse(I - AB_gg) - I                                                                           |
//     Q_gx = inverse(I - AB_gg) * AB_gx                                                                       |
//     Q_xg = AB_xg * inverse(I - AB_gg)                                                                       |
//     Q_xx = AB_xx + Q_xg * AB_gx                                                                             |
//                                                                                                             |
// numerical guard                                                                                             |
//   threshold_mul is the LABOS product-size gate. When abs(trace(A_gg) * trace(B_gg)) is below the caller     |
//   threshold, the product is treated as negligible and a zero matrix is returned.                            |
//   threshold_q skips the q-series inverse when AB_gg is negligible. lu_diagonal_floor returns the bounded AB |
//   product when a pivot would make the inverse unstable.                                                     |
// ------------------------------------------------------------------------------------------------------------|

pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    // smul (small matrix multiply with trace gate) ---------------------------------------------------------- |
    // Multiply two LABOS small dense matrices over the Gaussian directions.                                   |
    //                                                                                                         |
    //   C[i,j] = sum k=0..n_gauss-1 A[i,k] * B[k,j]                                                           |
    //                                                                                                         |
    // The trace gate is the cheap early exit used by LABOS layer doubling. If trace(A_gg) * trace(B_gg) is    |
    // below threshold_mul, the full multiply is skipped and a zero matrix is returned.                        |
    // Fixed n=12, n_gauss=10 uses the hand-shaped vector-pair kernel below.                                   |
    //                                                                                                         |
    // Generic rtm_config:                                                                                     |
    //   1. choose output column j                                                                             |
    //   2. initialize C[:,j] with the k=0 Gaussian term                                                       |
    //   3. add the remaining Gaussian terms k=1..n_gauss-1                                                    |
    //   4. walk idx += n because one column is stored across row-major rows                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        // Fixed trace gate -----------------------------------------------------------------------------------|
        // The Gaussian block is the first 10x10 part of a 12x12 stream matrix.                                |
        // Mat.data is row-major, so element M[row,col] is stored at row*12 + col. On the diagonal, row=col=k, |
        // so the index is k*12 + k = k*13.                                                                    |
        //                                                                                                     |
        //   k          : 0   1   2   3   4   5   6   7    8    9                                              |
        //   A[k,k] idx : 0  13  26  39  52  65  78  91  104  117                                              |
        //   B[k,k] idx : 0  13  26  39  52  65  78  91  104  117                                              |
        //                                                                                                     |
        // trace(A_gg) * trace(B_gg) is the cheap product-size test used before running the unrolled 12x10     |
        // multiply.                                                                                           |
        var tra = a.data[0];
        tra += a.data[13];
        tra += a.data[26];
        tra += a.data[39];
        tra += a.data[52];
        tra += a.data[65];
        tra += a.data[78];
        tra += a.data[91];
        tra += a.data[104];
        tra += a.data[117];

        // Same diagonal indexes, now in B. b.data[13] is B[1,1] in row-major storage.
        var trb = b.data[0];
        trb += b.data[13];
        trb += b.data[26];
        trb += b.data[39];
        trb += b.data[52];
        trb += b.data[65];
        trb += b.data[78];
        trb += b.data[91];
        trb += b.data[104];
        trb += b.data[117];
        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: fixed small-multiply trace gate                                                           |
        // Return zero when abs(trace(A_gg) * trace(B_gg)) <= threshold_mul.                                   |
        // ----------------------------------------------------------------------------------------------------|
        // LABOS layers pass threshold_mul = 1.0e-12 by generic default and 1.0e-8 in O2 A. This skips a       |
        // full 12x10 product when the Gaussian trace estimate says the product is too small to matter.        |
        if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);
        // end tradeoff: fixed small-multiply trace gate ------------------------------------------------------|

        // Retained fixed product -----------------------------------------------------------------------------|
        // Use the hand-shaped kernel documented below.                                                        |
        // ----------------------------------------------------------------------------------------------------|

        return smul12x10(a, b);
    }

    // Generic trace gate -------------------------------------------------------------------------------------|
    // Same test as the fixed rtm_config, with diagonal stride n + 1 for the generic row width.                |
    var tra: f64 = 0.0;
    var trb: f64 = 0.0;
    for (0..n_gauss) |k| {
        const idx = k * n + k;
        tra += a.data[idx];
        trb += b.data[idx];
    }
    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: generic small-multiply trace gate                                                             |
    // Return zero when abs(trace(A_gg) * trace(B_gg)) <= threshold_mul.                                       |
    // --------------------------------------------------------------------------------------------------------|
    // This is the same accuracy/speed cutoff as the fixed 12x10 path, but with runtime n and n_gauss.         |
    // It avoids the full product when the caller's threshold says the product is negligible.                  |
    if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);
    // end tradeoff: generic small-multiply trace gate --------------------------------------------------------|

    return smulNonzeroProduct(n, n_gauss, a, b);
}

pub inline fn smulInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    b: *const Mat,
) void {
    // smulInto (small matrix multiply into caller storage) -------------------------------------------------- |
    // Same trace-gated product as smul, but writes into caller-owned storage.                                 |
    //                                                                                                         |
    //   out = A * B over Gaussian k                                                                           |
    //                                                                                                         |
    // This avoids returning a Mat by value inside scattering-order loops.                                     |
    // The fixed 12x10 rtm_config repeats the trace scan here so it can call smul12x10Into                     |
    // directly when the product is retained.                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        // Fixed trace gate, caller-owned output --------------------------------------------------------------|
        // Same 10x10 Gaussian diagonal as smul. Mat.data is row-major, so diagonal M[k,k] is stored at        |
        // k*12 + k = k*13: indexes 0, 13, 26, ..., 117. The B trace uses the same positions in b.data.        |
        // This branch repeats the scan so a retained product can write directly into out with smul12x10Into.  |
        // If the trace product is tiny, out receives the zero matrix and no multiply is run.                  |
        // ----------------------------------------------------------------------------------------------------|

        var tra = a.data[0];
        tra += a.data[13];
        tra += a.data[26];
        tra += a.data[39];
        tra += a.data[52];
        tra += a.data[65];
        tra += a.data[78];
        tra += a.data[91];
        tra += a.data[104];
        tra += a.data[117];

        // Same diagonal indexes, now in B. b.data[13] is B[1,1] in row-major storage.
        var trb = b.data[0];
        trb += b.data[13];
        trb += b.data[26];
        trb += b.data[39];
        trb += b.data[52];
        trb += b.data[65];
        trb += b.data[78];
        trb += b.data[91];
        trb += b.data[104];
        trb += b.data[117];

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: caller-output fixed trace gate                                                            |
        // Write zero when abs(trace(A_gg) * trace(B_gg)) <= threshold_mul.                                    |
        // ----------------------------------------------------------------------------------------------------|
        // This is the caller-owned-output version of the same 12x10 product skip. It avoids the multiply and  |
        // writes a zero matrix into out.                                                                      |
        if (@abs(tra * trb) <= threshold_mul) {
            out.* = Mat.zero(n);
            return;
        }
        // end tradeoff: caller-output fixed trace gate -------------------------------------------------------|

        // Retained fixed product -----------------------------------------------------------------------------|
        // Use the hand-shaped kernel and write directly into the caller's Mat.                                |
        // ----------------------------------------------------------------------------------------------------|

        smul12x10Into(out, a, b);
        return;
    }

    // Generic rtm_config delegates to smul, then copies the returned Mat into caller-owned storage.
    out.* = smul(n, n_gauss, threshold_mul, a, b);
}

pub inline fn smulIntoKnownTraces(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: *const Mat,
    b: *const Mat,
) void {
    // smulIntoKnownTraces (small matrix multiply with caller traces) ---------------------------------------- |
    // Caller already has trace(A_gg) and trace(B_gg). Use those traces for the threshold decision, then write |
    // either the retained product or a zero matrix into caller storage.                                       |
    //                                                                                                         |
    // Used when an upstream fused kernel already scanned one or both Gaussian diagonals.                      |
    // --------------------------------------------------------------------------------------------------------|

    if (smulIntoKnownTracesIfNonzero(out, n, n_gauss, threshold_mul, trace_a, trace_b, a, b)) return;
    out.* = Mat.zero(n);
}

pub inline fn smulIntoKnownTracesIfNonzero(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    trace_a: f64,
    trace_b: f64,
    a: *const Mat,
    b: *const Mat,
) bool {
    // smulIntoKnownTracesIfNonzero (trace-gated product probe) ---------------------------------------------- |
    // Return false when the trace gate says A*B is negligible. Return true after writing the product into     |
    // caller storage.                                                                                         |
    //                                                                                                         |
    // Fused add/scale kernels use the boolean to choose between:                                              |
    //   retained product path                                                                                 |
    //   cheaper no-product path                                                                               |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(10_000);
    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: known-trace product gate                                                                      |
    // Return false when abs(trace(A_gg) * trace(B_gg)) <= threshold_mul.                                      |
    // --------------------------------------------------------------------------------------------------------|
    // The caller already paid for the traces, so this keeps fused kernels from doing a product they will      |
    // immediately treat as negligible.                                                                        |
    if (@abs(trace_a * trace_b) <= threshold_mul) {
        return false;
    }
    // end tradeoff: known-trace product gate -----------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        smul12x10Into(out, a, b);
        return true;
    }
    out.* = smulNonzeroProduct(n, n_gauss, a, b);
    return true;
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    // qseries (thresholded product, then q-series transform) ------------------------------------------------ |
    // Build AB with the same trace-gated small matrix multiply as smul, then convert AB into the LABOS        |
    // q-series matrix.                                                                                        |
    //                                                                                                         |
    //   AB = A * B over Gaussian k                                                                            |
    //   out = Q(AB)                                                                                           |
    // --------------------------------------------------------------------------------------------------------|

    const ab = smul(n, n_gauss, threshold_mul, a, b);
    return qseriesFromProduct(n, n_gauss, &ab);
}

pub inline fn qseriesKnownNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    // qseriesKnownNonzeroProduct (q-series after retained product) ------------------------------------------ |
    // Caller already knows A*B should not be thresholded to zero. Build the product directly, then apply the  |
    // q-series transform.                                                                                     |
    //                                                                                                         |
    // This is used by callers that already made the trace decision while building surrounding terms.          |
    // --------------------------------------------------------------------------------------------------------|

    const ab = smulNonzeroProduct(n, n_gauss, a, b);
    return qseriesFromProduct(n, n_gauss, &ab);
}

pub inline fn qseriesKnownNonzeroProductInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    a: *const Mat,
    b: *const Mat,
) void {
    // qseriesKnownNonzeroProductInto (q-series into caller storage) ----------------------------------------- |
    // Caller-owned-output version of qseriesKnownNonzeroProduct.                                              |
    //                                                                                                         |
    //   1. build retained AB = A * B                                                                          |
    //   2. write Q(AB) into out                                                                               |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 uses the same hand-shaped product kernel as smul12x10Into before the q-series    |
    // solve.                                                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    var ab: Mat = undefined;
    if (n == 12 and n_gauss == 10) {
        smul12x10Into(&ab, a, b);
    } else {
        ab = smulNonzeroProduct(n, n_gauss, a, b);
    }
    qseriesFromProductInto(out, n, n_gauss, &ab);
}

pub fn esmul(n: usize, e: *const Vec, a: *const Mat) Mat {
    // esmul (left diagonal scale: diag(e) * A) -------------------------------------------------------------- |
    // Scale each row by e[i].                                                                                 |
    //                                                                                                         |
    //   C[i,j] = e[i] * A[i,j]                                                                                |
    //                                                                                                         |
    // Fixed n=12 dispatches to a constant-bound kernel so the row/column limits are visible to the compiler.  |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return esmul12(e, a);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {

            // Left diagonal scale: C[i,j] = e[i] * A[i,j].
            result.data[idx] = e.data[i] * a.data[idx];
            idx += n;
        }
    }
    return result;
}

pub fn semul(n: usize, a: *const Mat, e: *const Vec) Mat {
    // semul (right diagonal scale: A * diag(e)) ------------------------------------------------------------- |
    // Scale each column by e[j].                                                                              |
    //                                                                                                         |
    //   C[i,j] = A[i,j] * e[j]                                                                                |
    //                                                                                                         |
    // This is the right-side diagonal scale used by LABOS layer-combination formulas.                         |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return semul12(a, e);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {

            // Right diagonal scale: C[i,j] = A[i,j] * e[j].
            result.data[idx] = a.data[idx] * ej;
            idx += n;
        }
    }
    return result;
}

pub fn matAdd(n: usize, a: *const Mat, b: *const Mat) Mat {
    // matAdd (elementwise matrix add) ----------------------------------------------------------------------- |
    // Add two row-major Mat values element by element.                                                        |
    //                                                                                                         |
    //   C[i,j] = A[i,j] + B[i,j]                                                                              |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = n };

    // Elementwise add: C = A + B.
    for (0..n * n) |idx| result.data[idx] = a.data[idx] + b.data[idx];
    return result;
}

pub inline fn matAddSemul3(
    n: usize,
    a: *const Mat,
    b: *const Mat,
    e: *const Vec,
    c: *const Mat,
) Mat {
    // matAddSemul3 (right diagonal scale plus two adds) ----------------------------------------------------- |
    // Fused right-diagonal scale plus two matrix adds.                                                        |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + B[i,j] * e[j] + C[i,j]                                                            |
    //                                                                                                         |
    // `semul` means scale on the right: each column j uses e[j]. Fixed n=12 uses the constant-bound path;     |
    // generic n keeps the same row-major formula.                                                             |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return matAddSemul3_12(a, b, e, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {

            // Right-scale add: out[i,j] = A[i,j] + B[i,j] * e[j] + C[i,j].
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

fn smulNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    // smulNonzeroProduct ------------------------------------------------------------------------------------ |
    // Build A * B after the caller has already retained the product.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = Mat{ .data = undefined, .n = n };

    for (0..n) |j| {
        if (n_gauss == 0) break;

        const b0j = b.data[j];
        var idx = j;
        var a_idx: usize = 0;

        for (0..n) |_| {
            result.data[idx] = a.data[a_idx] * b0j;
            idx += n;
            a_idx += n;
        }

        for (1..n_gauss) |k| {
            const bkj = b.data[k * n + j];
            idx = j;
            a_idx = k;

            for (0..n) |_| {
                result.data[idx] += a.data[a_idx] * bkj;
                idx += n;
                a_idx += n;
            }
        }
    }

    return result;
}

inline fn smul12x10(a: *const Mat, b: *const Mat) Mat {
    // smul12x10 (small matrix multiply, fixed 12x10 return value) ------------------------------------------- |
    // Returning wrapper around smul12x10Into. The real optimized work is in the caller-owned-output kernel so |
    // fused paths can reuse the same fixed-shape implementation without temporary return plumbing.            |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    smul12x10Into(&result, a, b);
    return result;
}

inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    // smul12x10Into (small matrix multiply, fixed 12x10) ---------------------------------------------------- |
    // Fixed n=12, n_gauss=10 product for the LABOS hot path.                                                  |
    //                                                                                                         |
    // The loop writes one output row at a time and two neighboring columns per @Vector(2, f64).               |
    // A row has 10 Gaussian columns plus 2 extra columns used for view/solar directions.                      |
    //                                                                                                         |
    // row-major slots for one n=12 row:                                                                       |
    //   [row + 0 .. row + 9]   Gaussian columns used in the k-sum                                             |
    //   [row + 10]              extra direction 0                                                             |
    //   [row + 11]              extra direction 1                                                             |
    //                                                                                                         |
    // vector pair at column j:                                                                                |
    //   |-- [j]                 first output column                                                           |
    //   |-- [j + 1]             second output column                                                          |
    //                                                                                                         |
    // Keep the multiply/add sequence explicit; @mulAdd becomes a compiler-rt fma call on generic x86_64.      |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(10_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;

        // A row broadcasts -----------------------------------------------------------------------------------|
        // Read A[i,0..9], the Gaussian part of row i. Each scalar is copied into both SIMD lanes so one       |
        // multiply contributes to C[i,j] and C[i,j+1] at the same time.                                       |
        //                                                                                                     |
        //   a0 = [A[i,0], A[i,0]]                                                                             |
        //   a1 = [A[i,1], A[i,1]]                                                                             |
        //   ...                                                                                               |
        //   a9 = [A[i,9], A[i,9]]                                                                             |
        const a0: @Vector(2, f64) = @splat(a.data[row]);
        const a1: @Vector(2, f64) = @splat(a.data[row + 1]);
        const a2: @Vector(2, f64) = @splat(a.data[row + 2]);
        const a3: @Vector(2, f64) = @splat(a.data[row + 3]);
        const a4: @Vector(2, f64) = @splat(a.data[row + 4]);
        const a5: @Vector(2, f64) = @splat(a.data[row + 5]);
        const a6: @Vector(2, f64) = @splat(a.data[row + 6]);
        const a7: @Vector(2, f64) = @splat(a.data[row + 7]);
        const a8: @Vector(2, f64) = @splat(a.data[row + 8]);
        const a9: @Vector(2, f64) = @splat(a.data[row + 9]);
        // ----------------------------------------------------------------------------------------------------|

        // B Gaussian rows ------------------------------------------------------------------------------------|
        // b0..b9 are the B rows that participate in the Gaussian sum. Each slice is one full row with         |
        // 12 output columns, including the two extra view/solar columns.                                      |
        //                                                                                                     |
        //   b0 = B[0, 0..12]                                                                                  |
        //   b1 = B[1, 0..12]                                                                                  |
        //   ...                                                                                               |
        //   b9 = B[9, 0..12]                                                                                  |
        const b0 = b.data[0..12];
        const b1 = b.data[12..24];
        const b2 = b.data[24..36];
        const b3 = b.data[36..48];
        const b4 = b.data[48..60];
        const b5 = b.data[60..72];
        const b6 = b.data[72..84];
        const b7 = b.data[84..96];
        const b8 = b.data[96..108];
        const b9 = b.data[108..120];
        // ----------------------------------------------------------------------------------------------------|

        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Two-column dot product -------------------------------------------------------------------------|
            // This computes two output columns at a time:                                                     |
            //                                                                                                 |
            //   C[i, j : j + 2] = sum k=0..9 A[i,k] * B[k, j : j + 2]                                         |
            //                                                                                                 |
            // k = 0..9 are the Gaussian directions.                                                           |
            // j = 0, 2, 4, 6, 8, 10 covers all 12 output columns as six vector pairs.                         |
            //                                                                                                 |
            // One vector lane pair:                                                                           |
            //                                                                                                 |
            //   A[i,k]                      B[k,j]        B[k,j+1]                                            |
            //      |                           |               |                                              |
            //      v                           v               v                                              |
            //   splat(A[i,k])       *       @Vector(2, f64) load                                              |
            //                                                                                                 |
            // This is visually repetitive because it is deliberately unrolled for the n=12, n_gauss=10        |
            // LABOS hot path.                                                                                 |

            var s = a0 * loadPair(b0, j);
            s += a1 * loadPair(b1, j);
            s += a2 * loadPair(b2, j);
            s += a3 * loadPair(b3, j);
            s += a4 * loadPair(b4, j);
            s += a5 * loadPair(b5, j);
            s += a6 * loadPair(b6, j);
            s += a7 * loadPair(b7, j);
            s += a8 * loadPair(b8, j);
            s += a9 * loadPair(b9, j);

            // ARM64 SIMD codegen proof -----------------------------------------------------------------------|
            // Current ReleaseFast codegen for this dot-product shape:                                         |
            //                                                                                                 |
            //   ldp       q0, q2, [x2]              load 128-bit vector registers                             |
            //   fmul.2d   v0, v0, v9[0]             multiply two f64 lanes                                    |
            //   fadd.2d   v0, v0, v1                add two f64 lanes                                         |
            //                                                                                                 |
            // q/v registers are ARM64 vector registers. The .2d suffix means two double-precision lanes.      |
            // ------------------------------------------------------------------------------------------------|

            result.data[row + j] = s[0];
            result.data[row + j + 1] = s[1];
        }
    }
}

inline fn loadPair(row: []const f64, comptime j: usize) @Vector(2, f64) {
    // loadPair (two-column f64 vector load) ----------------------------------------------------------------- |
    // Read columns j and j+1 from one row as @Vector(2, f64). The optimized kernels use this to compute two   |
    // neighboring output columns with one vector expression.                                                  |
    //                                                                                                         |
    // align(1) is deliberate: Mat rows are contiguous, but the slice is not promised to be vector-aligned.    |
    // --------------------------------------------------------------------------------------------------------|

    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&row[j]);
    return pair.*;
}

inline fn qseriesFromProductInto(noalias out: *Mat, n: usize, n_gauss: usize, noalias ab: *const Mat) void {
    // qseriesFromProductInto (Q(AB) into caller storage) ---------------------------------------------------- |
    // Caller-owned-output wrapper around qseriesFromProduct.                                                  |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 writes through the fixed q-series kernel; generic n delegates to the returning   |
    // implementation.                                                                                         |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        qseriesFromProduct12x10Into(out, ab);
        return;
    }
    out.* = qseriesFromProduct(n, n_gauss, ab);
}

inline fn qseriesFromProduct(n: usize, n_gauss: usize, noalias ab_product: *const Mat) Mat {
    // qseriesFromProduct (build Q(AB) from a retained AB product) ------------------------------------------- |
    // Turn an already-built AB product into the LABOS q-series matrix.                                        |
    //                                                                                                         |
    // zdisamar uses the same repeated-reflection shape as the reference Qseries:                              |
    //                                                                                                         |
    //   AB + AB * AB + AB * AB * AB + ...                                                                     |
    //                                                                                                         |
    // Instead of summing terms directly, LABOS inverts the Gaussian block of I - AB and fills the extra       |
    // view/solar rows and columns from that inverse.                                                          |
    //                                                                                                         |
    // Split AB by stream kind:                                                                                |
    //   [ gg | gx ]                                                                                           |
    //   [ xg | xx ]                                                                                           |
    //                                                                                                         |
    //   Q_gg = inverse(I - AB_gg) - I                                                                         |
    //   Q_gx = inverse(I - AB_gg) * AB_gx                                                                     |
    //   Q_xg = AB_xg * inverse(I - AB_gg)                                                                     |
    //   Q_xx = AB_xx + Q_xg * AB_gx                                                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return qseriesFromProduct12x10(ab_product);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: q-series trace gate                                                                           |
    // Return AB directly when abs(trace(AB_gg)) < threshold_q = 1.0e-3.                                       |
    // --------------------------------------------------------------------------------------------------------|
    // Q adds repeated-reflection feedback from inverse(I - AB_gg). When the Gaussian trace is tiny, this      |
    // skips the inversion and keeps AB as the q-series result.                                                |
    var gaussian_trace: f64 = 0.0;
    for (0..n_gauss) |gaussian_index| {
        gaussian_trace += ab_product.data[gaussian_index * n + gaussian_index];
    }
    if (@abs(gaussian_trace) < threshold_q) return ab_product.*;
    // end tradeoff: q-series trace gate ----------------------------------------------------------------------|

    const n_extra_streams = n - n_gauss;
    var factor_matrix: [rows.max_gauss * rows.max_gauss]f64 = undefined;
    for (0..n_gauss) |gaussian_row| {
        const factor_row_offset = gaussian_row * n_gauss;
        const product_row_offset = gaussian_row * n;

        for (0..n_gauss) |gaussian_col| {
            const identity_value: f64 = if (gaussian_row == gaussian_col) 1.0 else 0.0;

            // Factorization target: M = I - AB restricted to Gaussian streams.
            factor_matrix[factor_row_offset + gaussian_col] =
                identity_value - ab_product.data[product_row_offset + gaussian_col];
        }
    }

    var pivot_row: [rows.max_gauss]usize = undefined;
    var pivot_row_offset: [rows.max_gauss]usize = undefined;
    var upper_inverse_diag: [rows.max_gauss]f64 = undefined;

    // Generic LU storage -------------------------------------------------------------------------------------|
    // factor_matrix holds M = I - AB_gg in a flat n_gauss by n_gauss table.                                   |
    // pivot_row[i] is the original row currently used at LU row i.                                            |
    // pivot_row_offset[i] is pivot_row[i] * n_gauss, so inner loops avoid that multiply.                      |
    // upper_inverse_diag[i] stores 1 / U[i,i] after each accepted pivot.                                      |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_gauss) |factor_row| {
        pivot_row[factor_row] = factor_row;
        pivot_row_offset[factor_row] = factor_row * n_gauss;
    }

    // Pivoted LU ---------------------------------------------------------------------------------------------|
    // Factor M into L and U in-place. A near-zero pivot returns the bounded AB fallback.                      |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_gauss) |pivot_col| {
        var max_val: f64 = @abs(factor_matrix[pivot_row_offset[pivot_col] + pivot_col]);
        var max_row = pivot_col;

        for (pivot_col + 1..n_gauss) |candidate_row| {
            const val = @abs(factor_matrix[pivot_row_offset[candidate_row] + pivot_col]);
            if (val > max_val) {
                max_val = val;
                max_row = candidate_row;
            }
        }

        if (max_row != pivot_col) {
            const pivot_tmp = pivot_row[pivot_col];
            pivot_row[pivot_col] = pivot_row[max_row];
            pivot_row[max_row] = pivot_tmp;

            const offset_tmp = pivot_row_offset[pivot_col];
            pivot_row_offset[pivot_col] = pivot_row_offset[max_row];
            pivot_row_offset[max_row] = offset_tmp;
        }

        const factor_col_offset = pivot_row_offset[pivot_col];
        const diag = factor_matrix[factor_col_offset + pivot_col];

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: LU pivot floor                                                                            |
        // Return AB directly when an LU pivot is smaller than lu_diagonal_floor = 1.0e-30.                    |
        // ----------------------------------------------------------------------------------------------------|
        // This avoids unstable division in the Gaussian-block inverse. The fallback keeps the pre-inversion   |
        // product so the q-series correction remains bounded.                                                 |
        if (@abs(diag) < lu_diagonal_floor) return ab_product.*;
        // end tradeoff: LU pivot floor -----------------------------------------------------------------------|

        const inv_diag = 1.0 / diag;
        upper_inverse_diag[pivot_col] = inv_diag;

        for (pivot_col + 1..n_gauss) |target_row| {
            const target_row_offset = pivot_row_offset[target_row];
            const factor = factor_matrix[target_row_offset + pivot_col] * inv_diag;
            factor_matrix[target_row_offset + pivot_col] = factor;

            for (pivot_col + 1..n_gauss) |update_col| {
                factor_matrix[target_row_offset + update_col] -=
                    factor * factor_matrix[factor_col_offset + update_col];
            }
        }
    }

    // Inverse columns ----------------------------------------------------------------------------------------|
    // Invert M by solving one identity-column right-hand side at a time.                                      |
    //                                                                                                         |
    // For one inverse column:                                                                                 |
    //                                                                                                         |
    //   pivoted identity column -> solve L*y -> solve U*x -> store x in inverse[:, column]                    |
    //                                                                                                         |
    // The factor_matrix array now contains both L and U: L below the diagonal, U on and above the diagonal.   |
    // --------------------------------------------------------------------------------------------------------|

    var inverse: [rows.max_gauss * rows.max_gauss]f64 = undefined;
    for (0..n_gauss) |inverse_col| {

        // Forward solve: L * y = pivoted identity column.
        var forward_solution: [rows.max_gauss]f64 = undefined;
        for (0..n_gauss) |factor_row| {
            var residual: f64 = if (pivot_row[factor_row] == inverse_col) 1.0 else 0.0;
            const factor_row_offset = pivot_row_offset[factor_row];

            for (0..factor_row) |known_col| {
                residual -= factor_matrix[factor_row_offset + known_col] * forward_solution[known_col];
            }

            forward_solution[factor_row] = residual;
        }

        // Back solve: U * x = y. Walk upward because each row uses
        // already-solved rows below it.
        var inverse_column: [rows.max_gauss]f64 = undefined;
        var reverse_row = n_gauss;
        while (reverse_row > 0) {
            reverse_row -= 1;

            var residual: f64 = forward_solution[reverse_row];
            const factor_row_offset = pivot_row_offset[reverse_row];

            for (reverse_row + 1..n_gauss) |known_col| {
                residual -= factor_matrix[factor_row_offset + known_col] * inverse_column[known_col];
            }

            inverse_column[reverse_row] = residual * upper_inverse_diag[reverse_row];
        }

        for (0..n_gauss) |factor_row| {
            inverse[factor_row * n_gauss + inverse_col] = inverse_column[factor_row];
        }
    }

    // Gaussian block -----------------------------------------------------------------------------------------|
    // Q_gg = inverse(I - AB_gg) - I.                                                                          |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = n };
    for (0..n_gauss) |gaussian_row| {
        const result_row_offset = gaussian_row * n;
        const inverse_row_offset = gaussian_row * n_gauss;

        for (0..n_gauss) |gaussian_col| {
            const identity_value: f64 = if (gaussian_row == gaussian_col) 1.0 else 0.0;

            // Gaussian block: Q[i,j] = inverse(I - AB)[i,j] - delta[i,j].
            result.data[result_row_offset + gaussian_col] =
                inverse[inverse_row_offset + gaussian_col] - identity_value;
        }
    }

    // Gaussian-to-extra block --------------------------------------------------------------------------------|
    // Fill the upper-right q-series block. This is one ordinary matrix multiply, but only for the             |
    // Gaussian rows and extra-stream columns.                                                                 |
    //                                                                                                         |
    //   Q_gx = inverse(I - AB_gg) * AB_gx                                                                     |
    //                                                                                                         |
    // One output cell:                                                                                        |
    //                                                                                                         |
    //   Q[row, extra_col] = sum k=0..n_gauss-1 inverse[row,k] * AB[k, extra_col]                              |
    //                                                                                                         |
    // Loop order:                                                                                             |
    //   1. choose one extra output column: n_gauss + extra_col_index                                          |
    //   2. choose one Gaussian output row                                                                     |
    //   3. dot across Gaussian columns k=0..n_gauss-1                                                         |
    //                                                                                                         |
    // For n=11 and n_gauss=9, this writes 9 rows x 2 extra columns = 18 output cells.                         |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_extra_streams) |extra_col_index| {
        const output_col = n_gauss + extra_col_index;

        for (0..n_gauss) |gaussian_row| {
            const inverse_row_offset = gaussian_row * n_gauss;
            var dot_sum: f64 = 0.0;

            for (0..n_gauss) |gaussian_col| {
                dot_sum += inverse[inverse_row_offset + gaussian_col] *
                    ab_product.data[gaussian_col * n + output_col];
            }

            // Upper-extra block: Q_gx = inverse(I - AB_gg) * AB_gx.
            result.data[gaussian_row * n + output_col] = dot_sum;
        }
    }

    // Extra-to-Gaussian block --------------------------------------------------------------------------------|
    // Q_xg = AB_xg * inverse(I - AB_gg). extra_to_gaussian is reused when filling Q_xx.                       |
    // --------------------------------------------------------------------------------------------------------|

    var extra_to_gaussian: [rows.max_extra_streams * rows.max_gauss]f64 = undefined;

    // The nested loops are one block multiply:
    //   output extra row -> output Gaussian column -> Gaussian dot product.
    for (0..n_extra_streams) |extra_row_index| {
        const output_row = n_gauss + extra_row_index;
        const product_row_offset = output_row * n;
        const extra_to_gaussian_row_offset = extra_row_index * n_gauss;

        for (0..n_gauss) |gaussian_col| {
            var dot_sum: f64 = 0.0;

            for (0..n_gauss) |gaussian_inner| {
                dot_sum += ab_product.data[product_row_offset + gaussian_inner] *
                    inverse[gaussian_inner * n_gauss + gaussian_col];
            }

            extra_to_gaussian[extra_to_gaussian_row_offset + gaussian_col] = dot_sum;

            // Lower-Gaussian block: Q_xg = AB_xg * inverse(I - AB_gg).
            result.data[product_row_offset + gaussian_col] = dot_sum;
        }
    }

    // Extra-to-extra block -----------------------------------------------------------------------------------|
    // Q_xx = AB_xx + Q_xg * AB_gx.                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    // The nested loops are one block multiply:
    //   output extra row -> output extra column -> Gaussian feedback dot product.
    for (0..n_extra_streams) |extra_row_index| {
        const output_row = n_gauss + extra_row_index;
        const result_row_offset = output_row * n;
        const extra_to_gaussian_row_offset = extra_row_index * n_gauss;

        for (0..n_extra_streams) |extra_col_index| {
            const output_col = n_gauss + extra_col_index;
            var feedback_sum: f64 = 0.0;

            for (0..n_gauss) |gaussian_col| {
                feedback_sum += extra_to_gaussian[extra_to_gaussian_row_offset + gaussian_col] *
                    ab_product.data[gaussian_col * n + output_col];
            }

            // Extra-extra block:
            // Q_xx = AB_xx + AB_xg * inverse(I - AB_gg) * AB_gx.
            result.data[result_row_offset + output_col] =
                feedback_sum + ab_product.data[result_row_offset + output_col];
        }
    }

    return result;
}

fn qseriesFromProduct12x10(noalias ab: *const Mat) Mat {
    // qseriesFromProduct12x10 (Q(AB), fixed 12x10 return value) --------------------------------------------- |
    // Returning wrapper around qseriesFromProduct12x10Into.                                                   |
    // The caller-owned-output version holds the fixed 10x10 Gaussian solve and block fill.                    |
    // --------------------------------------------------------------------------------------------------------|

    var result: Mat = undefined;
    qseriesFromProduct12x10Into(&result, ab);
    return result;
}

fn qseriesFromProduct12x10Into(noalias result: *Mat, noalias ab: *const Mat) void {
    // qseriesFromProduct12x10Into (Q(AB), fixed 12x10) ------------------------------------------------------ |
    // Fixed n=12, n_gauss=10 version of qseriesFromProduct.                                                   |
    // Works on the same gg/gx/xg/xx split but keeps loop bounds constant for the compiler.                    |
    //                                                                                                         |
    // The first 10 rows/columns are Gaussian streams. The final 2 are extra directions.                       |
    // The 10x10 Gaussian block is LU-factorized, inverted, then used to fill all four blocks:                 |
    //                                                                                                         |
    //   Q_gg = inverse(I - AB_gg) - I                                                                         |
    //   Q_gx = inverse(I - AB_gg) * AB_gx                                                                     |
    //   Q_xg = AB_xg * inverse(I - AB_gg)                                                                     |
    //   Q_xx = AB_xx + Q_xg * AB_gx                                                                           |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: fixed q-series trace gate                                                                     |
    // Return AB directly when abs(trace(AB_gg)) < threshold_q = 1.0e-3.                                       |
    // --------------------------------------------------------------------------------------------------------|
    // Same cutoff as the generic rtm_config, but with fixed 10x10 Gaussian diagonal indexes.                  |
    // This avoids the fixed LU solve when the repeated-reflection correction is already negligible.           |

    var trab = ab.data[0];
    trab += ab.data[13];
    trab += ab.data[26];
    trab += ab.data[39];
    trab += ab.data[52];
    trab += ab.data[65];
    trab += ab.data[78];
    trab += ab.data[91];
    trab += ab.data[104];
    trab += ab.data[117];
    if (@abs(trab) < threshold_q) {
        result.* = ab.*;
        return;
    }
    // end tradeoff: fixed q-series trace gate ----------------------------------------------------------------|

    // Factorization matrix -----------------------------------------------------------------------------------|
    // Build the fixed 10x10 matrix M = I - AB_gg. The final two rows/columns are handled after the inverse.   |
    // --------------------------------------------------------------------------------------------------------|

    var one_minus_ab_gg: [rows.max_gauss * rows.max_gauss]f64 = undefined;
    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * 10 + j] = delta - ab.data[i * 12 + j];
        }
    }

    // Pivot bookkeeping --------------------------------------------------------------------------------------|
    // Fixed n=12 swaps full 10-wide rows when pivoting. The pivot array maps inverse right-hand sides.        |
    // --------------------------------------------------------------------------------------------------------|

    var pivot: [rows.max_gauss]usize = undefined;
    var inverse_diag: [rows.max_gauss]f64 = undefined;

    // Fixed LU storage ---------------------------------------------------------------------------------------|
    // one_minus_ab_gg holds M = I - AB_gg as a flat 10 by 10 table.                                           |
    //                                                                                                         |
    // pivot[i]        tells which original row now sits at factorization row i.                               |
    // inverse_diag[i] stores 1 / U[i,i] after each accepted pivot.                                            |
    //                                                                                                         |
    // This fixed rtm_config swaps the row contents directly, so it does not need pivot_offset.                |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..10) |i| {
        pivot[i] = i;
    }

    // Pivoted LU ---------------------------------------------------------------------------------------------|
    // Factor M into L and U in-place. A near-zero pivot returns the bounded AB fallback.                      |
    // --------------------------------------------------------------------------------------------------------|

    for (0..10) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[col * 10 + col]);
        var max_row: usize = col;
        for (col + 1..10) |row| {
            const val = @abs(one_minus_ab_gg[row * 10 + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }

        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;

            // Previous-column LU factors belong to the pivoted row too.
            inline for (0..10) |k| {
                const lhs = col * 10 + k;
                const rhs = max_row * 10 + k;
                const matrix_tmp = one_minus_ab_gg[lhs];
                one_minus_ab_gg[lhs] = one_minus_ab_gg[rhs];
                one_minus_ab_gg[rhs] = matrix_tmp;
            }
        }

        const diag = one_minus_ab_gg[col * 10 + col];

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: fixed LU pivot floor                                                                      |
        // Return AB directly when an LU pivot is smaller than lu_diagonal_floor = 1.0e-30.                    |
        // ----------------------------------------------------------------------------------------------------|
        // This avoids unstable division in the fixed 10x10 inverse. The fallback keeps the pre-inversion      |
        // product so the q-series correction remains bounded.                                                 |
        if (@abs(diag) < lu_diagonal_floor) {
            result.* = ab.*;
            return;
        }
        // end tradeoff: fixed LU pivot floor -----------------------------------------------------------------|

        const inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;
        const col_offset = col * 10;

        for (col + 1..10) |row| {
            const row_offset = row * 10;
            const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for (col + 1..10) |k| {
                one_minus_ab_gg[row_offset + k] -=
                    factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    // Inverse columns ----------------------------------------------------------------------------------------|
    // Solve M * x = one basis column at a time. Forward substitution builds y, back substitution builds x.    |
    //                                                                                                         |
    // rhs_col chooses one column of inverse(M). The solved x is written into inverse[:, rhs_col].             |
    // --------------------------------------------------------------------------------------------------------|

    var inverse: [rows.max_gauss * rows.max_gauss]f64 = undefined;
    for (0..10) |rhs_col| {
        var y: [rows.max_gauss]f64 = undefined;
        for (0..10) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = i * 10;
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [rows.max_gauss]f64 = undefined;
        var ii: usize = 10;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            const row_offset = ii * 10;
            for (ii + 1..10) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
            x[ii] = s * inverse_diag[ii];
        }
        inline for (0..10) |i| inverse[i * 10 + rhs_col] = x[i];
    }

    // Gaussian block -----------------------------------------------------------------------------------------|
    // Q_gg = inverse(I - AB_gg) - I.                                                                          |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.data[i * 12 + j] = inverse[i * 10 + j] - delta;
        }
    }

    // Gaussian-to-extra block --------------------------------------------------------------------------------|
    // Q_gx = inverse(I - AB_gg) * AB_gx.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..10) |i| {
        inline for (0..2) |ja| {
            const j = 10 + ja;
            var s: f64 = 0.0;
            inline for (0..10) |k| s += inverse[i * 10 + k] * ab.data[k * 12 + j];
            result.data[i * 12 + j] = s;
        }
    }

    // Extra-to-Gaussian block --------------------------------------------------------------------------------|
    // Q_xg = AB_xg * inverse(I - AB_gg).                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..2) |ia| {
        inline for (0..10) |j| {
            var s: f64 = 0.0;
            inline for (0..10) |k| s += ab.data[(10 + ia) * 12 + k] * inverse[k * 10 + j];
            result.data[(10 + ia) * 12 + j] = s;
        }
    }

    // Extra-to-extra block -----------------------------------------------------------------------------------|
    // Q_xx = AB_xx + Q_xg * AB_gx. This uses the Q_xg values already written into result.                     |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..2) |ia| {
        const i = 10 + ia;
        inline for (0..2) |ja| {
            const j = 10 + ja;
            var s: f64 = 0.0;
            inline for (0..10) |k| s += result.data[i * 12 + k] * ab.data[k * 12 + j];
            result.data[i * 12 + j] = s + ab.data[i * 12 + j];
        }
    }
}

fn esmul12(e: *const Vec, a: *const Mat) Mat {
    // esmul12 (left diagonal scale, fixed n=12) ------------------------------------------------------------- |
    // Fixed-shape version of esmul.                                                                           |
    //                                                                                                         |
    //   C[i,j] = e[i] * A[i,j]                                                                                |
    //                                                                                                         |
    // inline for keeps the source readable while generating constant-bound row and column code.               |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        var idx = j;
        inline for (0..12) |i| {
            result.data[idx] = e.data[i] * a.data[idx];
            idx += 12;
        }
    }
    return result;
}

fn semul12(a: *const Mat, e: *const Vec) Mat {
    // semul12 (right diagonal scale, fixed n=12 return value) ----------------------------------------------- |
    // Returning wrapper around semul12Into. The caller-owned-output version holds the actual fixed-shape loop.|
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    semul12Into(&result, a, e);
    return result;
}

fn semul12Into(noalias result: *Mat, a: *const Mat, e: *const Vec) void {
    // semul12Into (right diagonal scale, fixed n=12) -------------------------------------------------------- |
    // Fixed-shape version of semul.                                                                           |
    //                                                                                                         |
    //   C[i,j] = A[i,j] * e[j]                                                                                |
    //                                                                                                         |
    // The outer loop fixes column j once, then reuses e[j] down the column.                                   |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        inline for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej;
            idx += 12;
        }
    }
}

fn matAddSemul3_12(
    noalias a: *const Mat,
    noalias b: *const Mat,
    noalias e: *const Vec,
    noalias c: *const Mat,
) Mat {
    // matAddSemul3_12 (right diagonal scale plus two adds, fixed n=12) -------------------------------------- |
    // Fixed-shape fused right-diagonal scale plus two matrix adds.                                            |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + B[i,j] * e[j] + C[i,j]                                                            |
    //                                                                                                         |
    // inline for exposes all 12 rows and columns as compile-time bounds.                                      |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = (a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
    return result;
}
