const types = @import("types.zig");

const Mat = types.Mat;
const Vec = types.Vec;

const threshold_q: f64 = 1.0e-3;
const lu_diagonal_floor: f64 = 1.0e-30;

// matrix.zig -------------------------------------------------------------------------------------------------|
// Small dense matrix kernels used by LABOS layer doubling and q-series solves.                                |
//                                                                                                             |
// stream layout                                                                                               |
//   n=12 means 10 Gaussian quadrature directions plus 2 extra directions.                                     |
//   Mat.data is row-major: index = row * n + column.                                                          |
//                                                                                                             |
// common fast path                                                                                            |
//   fixed 12x10 kernels keep the Gaussian sum unrolled and process two columns per vector.                    |
//   generic kernels keep the same formulas for other stream counts.                                           |
//   inline for is used to spell repeated rows/columns once while giving the compiler constant loop bounds.    |
//                                                                                                             |
// name shortcuts                                                                                              |
//   smul   = small matrix multiply: C = A * B over Gaussian k.                                                |
//   esmul  = left scale by vector e: C[i,j] = e[i] * A[i,j].                                                  |
//   semul  = right scale by vector e: C[i,j] = A[i,j] * e[j].                                                 |
//   qseries = LABOS multiple-scattering q-series transform from AB.                                           |
//                                                                                                             |
// math                                                                                                        |
//   C[i,j] = sum over Gaussian k of A[i,k] * B[k,j].                                                          |
//   Q(AB) = inverse(I - AB_gg) - I on the Gaussian block.                                                     |
//                                                                                                             |
// numbers                                                                                                     |
//   threshold_q skips q-series inversion when the AB trace is already tiny.                                   |
//   lu_diagonal_floor is the singular-pivot fallback for LU factorization.                                    |
//                                                                                                             |
// memory                                                                                                      |
//   Mat stores [144]f64 plus n: 1160 B (1.133 KiB), no unused bits.                                           |
// ------------------------------------------------------------------------------------------------------------|

pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    // smul (small matrix multiply with trace gate) -----------------------------------------------------------|
    // Multiply two LABOS small dense matrices over the Gaussian directions.                                   |
    //                                                                                                         |
    //   C[i,j] = sum k=0..n_gauss-1 A[i,k] * B[k,j]                                                           |
    //                                                                                                         |
    // The trace gate is the cheap early exit used by LABOS layer doubling. If trace(A_gg) * trace(B_gg) is    |
    // below threshold_mul, the full multiply is skipped and a zero matrix is returned.                        |
    // Fixed n=12, n_gauss=10 uses the hand-shaped vector-pair kernel below.                                   |
    //                                                                                                         |
    // Generic route:                                                                                          |
    //   1. choose output column j                                                                             |
    //   2. initialize C[:,j] with the k=0 Gaussian term                                                       |
    //   3. add the remaining Gaussian terms k=1..n_gauss-1                                                    |
    //   4. walk idx += n because one column is stored across row-major rows                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        // Fixed trace gate -----------------------------------------------------------------------------------|
        // The Gaussian block is the first 10x10 part of a 12x12 stream matrix.                                |
        // In row-major storage, its diagonal is:                                                              |
        //                                                                                                     |
        //   k       : 0   1   2   3   4   5   6   7    8    9                                                 |
        //   index   : 0  13  26  39  52  65  78  91  104  117                                                 |
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
        if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);

        // Retained fixed product -----------------------------------------------------------------------------|
        return smul12x10(a, b);
    }

    // Generic trace gate -------------------------------------------------------------------------------------|
    // Same test as the fixed route, but the diagonal stride is n+1 instead of the literal 13 above.           |
    var tra: f64 = 0.0;
    var trb: f64 = 0.0;
    for (0..n_gauss) |k| {
        const idx = k * n + k;
        tra += a.data[idx];
        trb += b.data[idx];
    }
    if (@abs(tra * trb) <= threshold_mul) return Mat.zero(n);
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = n };

    // Generic multiply ---------------------------------------------------------------------------------------|
    // Each j pass writes one output column. B[k,j] stays constant while idx walks C[i,j] down that column.    |
    // a_idx walks A[i,k] down the matching input column.                                                      |
    //                                                                                                         |
    //   result.data[idx]  means C[i,j]                                                                        |
    //   a.data[a_idx]     means A[i,k]                                                                        |
    //   bkj               means B[k,j]                                                                        |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n) |j| {
        if (n_gauss == 0) break;

        // First Gaussian term --------------------------------------------------------------------------------|
        // Initialize with k=0 so the later loop can use += for k=1..n_gauss-1.                                |
        // ----------------------------------------------------------------------------------------------------|

        const b0j = b.data[j];
        var idx = j;
        var a_idx: usize = 0;

        for (0..n) |_| {
            result.data[idx] = a.data[a_idx] * b0j;
            idx += n;
            a_idx += n;
        }

        // Remaining Gaussian terms ---------------------------------------------------------------------------|
        // Add the remaining Gaussian source directions to the same output column.                             |
        // ----------------------------------------------------------------------------------------------------|

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

pub inline fn smulInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    b: *const Mat,
) void {
    // smulInto (small matrix multiply into caller storage) ---------------------------------------------------|
    // Same trace-gated product as smul, but writes into caller-owned storage.                                 |
    //                                                                                                         |
    //   out = A * B over Gaussian k                                                                           |
    //                                                                                                         |
    // This avoids returning a Mat by value inside scattering-order loops. The fixed 12x10 route repeats the   |
    // trace scan here so it can call smul12x10Into directly when the product is retained.                     |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
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
        if (@abs(tra * trb) <= threshold_mul) {
            out.* = Mat.zero(n);
            return;
        }
        smul12x10Into(out, a, b);
        return;
    }
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
    // smulIntoKnownTraces (small matrix multiply with caller traces) -----------------------------------------|
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
    // smulIntoKnownTracesIfNonzero (trace-gated product probe) -----------------------------------------------|
    // Return false when the trace gate says A*B is negligible. Return true after writing the product into     |
    // caller storage.                                                                                         |
    //                                                                                                         |
    // Fused add/scale kernels use the boolean to choose between:                                              |
    //   retained product path                                                                                 |
    //   cheaper no-product path                                                                               |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(10_000);
    if (@abs(trace_a * trace_b) <= threshold_mul) {
        return false;
    }
    if (n == 12 and n_gauss == 10) {
        smul12x10Into(out, a, b);
        return true;
    }
    out.* = smulNonzeroProduct(n, n_gauss, a, b);
    return true;
}

pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    // qseries (thresholded product, then q-series transform) -------------------------------------------------|
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
    // qseriesKnownNonzeroProduct (q-series after retained product) -------------------------------------------|
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
    // qseriesKnownNonzeroProductInto (q-series into caller storage) ------------------------------------------|
    // Caller-owned-output version of qseriesKnownNonzeroProduct.                                              |
    //                                                                                                         |
    //   1. build retained AB = A * B                                                                          |
    //   2. write Q(AB) into out                                                                               |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 uses the same hand-shaped product kernel as smul12x10Into before the q-series    |
    // solve.                                                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    var ab: Mat = undefined;
    if (n == 12 and n_gauss == 10) {
        smul12x10Into(&ab, a, b);
    } else {
        ab = smulNonzeroProduct(n, n_gauss, a, b);
    }
    qseriesFromProductInto(out, n, n_gauss, &ab);
}

inline fn smul12x10(a: *const Mat, b: *const Mat) Mat {
    // smul12x10 (small matrix multiply, fixed 12x10 return value) --------------------------------------------|
    // Returning wrapper around smul12x10Into. The real optimized work is in the caller-owned-output kernel so |
    // fused paths can reuse the same fixed-shape implementation without temporary return plumbing.            |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    smul12x10Into(&result, a, b);
    return result;
}

inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    // smul12x10Into (small matrix multiply, fixed 12x10) -----------------------------------------------------|
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
    // loadPair (two-column f64 vector load) ------------------------------------------------------------------|
    // Read columns j and j+1 from one row as @Vector(2, f64). The optimized kernels use this to compute two   |
    // neighboring output columns with one vector expression.                                                  |
    //                                                                                                         |
    // align(1) is deliberate: Mat rows are contiguous, but the slice is not promised to be vector-aligned.    |
    // --------------------------------------------------------------------------------------------------------|

    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&row[j]);
    return pair.*;
}

inline fn storePair(row: []f64, comptime j: usize, values: @Vector(2, f64)) void {
    // storePair (two-column f64 vector store) ----------------------------------------------------------------|
    // Write columns j and j+1 from one @Vector(2, f64).                                                       |
    //                                                                                                         |
    //   lane 0 -> column j                                                                                    |
    //   lane 1 -> column j+1                                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    const pair: *align(1) @Vector(2, f64) = @ptrCast(&row[j]);
    pair.* = values;
}

pub fn esmul(n: usize, e: *const Vec, a: *const Mat) Mat {
    // esmul (left diagonal scale: diag(e) * A) ---------------------------------------------------------------|
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
    // semul (right diagonal scale: A * diag(e)) --------------------------------------------------------------|
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
    // matAdd (elementwise matrix add) ------------------------------------------------------------------------|
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
    // matAddSemul3 (right diagonal scale plus two adds) ------------------------------------------------------|
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

pub inline fn smulAddSemul3(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
) Mat {
    // smulAddSemul3 (small multiply plus right diagonal scale) -----------------------------------------------|
    // Fused LABOS update used in layer-combination algebra.                                                   |
    //                                                                                                         |
    //   product[i,j] = sum k=0..n_gauss-1 A[i,k] * C[k,j]                                                     |
    //   out[i,j]     = C[i,j] + A[i,j] * e[j] + product[i,j]                                                  |
    //                                                                                                         |
    // `smul` supplies the Gaussian product. `semul` supplies the right diagonal scale. The trace gate can     |
    // skip product and fall back to the cheaper right-scale add route.                                        |
    // --------------------------------------------------------------------------------------------------------|

    // Fused update: out = C + A*diag(e) + A*C over Gaussian k.
    if (n == 12 and n_gauss == 10) return smulAddSemul3_12(threshold_mul, a, e, c);
    var product: Mat = undefined;
    smulInto(&product, n, n_gauss, threshold_mul, a, c);
    return matAddSemul3(n, c, a, e, &product);
}

pub inline fn smulAddSemul3KnownRightTrace(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    trace_c: f64,
) Mat {
    // smulAddSemul3KnownRightTrace (small multiply plus right scale, trace(C_gg) known) ----------------------|
    // Same fused update as smulAddSemul3, but the caller already computed trace(C_gg).                        |
    //                                                                                                         |
    // This function scans only trace(A_gg), then uses both traces to decide whether A*C should be retained.   |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return smulAddSemul3_12KnownRightTrace(threshold_mul, a, e, c, trace_c);

    var trace_a: f64 = 0.0;
    for (0..n_gauss) |k| trace_a += a.data[k * n + k];

    var product: Mat = undefined;
    if (smulIntoKnownTracesIfNonzero(&product, n, n_gauss, threshold_mul, trace_a, trace_c, a, c)) {
        return matAddSemul3(n, c, a, e, &product);
    }
    return semulAdd(n, a, e, c);
}

pub inline fn smulAddSemul3KnownRightTraceInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    trace_c: f64,
) void {
    // smulAddSemul3KnownRightTraceInto (small multiply plus right scale into caller storage) -----------------|
    // Caller-owned-output version of smulAddSemul3KnownRightTrace.                                            |
    //                                                                                                         |
    // Used when the surrounding LABOS loop already owns the output buffer and already knows trace(C_gg).      |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) {
        return smulAddSemul3_12KnownRightTraceInto(out, threshold_mul, a, e, c, trace_c);
    }
    out.* = smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, a, e, c, trace_c);
}

pub inline fn matAddEsmul3(
    n: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
    c: *const Mat,
) Mat {
    // matAddEsmul3 (left diagonal scale plus two adds) -------------------------------------------------------|
    // Fused left-diagonal scale plus two matrix adds.                                                         |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + e[i] * B[i,j] + C[i,j]                                                            |
    //                                                                                                         |
    // `esmul` means scale on the left: each row i uses e[i]. Fixed n=12 dispatches to a constant-bound        |
    // kernel.                                                                                                 |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return matAddEsmul3_12(a, e, b, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {

            // Left-scale add: out[i,j] = A[i,j] + e[i] * B[i,j] + C[i,j].
            result.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

pub inline fn matAddEsmul3ProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
    c: *const Mat,
) void {
    // matAddEsmul3ProductKnownNonzeroInto (retained product plus left diagonal scale) ------------------------|
    // Caller already knows C*B should be retained. Write the fused left-scale plus product into caller        |
    // storage.                                                                                                |
    //                                                                                                         |
    //   product[i,j] = sum k=0..n_gauss-1 C[i,k] * B[k,j]                                                     |
    //   out[i,j]     = A[i,j] + e[i] * B[i,j] + product[i,j]                                                  |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return matAddEsmul3ProductKnownNonzero12x10Into(out, a, e, b, c);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += c.data[i * n + k] * b.data[k * n + j];
            const idx = i * n + j;

            // Retained product: out[i,j] = A[i,j] + e[i] * B[i,j] + sum k C[i,k] * B[k,j].
            out.data[idx] = (a.data[idx] + e.data[i] * b.data[idx]) + product;
        }
    }
}

pub inline fn matAddEsmul(n: usize, a: *const Mat, e: *const Vec, b: *const Mat) Mat {
    // matAddEsmul (left diagonal scale plus add) -------------------------------------------------------------|
    // Fused left-diagonal scale plus add.                                                                     |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + e[i] * B[i,j]                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return matAddEsmul12(a, e, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        var idx = j;
        for (0..n) |i| {

            // Left-scale add: out[i,j] = A[i,j] + e[i] * B[i,j].
            result.data[idx] = a.data[idx] + e.data[i] * b.data[idx];
            idx += n;
        }
    }
    return result;
}

pub inline fn matAddEsmulInto(
    noalias out: *Mat,
    n: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
) void {
    // matAddEsmulInto (left diagonal scale plus add into caller storage) -------------------------------------|
    // Caller-owned-output version of matAddEsmul.                                                             |
    // Fixed n=12 writes through matAddEsmul12Into; generic n delegates to the returning wrapper.              |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return matAddEsmul12Into(out, a, e, b);
    out.* = matAddEsmul(n, a, e, b);
}

pub inline fn semulAdd(n: usize, a: *const Mat, e: *const Vec, b: *const Mat) Mat {
    // semulAdd (right diagonal scale plus add) ---------------------------------------------------------------|
    // Fused right-diagonal scale plus add.                                                                    |
    //                                                                                                         |
    //   out[i,j] = A[i,j] * e[j] + B[i,j]                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return semulAdd12(a, e, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |_| {

            // Right-scale add: out[i,j] = A[i,j] * e[j] + B[i,j].
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += n;
        }
    }
    return result;
}

pub inline fn semulAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    a: *const Mat,
    e: *const Vec,
    b: *const Mat,
) void {
    // semulAddProductKnownNonzeroInto (retained product plus right diagonal scale) ---------------------------|
    // Caller already knows A*B should be retained. Write the right-scale base term plus the retained product  |
    // into caller storage.                                                                                    |
    //                                                                                                         |
    //   product[i,j] = sum k=0..n_gauss-1 A[i,k] * B[k,j]                                                     |
    //   out[i,j]     = A[i,j] * e[j] + product[i,j]                                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return semulAddProductKnownNonzero12x10Into(out, a, e, b);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += a.data[i * n + k] * b.data[k * n + j];
            const idx = i * n + j;

            // Retained product: out[i,j] = A[i,j] * e[j] + sum k A[i,k] * B[k,j].
            out.data[idx] = a.data[idx] * ej + product;
        }
    }
}

pub inline fn semulInto(noalias out: *Mat, n: usize, a: *const Mat, e: *const Vec) void {
    // semulInto (right diagonal scale into caller storage) ---------------------------------------------------|
    // Caller-owned-output version of semul.                                                                   |
    // Fixed n=12 writes through semul12Into; generic n delegates to the returning wrapper.                    |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return semul12Into(out, a, e);
    out.* = semul(n, a, e);
}

pub inline fn esmulSemul(
    n: usize,
    e: *const Vec,
    a: *const Mat,
    b: *const Mat,
) Mat {
    // esmulSemul (left and right diagonal scales) ------------------------------------------------------------|
    // Combine a left-diagonal scale and a right-diagonal scale.                                               |
    //                                                                                                         |
    //   out[i,j] = e[i] * A[i,j] + B[i,j] * e[j]                                                              |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return esmulSemul12(e, a, b);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {

            // Two-sided scale: out[i,j] = e[i] * A[i,j] + B[i,j] * e[j].
            result.data[idx] = e.data[i] * a.data[idx] + b.data[idx] * ej;
            idx += n;
        }
    }
    return result;
}

pub inline fn esmulSemulInto(
    noalias out: *Mat,
    n: usize,
    e: *const Vec,
    a: *const Mat,
    b: *const Mat,
) void {
    // esmulSemulInto (left and right diagonal scales into caller storage) ------------------------------------|
    // Caller-owned-output version of esmulSemul.                                                              |
    // Fixed n=12 writes through esmulSemul12Into; generic n delegates to the returning wrapper.               |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return esmulSemul12Into(out, e, a, b);
    out.* = esmulSemul(n, e, a, b);
}

pub inline fn esmulSemulSelfInto(noalias out: *Mat, n: usize, e: *const Vec, a: *const Mat) void {
    // esmulSemulSelfInto (self left and right diagonal scales into caller storage) ---------------------------|
    // Same matrix appears on both sides of the diagonal scaling.                                              |
    //                                                                                                         |
    //   out[i,j] = A[i,j] * (e[i] + e[j])                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return esmulSemulSelf12Into(out, e, a);
    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {

            // Symmetric scale: out[i,j] = A[i,j] * (e[i] + e[j]).
            out.data[idx] = a.data[idx] * (e.data[i] + ej);
            idx += n;
        }
    }
}

pub inline fn esmulSemulAdd(
    n: usize,
    e: *const Vec,
    a: *const Mat,
    b: *const Mat,
    c: *const Mat,
) Mat {
    // esmulSemulAdd (two diagonal scales plus add) -----------------------------------------------------------|
    // Combine both diagonal scales and add a third matrix.                                                    |
    //                                                                                                         |
    //   out[i,j] = e[i] * A[i,j] + B[i,j] * e[j] + C[i,j]                                                     |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12) return esmulSemulAdd12(e, a, b, c);
    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        var idx = j;
        for (0..n) |i| {

            // Two-sided scale plus add: out[i,j] = e[i] * A[i,j] + B[i,j] * e[j] + C[i,j].
            result.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + c.data[idx];
            idx += n;
        }
    }
    return result;
}

pub inline fn esmulSemulAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    e: *const Vec,
    a: *const Mat,
    b: *const Mat,
) void {
    // esmulSemulAddProductKnownNonzeroInto (retained product plus two diagonal scales) -----------------------|
    // Caller already knows B*A should be retained. Write both diagonal-scale terms plus the retained product  |
    // into caller storage.                                                                                    |
    //                                                                                                         |
    //   product[i,j] = sum k=0..n_gauss-1 B[i,k] * A[k,j]                                                     |
    //   out[i,j]     = e[i] * A[i,j] + B[i,j] * e[j] + product[i,j]                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return esmulSemulAddProductKnownNonzero12x10Into(out, e, a, b);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += b.data[i * n + k] * a.data[k * n + j];
            const idx = i * n + j;

            // Retained product: out[i,j] = e[i] * A[i,j] + B[i,j] * e[j] + sum k B[i,k] * A[k,j].
            out.data[idx] = (e.data[i] * a.data[idx] + b.data[idx] * ej) + product;
        }
    }
}

pub inline fn esmulSemulSelfAddProductKnownNonzeroInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    e: *const Vec,
    a: *const Mat,
) void {
    // esmulSemulSelfAddProductKnownNonzeroInto (retained self-product plus two diagonal scales) --------------|
    // Caller already knows A*A should be retained. Write the symmetric diagonal-scale term plus the retained  |
    // self-product into caller storage.                                                                       |
    //                                                                                                         |
    //   product[i,j] = sum k=0..n_gauss-1 A[i,k] * A[k,j]                                                     |
    //   out[i,j]     = A[i,j] * (e[i] + e[j]) + product[i,j]                                                  |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return esmulSemulSelfAddProductKnownNonzero12x10Into(out, e, a);

    out.* = .{ .data = undefined, .n = n };
    for (0..n) |j| {
        const ej = e.data[j];
        for (0..n) |i| {
            var product: f64 = 0.0;
            for (0..n_gauss) |k| product += a.data[i * n + k] * a.data[k * n + j];
            const idx = i * n + j;

            // Retained self-product: out[i,j] = A[i,j] * (e[i] + e[j]) + sum k A[i,k] * A[k,j].
            out.data[idx] = a.data[idx] * (e.data[i] + ej) + product;
        }
    }
}

fn esmul12(e: *const Vec, a: *const Mat) Mat {
    // esmul12 (left diagonal scale, fixed n=12) --------------------------------------------------------------|
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
    // semul12 (right diagonal scale, fixed n=12 return value) ------------------------------------------------|
    // Returning wrapper around semul12Into. The caller-owned-output version holds the actual fixed-shape loop.|
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    semul12Into(&result, a, e);
    return result;
}

fn semul12Into(noalias result: *Mat, a: *const Mat, e: *const Vec) void {
    // semul12Into (right diagonal scale, fixed n=12) ---------------------------------------------------------|
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

fn matAddSemul3_12(noalias a: *const Mat, noalias b: *const Mat, noalias e: *const Vec, noalias c: *const Mat) Mat {
    // matAddSemul3_12 (right diagonal scale plus two adds, fixed n=12) ---------------------------------------|
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

fn smulAddSemul3_12(threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat) Mat {
    // smulAddSemul3_12 (small multiply plus right diagonal scale, fixed 12x10) -------------------------------|
    // Fixed-shape entry point for the fused product/update path when neither Gaussian trace is known.         |
    //                                                                                                         |
    //   product = A*C over Gaussian k=0..9                                                                    |
    //   out     = C + A*diag(e) + product                                                                     |
    //                                                                                                         |
    // This wrapper scans trace(A_gg) and trace(C_gg), then calls the known-traces kernel so the threshold     |
    // decision stays in one place.                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    // Gaussian-block traces ----------------------------------------------------------------------------------|
    // The threshold uses only the 10 Gaussian directions, not the two extra view/solar columns.               |
    //                                                                                                         |
    //   trace(A_gg) = A[0,0] + A[1,1] + ... + A[9,9]                                                          |
    //   trace(C_gg) = C[0,0] + C[1,1] + ... + C[9,9]                                                          |
    //                                                                                                         |
    // Row-major n=12 puts diagonal slot k at k*12 + k = 13*k.                                                 |
    // That is why the hard-coded slots are 0, 13, 26, ..., 117.                                               |
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
    var trc = c.data[0];
    trc += c.data[13];
    trc += c.data[26];
    trc += c.data[39];
    trc += c.data[52];
    trc += c.data[65];
    trc += c.data[78];
    trc += c.data[91];
    trc += c.data[104];
    trc += c.data[117];
    // --------------------------------------------------------------------------------------------------------|

    return smulAddSemul3_12KnownTraces(threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownRightTrace(
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    trc: f64,
) Mat {
    // smulAddSemul3_12KnownRightTrace (small multiply plus right scale, trace(C_gg) known) -------------------|
    // Same fused update as smulAddSemul3_12, but the caller already has trace(C_gg).                          |
    //                                                                                                         |
    // This wrapper scans only trace(A_gg), then reuses the known-traces kernel.                               |
    // --------------------------------------------------------------------------------------------------------|

    // Gaussian-block trace -----------------------------------------------------------------------------------|
    // trace(C_gg) came from the caller. This wrapper only scans trace(A_gg).                                  |
    // Row-major n=12 puts A[k,k] at k*12 + k = 13*k for k = 0..9.                                             |
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
    // --------------------------------------------------------------------------------------------------------|

    return smulAddSemul3_12KnownTraces(threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownRightTraceInto(
    noalias result: *Mat,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    trc: f64,
) void {
    // smulAddSemul3_12KnownRightTraceInto (small multiply plus right scale into caller storage) --------------|
    // Caller-owned-output version when trace(C_gg) is already known.                                          |
    //                                                                                                         |
    // It scans trace(A_gg) only, then writes the fused update through the known-traces kernel.                |
    // --------------------------------------------------------------------------------------------------------|

    // Gaussian-block trace -----------------------------------------------------------------------------------|
    // trace(C_gg) came from the caller. This caller-owned-output wrapper only scans trace(A_gg).              |
    // Row-major n=12 puts A[k,k] at k*12 + k = 13*k for k = 0..9.                                             |
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
    // --------------------------------------------------------------------------------------------------------|

    smulAddSemul3_12KnownTracesInto(result, threshold_mul, a, e, c, tra, trc);
}

fn smulAddSemul3_12KnownTraces(
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    tra: f64,
    trc: f64,
) Mat {
    // smulAddSemul3_12KnownTraces (small multiply plus right scale, both traces known) -----------------------|
    // Returning wrapper around smulAddSemul3_12KnownTracesInto.                                               |
    // Both Gaussian traces are already available, so this does no diagonal scans itself.                      |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    smulAddSemul3_12KnownTracesInto(&result, threshold_mul, a, e, c, tra, trc);
    return result;
}

fn smulAddSemul3_12KnownTracesInto(
    noalias result: *Mat,
    threshold_mul: f64,
    a: *const Mat,
    e: *const Vec,
    c: *const Mat,
    tra: f64,
    trc: f64,
) void {
    // smulAddSemul3_12KnownTracesInto (small multiply plus right scale, fixed 12x10) -------------------------|
    // Fixed-shape fused kernel for the retained or skipped A*C update.                                        |
    //                                                                                                         |
    // If trace(A_gg) * trace(C_gg) is below threshold, the A*C product is skipped and the function writes     |
    // only C + A*diag(e). Otherwise it uses the same row broadcast / B-row / two-column vector-pair shape     |
    // as smul12x10Into, then adds the base C + A*diag(e) pair.                                                |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    if (@abs(tra * trc) <= threshold_mul) {
        // Product skipped ------------------------------------------------------------------------------------|
        // The Gaussian product A*C is small enough to ignore. Write only the base term:                       |
        //                                                                                                     |
        //   out[i, j : j+2] = C[i, j : j+2] + A[i, j : j+2] * e[j : j+2]                                      |
        // ----------------------------------------------------------------------------------------------------|

        inline for (0..12) |i| {
            const row = i * 12;
            const a_row = a.data[row .. row + 12];
            const c_row = c.data[row .. row + 12];
            const result_row = result.data[row .. row + 12];
            inline for (0..6) |pair_index| {
                const j = pair_index * 2;

                // Paired base path ---------------------------------------------------------------------------|
                // No Gaussian product is retained here. loadPair still handles columns j and j+1 together, so |
                // the skipped-product route keeps the same two-lane store shape for the base term.            |
                // --------------------------------------------------------------------------------------------|

                const value = loadPair(c_row, j) + loadPair(a_row, j) * loadPair(e.data[0..], j);
                storePair(result_row, j, value);
            }
        }
        return;
    }

    inline for (0..12) |i| {
        const row = i * 12;

        // A row scalars --------------------------------------------------------------------------------------|
        // Read A[i,0..9] once for this output row. The scalar values are splatted below so each one can       |
        // multiply a two-column pair from C.                                                                  |
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a2 = a.data[row + 2];
        const a3 = a.data[row + 3];
        const a4 = a.data[row + 4];
        const a5 = a.data[row + 5];
        const a6 = a.data[row + 6];
        const a7 = a.data[row + 7];
        const a8 = a.data[row + 8];
        const a9 = a.data[row + 9];
        // ----------------------------------------------------------------------------------------------------|

        // C Gaussian rows ------------------------------------------------------------------------------------|
        // c0..c9 are the right-hand rows used in product = A*C over Gaussian k.                               |
        const c0 = c.data[0..12];
        const c1 = c.data[12..24];
        const c2 = c.data[24..36];
        const c3 = c.data[36..48];
        const c4 = c.data[48..60];
        const c5 = c.data[60..72];
        const c6 = c.data[72..84];
        const c7 = c.data[84..96];
        const c8 = c.data[96..108];
        const c9 = c.data[108..120];
        // ----------------------------------------------------------------------------------------------------|

        // Local row slices -----------------------------------------------------------------------------------|
        // These rows are loaded in two-column pairs inside the inner loop.                                    |
        //                                                                                                     |
        //   A[i,j:j+2]          right-scale base term                                                         |
        //   C[i,j:j+2]          base add term                                                                 |
        //   result[i,j:j+2]     two output columns                                                            |
        const a_row = a.data[row .. row + 12];
        const c_row = c.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        // ----------------------------------------------------------------------------------------------------|

        // A row broadcasts -----------------------------------------------------------------------------------|
        // Copy A[i,0..9] into both SIMD lanes so each A[i,k] multiplies C[k,j] and C[k,j+1].                  |
        //                                                                                                     |
        //   a0v = [A[i,0], A[i,0]]                                                                            |
        //   a1v = [A[i,1], A[i,1]]                                                                            |
        //   ...                                                                                               |
        //   a9v = [A[i,9], A[i,9]]                                                                            |
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        // ----------------------------------------------------------------------------------------------------|
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Product pair plus base pair --------------------------------------------------------------------|
            // First compute product[j:j+2] = sum k=0..9 A[i,k] * C[k,j:j+2].                                  |
            // Then add the local base term C[i,j:j+2] + A[i,j:j+2] * e[j:j+2].                                |
            // ------------------------------------------------------------------------------------------------|

            var product = a0v * loadPair(c0, j);
            product += a1v * loadPair(c1, j);
            product += a2v * loadPair(c2, j);
            product += a3v * loadPair(c3, j);
            product += a4v * loadPair(c4, j);
            product += a5v * loadPair(c5, j);
            product += a6v * loadPair(c6, j);
            product += a7v * loadPair(c7, j);
            product += a8v * loadPair(c8, j);
            product += a9v * loadPair(c9, j);
            const base = loadPair(c_row, j) + loadPair(a_row, j) * loadPair(e.data[0..], j);

            // ARM64 SIMD codegen proof -----------------------------------------------------------------------|
            // Retained primitive harness symbols codegen_smul_add_semul3_12 and                               |
            // codegen_smul_add_semul3_known_right_trace_12 both call this known-traces shape.                 |
            // Current ReleaseFast disassembly for the shared pair loop includes:                              |
            //                                                                                                 |
            //   fmul.2d   v4, v29, v5[0]          multiply two f64 lanes by one row scalar                    |
            //   fadd.2d   v4, v4, v23             add two f64 product lanes                                   |
            //   str       q3, [sp, #0x400]        store two f64 result lanes                                  |
            //                                                                                                 |
            // Retained harness mix: 1729 floating-point arithmetic instructions, zero floating-point divides. |
            // ------------------------------------------------------------------------------------------------|

            storePair(result_row, j, base + product);
        }
    }
}

fn matAddEsmul3_12(
    noalias a: *const Mat,
    noalias e: *const Vec,
    noalias b: *const Mat,
    noalias c: *const Mat,
) Mat {
    // matAddEsmul3_12 (left diagonal scale plus two adds, fixed n=12 return value) ---------------------------|
    // Returning wrapper around matAddEsmul3_12Into. The caller-owned-output version holds the fixed-shape     |
    // left-diagonal scale plus add loop.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    matAddEsmul3_12Into(&result, a, e, b, c);
    return result;
}

fn matAddEsmul3_12Into(
    noalias result: *Mat,
    noalias a: *const Mat,
    noalias e: *const Vec,
    noalias b: *const Mat,
    noalias c: *const Mat,
) void {
    // matAddEsmul3_12Into (left diagonal scale plus two adds, fixed n=12) ------------------------------------|
    // Fixed-shape left-diagonal scale plus two matrix adds.                                                   |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + e[i] * B[i,j] + C[i,j]                                                            |
    //                                                                                                         |
    // The row scale e[i] is loaded once per row, then reused across all 12 columns.                           |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = (a.data[idx] + ei * b.data[idx]) + c.data[idx];
        }
    }
}

fn matAddEsmul12(noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) Mat {
    // matAddEsmul12 (left diagonal scale plus add, fixed n=12 return value) ----------------------------------|
    // Returning wrapper around matAddEsmul12Into.                                                             |
    // The caller-owned-output version holds the fixed-shape left-diagonal scale plus add loop.                |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    matAddEsmul12Into(&result, a, e, b);
    return result;
}

fn matAddEsmul12Into(
    noalias result: *Mat,
    noalias a: *const Mat,
    noalias e: *const Vec,
    noalias b: *const Mat,
) void {
    // matAddEsmul12Into (left diagonal scale plus add, fixed n=12) -------------------------------------------|
    // Fixed-shape left-diagonal scale plus add.                                                               |
    //                                                                                                         |
    //   out[i,j] = A[i,j] + e[i] * B[i,j]                                                                     |
    //                                                                                                         |
    // The row scale e[i] is loaded once per row, then reused across all 12 columns.                           |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = a.data[idx] + ei * b.data[idx];
        }
    }
}

fn matAddEsmul3ProductKnownNonzero12x10Into(
    noalias result: *Mat,
    noalias a: *const Mat,
    noalias e: *const Vec,
    noalias b: *const Mat,
    noalias c: *const Mat,
) void {
    // matAddEsmul3ProductKnownNonzero12x10Into (retained product plus left scale, fixed 12x10) ---------------|
    // Fixed-shape fused kernel after the caller has already retained C*B.                                     |
    //                                                                                                         |
    // C*B uses the Gaussian sum k=0..9. For each row i, C[i,0..9] is splatted once, then reused while the     |
    // loop walks B column pairs. The local base term A + diag(e)*B is added after the product pair.           |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;

        // C row scalars --------------------------------------------------------------------------------------|
        // Read C[i,0..9] once for this output row. Each value becomes a two-lane vector below.                |
        const c0 = c.data[row];
        const c1 = c.data[row + 1];
        const c2 = c.data[row + 2];
        const c3 = c.data[row + 3];
        const c4 = c.data[row + 4];
        const c5 = c.data[row + 5];
        const c6 = c.data[row + 6];
        const c7 = c.data[row + 7];
        const c8 = c.data[row + 8];
        const c9 = c.data[row + 9];
        // ----------------------------------------------------------------------------------------------------|

        // B Gaussian rows ------------------------------------------------------------------------------------|
        // b0..b9 are the B rows used in product = C*B over Gaussian k.                                        |
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

        // Local row slices -----------------------------------------------------------------------------------|
        // These rows are loaded in two-column pairs inside the inner loop.                                    |
        //                                                                                                     |
        //   A[i,j:j+2]          base add term                                                                 |
        //   B[i,j:j+2]          left-scale base term                                                          |
        //   result[i,j:j+2]     two output columns                                                            |
        const a_row = a.data[row .. row + 12];
        const b_row = b.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        // ----------------------------------------------------------------------------------------------------|

        // Row scale and C broadcasts -------------------------------------------------------------------------|
        // e[i] is copied into both lanes because the left-scale base uses the same row scale for both output  |
        // columns. C[i,0..9] is copied the same way so each C[i,k] multiplies B[k,j] and B[k,j+1].            |
        //                                                                                                     |
        //   ei  = [e[i], e[i]]                                                                                |
        //   c0v = [C[i,0], C[i,0]]                                                                            |
        //   c1v = [C[i,1], C[i,1]]                                                                            |
        //   ...                                                                                               |
        //   c9v = [C[i,9], C[i,9]]                                                                            |
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const c0v: @Vector(2, f64) = @splat(c0);
        const c1v: @Vector(2, f64) = @splat(c1);
        const c2v: @Vector(2, f64) = @splat(c2);
        const c3v: @Vector(2, f64) = @splat(c3);
        const c4v: @Vector(2, f64) = @splat(c4);
        const c5v: @Vector(2, f64) = @splat(c5);
        const c6v: @Vector(2, f64) = @splat(c6);
        const c7v: @Vector(2, f64) = @splat(c7);
        const c8v: @Vector(2, f64) = @splat(c8);
        const c9v: @Vector(2, f64) = @splat(c9);
        // ----------------------------------------------------------------------------------------------------|
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Product pair plus base pair --------------------------------------------------------------------|
            // product[j:j+2] = sum k=0..9 C[i,k] * B[k,j:j+2].                                                |
            // base[j:j+2]    = A[i,j:j+2] + e[i] * B[i,j:j+2].                                                |
            // ------------------------------------------------------------------------------------------------|

            var product = c0v * loadPair(b0, j);
            product += c1v * loadPair(b1, j);
            product += c2v * loadPair(b2, j);
            product += c3v * loadPair(b3, j);
            product += c4v * loadPair(b4, j);
            product += c5v * loadPair(b5, j);
            product += c6v * loadPair(b6, j);
            product += c7v * loadPair(b7, j);
            product += c8v * loadPair(b8, j);
            product += c9v * loadPair(b9, j);
            const value = (loadPair(a_row, j) + ei * loadPair(b_row, j)) + product;

            // SIMD source shape and retained codegen ---------------------------------------------------------|
            // This is the same two-column dot-product shape as smulAddSemul3_12KnownTracesInto:               |
            // splat one row scalar, load B[k,j:j+2], add two product lanes, then store one output pair.       |
            // The retained ARM64 harness for that shared shape lowers to fmul.2d / fadd.2d and q-register     |
            // stores, with zero floating-point divides.                                                       |
            // ------------------------------------------------------------------------------------------------|

            storePair(result_row, j, value);
        }
    }
}

fn semulAdd12(noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) Mat {
    // semulAdd12 (right diagonal scale plus add, fixed n=12 return value) ------------------------------------|
    // Returning wrapper around semulAdd12Into.                                                                |
    // The caller-owned-output version holds the fixed-shape right-diagonal scale plus add loop.               |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    semulAdd12Into(&result, a, e, b);
    return result;
}

fn semulAdd12Into(noalias result: *Mat, noalias a: *const Mat, noalias e: *const Vec, noalias b: *const Mat) void {
    // semulAdd12Into (right diagonal scale plus add, fixed n=12) ---------------------------------------------|
    // Fixed-shape right-diagonal scale plus add.                                                              |
    //                                                                                                         |
    //   out[i,j] = A[i,j] * e[j] + B[i,j]                                                                     |
    //                                                                                                         |
    // The column scale e[j] is loaded once, then reused down that column.                                     |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |j| {
        const ej = e.data[j];
        var idx = j;
        inline for (0..12) |_| {
            result.data[idx] = a.data[idx] * ej + b.data[idx];
            idx += 12;
        }
    }
}

fn semulAddProductKnownNonzero12x10Into(
    noalias result: *Mat,
    noalias a: *const Mat,
    noalias e: *const Vec,
    noalias b: *const Mat,
) void {
    // semulAddProductKnownNonzero12x10Into (retained product plus right scale, fixed 12x10) ------------------|
    // Fixed-shape fused kernel after the caller has already retained A*B.                                     |
    //                                                                                                         |
    // A*B uses the Gaussian sum k=0..9. For each row i, A[i,0..9] is splatted once, then reused while the     |
    // loop walks B column pairs. The local base term A*diag(e) is added after the product pair.               |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;

        // A row scalars --------------------------------------------------------------------------------------|
        // Read A[i,0..9] once for this output row. Each value becomes a two-lane vector below.                |
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a2 = a.data[row + 2];
        const a3 = a.data[row + 3];
        const a4 = a.data[row + 4];
        const a5 = a.data[row + 5];
        const a6 = a.data[row + 6];
        const a7 = a.data[row + 7];
        const a8 = a.data[row + 8];
        const a9 = a.data[row + 9];
        // ----------------------------------------------------------------------------------------------------|

        // B Gaussian rows ------------------------------------------------------------------------------------|
        // b0..b9 are the B rows used in product = A*B over Gaussian k.                                        |
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

        // Local row slices -----------------------------------------------------------------------------------|
        // A[i,j:j+2] supplies the right-scale base term. result[i,j:j+2] receives the two output columns.     |
        const a_row = a.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        // ----------------------------------------------------------------------------------------------------|

        // A row broadcasts -----------------------------------------------------------------------------------|
        // Copy A[i,0..9] into both SIMD lanes so each A[i,k] multiplies B[k,j] and B[k,j+1].                  |
        //                                                                                                     |
        //   a0v = [A[i,0], A[i,0]]                                                                            |
        //   a1v = [A[i,1], A[i,1]]                                                                            |
        //   ...                                                                                               |
        //   a9v = [A[i,9], A[i,9]]                                                                            |
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        // ----------------------------------------------------------------------------------------------------|
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Product pair plus right-scale pair -------------------------------------------------------------|
            // product[j:j+2] = sum k=0..9 A[i,k] * B[k,j:j+2].                                                |
            // base[j:j+2]    = A[i,j:j+2] * e[j:j+2].                                                         |
            // ------------------------------------------------------------------------------------------------|

            var product = a0v * loadPair(b0, j);
            product += a1v * loadPair(b1, j);
            product += a2v * loadPair(b2, j);
            product += a3v * loadPair(b3, j);
            product += a4v * loadPair(b4, j);
            product += a5v * loadPair(b5, j);
            product += a6v * loadPair(b6, j);
            product += a7v * loadPair(b7, j);
            product += a8v * loadPair(b8, j);
            product += a9v * loadPair(b9, j);
            const value = loadPair(a_row, j) * loadPair(e.data[0..], j) + product;

            // SIMD source shape and retained codegen ---------------------------------------------------------|
            // Each product line multiplies A[i,k] across the two output columns B[k,j] and B[k,j+1].          |
            // This is the same pair-loop shape as the retained smulAdd proof above: one splat, one            |
            // two-lane load, one two-lane multiply-add chain, then one two-lane store.                        |
            // ------------------------------------------------------------------------------------------------|

            storePair(result_row, j, value);
        }
    }
}

fn esmulSemul12(noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat) Mat {
    // esmulSemul12 (left and right diagonal scales, fixed n=12 return value) ---------------------------------|
    // Returning wrapper around esmulSemul12Into.                                                              |
    // The caller-owned-output version holds the fixed-shape two-sided diagonal scale loop.                    |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    esmulSemul12Into(&result, e, a, b);
    return result;
}

fn esmulSemul12Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat, noalias b: *const Mat) void {
    // esmulSemul12Into (left and right diagonal scales, fixed n=12) ------------------------------------------|
    // Fixed-shape two-sided diagonal scale.                                                                   |
    //                                                                                                         |
    //   left term  : e[i] * A[i,j]                                                                            |
    //   right term : B[i,j] * e[j]                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = ei * a.data[idx] + b.data[idx] * ej;
        }
    }
}

fn esmulSemulSelf12Into(noalias result: *Mat, noalias e: *const Vec, noalias a: *const Mat) void {
    // esmulSemulSelf12Into (self left and right diagonal scales, fixed n=12) ---------------------------------|
    // Same matrix appears on both sides of the diagonal scale.                                                |
    //                                                                                                         |
    //   out[i,j] = A[i,j] * (e[i] + e[j])                                                                     |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            result.data[idx] = a.data[idx] * (ei + e.data[j]);
        }
    }
}

fn esmulSemulAdd12(
    noalias e: *const Vec,
    noalias a: *const Mat,
    noalias b: *const Mat,
    noalias c: *const Mat,
) Mat {
    // esmulSemulAdd12 (two diagonal scales plus add, fixed n=12 return value) --------------------------------|
    // Returning wrapper around esmulSemulAdd12Into.                                                           |
    // The caller-owned-output version holds the fixed-shape two-sided diagonal scale plus add loop.           |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = 12 };
    esmulSemulAdd12Into(&result, e, a, b, c);
    return result;
}

fn esmulSemulAdd12Into(
    noalias result: *Mat,
    noalias e: *const Vec,
    noalias a: *const Mat,
    noalias b: *const Mat,
    noalias c: *const Mat,
) void {
    // esmulSemulAdd12Into (two diagonal scales plus add, fixed n=12) -----------------------------------------|
    // Fixed-shape two-sided diagonal scale plus add.                                                          |
    //                                                                                                         |
    //   left term  : e[i] * A[i,j]                                                                            |
    //   right term : B[i,j] * e[j]                                                                            |
    //   add term   : C[i,j]                                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;
        const ei = e.data[i];
        inline for (0..12) |j| {
            const idx = row + j;
            const ej = e.data[j];
            result.data[idx] = (ei * a.data[idx] + b.data[idx] * ej) + c.data[idx];
        }
    }
}

fn esmulSemulAddProductKnownNonzero12x10Into(
    noalias result: *Mat,
    noalias e: *const Vec,
    noalias a: *const Mat,
    noalias b: *const Mat,
) void {
    // esmulSemulAddProductKnownNonzero12x10Into (retained product plus two scales, fixed 12x10) --------------|
    // Fixed-shape fused kernel after the caller has already retained B*A.                                     |
    //                                                                                                         |
    // B*A uses the Gaussian sum k=0..9. For each row i, B[i,0..9] is splatted once, then reused while the     |
    // loop walks A column pairs. The two diagonal-scale terms are added after the product pair.               |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;

        // B row scalars --------------------------------------------------------------------------------------|
        // Read B[i,0..9] once for this output row. Each value becomes a two-lane vector below.                |
        const b0 = b.data[row];
        const b1 = b.data[row + 1];
        const b2 = b.data[row + 2];
        const b3 = b.data[row + 3];
        const b4 = b.data[row + 4];
        const b5 = b.data[row + 5];
        const b6 = b.data[row + 6];
        const b7 = b.data[row + 7];
        const b8 = b.data[row + 8];
        const b9 = b.data[row + 9];
        // ----------------------------------------------------------------------------------------------------|

        // A Gaussian rows ------------------------------------------------------------------------------------|
        // a0..a9 are the A rows used in product = B*A over Gaussian k.                                        |
        const a0 = a.data[0..12];
        const a1 = a.data[12..24];
        const a2 = a.data[24..36];
        const a3 = a.data[36..48];
        const a4 = a.data[48..60];
        const a5 = a.data[60..72];
        const a6 = a.data[72..84];
        const a7 = a.data[84..96];
        const a8 = a.data[96..108];
        const a9 = a.data[108..120];
        // ----------------------------------------------------------------------------------------------------|

        // Local row slices -----------------------------------------------------------------------------------|
        // These rows are loaded in two-column pairs inside the inner loop.                                    |
        //                                                                                                     |
        //   A[i,j:j+2]          left-scale base term                                                          |
        //   B[i,j:j+2]          right-scale base term                                                         |
        //   result[i,j:j+2]     two output columns                                                            |
        const a_row = a.data[row .. row + 12];
        const b_row = b.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        // ----------------------------------------------------------------------------------------------------|

        // Row scale and B broadcasts -------------------------------------------------------------------------|
        // e[i] is copied into both lanes because the left-scale base uses the same row scale for both output  |
        // columns. B[i,0..9] is copied the same way so each B[i,k] multiplies A[k,j] and A[k,j+1].            |
        //                                                                                                     |
        //   ei  = [e[i], e[i]]                                                                                |
        //   b0v = [B[i,0], B[i,0]]                                                                            |
        //   b1v = [B[i,1], B[i,1]]                                                                            |
        //   ...                                                                                               |
        //   b9v = [B[i,9], B[i,9]]                                                                            |
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const b0v: @Vector(2, f64) = @splat(b0);
        const b1v: @Vector(2, f64) = @splat(b1);
        const b2v: @Vector(2, f64) = @splat(b2);
        const b3v: @Vector(2, f64) = @splat(b3);
        const b4v: @Vector(2, f64) = @splat(b4);
        const b5v: @Vector(2, f64) = @splat(b5);
        const b6v: @Vector(2, f64) = @splat(b6);
        const b7v: @Vector(2, f64) = @splat(b7);
        const b8v: @Vector(2, f64) = @splat(b8);
        const b9v: @Vector(2, f64) = @splat(b9);
        // ----------------------------------------------------------------------------------------------------|
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Product pair plus two diagonal-scale pairs -----------------------------------------------------|
            // product[j:j+2] = sum k=0..9 B[i,k] * A[k,j:j+2].                                                |
            // base[j:j+2]    = e[i] * A[i,j:j+2] + B[i,j:j+2] * e[j:j+2].                                     |
            // ------------------------------------------------------------------------------------------------|

            var product = b0v * loadPair(a0, j);
            product += b1v * loadPair(a1, j);
            product += b2v * loadPair(a2, j);
            product += b3v * loadPair(a3, j);
            product += b4v * loadPair(a4, j);
            product += b5v * loadPair(a5, j);
            product += b6v * loadPair(a6, j);
            product += b7v * loadPair(a7, j);
            product += b8v * loadPair(a8, j);
            product += b9v * loadPair(a9, j);
            const value =
                (ei * loadPair(a_row, j) + loadPair(b_row, j) * loadPair(e.data[0..], j)) +
                product;

            // SIMD source shape and retained codegen ---------------------------------------------------------|
            // The retained product is B*A, but the vector shape is the same: B[i,k] is copied into both       |
            // lanes, A[k,j:j+2] is loaded as one pair, and the result pair is stored once.                    |
            // The extra scale terms use the same j:j+2 pair, so they do not change the two-lane layout.       |
            // ------------------------------------------------------------------------------------------------|

            storePair(result_row, j, value);
        }
    }
}

fn esmulSemulSelfAddProductKnownNonzero12x10Into(
    noalias result: *Mat,
    noalias e: *const Vec,
    noalias a: *const Mat,
) void {
    // esmulSemulSelfAddProductKnownNonzero12x10Into (retained self-product plus two scales, fixed 12x10) -----|
    // Fixed-shape fused kernel after the caller has already retained A*A.                                     |
    //                                                                                                         |
    // A*A uses the Gaussian sum k=0..9. The same matrix supplies both the row scalars and the Gaussian rows.  |
    // The symmetric diagonal-scale term A[i,j] * (e[i] + e[j]) is added after the product pair.               |
    // --------------------------------------------------------------------------------------------------------|

    @setEvalBranchQuota(20_000);
    result.* = .{ .data = undefined, .n = 12 };
    inline for (0..12) |i| {
        const row = i * 12;

        // A row scalars --------------------------------------------------------------------------------------|
        // Read A[i,0..9] once for this output row. Each value becomes a two-lane vector below.                |
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a2 = a.data[row + 2];
        const a3 = a.data[row + 3];
        const a4 = a.data[row + 4];
        const a5 = a.data[row + 5];
        const a6 = a.data[row + 6];
        const a7 = a.data[row + 7];
        const a8 = a.data[row + 8];
        const a9 = a.data[row + 9];
        // ----------------------------------------------------------------------------------------------------|

        // A Gaussian rows ------------------------------------------------------------------------------------|
        // c0..c9 are A rows used as the right-hand side of product = A*A over Gaussian k.                     |
        const c0 = a.data[0..12];
        const c1 = a.data[12..24];
        const c2 = a.data[24..36];
        const c3 = a.data[36..48];
        const c4 = a.data[48..60];
        const c5 = a.data[60..72];
        const c6 = a.data[72..84];
        const c7 = a.data[84..96];
        const c8 = a.data[96..108];
        const c9 = a.data[108..120];
        // ----------------------------------------------------------------------------------------------------|

        // Local row slices -----------------------------------------------------------------------------------|
        // A[i,j:j+2] supplies the symmetric scale term. result[i,j:j+2] receives the two output columns.      |
        const a_row = a.data[row .. row + 12];
        const result_row = result.data[row .. row + 12];
        // ----------------------------------------------------------------------------------------------------|

        // Row scale and A broadcasts -------------------------------------------------------------------------|
        // e[i] is copied into both lanes for the symmetric scale. A[i,0..9] is copied the same way so each    |
        // A[i,k] multiplies A[k,j] and A[k,j+1].                                                              |
        //                                                                                                     |
        //   ei  = [e[i], e[i]]                                                                                |
        //   a0v = [A[i,0], A[i,0]]                                                                            |
        //   a1v = [A[i,1], A[i,1]]                                                                            |
        //   ...                                                                                               |
        //   a9v = [A[i,9], A[i,9]]                                                                            |
        const ei: @Vector(2, f64) = @splat(e.data[i]);
        const a0v: @Vector(2, f64) = @splat(a0);
        const a1v: @Vector(2, f64) = @splat(a1);
        const a2v: @Vector(2, f64) = @splat(a2);
        const a3v: @Vector(2, f64) = @splat(a3);
        const a4v: @Vector(2, f64) = @splat(a4);
        const a5v: @Vector(2, f64) = @splat(a5);
        const a6v: @Vector(2, f64) = @splat(a6);
        const a7v: @Vector(2, f64) = @splat(a7);
        const a8v: @Vector(2, f64) = @splat(a8);
        const a9v: @Vector(2, f64) = @splat(a9);
        // ----------------------------------------------------------------------------------------------------|
        inline for (0..6) |pair_index| {
            const j = pair_index * 2;

            // Self-product pair plus symmetric scale ---------------------------------------------------------|
            // product[j:j+2] = sum k=0..9 A[i,k] * A[k,j:j+2].                                                |
            // base[j:j+2]    = A[i,j:j+2] * (e[i] + e[j:j+2]).                                                |
            // ------------------------------------------------------------------------------------------------|

            var product = a0v * loadPair(c0, j);
            product += a1v * loadPair(c1, j);
            product += a2v * loadPair(c2, j);
            product += a3v * loadPair(c3, j);
            product += a4v * loadPair(c4, j);
            product += a5v * loadPair(c5, j);
            product += a6v * loadPair(c6, j);
            product += a7v * loadPair(c7, j);
            product += a8v * loadPair(c8, j);
            product += a9v * loadPair(c9, j);
            const value = loadPair(a_row, j) * (ei + loadPair(e.data[0..], j)) + product;

            // SIMD source shape and retained codegen ---------------------------------------------------------|
            // The self-product still follows the same pair-loop proof: A[i,k] is splatted, A[k,j:j+2] is      |
            // loaded as two lanes, and the symmetric scale term is added to the same output pair.             |
            // ------------------------------------------------------------------------------------------------|

            storePair(result_row, j, value);
        }
    }
}

inline fn qseriesFromProductInto(noalias out: *Mat, n: usize, n_gauss: usize, noalias ab: *const Mat) void {
    // qseriesFromProductInto (Q(AB) into caller storage) -----------------------------------------------------|
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

inline fn qseriesFromProduct(n: usize, n_gauss: usize, noalias ab: *const Mat) Mat {
    // qseriesFromProduct (build Q(AB) from a retained AB product) --------------------------------------------|
    // Turn an already-built AB product into the LABOS q-series matrix.                                        |
    //                                                                                                         |
    // Split AB by stream kind:                                                                                |
    //   [ gg | gx ]                                                                                           |
    //   [ xg | xx ]                                                                                           |
    //                                                                                                         |
    //   Q_gg = inverse(I - AB_gg) - I                                                                         |
    //   Q_gx = inverse(I - AB_gg) * AB_gx                                                                     |
    //   Q_xg = AB_xg * inverse(I - AB_gg)                                                                     |
    //   Q_xx = AB_xx + Q_xg * AB_gx                                                                           |
    //                                                                                                         |
    // The generic route keeps row swaps as pivot offsets. The fixed 12x10 route below swaps full 10-wide      |
    // rows because its bounds are constant.                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return qseriesFromProduct12x10(ab);

    // Product trace gate -------------------------------------------------------------------------------------|
    // A tiny trace means AB already has negligible Gaussian feedback, so the q-series correction is skipped.  |
    // --------------------------------------------------------------------------------------------------------|

    var trab: f64 = 0.0;
    for (0..n_gauss) |k| trab += ab.data[k * n + k];
    if (@abs(trab) < threshold_q) return ab.*;

    const n_extra = n - n_gauss;

    // Factorization matrix -----------------------------------------------------------------------------------|
    // Build M = I - AB_gg. Only the Gaussian block is inverted; the extra rows/columns are filled afterward.  |
    // --------------------------------------------------------------------------------------------------------|

    var one_minus_ab_gg: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;

            // Factorization target: M = I - AB restricted to Gaussian streams.
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.data[i * n + j];
        }
    }

    var pivot: [types.max_gauss]usize = undefined;
    var pivot_offset: [types.max_gauss]usize = undefined;
    var inverse_diag: [types.max_gauss]f64 = undefined;

    // Pivot bookkeeping --------------------------------------------------------------------------------------|
    // Generic n keeps row swaps as offsets into M. That avoids moving an entire max_gauss row for every pivot.|
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_gauss) |i| {
        pivot[i] = i;
        pivot_offset[i] = i * n_gauss;
    }

    // Pivoted LU ---------------------------------------------------------------------------------------------|
    // Factor M into L and U in-place. A near-zero pivot falls back to AB instead of producing unstable Q.     |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_gauss) |col| {
        var max_val: f64 = @abs(one_minus_ab_gg[pivot_offset[col] + col]);
        var max_row: usize = col;
        for (col + 1..n_gauss) |row| {
            const val = @abs(one_minus_ab_gg[pivot_offset[row] + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }

        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;

            const tmp_offset = pivot_offset[col];
            pivot_offset[col] = pivot_offset[max_row];
            pivot_offset[max_row] = tmp_offset;
        }

        const diag = one_minus_ab_gg[pivot_offset[col] + col];
        if (@abs(diag) < lu_diagonal_floor) return ab.*;

        const inv_diag = 1.0 / diag;
        inverse_diag[col] = inv_diag;

        for (col + 1..n_gauss) |row| {
            const row_offset = pivot_offset[row];
            const col_offset = pivot_offset[col];
            const factor = one_minus_ab_gg[row_offset + col] * inv_diag;
            one_minus_ab_gg[row_offset + col] = factor;
            for (col + 1..n_gauss) |k| {

                // LU elimination update: M[row,k] -= factor * M[col,k].
                one_minus_ab_gg[row_offset + k] -=
                    factor * one_minus_ab_gg[col_offset + k];
            }
        }
    }

    // Inverse columns ----------------------------------------------------------------------------------------|
    // Solve M * x = one basis column at a time. Forward substitution builds y, back substitution builds x.    |
    // --------------------------------------------------------------------------------------------------------|

    var inverse: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..n_gauss) |rhs_col| {
        var y: [types.max_gauss]f64 = undefined;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = pivot_offset[i];
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [types.max_gauss]f64 = undefined;
        var ii: usize = n_gauss;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            const row_offset = pivot_offset[ii];
            for (ii + 1..n_gauss) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
            x[ii] = s * inverse_diag[ii];
        }
        for (0..n_gauss) |i| inverse[i * n_gauss + rhs_col] = x[i];
    }

    // Gaussian block -----------------------------------------------------------------------------------------|
    // Q_gg = inverse(I - AB_gg) - I.                                                                          |
    // --------------------------------------------------------------------------------------------------------|

    var result = Mat{ .data = undefined, .n = n };
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;

            // Gaussian block: Q[i,j] = inverse(I - AB)[i,j] - delta[i,j].
            result.data[i * n + j] = inverse[i * n_gauss + j] - delta;
        }
    }

    // Gaussian-to-extra block --------------------------------------------------------------------------------|
    // Q_gx = inverse(I - AB_gg) * AB_gx.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_extra) |ja| {
        const j = n_gauss + ja;
        for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += inverse[i * n_gauss + k] * ab.data[k * n + j];

            // Upper-extra block: Q_gx = inverse(I - AB_gg) * AB_gx.
            result.data[i * n + j] = s;
        }
    }

    // Extra-to-Gaussian block --------------------------------------------------------------------------------|
    // Q_xg = AB_xg * inverse(I - AB_gg). Keep it in tmp too; Q_xx uses it next.                               |
    // --------------------------------------------------------------------------------------------------------|

    var tmp: [types.max_extra * types.max_gauss]f64 = undefined;
    for (0..n_extra) |ia| {
        for (0..n_gauss) |j| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += ab.data[(n_gauss + ia) * n + k] * inverse[k * n_gauss + j];
            tmp[ia * n_gauss + j] = s;

            // Lower-Gaussian block: Q_xg = AB_xg * inverse(I - AB_gg).
            result.data[(n_gauss + ia) * n + j] = s;
        }
    }

    // Extra-to-extra block -----------------------------------------------------------------------------------|
    // Q_xx = AB_xx + Q_xg * AB_gx.                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    for (0..n_extra) |ia| {
        const i = n_gauss + ia;
        for (0..n_extra) |ja| {
            const j = n_gauss + ja;
            var s: f64 = 0.0;
            for (0..n_gauss) |k| s += tmp[ia * n_gauss + k] * ab.data[k * n + j];

            // Extra-extra block: Q_xx = AB_xx + AB_xg * inverse(I - AB_gg) * AB_gx.
            result.data[i * n + j] = s + ab.data[i * n + j];
        }
    }

    return result;
}

fn qseriesFromProduct12x10(noalias ab: *const Mat) Mat {
    // qseriesFromProduct12x10 (Q(AB), fixed 12x10 return value) ----------------------------------------------|
    // Returning wrapper around qseriesFromProduct12x10Into.                                                   |
    // The caller-owned-output version holds the fixed 10x10 Gaussian solve and block fill.                    |
    // --------------------------------------------------------------------------------------------------------|

    var result: Mat = undefined;
    qseriesFromProduct12x10Into(&result, ab);
    return result;
}

fn qseriesFromProduct12x10Into(noalias result: *Mat, noalias ab: *const Mat) void {
    // qseriesFromProduct12x10Into (Q(AB), fixed 12x10) -------------------------------------------------------|
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

    // Product trace gate -------------------------------------------------------------------------------------|
    // A tiny trace means AB already has negligible Gaussian feedback, so the q-series correction is skipped.  |
    // --------------------------------------------------------------------------------------------------------|

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

    // Factorization matrix -----------------------------------------------------------------------------------|
    // Build the fixed 10x10 matrix M = I - AB_gg. The final two rows/columns are handled after the inverse.   |
    // --------------------------------------------------------------------------------------------------------|

    var one_minus_ab_gg: [types.max_gauss * types.max_gauss]f64 = undefined;
    inline for (0..10) |i| {
        inline for (0..10) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * 10 + j] = delta - ab.data[i * 12 + j];
        }
    }

    // Pivot bookkeeping --------------------------------------------------------------------------------------|
    // Fixed n=12 swaps full 10-wide rows when pivoting. The pivot array maps inverse right-hand sides.        |
    // --------------------------------------------------------------------------------------------------------|

    var pivot: [types.max_gauss]usize = undefined;
    var inverse_diag: [types.max_gauss]f64 = undefined;
    inline for (0..10) |i| {
        pivot[i] = i;
    }

    // Pivoted LU ---------------------------------------------------------------------------------------------|
    // Factor M into L and U in-place. A near-zero pivot falls back to AB instead of producing unstable Q.     |
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
        if (@abs(diag) < lu_diagonal_floor) {
            result.* = ab.*;
            return;
        }

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
    // --------------------------------------------------------------------------------------------------------|

    var inverse: [types.max_gauss * types.max_gauss]f64 = undefined;
    for (0..10) |rhs_col| {
        var y: [types.max_gauss]f64 = undefined;
        for (0..10) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            const row_offset = i * 10;
            for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
            y[i] = s;
        }

        var x: [types.max_gauss]f64 = undefined;
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

inline fn smulNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    // smulNonzeroProduct (small matrix multiply after trace gate has passed) ---------------------------------|
    // Generic C = A*B after the caller has already decided the product is worth retaining.                    |
    //                                                                                                         |
    //   C[i,j] = sum k=0..n_gauss-1 A[i,k] * B[k,j]                                                           |
    //                                                                                                         |
    // Uses smul12x10 for the fixed LABOS hot path. The generic path walks one output column at a time and     |
    // initializes the column with k=0 before adding the remaining Gaussian terms.                             |
    // --------------------------------------------------------------------------------------------------------|

    if (n == 12 and n_gauss == 10) return smul12x10(a, b);

    var result = Mat{ .data = undefined, .n = n };
    for (0..n) |j| {
        if (n_gauss == 0) break;

        // First Gaussian term --------------------------------------------------------------------------------|
        // Initialize every row of output column j with A[i,0] * B[0,j]. Later k terms add onto this column.   |
        // ----------------------------------------------------------------------------------------------------|

        const b0j = b.data[j];
        var idx = j;
        var a_idx: usize = 0;
        for (0..n) |_| {
            result.data[idx] = a.data[a_idx] * b0j;
            idx += n;
            a_idx += n;
        }

        // Remaining Gaussian terms ---------------------------------------------------------------------------|
        // Add A[i,k] * B[k,j] for k = 1..n_gauss-1, still walking one output column at a time.                |
        // ----------------------------------------------------------------------------------------------------|

        for (1..n_gauss) |k| {
            const bkj = b.data[k * n + j];
            idx = j;
            a_idx = k;

            for (0..n) |_| {

                // Nonzero product: C[i,j] += A[i,k] * B[k,j].
                result.data[idx] += a.data[a_idx] * bkj;
                idx += n;
                a_idx += n;
            }
        }
    }
    return result;
}
