const rows = @import("rows.zig");

const Mat = rows.Mat;

// matrix_12x10.zig -----------------------------------------------------------------------------------------  |
// Small LABOS matrix multiply kernels used by layer-doubling and q-series transport.                          |
//                                                                                                             |
// provenance                                                                                                  |
//   Trace gates, generic multiply shape, and the fixed 12x10 loop are ported from main:                       |
//   `src/forward_model/radiative_transfer/labos/matrix.zig` `smul`, `smulInto`, and `smul12x10Into`.          |
//                                                                                                             |
// math                                                                                                        |
//   C[i,j] = sum over Gaussian k of A[i,k] * B[k,j].                                                          |
//                                                                                                             |
// numerical guard                                                                                             |
//   threshold_mul is the LABOS product-size gate. When abs(trace(A_gg) * trace(B_gg)) is below the caller     |
//   threshold, the product is treated as negligible and a zero matrix is returned.                            |
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
