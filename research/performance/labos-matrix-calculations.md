# LABOS Matrix Calculations

This note explains why the optimized per-spectrum path remains expensive. The core issue is not one slow helper. The issue is that O2 A asks LABOS to repeat many small, exact matrix calculations millions of times.

The deeper layered trace is in [where-is-the-bottleneck](where-is-the-bottleneck/). That folder keeps the regeneration harness, retained CSV/JSON evidence, and a top-down explanation from the spectrum wall through LABOS layer construction, doubling, scattering orders, matrix primitives, and assembly-level inspection notes.

## Fourier Loop

The LABOS layer-resolved path is [execute.zig:153-340](../../src/forward_model/radiative_transfer/labos/execute.zig#L153-L340).

For each high-resolution wavelength:

```text
for m in 0..fourier_max:
    build the Fourier basis for m
    build the RT layers for this wavelength and m
    propagate scattering orders through those layers
    add this Fourier term to the reflectance
```

The instrumented spectrum measured 120,390 Fourier terms over 3,874 high-resolution wavelengths. That is 31.076 Fourier terms per wavelength.

This step exists because the azimuth-dependent reflectance is written as a Fourier series. The O2 A case cannot use only the first term: the atmosphere and viewing geometry leave enough angular structure that many terms have to be included before the remaining tail is negligible.

## RT-Layer Construction

The largest measured block is [layers.zig:304-407](../../src/forward_model/radiative_transfer/labos/layers.zig#L304-L407). The timing breakdown measured:

```text
RT-layer construction       8.026027 s
layer visits            5,417,550
doubled layers          1,075,939
doubling steps          8,389,666
doubling calculation        6.036863 s
phase-matrix calculation    1.038334 s
```

For each layer and Fourier term, the code:

1. skips the layer if it cannot contribute for this Fourier term;
2. builds the `Zplus` and `Zmin` phase matrices;
3. computes an effective scattering strength;
4. uses layer doubling if scattering is strong enough;
5. keeps splitting the layer until the starting layer is thin enough for the configured threshold.

The doubling trigger is:

```text
effective_scattering * optical_depth > threshold_doubl
```

The split count is approximately:

```text
ceil(log2(effective_scattering * optical_depth / threshold_doubl))
```

bounded by the loop in [layers.zig:377-382](../../src/forward_model/radiative_transfer/labos/layers.zig#L377-L382).

This is expensive because the condition is checked for many wavelength, Fourier, and layer combinations. Thick or strongly scattering layers then run several doubling steps before they can be added to the full atmosphere.

## Layer Doubling Math

The doubling loop is [layers.zig:228-284](../../src/forward_model/radiative_transfer/labos/layers.zig#L228-L284). In matrix notation:

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

`R` and `T` are the layer reflection and transmission matrices. `E` starts as:

```text
E_i = exp(-b_start / max(mu_i, 1e-12))
```

and then either squares cheaply or is recomputed with `exp`, depending on optical thickness.

This is why doubling is expensive even after the matrix routines are fast. It is not one matrix multiply. It is a sequence of matrix multiplies, diagonal updates, trace checks, inversions on the Gauss block, exponentials, divisions, and threshold checks.

## Phase Matrices

Phase-matrix construction is [phase_basis.zig:195-260](../../src/forward_model/radiative_transfer/labos/phase_basis.zig#L195-L260). The core shape is:

```text
Zplus_ij += alpha_l * P_lm_plus(mu_i)  * w_i * P_lm_plus(mu_j) * w_j
Zmin_ij  += alpha_l * P_lm_minus(mu_i) * w_i * P_lm_plus(mu_j) * w_j
```

For the O2 A route `nmutot=12`, so each nonzero phase coefficient updates a 12x12 matrix. The Fourier basis is reused, but each wavelength, layer, and Fourier term still has to combine the active phase coefficients into layer-specific `Zplus` and `Zmin` matrices.

This step exists because scattering redistributes light between directions. LABOS needs those matrices before it can build layer reflection and transmission.

## Small Matrix Calculations

The fixed 20-stream O2 A route becomes `n_gauss=10` and `nmutot=12`. The direct solar and viewing directions add two rows/columns on top of the 10 Gauss directions. That is why the common matrix shapes are 12x10 and 12x12.

The small matrix routines live in [matrix.zig](../../src/forward_model/radiative_transfer/labos/matrix.zig):

- `smul12x10Into`: [matrix.zig:106-144](../../src/forward_model/radiative_transfer/labos/matrix.zig#L106-L144)
- add/scale helpers: [matrix.zig:266-390](../../src/forward_model/radiative_transfer/labos/matrix.zig#L266-L390)
- `qseriesFromProduct`: [matrix.zig:402-530](../../src/forward_model/radiative_transfer/labos/matrix.zig#L402-L530)

At the single-call level:

```text
smul12x10 = 12 rows * 12 columns * 10 multiply-add terms
          = 1,440 floating-point multiply-add terms, plus loads and stores
```

`qseriesFromProduct` is more expensive than a multiply. It builds `I - AB` on the 10-stream Gauss block, chooses pivots, factors the matrix, performs triangular back-substitution, and then fills the extra direct/view rows and columns. That means divisions, comparisons, and dependent arithmetic.

Current `zig build bench` sample:

```text
qseries_12x10:              693.590 ns/call
qseries_nonzero_12x10:      519.493 ns/call
smul_12x10:                 155.266 ns/call
smulAddSemul3_12:           168.916 ns/call
matAddSemul3_12:             88.427 ns/call
matAddEsmul3_12:             90.744 ns/call
semulAdd_12:                 66.846 ns/call
esmulSemulAdd_12:            93.381 ns/call
```

These calls are already sub-microsecond. The wall comes from repetition. The instrumented run counted millions of calls: `qseries=3,408,299`, `rd=8,389,666`, `tu=8,389,666`, `td=8,389,666`, plus the matching add/update calls.

## Scattering Orders

Scattering orders are in [orders.zig:311-529](../../src/forward_model/radiative_transfer/labos/orders.zig#L311-L529). The hot loops use `dotGaussPair` at [orders.zig:184-226](../../src/forward_model/radiative_transfer/labos/orders.zig#L184-L226): for `n_gauss=10`, each call forms two 10-term dot products from the same matrix row.

The loop continues until:

```text
max_value < threshold_conv_mult or num_orders >= num_orders_max
```

This step exists because LABOS represents multiple scattering as successive scattering orders. zdisamar has already removed unused local-order accumulation for the non-Jacobian integrated-source path, but the remaining propagation still has to move upward and downward radiation through active levels until convergence.

## Wavelength-Specific Optical Input

Wavelength-specific optical input was smaller than LABOS transport but still real: 3.927454 s accumulated across the 3,874 high-resolution wavelengths. The relevant code is:

- [forward_input.zig:21-103](../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L103)
- [carrier_eval.zig:42-110](../../src/forward_model/optical_properties/state_build/carrier_eval.zig#L42-L110)
- [state_spectroscopy.zig:13-103](../../src/forward_model/optical_properties/state_build/state_spectroscopy.zig#L13-L103)
- [line_list_eval.zig:179-260](../../src/input/reference/spectroscopy/line_list_eval.zig#L179-L260)
- [physics_core.zig:453-470](../../src/input/reference/spectroscopy/physics_core.zig#L453-L470)
- [strong_lines.zig:74-118](../../src/input/reference/spectroscopy/strong_lines.zig#L74-L118)

The expensive spectroscopy calculation is the O2 line shape:

```text
sigma = prefactor * complex_probability_function(x, y)
x = (line_center_cm1 - evaluation_wavenumber_cm1) * cte
y = half_width_cm1_at_t * pressure * cte
```

The complex probability approximation is [physics_core.zig:112-157](../../src/input/reference/spectroscopy/physics_core.zig#L112-L157). It has reciprocal-heavy rational terms and sometimes an `exp`. Line states and spline samples are cached, so this is no longer the dominant wall, but it remains part of every high-resolution radiance calculation.

## Why Cheap Still Becomes Expensive

Each small matrix calculation is cheap because the shape is fixed and small. The matrices fit close to the CPU, there is no heap allocation in the inner routines, and the 12x10 multiply is written as direct multiply-add chains.

The spectrum is still expensive because the cheap calculation is multiplied by the O2 A work count:

```text
3,874 high-resolution wavelengths
* about 31 Fourier terms per wavelength
* active layers
* doubling and scattering-order iterations
```

Small assembly-level improvements can shave a small matrix routine. They cannot remove that outer product. A larger speedup has to reduce one of those counts or find a new reuse boundary that preserves the O2 A result.
