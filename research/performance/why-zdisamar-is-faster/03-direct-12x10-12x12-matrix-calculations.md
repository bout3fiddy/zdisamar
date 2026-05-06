# 03. Use Direct 12x10 And 12x12 Matrix Calculations

Measured forward-time saving: `97088cf -> 0ae1cad`, 6.006493 s to 2.503199 s, saving 3.503294 s for one spectrum. This is the largest measured checkpoint win in the table.

## Why This Shape Exists

The O2 A route uses 20 streams. LABOS represents that as 10 Gauss directions, plus the direct solar and viewing directions. That makes the frequent matrix shapes 12x10 and 12x12.

## What DISAMAR Does

DISAMAR keeps the matrix dimensions general. That is good for a configurable model, because other runs may use different stream counts and polarization dimensions. For the fixed O2 A 20-stream route, that generality costs time.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L1799-L1803)

Excerpt:

```fortran
real(8) :: E(dimSV_fc*nmutot)
real(8) :: DmuPlus(nmutot,nmutot),DmuMin(nmutot,nmutot)
real(8) :: Zplus(dimSV_fc*nmutot,dimSV_fc*nmutot),Zmin(dimSV_fc*nmutot,dimSV_fc*nmutot)
real(8) :: R(dimSV_fc*nmutot,dimSV_fc*nmutot), T(dimSV_fc*nmutot,dimSV_fc*nmutot)
```

## What zdisamar Does

zdisamar writes the common 12x10 multiply directly.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L106-L144)

Excerpt:

```zig
inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    result.* = .{ .data = undefined, .n = 12 };
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
        inline for (0..12) |j| {
            var s = a0 * b0[j];
            s += a1 * b1[j];
            s += a2 * b2[j];
            s += a3 * b3[j];
            s += a4 * b4[j];
            s += a5 * b5[j];
            s += a6 * b6[j];
            s += a7 * b7[j];
            s += a8 * b8[j];
            s += a9 * b9[j];
            result.data[row + j] = s;
        }
    }
}
```

## Why It Matters

This replaces a general matrix path with direct code for the actual O2 A shape. The single call is already sub-microsecond, but the call count is in the millions. That is why this mechanism has a large wall-clock effect.
