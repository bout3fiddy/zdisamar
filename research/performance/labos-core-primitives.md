# LABOS Core Primitives

This note explains why the optimized per-spectrum path remains expensive. The core issue is not a single slow helper. It is millions of small, exact f64 kernels with parity-sensitive control flow.

## Fourier Loop

The LABOS layer-resolved path is [execute.zig:153-340](../../src/forward_model/radiative_transfer/labos/execute.zig#L153-L340).

For each exact wavelength:

```text
for m in 0..fourier_max:
    PLM_m = FourierPlmBasis(m)
    RT_layers_m = calcRTlayersIntoWithBasis(lambda, m)
    UD_m = ordersScatInto(RT_layers_m)
    reflectance += weight_m * integrated_source_reflectance(UD_m)
```

The instrumented spectrum measured `120390` Fourier terms over `3874` wavelength solves. That is `31.076` Fourier terms per solve.

## RT-Layer Construction

The dominant primitive is [layers.zig:304-407](../../src/forward_model/radiative_transfer/labos/layers.zig#L304-L407). The timing breakdown measured:

```text
rt_layers=10760.022ms
labos_layers=5417550
doubled_layers=1075939
double_steps=8389666
doubling=8347.130ms
fill_phase=1090.265ms
```

For each layer and Fourier term, the code:

1. Gates inactive layers by phase order, optical depth, scattering optical depth, and single-scattering albedo.
2. Builds phase kernels `Zplus` and `Zmin`.
3. Computes a scaled scattering strength:

```text
max_beta_eff = max_i |phase_coef_i| / (2*i + 1)
a_eff = single_scatter_albedo * max_beta_eff
```

4. Uses doubling when:

```text
a_eff * optical_depth > threshold_doubl
```

5. Splits the layer until:

```text
a_eff * (optical_depth / 2^ndouble) < threshold_doubl
```

So, approximately:

```text
ndouble ~= ceil(log2(a_eff * optical_depth / threshold_doubl))
```

bounded by the loop in [layers.zig:377-382](../../src/forward_model/radiative_transfer/labos/layers.zig#L377-L382).

## Doubling Math

The hot doubling loop is [layers.zig:228-284](../../src/forward_model/radiative_transfer/labos/layers.zig#L228-L284). In code-level matrix notation, where `*` is the LABOS `smul` operation over the Gauss block:

```text
Q      = qseries(R * R)
D      = T + Q * diag(E) + Q * T
rd     = R * D
U      = R * diag(E) + rd
tu     = T * U
R_next = R + diag(E) * U + tu
td     = T * D
T_next = diag(E) * D + T * diag(E) + td
```

`E_i` starts as:

```text
E_i = exp(-b_start / max(mu_i, 1e-12))
```

and then either squares cheaply or recomputes with `exp`, depending on optical thickness. The expensive branch is not just arithmetic count; it includes divisions, exponentials, and data-dependent thresholds.

## Phase Kernels

Phase kernel construction is [phase_basis.zig:195-260](../../src/forward_model/radiative_transfer/labos/phase_basis.zig#L195-L260). The core shape is:

```text
Zplus_ij += alpha_l * P_lm_plus(mu_i) * w_i * P_lm_plus(mu_j) * w_j
Zmin_ij  += alpha_l * P_lm_minus(mu_i) * w_i * P_lm_plus(mu_j) * w_j
```

For the O2 A route `nmutot=12`, so each nonzero phase coefficient updates a 12x12 matrix. The PLM basis is heavily reused, but each wavelength/layer/Fourier still has to combine the active phase coefficients into layer-specific kernels.

## Matrix Primitives

The fixed-size kernels live in [matrix.zig](../../src/forward_model/radiative_transfer/labos/matrix.zig):

- `smul12x10Into`: [matrix.zig:106-144](../../src/forward_model/radiative_transfer/labos/matrix.zig#L106-L144)
- add/scale fused helpers: [matrix.zig:266-390](../../src/forward_model/radiative_transfer/labos/matrix.zig#L266-L390)
- `qseriesFromProduct`: [matrix.zig:402-530](../../src/forward_model/radiative_transfer/labos/matrix.zig#L402-L530)

At the primitive level:

```text
smul12x10 = 12 rows * 12 columns * 10 multiply-add terms
          = 1440 f64 multiply-add terms, plus loads/stores
```

`qseriesFromProduct` is harder for the CPU: it builds `I - AB` on the 10x10 Gauss block, does pivoted elimination, triangular solves, and then fills the extra rows/columns. It has divisions and data-dependent pivot branches, so it is not a clean SIMD throughput kernel.

Current `zig build bench` sample:

```text
qseries_12x10:              534.184 ns/call
qseries_nonzero_12x10:      512.396 ns/call
smul_12x10:                 157.265 ns/call
smulAddSemul3_12:           169.972 ns/call
matAddSemul3_12:             88.298 ns/call
matAddEsmul3_12:             92.961 ns/call
semulAdd_12:                 67.475 ns/call
esmulSemulAdd_12:            93.168 ns/call
```

These are already sub-microsecond. The wall comes from repetition. The instrumented run counted millions of calls: `qseries=3408299`, `rd=8389666`, `tu=8389666`, `td=8389666`, plus the matching fused add/update kernels.

## Scattering Orders

Orders are in [orders.zig:311-529](../../src/forward_model/radiative_transfer/labos/orders.zig#L311-L529). The hot loops use `dotGaussPair` at [orders.zig:184-226](../../src/forward_model/radiative_transfer/labos/orders.zig#L184-L226): for `n_gauss=10`, each call forms two 10-term f64 dot products from the same matrix row.

The loop continues until:

```text
max_value < threshold_conv_mult or num_orders >= num_orders_max
```

Unused local-order accumulation has already been skipped for the non-Jacobian integrated-source path, but the remaining order propagation still has to move `U` and `D` through active levels until convergence.

## Configured Input

Configured input was smaller than transport but still real: `3744.483ms` aggregate worker time. The relevant code is:

- [forward_input.zig:21-103](../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L103)
- [carrier_eval.zig:42-110](../../src/forward_model/optical_properties/state_build/carrier_eval.zig#L42-L110)
- [state_spectroscopy.zig:13-103](../../src/forward_model/optical_properties/state_build/state_spectroscopy.zig#L13-L103)
- [line_list_eval.zig:179-260](../../src/input/reference/spectroscopy/line_list_eval.zig#L179-L260)
- [physics_core.zig:453-470](../../src/input/reference/spectroscopy/physics_core.zig#L453-L470)
- [strong_lines.zig:74-118](../../src/input/reference/spectroscopy/strong_lines.zig#L74-L118)

The expensive spectroscopy primitive is the line-shape evaluation:

```text
sigma = prefactor * complex_probability_function(x, y)
x = (line_center_cm1 - evaluation_wavenumber_cm1) * cte
y = half_width_cm1_at_t * pressure * cte
```

The complex probability approximation is [physics_core.zig:112-157](../../src/input/reference/spectroscopy/physics_core.zig#L112-L157). It performs reciprocal-heavy rational terms and sometimes an `exp`. Line states and spline samples are cached, so this is no longer the dominant wall, but it remains part of every exact wavelength solve.

## Machine-Level Shape

The remaining kernels are small and scalar:

- The 12x10 matrix multiply is unrolled, but each output element has a dependent 10-term f64 accumulation chain. Even with fused multiply-add, each element has serial latency.
- `qseriesFromProduct` includes divisions, pivot comparisons, and triangular solves. That is latency-sensitive and branchy, not a wide streaming loop.
- Attenuation and line-shape paths use `exp`, `sqrt`, and division. Those are high-latency scalar operations relative to add/multiply.
- The matrices fit in L1 cache, so the primary cost is instruction count, f64 latency, and repetition, not large memory bandwidth.

Assembly-level micro-optimization can shave kernels, but it cannot remove the outer product:

```text
3874 wavelengths * ~31 Fourier terms * active layers * doubling/order iterations
```

That product is the current per-spectrum wall.
