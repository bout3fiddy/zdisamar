# 08. Skip Empty Q-Series Work

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

  ! DISAMAR computes a*b before it knows whether the q-series matters.
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
const trace_r = gaussTrace(n, n_gauss, R);
const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

const D = if (q_is_zero) blk: {
    // R*R is below the multiply threshold, so Q contributes nothing.
    break :blk T.*;
} else blk: {
    const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
    break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
};
```

The q-series function also reuses that decision by calling the product route that assumes the product is worth calculating.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L397-L420)

```zig
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

The q-series sits inside the layer-doubling loop. It is not called once per spectrum; it is called across many doubled layers and many Fourier terms. A cheap trace check saves time because it prevents a full matrix product, and sometimes prevents the later inverse-based q-series work too.
