# O2 A Per-Spectrum Wall

Scope: one O2 A forward spectrum. Retrieval iteration reuse and `prepare_o2a` are excluded.

## Finding

The wall is the set of high-resolution radiance calculations. In the instrumented validation case, 701 output wavelengths required 3,874 high-resolution radiance wavelengths. Calculating those radiances took 1.958706 s of a 2.252623 s forward run, about 87% of wall time.

The current generated O2 A summary used by this note is [out/ci/o2a_validation_spectrum/summary.json](../../out/ci/o2a_validation_spectrum/summary.json). It records `prepare_o2a_s=0.1612624591216445` and `forward_model_s=2.033145166002214` for 701 output wavelengths.

## Measured Split

Representative instrumented timing for one standard O2 A validation spectrum:

```text
forward model                         2.252623 s
prepare_o2a                           0.175714 s
output wavelengths                         701
high-resolution radiance wavelengths     3,874
calculate high-resolution radiance     1.958706 s
choose wavelength and weights          0.283174 s
make high-resolution wavelength list   0.003549 s
average radiance to output grid        0.003225 s
average irradiance to output grid      0.003286 s
```

The source instrumentation still uses older internal names for these rows. The table above is the intended research wording.

Time accumulated inside the 3,874 high-resolution radiance calculations:

```text
build wavelength-specific optical input   3.744483 s total, 0.967 ms each
LABOS radiative transfer                 14.236660 s total, 3.675 ms each
convert reflectance to radiance           0.001067 s total
```

Those totals are larger than the wall clock because the radiance calculations are split across CPU threads.

LABOS transport split:

```text
LABOS wavelength count                 3,874
Fourier terms                        120,390      31.076 terms per wavelength
RT-layer construction                 10.760022 s 75.6% of LABOS transport
scattering orders                      2.758174 s 19.4% of LABOS transport
attenuation                            0.333512 s
final reflectance sum                  0.286904 s
layer visits                       5,417,550
doubled layers                     1,075,939
doubling steps                     8,389,666
```

## Code Path

1. [simulate.zig:51-75](../../src/forward_model/instrument_grid/grid_calculation/simulate.zig#L51-L75) chooses the high-resolution wavelengths needed for the instrument response, calculates radiance at those wavelengths, and then averages back to the 701 output wavelengths.
2. [wavelength_sampling.zig:109-135](../../src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig#L109-L135) creates the high-resolution wavelength list. It keeps exactly repeated wavelengths once; nearby wavelengths are still separate radiance calculations.
3. [spectral_forward.zig:256-295](../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L256-L295) calculates each high-resolution radiance with reusable temporary arrays.
4. [spectral_forward.zig:228-249](../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L228-L249) does the per-wavelength work: build optical input, run radiative transfer, convert reflectance to radiance.
5. [forward_input.zig:21-103](../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L103) builds the wavelength-specific layer, RTM quadrature, source-interface, and pseudo-spherical inputs.
6. [execute.zig:245-340](../../src/forward_model/radiative_transfer/labos/execute.zig#L245-L340) loops over Fourier terms, builds RT layers, propagates scattering orders, and adds the weighted reflectance contribution.

## Work Count

Let `w_i` be an output wavelength and `d_ij` be one of its instrument-response offsets.

```text
high_resolution_wavelengths = unique_exact(w_i + d_ij)
count = 3,874
```

`unique_exact` means only exactly repeated floating-point wavelengths are reused. It does not merge nearby wavelengths.

For each high-resolution wavelength:

```text
time(wavelength)
  = build optical input for that wavelength
  + sum over Fourier terms:
      build RT layers
      propagate scattering orders
      add reflectance contribution
```

The measured sum over all high-resolution wavelengths had 120,390 Fourier terms. The wall is therefore not 701 output values. It is about 3,874 wavelengths times 31 Fourier terms, with active layer and doubling work below each Fourier term.

## Optimization Boundary

The optimized path has already removed the avoidable repeated work we know about: cached fixed inputs, reusable LABOS storage, direct 12x10 and 12x12 matrix calculations, Fourier tail stopping, active-layer skips, and unused local-order accumulation.

Further per-spectrum wins need to change one of the large factors:

- fewer high-resolution radiance wavelengths while preserving the O2 A result;
- fewer active Fourier, layer, or doubling calculations per wavelength;
- faster mathematically equivalent LABOS matrix calculations;
- more reuse inside each high-resolution radiance calculation.

Small improvements to the final averaging step cannot move the wall much because that step is already only a few milliseconds.
