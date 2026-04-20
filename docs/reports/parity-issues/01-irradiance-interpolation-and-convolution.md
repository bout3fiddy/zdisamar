# Irradiance: Interpolation And Convolution Mismatch

## Issue

Zig no longer has the old raw-solar-source bug, but the parity path still does
not realize irradiance the way DISAMAR does. The remaining residuals cluster at
sharp solar corners because Zig is still feeding a different continuous solar
field into a different convolution kernel.

## DISAMAR Does

### 1. Spline-interpolates the raw solar spectrum

DISAMAR reads the raw solar file, builds cubic-spline second derivatives, then
evaluates the solar spectrum on its measurement and high-resolution grids:

- [vendor/disamar-fortran/src/readModule.f90:196](../../../vendor/disamar-fortran/src/readModule.f90:196)
- [readModule.f90:197](../../../vendor/disamar-fortran/src/readModule.f90:197)
- [readModule.f90:201](../../../vendor/disamar-fortran/src/readModule.f90:201)
- [readModule.f90:209](../../../vendor/disamar-fortran/src/readModule.f90:209)

```fortran
! prepare for spline interpolation (second order derivatives)
call spline(errS, w_fitwindow, solIrr_fitwindow, SDsolIrr_fitwindow, status_spline)
if (errorCheck(errS)) return

do iwave = 1, wavelMRS%nwavel
  solarIrradianceS%solIrrMR(iwave) = splint(errS, w_fitwindow, solIrr_fitwindow, SDsolIrr_fitwindow, &
                 wavelMRS%wavel(iwave)+solarIrradianceS%wavelShift, statusSplint)
end do

if ( present(wavelHRS) ) then
  do iwave = 1, wavelHRS%nwavel
    solarIrradianceS%solIrrHR(iwave) = splint(errS, w_fitwindow, solIrr_fitwindow, SDsolIrr_fitwindow, &
                   wavelHRS%wavel(iwave)+solarIrradianceS%wavelShift, statusSplint)
  end do
end if
```

DISAMAR is deliberately not using linear interpolation here; the commented
`splintLin` lines in the same routine make that explicit.

### 2. Builds an HR irradiance grid from FWHM-sized intervals with Gauss nodes

DISAMAR does not use the configured `±half_span` directly as the irradiance
kernel support. It expands the fit window by `±2*FWHM`, partitions that range
into FWHM-sized intervals, and fills them with Gauss points and weights:

- [vendor/disamar-fortran/src/readIrrRadFromFileModule.f90:1272](../../../vendor/disamar-fortran/src/readIrrRadFromFileModule.f90:1272)
- [readIrrRadFromFileModule.f90:1338](../../../vendor/disamar-fortran/src/readIrrRadFromFileModule.f90:1338)
- [readIrrRadFromFileModule.f90:1363](../../../vendor/disamar-fortran/src/readIrrRadFromFileModule.f90:1363)

```fortran
waveStart = wavelInstrS%startWavel - 2.0d0 * FWHM
waveEnd   = wavelInstrS%endWavel   + 2.0d0 * FWHM

...

do iinterval = 1, size(intervalBoundaries) - 1
  dw = intervalBoundaries(iinterval) - intervalBoundaries(iinterval-1)
  sw = intervalBoundaries(iinterval-1)
  nGauss = max( nGaussMin, nint( nGaussMax * dw / maxInterval ) )
  if (nGauss >  nGaussMax ) nGauss = nGaussMax
  do iGauss = 1, nGauss
    wavelBand(index)       = sw + dw * x0(iGauss, nGauss)
    wavelBandWeight(index) = dw * w0(iGauss, nGauss)
    index = index + 1
  end do
end do
```

### 3. Convolves with slit support trimmed on the realized HR grid

DISAMAR finds the local support on the realized `wavelHRS` grid, limits it to
roughly `±3*FWHM`, evaluates the slit only on that subset, and normalizes with
the realized quadrature weights:

- [vendor/disamar-fortran/src/mathToolsModule.f90:703](../../../vendor/disamar-fortran/src/mathToolsModule.f90:703)
- [mathToolsModule.f90:774](../../../vendor/disamar-fortran/src/mathToolsModule.f90:774)
- [vendor/disamar-fortran/src/radianceIrradianceModule.f90:283](../../../vendor/disamar-fortran/src/radianceIrradianceModule.f90:283)

```fortran
closestIndex = minloc(abs(wavelHRS%wavel(:) - wavelInstr(iwaveInstr) ) )
...
if ( abs( wavelInstr(iwaveInstr) - wavelHRS%wavel(index) ) > 3.0 * FWHM ) then
  startIndex = index
  exit
end if

...

do iwave = startIndex, endIndex
  deltaWave        = wavelHRS%wavel(iwave) - wavelInstr(iwaveInstr)
  slitValue(iwave) = 2**( - 2*(deltaWave / w)**4 )
  slitIntegrated   = slitIntegrated + wavelHRS%weight(iwave) * slitValue(iwave)
end do

slitfunction = slitValue / slitIntegrated
```

## Zig Does

### 1. Linearly interpolates the raw solar spectrum

Zig’s parity path uses the tracked raw solar asset directly through the generic
`OperationalSolarSpectrum` interpolator:

- [src/model/instrument/solar_spectrum.zig:77](../../../src/model/instrument/solar_spectrum.zig:77)
- [solar_spectrum.zig:112](../../../src/model/instrument/solar_spectrum.zig:112)
- [src/o2a/data/vendor_parity_runtime.zig:297](../../../src/o2a/data/vendor_parity_runtime.zig:297)
- [src/kernels/transport/measurement/spectral_eval.zig:301](../../../src/kernels/transport/measurement/spectral_eval.zig:301)

```zig
pub fn interpolateIrradiance(self: *const OperationalSolarSpectrum, wavelength_nm: f64) f64 {
    return self.interpolateIrradianceWithinBounds(wavelength_nm) orelse {
        if (!self.enabled()) return 0.0;
        if (wavelength_nm <= self.wavelengths_nm[0]) return self.irradiance[0];
        return self.irradiance[self.irradiance.len - 1];
    };
}

pub fn interpolateIrradianceWithinBounds(
    self: *const OperationalSolarSpectrum,
    wavelength_nm: f64,
) ?f64 {
    ...
    const weight = (wavelength_nm - left_nm) / span;
    return left_irradiance + weight * (right_irradiance - left_irradiance);
}
```

### 2. Uses a uniform explicit grid for `.disamar_hr_grid`

The parity runtime sets `.integration_mode = .disamar_hr_grid`, but the runtime
kernel builder still treats that mode as “uniform explicit HR grid with constant
step”:

- [src/o2a/providers/instrument/integration.zig:100](../../../src/o2a/providers/instrument/integration.zig:100)
- [integration.zig:107](../../../src/o2a/providers/instrument/integration.zig:107)
- [integration.zig:119](../../../src/o2a/providers/instrument/integration.zig:119)

```zig
const prefer_explicit_hr_grid = switch (response.integration_mode) {
    .auto, .explicit_hr_grid, .disamar_hr_grid => true,
    .adaptive => false,
};

if (prefer_explicit_hr_grid and response.high_resolution_step_nm > 0.0 and response.high_resolution_half_span_nm > 0.0) {
    const step_nm = response.high_resolution_step_nm;
    const half_span_nm = response.high_resolution_half_span_nm;
    var offset_nm = -half_span_nm;
    while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
        kernel.offsets_nm[sample_count] = offset_nm;
        const response_weight = response_support.spectralResponseWeight(response, offset_nm);
        kernel.weights[sample_count] = if (disamar_hr_grid)
            response_weight * step_nm
        else
            response_weight;
        sample_count += 1;
    }
}
```

The parity runtime injects irradiance into exactly that path:

```zig
.measurement_pipeline = .{
    .irradiance = .{
        .explicit = true,
        .response = .{
            .integration_mode = .disamar_hr_grid,
            .slit_index = resolved_slit_index,
            .fwhm_nm = resolved.observation.instrument_line_fwhm_nm,
            .builtin_line_shape = resolved.observation.builtin_line_shape,
            .high_resolution_step_nm = resolved.observation.high_resolution_step_nm,
            .high_resolution_half_span_nm = resolved.observation.high_resolution_half_span_nm,
        },
    },
},
```

And samples the solar spectrum directly:

```zig
const value = if (response.integration_mode == .disamar_hr_grid and
    operational_band_support.operational_solar_spectrum.enabled())
    operational_band_support.operational_solar_spectrum.interpolateIrradianceWithinBounds(wavelength_nm) orelse
        return error.InvalidRequest
else
    irradianceAtWavelength(scene, prepared, wavelength_nm, safe_span);
```

## Why Zig Is Wrong For Parity

For parity, the target is DISAMAR’s irradiance realization:

- spline-smoothed solar field
- HR grid built from FWHM interval geometry and Gauss quadrature
- slit support chosen on the realized HR nodes
- normalization over that local realized support

Zig still differs on all three of those layers. It is still integrating a
different function over a different grid, even though the old support-coverage
bug has been fixed.

## Evidence From Current Probes

### 1. Support is now covered

The support diagnostic for `755.0 nm` now says the tracked solar asset fully
covers the required parity support:

- [edge_7550_after_parity/diff/irradiance_support_summary.txt](../../../out/analysis/o2a/function_diff/edge_7550_after_parity/diff/irradiance_support_summary.txt)

### 2. The realized kernel is still structurally different

At `755.0 nm`:

- vendor `kernel_samples.csv`: `201` rows
- Zig `kernel_samples.csv`: `229` rows
- vendor first sample: `754.240334835155 nm`
- Zig first sample: `753.86 nm`

Source:

- [edge_7550_after_parity/diff/summary.txt](../../../out/analysis/o2a/function_diff/edge_7550_after_parity/diff/summary.txt)

### 3. The residuals now cluster at sharp solar corners

Current bundle metrics:

- irradiance `max_abs = 6.4096948e9` at `761.99 nm`

Source:

- [validation/compatibility/o2a_plots/comparison_metrics.json](../../../validation/compatibility/o2a_plots/comparison_metrics.json)

That pattern fits spline-vs-linear source interpolation and Gauss-vs-uniform
convolution much better than it fits a remaining support-truncation problem.

## Minimal Corrective Direction

1. Add a parity-only spline-backed solar interpolator that matches DISAMAR’s
   `spline/splint` behavior.
2. Replace Zig’s current `.disamar_hr_grid` irradiance path with a vendor-style
   HR irradiance grid builder:
   - expand by `±2*FWHM`
   - split into FWHM-sized intervals
   - realize Gauss nodes and weights
3. Apply slit support trimming and normalization on that realized HR grid, not
   on the current uniform explicit grid.
