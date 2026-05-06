# 10. Combine The D Update In Doubling

Measured forward-time saving: `4791c22 -> baf0b4f`, 1.915826 s to 1.889351 s, saving 0.026476 s for one spectrum.

## Why This Step Exists

During layer doubling, `D` is the down-going transmission update for the doubled layer. It combines three terms:

```text
D = T + Q*E + Q*T
```

That calculation runs inside the doubling loop, so even one extra pass over the matrix matters.

## What DISAMAR Does

DISAMAR writes the `D` update as a whole-array expression. That is clear and general, but it evaluates `semul(Q,E)` and `smul(Q,T)` as separate pieces before the final sum.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L2196-L2204)

Excerpt:

```fortran
do idouble = 1, ndouble
  Rst  = transform_top_bottom(dimSV_fc, nmutot, R)
  Tst  = transform_top_bottom(dimSV_fc, nmutot, T)
  Q    = Qseries(errS, dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Rst, R)

  ! D is clear to read, but it is built from separate matrix operations.
  D    = T + semul(dimSV_fc*nmutot, Q, E) + &
              smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Q, T)

  U    = semul(dimSV_fc*nmutot, R, E) + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, R, D)
  R    = R + esmul(dimSV_fc*nmutot, E, U) + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Tst, U)
end do
```

## What zdisamar Does

zdisamar combines the `D` update into one matrix routine for the common 12x12 O2 A shape.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L245-L250)

Excerpt:

```zig
const D = if (q_is_zero) blk: {
    break :blk T.*;
} else blk: {
    const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
    break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
};
```

The fixed-shape routine handles both cases: if `Q*T` is below threshold, it writes only `T + Q*E`; otherwise it computes `Q*T` and adds all three terms in the same pass.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L279-L352)

```zig
fn smulAddSemul3_12(threshold_mul: f64, a: *const Mat, e: *const Vec, c: *const Mat) Mat {
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

    var result = Mat{ .data = undefined, .n = 12 };
    if (@abs(tra * trc) <= threshold_mul) {
        inline for (0..12) |j| {
            const ej = e.data[j];
            var idx = j;
            inline for (0..12) |_| {
                // Q*T is zero, so D is just T + Q*E.
                result.data[idx] = c.data[idx] + a.data[idx] * ej;
                idx += 12;
            }
        }
        return result;
    }

    inline for (0..12) |i| {
        const row = i * 12;
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
        inline for (0..12) |j| {
            var s = a0 * c0[j];
            s += a1 * c1[j];
            s += a2 * c2[j];
            s += a3 * c3[j];
            s += a4 * c4[j];
            s += a5 * c5[j];
            s += a6 * c6[j];
            s += a7 * c7[j];
            s += a8 * c8[j];
            s += a9 * c9[j];
            const idx = row + j;
            result.data[idx] = (c.data[idx] + a.data[idx] * e.data[j]) + s;
        }
    }
    return result;
}
```

## Why It Matters

This is a smaller win because earlier matrix work already removed the largest overhead. It still saves about 0.026 s for one spectrum because it sits inside the repeated layer-doubling loop.
