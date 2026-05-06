# 05. Fuse Layer-Doubling Matrix Updates

Measured forward-time saving: `b0a9e0f -> 97088cf`, 7.020602 s to 5.911137 s, saving 1.109465 s for one spectrum.

## What DISAMAR Does

DISAMAR uses doubling when a layer is too optically thick for the starting single-scattering layer. This is physically necessary: the layer is split into thinner pieces, and those pieces are repeatedly doubled until they represent the original layer.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L1857-L1895)

Excerpt:

```fortran
if (aeff*b > controlS%thresholdDoubl) then
  doubling = .true.
  bstart = b
  ndouble = 0
  do l = 1, ndouble_max
    bstart = bstart/2.0d0
    ndouble = ndouble + 1
    if (aeff*bstart < controlS%thresholdDoubl) exit
  end do
end if

call fillZplusZmin(errS, fcCoef, iFourier, optPropRTMGridS%maxExpCoefLay(ilayer), dimSV, dimSV_fc, nmutot, &
                   optPropRTMGridS%phasefCoefLay(:,:,:,ilayer), geometryS, Zplus, Zmin, string)

if (doubling) then
  do imu = 1, nmutot
    do iSV = 1, dimSV_fc
      E( iSV + (imu-1) * dimSV_fc ) = exp(-bstart/geometryS%u(imu))
    end do
  end do

  ! SLOW: each step writes its result to a fresh whole-matrix variable, so
  !       the doubling update walks the same data multiple times: build R,
  !       build T, then `double` re-reads them inside its own loop.
  R = Rsingle(dimSV_fc, nmutot, a, E, Zmin, DmuPlus)
  T = Tsingle(dimSV_fc, nmutot, a, bstart, E, Zplus, DmuMin, geometryS)

  call double(errS, ndouble, dimSV_fc, nmutot, nGauss, controlS%thresholdMul, geometryS, &
              bstart, E, R, T)
end if
```

## What zdisamar Does

zdisamar keeps the same layer-doubling idea but reduces repeated matrix traffic inside the doubling update.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L228-L284)

Excerpt:

```zig
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
) void {
    var b = b_start;
    for (0..ndouble) |_| {
        // FAST: a 12-number trace check decides whether the q-series
        //       contributes anything. If not, D = T directly — the entire
        //       Q*E + Q*T branch is skipped.
        const trace_r = gaussTrace(n, n_gauss, R);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

        const D = if (q_is_zero) blk: {
            break :blk T.*;
        } else blk: {
            // FAST: smulAddSemul3 fuses (T + Q*E + Q*T) into one pass over
            //       the 12x12 result, so D is built without intermediate
            //       temporary matrices.
            const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
            break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
        };

        // FAST: smulInto writes directly into a caller-supplied buffer,
        //       and matAddEsmul3 / esmulSemulAdd fuse the next combine
        //       steps. Together this collapses what was several separate
        //       matrix passes into one.
        var rd: basis.Mat = undefined;
        basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);
        const U = basis.semulAdd(n, R, E, &rd);

        var tu: basis.Mat = undefined;
        basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);
        const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);
```

## Why It Matters

Doubling builds the new layer from several intermediate matrices: a `Q*E` term, a `Q*T` term, the existing `T`, and so on. Writing each piece to its own temporary array means walking the matrix many times when one walk would do.

The classic novice example is a multi-step array recipe:

```python
# Slow: each step writes to a fresh array, three passes total
tmp1 = [a[i] * b[i] for i in range(n)]    # pass 1
tmp2 = [tmp1[i] + d[i] for i in range(n)] # pass 2
out  = [tmp2[i] * e[i] for i in range(n)] # pass 3

# Fast: one pass, no temporaries
out = [(a[i] * b[i] + d[i]) * e[i] for i in range(n)]
```

RT-layer construction is the largest measured LABOS block (10.76 s, with 8.35 s in doubling), so removing intermediate passes there saved about 1.11 s in the checkpoint table.
