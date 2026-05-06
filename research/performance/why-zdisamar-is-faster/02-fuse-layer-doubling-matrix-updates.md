# 02. Fuse Layer-Doubling Matrix Updates

Measured forward-time saving: `b0a9e0f -> 97088cf`, 7.057182 s to 6.006493 s, saving 1.050689 s for one spectrum.

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
        const trace_r = gaussTrace(n, n_gauss, R);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

        const D = if (q_is_zero) blk: {
            break :blk T.*;
        } else blk: {
            const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
            break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
        };

        var rd: basis.Mat = undefined;
        basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);
        const U = basis.semulAdd(n, R, E, &rd);

        var tu: basis.Mat = undefined;
        basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);
        const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);
```

## Why It Matters

RT-layer construction is the largest measured LABOS block. The instrumented run measured 10.760022 s accumulated in RT-layer construction, with 8.347130 s in the doubling calculation. Reducing repeated matrix work in this block saved about 1.05 s in the checkpoint table.
