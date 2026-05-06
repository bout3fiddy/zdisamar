# 12. Write Matrix Results Into Separate Outputs

Measured forward-time saving: `63df87e -> 4791c22`, 2.136820 s to 1.915826 s, saving 0.220993 s for one spectrum.

## Why This Step Exists

LABOS doubling repeatedly multiplies small matrices, then immediately feeds the result into the next expression. The result matrix is not the same memory as either input matrix.

zdisamar uses that fact directly: the multiply writes into its final destination instead of returning a separate matrix value first.

## What DISAMAR Does

DISAMAR's `smul` returns a matrix value. The caller receives that returned array inside a larger expression.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L3528-L3569)

Excerpt:

```fortran
function smul(nmutot, nGauss, thresholdMul, a, b)

  real(8), dimension(nmutot,nmutot), intent(in)  :: a, b
  real(8), dimension(nmutot,nmutot)              :: smul

  smul = 0.0d0

  Tra = 0.0d0
  Trb = 0.0d0
  do k = 1, nGauss
    Tra = Tra + a(k,k)
    Trb = Trb + b(k,k)
  end do

  if (abs(Tra * Trb) > thresholdMul) then
    do j = 1, nmutot
      do i = 1, nmutot
        smul(i,j)=0.d0
      end do
      do k = 1, nGauss
        do i= 1, nmutot
          smul(i,j) = smul(i,j) + a(i,k) * b(k,j)
        end do
      end do
    end do
  end if
end function smul
```

The doubling routine then uses these returned arrays in expressions such as `U` and `R`.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L2199-L2204)

```fortran
Q = Qseries(errS, dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Rst, R)
D = T + semul(dimSV_fc*nmutot, Q, E) + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Q, T)
U = semul(dimSV_fc*nmutot, R, E) + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, R, D)
R = R + esmul(dimSV_fc*nmutot, E, U) + smul(dimSV_fc*nmutot, dimSV_fc*nGauss, thresholdMul, Tst, U)
```

## What zdisamar Does

zdisamar gives the multiply its final output matrix. The `noalias` marker records that the output is separate from the inputs.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L68-L98)

Excerpt:

```zig
pub inline fn smulInto(
    noalias out: *Mat,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    a: *const Mat,
    b: *const Mat,
) void {
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
```

The doubling code passes a fresh destination for each product.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L252-L265)

```zig
var rd: basis.Mat = undefined;
basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);
const U = basis.semulAdd(n, R, E, &rd);

var tu: basis.Mat = undefined;
basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);
const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);

var td: basis.Mat = undefined;
basis.smulInto(&td, n, n_gauss, threshold_mul, T, &D);
const T_new = basis.esmulSemulAdd(n, E, &D, T, &td);
```

## Why It Matters

The matrix is small, but the call count is high. Writing directly into a separate output keeps the frequent 12x10 product as a simple "read inputs, write result" operation. That is why this small-looking change moves wall time by about 0.22 s in the checkpoint table.
