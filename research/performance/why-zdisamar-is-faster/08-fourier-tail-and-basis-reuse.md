# 08. Stop Tiny Fourier Tails

Measured forward-time saving: `f42445d -> c423f4a`, 2.266849 s to 2.025331 s, saving 0.241518 s for one spectrum.

## What DISAMAR Does

DISAMAR loops over Fourier terms up to `FourierMax`. Inside that loop it rebuilds the generalized spherical functions used by the layer calculation.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L268-L303)

Excerpt:

```fortran
do iFourier = 0, FourierMax

  if ( .not. controlS%aerosolLayerHeight ) then
    if ( iFourier > controlS%fourierFloorScalar ) then
      dimSV_fc = 1
    else
      dimSV_fc = dimSV
    end if
  end if

  ! These values are rebuilt here before the RT-layer calculation.
  ! zdisamar keeps the same kind of values in reusable LABOS storage.
  call fillPlmVector(errS, fcCoef, iFourier, dimSV_fc, nmutot, maxExpCoef, geometryS)
  call CalcRTlayers(errS, fcCoef, iFourier, maxExpCoef, RTMnlevelCloud, RTMnlayer, dimSV, dimSV_fc, nmutot, &
                    nGauss, controlS, geometryS, optPropRTMGridS, RT_fc)
```

## What zdisamar Does

zdisamar keeps Fourier basis values in reusable LABOS storage.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/workspace.zig#L155-L180)

Excerpt:

```zig
pub fn fourierPlmBasisWithStatus(
    self: *Workspace,
    i_fourier: usize,
    max_phase_index: usize,
    geo: *const basis.Geometry,
) !PlmBasisCacheStatus {
    std.debug.assert(i_fourier < basis.max_phase_coef);
    const previous_cache_len = self.plm_basis_cache.len;
    const previous_valid_len = self.plm_basis_cache_valid.len;
    try ensureCapacity(basis.FourierPlmBasis, self.allocator, &self.plm_basis_cache, basis.max_phase_coef);
    try ensureCapacity(bool, self.allocator, &self.plm_basis_cache_valid, basis.max_phase_coef);
    if (previous_cache_len < basis.max_phase_coef or previous_valid_len < basis.max_phase_coef) {
        @memset(self.plm_basis_cache_valid, false);
    }
    const was_valid = self.plm_basis_cache_valid[i_fourier];
    const needs_extend = was_valid and self.plm_basis_cache[i_fourier].max_phase_index < max_phase_index;
    if (!was_valid or needs_extend) {
        self.plm_basis_cache[i_fourier] = basis.FourierPlmBasis.init(i_fourier, max_phase_index, geo);
        self.plm_basis_cache_valid[i_fourier] = true;
    }
```

zdisamar also stops once later Fourier terms are too small to matter after the configured floor.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/execute.zig#L408-L414)

```zig
const weighted_pressure_tangent_refl_fc = if (i_fourier == 0) blk: {
    break :blk pressure_tangent_refl_fc;
} else blk: {
    const cos_m_dphi = math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
    break :blk (2.0 * pressure_tangent_refl_fc) * cos_m_dphi;
};
aerosol_layer_mid_pressure_tangent += weighted_pressure_tangent_refl_fc;
if (i_fourier >= controls.fourier_floor_scalar and @abs(refl_fc) <= fourier_tail_reflectance_epsilon) break;
```

## Why It Matters

The O2 A run averages about 31 Fourier terms per high-resolution wavelength. Reusing the Fourier basis avoids repeated setup. Stopping tiny tails keeps the loop from spending time on terms that cannot move the result at the required scale.
