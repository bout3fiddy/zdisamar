# 04. Skip Layers And Terms That Cannot Contribute

Measured forward-time saving: `0ae1cad -> f42445d`, 2.460360 s to 2.266849 s, saving 0.193511 s for one spectrum.

## What DISAMAR Does

DISAMAR checks whether the current Fourier term is within the layer's phase-function range, then builds the layer matrices if it is.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L1832-L1870)

Excerpt:

```fortran
do ilayer = RTMnlevelCloud + 1, RTMnlayer

  if ( iFourier <= optPropRTMGridS%maxExpCoefLay(ilayer) ) then

    b = optPropRTMGridS%opticalThicknLay(ilayer)
    a = optPropRTMGridS%ssaLay(ilayer)

    beta(:)  = optPropRTMGridS%phasefCoefLay(1,1,:,ilayer)

    doubling = .false.

    beta_eff = beta
    do iCoef = iFourier, optPropRTMGridS%maxExpCoefLay(ilayer)
      beta_eff(iCoef) = abs(beta_eff(iCoef))/(2*iCoef+1)
    end do

    call fillZplusZmin(errS, fcCoef, iFourier, optPropRTMGridS%maxExpCoefLay(ilayer), dimSV, dimSV_fc, nmutot, &
                       optPropRTMGridS%phasefCoefLay(:,:,:,ilayer), geometryS, Zplus, Zmin, string)
```

## What zdisamar Does

zdisamar makes more no-contribution checks before doing the expensive matrix work.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L321-L344)

Excerpt:

```zig
for (0..nlayer) |layer_idx| {
    const rt_idx = layer_idx + 1;
    const layer = layers[layer_idx];
    if (i_fourier >= basis.max_phase_coef) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        if (rt_active) |active| active[rt_idx] = false;
        continue;
    }

    const phase_coefs = layer.phase_coefficients;
    const max_phase_index = if (layer_phase_max_indices) |indices|
        indices[layer_idx]
    else
        phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    if (i_fourier > max_phase_index) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        if (rt_active) |active| active[rt_idx] = false;
        continue;
    }
    if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0 or layer.single_scatter_albedo <= 0.0) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        if (rt_active) |active| active[rt_idx] = false;
        continue;
    }
```

The scattering-order code also skips dot products for inactive layers.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/orders.zig#L432-L441)

```zig
for (start_level..end_level) |ilevel| {
    const local_d0 = &ud_local_view[ilevel].D.col[0].data;
    const local_d1 = &ud_local_view[ilevel].D.col[1].data;
    if (!rt_active_view[ilevel + 1]) {
        for (0..nmutot) |imu| {
            local_d0[imu] = 0.0;
            local_d1[imu] = 0.0;
        }
        continue;
    }
```

## Why It Matters

The O2 A run visits millions of layer/Fourier combinations. A small skip is valuable when it prevents phase-matrix work, layer-doubling work, or scattering-order dot products inside that repeated structure.
