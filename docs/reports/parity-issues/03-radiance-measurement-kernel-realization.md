# Radiance: Measurement Kernel Realization Mismatch

## Issue

Zig’s parity runtime can reconstruct DISAMAR’s adaptive interval topology, but
the live kernel used for radiance still goes through the wrong runtime path. The
result is that `adaptive_grid.csv` matches while `kernel_samples.csv` and
`transport_samples.csv` do not.

## DISAMAR Does

### 1. Integrates over the realized `wavelHRS` grid

DISAMAR’s measured irradiance and radiance are accumulated over the realized HR
grid, not over a synthetic explicit kernel:

- [vendor/disamar-fortran/src/radianceIrradianceModule.f90:249](../../../vendor/disamar-fortran/src/radianceIrradianceModule.f90:249)
- [radianceIrradianceModule.f90:353](../../../vendor/disamar-fortran/src/radianceIrradianceModule.f90:353)

```fortran
do index = startIndex, endIndex
  solIrrVal = solIrrVal + slit(index) * wavelHRS%weight(index) * solarIrradianceS%solIrrHR(index)
end do
```

### 2. Uses slit support on the realized node set

The slit support is chosen on `wavelHRS%wavel`, then the final kernel is
`slitfunction * wavelHRS%weight` on that realized subset:

- [vendor/disamar-fortran/src/mathToolsModule.f90:703](../../../vendor/disamar-fortran/src/mathToolsModule.f90:703)

```fortran
closestIndex = minloc(abs(wavelHRS%wavel(:) - wavelInstr(iwaveInstr) ) )
...
if ( abs( wavelInstr(iwaveInstr) - wavelHRS%wavel(index) ) > 3.0 * FWHM ) then
  startIndex = index
  exit
end if
```

## Zig Does

### 1. Traces adaptive intervals and runtime kernels through different paths

The probe writes `adaptive_grid.csv` from the adaptive-plan trace helper, but
`kernel_samples.csv` comes from the live runtime kernel:

- [src/o2a/providers/instrument/adaptive_trace.zig:31](../../../src/o2a/providers/instrument/adaptive_trace.zig:31)
- [scripts/testing_harness/o2a_function_trace.zig:915](../../../scripts/testing_harness/o2a_function_trace.zig:915)

Trace path:

```zig
if (!adaptive_reference_grid.enabled()) return error.InvalidRequest;
const support = legacy_support.primaryOperationalBandSupport(scene.observation_model);
const response = scene.observation_model.resolvedChannelControls(.radiance).response;
const trace = try adaptive_plan.buildKernelTraceForWavelength(
    allocator,
    adaptive_reference_grid,
    response,
    support,
    wavelength_nm,
);
```

Runtime path:

```zig
const integration = try InstrumentIntegration.integrationForWavelength(
    scene,
    midpoint_nm,
    route,
    safe_span,
);
for (0..integration.sample_count) |sample_index| {
    const sample_wavelength_nm = midpoint_nm + integration.offsets_nm[sample_index];
    ...
}
```

### 2. Routes `.disamar_hr_grid` into the uniform explicit-HR branch

The runtime kernel builder groups `.disamar_hr_grid` with `.explicit_hr_grid`:

- [src/o2a/providers/instrument/integration.zig:100](../../../src/o2a/providers/instrument/integration.zig:100)

```zig
const prefer_explicit_hr_grid = switch (response.integration_mode) {
    .auto, .explicit_hr_grid, .disamar_hr_grid => true,
    .adaptive => false,
};
```

And then uses the uniform explicit builder:

```zig
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

## Why Zig Is Wrong For Parity

Zig already has vendor-like adaptive kernel realization code, but parity is not
using it at runtime. So the current state is:

- plan surface looks vendor-aligned
- live kernel surface is still a symmetric uniform explicit-HR kernel

That is why the current parity mode is wrong even though `adaptive_grid.csv`
looks encouraging.

## Evidence From Current Probes

### 1. `755.0 nm` edge probe

`adaptive_grid.csv` matches, but `kernel_samples.csv` does not:

- vendor rows: `201`
- Zig rows: `229`
- vendor first sample: `754.240334835155`
- Zig first sample: `753.86`

Source:

- [edge_7550_after_parity/diff/summary.txt](../../../out/analysis/o2a/function_diff/edge_7550_after_parity/diff/summary.txt)

### 2. `759.62 nm` hotspot probe

Again, `adaptive_grid.csv` matches, but the live kernel does not:

- vendor rows: `980`
- Zig rows: `229`
- vendor first sample: `758.4718095315138`
- Zig first sample: `758.48`

Source:

- [hotspot_75962_after_parity/diff/summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/summary.txt)

### 3. The downstream transport samples diverge in exactly the same way

`transport_samples.csv` inherits the same sample-wavelength mismatch because the
kernel is already wrong upstream.

## Minimal Corrective Direction

1. Change `.disamar_hr_grid` so it uses the existing adaptive-plan / realized
   Gauss-node kernel builder instead of the current uniform explicit-HR loop.
2. Make the parity trace emit `adaptive_grid.csv` and `kernel_samples.csv` from
   the same chosen runtime path.
3. Keep the current analytic slit formulas, because the main divergence is not
   the slit shape itself; it is sample realization and quadrature.
