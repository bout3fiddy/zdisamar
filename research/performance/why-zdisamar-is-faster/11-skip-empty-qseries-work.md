# 11. Skip Empty Q-Series Work

Measured forward-time saving: `9138e6a -> 63df87e`, 2.224609 s to 2.136820 s, saving 0.087789 s for one spectrum.

## Why This Step Exists

Layer doubling needs a q-series when repeated reflection between two half-layers matters. In many O2 A doubling steps, the reflection matrix is so small that this repeated-reflection term is zero at the configured threshold.

The speedup is to test that cheaply before building the q-series.

## What DISAMAR Does

DISAMAR enters `Qseries`, multiplies the two matrices, then checks whether the product is small enough to return immediately. That avoids the later inverse calculation, but the matrix product has already been paid for.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L3616-L3711)

Excerpt:

```fortran
function Qseries(errS, nmutot, nGauss, thresholdMul, a, b)

  ! SLOW: the full matrix product runs first, *then* its trace is checked.
  !       When abs(Trab) < ThresholdQ, the entire smul above was wasted —
  !       we paid for ~144 multiply-adds just to throw the result away.
  ab =  smul(nmutot, nGauss, thresholdMul, a, b)

  Trab = 0.0d0
  do k = 1, nGauss
    Trab = Trab + ab(k,k)
  end do

  if ( abs(Trab) < ThresholdQ ) then
    Qseries = ab
    return
  end if

  one_minus_ab_gg = one - ab_gg
  call LU_decomposition(errS, one_minus_ab_gg, indx, d, status_LUdecomp)
  do k = 1, nGauss
    col(1:nGauss) = one(1:nGauss, k)
    call solve_lin_system_LU_based(errS, one_minus_ab_gg, indx, col)
    inverse(1:nGauss, k) = col(1:nGauss)
  end do
```

## What zdisamar Does

zdisamar checks the reflection trace before entering the q-series calculation. If the product would be zero at the configured threshold, the doubling update can use `T` directly.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L240-L250)

Excerpt:

```zig
// FAST: pre-check using only the diagonal — gaussTrace reads ~10 numbers
//       and one multiply tells us whether R*R can produce anything above
//       threshold. If not, we never enter the q-series at all.
const trace_r = gaussTrace(n, n_gauss, R);
const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

const D = if (q_is_zero) blk: {
    // FAST: short-circuit — D = T directly, no matmul, no inverse.
    break :blk T.*;
} else blk: {
    // FAST: trace already proved Q*Q is nonzero, so the dedicated
    //       "knownNonzeroProduct" path skips the redundant smallness test.
    const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
    break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
};
```

The q-series function also reuses that decision by calling the product route that assumes the product is worth calculating.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L397-L420)

```zig
// FAST: caller has already proved a*b is above threshold, so this routine
//       skips the diagonal pre-check and goes straight to the multiply.
pub inline fn qseriesKnownNonzeroProduct(n: usize, n_gauss: usize, a: *const Mat, b: *const Mat) Mat {
    const ab = smulNonzeroProduct(n, n_gauss, a, b);
    return qseriesFromProduct(n, n_gauss, &ab);
}

inline fn qseriesFromProduct(n: usize, n_gauss: usize, noalias ab: *const Mat) Mat {
    const trab: f64 = if (n == 12 and n_gauss == 10) blk: {
        var trace = ab.data[0];
        trace += ab.data[13];
        trace += ab.data[26];
        trace += ab.data[39];
        trace += ab.data[52];
        trace += ab.data[65];
        trace += ab.data[78];
        trace += ab.data[91];
        trace += ab.data[104];
        trace += ab.data[117];
        break :blk trace;
    } else blk: {
        var trace: f64 = 0.0;
        for (0..n_gauss) |k| trace += ab.data[k * n + k];
        break :blk trace;
    };
    if (@abs(trab) < threshold_q) return ab.*;
```

## Why It Matters

Computing `a*b` and then deciding "actually that was zero" wastes the whole multiply. A trace-only check uses about 12 numbers instead of 144 and tells us the same answer in the common case where the product is below the threshold.

```python
# Slow: do the full matrix multiply, then test the trace of the result
def qseries(a, b):
    ab = matmul(a, b)            # 144 multiply-adds for a 12x12 matrix
    if abs(trace(ab)) < eps:
        return ab                # we paid for matmul, only to throw it away
    return inverse_step(ab)

# Fast: cheap pre-check using only the diagonals
def qseries(a, b):
    if abs(trace(a) * trace(b)) < eps:
        return zeros_like(a)     # 24 reads and a multiply, no matmul
    ab = matmul(a, b)
    if abs(trace(ab)) < eps:
        return ab
    return inverse_step(ab)
```

The q-series sits inside the layer-doubling loop and is called across many doubled layers and many Fourier terms, so a cheap trace check that often skips both the multiply and the later inverse adds up.
