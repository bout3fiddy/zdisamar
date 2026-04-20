# Radiance: Optics-State And RTM Grid Mismatch

## Issue

Zig and DISAMAR are still preparing different objects before transport. DISAMAR
prepares optics on an RTM support grid with quadrature weights. Zig prepares
physical sublayers with geometric thickness. That is why the radiance residuals
persist even after weak-line membership and irradiance source issues improved.

## DISAMAR Does

### 1. Builds an RTM support grid, not a physical-sublayer grid

`fillAltPresGridRTM` creates an RTM altitude/weight structure with Gauss support
points inside each RTM layer and explicit interface points with zero weight:

- [vendor/disamar-fortran/src/radianceIrradianceModule.f90:119](../../../vendor/disamar-fortran/src/radianceIrradianceModule.f90:119)

```fortran
optPropRTMGridS%RTMaltitudeSub(0) = optPropRTMGridS%RTMaltitude(0)
optPropRTMGridS%RTMweightSub  (0) = 0.0d0
do ilayer = 1, optPropRTMGridS%RTMnlayer
  dzLay = optPropRTMGridS%RTMaltitude(ilayer) - optPropRTMGridS%RTMaltitude(ilayer-1)
  do iGauss = 1, optPropRTMGridS%ngaussLay
    index = index + 1
    optPropRTMGridS%RTMweightSub  (index) = w0(iGauss) * dzLay
    optPropRTMGridS%RTMaltitudeSub(index) = optPropRTMGridS%RTMaltitude(ilayer-1) &
                                          + x0(iGauss) * dzLay
  end do
  index = index + 1
  optPropRTMGridS%RTMaltitudeSub(index) = optPropRTMGridS%RTMaltitude(ilayer)
  optPropRTMGridS%RTMweightSub  (index) = 0.0d0
end do
```

### 2. Samples state on that RTM support grid

`getOptPropAtm` interpolates pressure and temperature at each `RTMaltitudeSub`
support point and derives air density from `p / T / k_B`:

- [vendor/disamar-fortran/src/propAtmosphere.f90:2438](../../../vendor/disamar-fortran/src/propAtmosphere.f90:2438)
- [propAtmosphere.f90:2464](../../../vendor/disamar-fortran/src/propAtmosphere.f90:2464)

```fortran
lnpressureGrid = log(gasPTS%pressure)
call spline(errS, gasPTS%alt, lnpressureGrid, SDlnpressure , statusSpline)
...
do ilevel = 0, optPropRTMGridS%RTMnlayerSub
  lnpressure(ilevel) = splint(errS, gasPTS%alt, lnpressureGrid, SDlnpressure , &
                               optPropRTMGridS%RTMaltitudeSub(ilevel), statusSplint)
end do
pressure(:) = exp(lnpressure(:))

...

optPropRTMGridS%tempSub(:) = temperature(:)
numberDensityAir(:) = pressure(:) / temperature(:) / 1.380658d-19
```

### 3. Integrates optical depth from coefficients times RTM weights

DISAMAR integrates layer optical depth by summing `coefficient * RTMweightSub`
over the support points:

- [vendor/disamar-fortran/src/propAtmosphere.f90:3036](../../../vendor/disamar-fortran/src/propAtmosphere.f90:3036)

```fortran
do igaussSub = 1, optPropRTMGridS%nGaussLay
  babs(index)    = babs(index)    + optPropRTMGridS%RTMweightSub(indexSub) * kabs(indexSub)
  bsca(index)    = bsca(index)    + optPropRTMGridS%RTMweightSub(indexSub) * ksca(indexSub)
  babsGas(index) = babsGas(index) + optPropRTMGridS%RTMweightSub(indexSub) * kabsGas(indexSub)
  bscaGas(index) = bscaGas(index) + optPropRTMGridS%RTMweightSub(indexSub) * kscaGas(indexSub)
end do
```

## Zig Does

### 1. Builds physical sublayers directly from the explicit interval grid

Zig’s `buildExplicit` creates one physical sublayer per declared interval
division:

- [src/kernels/optics/preparation/vertical_grid.zig:91](../../../src/kernels/optics/preparation/vertical_grid.zig:91)

```zig
const layer_count = intervals.len;
var total_sublayer_count: usize = 0;
for (intervals) |interval| total_sublayer_count += interval.altitude_divisions;

...

for (0..interval.altitude_divisions) |sublayer_index| {
    const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / @as(f64, @floatFromInt(interval.altitude_divisions));
    const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / @as(f64, @floatFromInt(interval.altitude_divisions));
    ...
    grid.sublayer_mid_altitudes_km[global_index] = 0.5 * (top_altitude_km + bottom_altitude_km);
    grid.sublayer_interval_indices_1based[global_index] = interval.index_1based;
}
```

### 2. Samples pressure, temperature, and density from mixed semantics

`populateSublayer` currently mixes midpoint altitude, geometric-mean pressure,
midpoint temperature, and independently interpolated density:

- [src/kernels/optics/preparation/layer_accumulation.zig:305](../../../src/kernels/optics/preparation/layer_accumulation.zig:305)

```zig
const altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
const density = context.profile.interpolateDensity(altitude_km);
const pressure = if (context.scene.atmosphere.interval_grid.enabled() and
    top_pressure_hpa > 0.0 and
    bottom_pressure_hpa > 0.0)
    @sqrt(top_pressure_hpa * bottom_pressure_hpa)
else
    context.profile.interpolatePressure(altitude_km);
const temperature = context.profile.interpolateTemperature(altitude_km);
const sublayer_thickness_km = @max(top_altitude_km - bottom_altitude_km, 0.0);
const sublayer_path_length_cm = @max(sublayer_thickness_km, 1.0e-9) * centimeters_per_kilometer;
```

### 3. Uses geometric thickness as path length

Zig turns physical thickness into `path_length_cm`, then forms gas/CIA/scatter
optical depths directly from that path length:

```zig
const molecular_gas_optical_depth =
    absorbers.midpoint_continuum_sigma * continuum_column_density_cm2 +
    spectroscopy_eval.total_sigma_cm2_per_molecule * line_gas_column_density_cm2 +
    cross_section_optical_depth;
```

## Why Zig Is Wrong For Parity

The parity trace surface `sublayer_optics.csv` is supposed to compare like with
like. DISAMAR’s traced rows are RTM support samples. Zig’s traced rows are
physical sublayers. Once that mismatch exists:

- interval ids no longer mean the same thing
- PT state is sampled at different support locations
- density is no longer consistent with sampled `p/T`
- path length is not comparable to RTM quadrature weight
- optical depths derived from those quantities drift systematically

This is not a loose scalar bug. It is a wrong object-model for parity.

## Evidence From Current Probes

### 1. Zero-weight RTM interface rows exist in DISAMAR but not in Zig

At hotspot row 18:

- vendor `path_length_cm = 0`
- vendor gas/scatter/CIA optical depths are all `0`
- Zig `path_length_cm = 31500.664...`
- Zig optics are nonzero

Sources:

- [vendor row 18](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/vendor/sublayer_optics.csv:19)
- [yaml row 18](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/yaml/sublayer_optics.csv:19)

### 2. PT and density are still realized differently

Hotspot row 1:

- vendor `T = 294.194 K`
- Zig `T = 288.103 K`
- vendor `number_density = 2.492e19`
- Zig `number_density = 2.545e19`

Hotspot row 119:

- vendor `p = 62.85 hPa`
- Zig `p = 203.60 hPa`
- vendor `number_density = 2.081e18`
- Zig `number_density = 5.062e18`

Sources:

- [vendor row 1](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/vendor/sublayer_optics.csv:2)
- [yaml row 1](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/yaml/sublayer_optics.csv:2)
- [vendor row 119](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/vendor/sublayer_optics.csv:120)
- [yaml row 119](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/yaml/sublayer_optics.csv:120)

### 3. Interval identity still diverges because grid semantics differ

Both probe summaries still show the first nonzero `interval_index_1based` delta
at row 37:

- vendor `1`
- Zig `2`

Sources:

- [hotspot summary](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/summary.txt)
- [edge summary](../../../out/analysis/o2a/function_diff/edge_7550_after_parity/diff/summary.txt)

## Minimal Corrective Direction

1. Add a DISAMAR-parity optics-preparation route that builds an RTM support
   grid explicitly instead of reusing physical explicit-interval sublayers.
2. In that parity route, sample:
   - `pressure` at RTM support altitude
   - `temperature` at RTM support altitude
   - `number_density` from `p / T / k_B`
3. Carry RTM support weights explicitly and form parity optical depths from
   `coefficient * RTMweightSub`, not from physical thickness.
4. Keep RTM support samples distinct from transport layers in the prepared state
   and workspace sizing.
