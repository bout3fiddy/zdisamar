# 07. Skip Layers And Terms That Cannot Contribute

Measured forward-time saving: `0ae1cad -> f42445d`, 2.460360 s to 2.266849 s, saving 0.193511 s for one spectrum.

## What DISAMAR Does

DISAMAR checks whether the current Fourier term is within the layer's phase-function range, then builds the layer matrices if it is.

Source link: [DISAMAR GitLab source](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L1832-L1870)

Excerpt:

```fortran
do ilayer = RTMnlevelCloud + 1, RTMnlayer

  ! SLOW: only one no-contribution check (Fourier index vs phase coefs).
  !       Layers with effectively zero optical depth or zero scattering
  !       albedo still go through the heavy phase-matrix and doubling
  !       work below — the result is zero, but the cost is paid.
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
    // FAST: skip #1 — Fourier term is past the global cap.
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
    // FAST: skip #2 — Fourier term is past *this layer's* phase coefs.
    if (i_fourier > max_phase_index) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        if (rt_active) |active| active[rt_idx] = false;
        continue;
    }
    // FAST: skip #3 — layer cannot contribute at the retained scale
    //       (vanishing optical depth, or zero single-scatter albedo), so
    //       record the zero and skip the heavy work.
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
    // FAST: rt_active was decided once during layer construction. If the
    //       layer was marked inactive, write zeros and skip the dot
    //       products entirely instead of computing zero through them.
    if (!rt_active_view[ilevel + 1]) {
        for (0..nmutot) |imu| {
            local_d0[imu] = 0.0;
            local_d1[imu] = 0.0;
        }
        continue;
    }
```

## Why It Matters

If a layer cannot scatter at the retained scale, or this Fourier term is past the layer's phase-function range, the heavy matrix work is treated as zero. Doing the work anyway just produces that zero through the long path.

The fix is the cheapest optimization in the book: check first, then skip.

```python
# Slow: do the expensive work even when the answer is going to be zero
for layer in layers:
    R = build_phase_matrix(layer)        # a lot of work
    R = layer_doubling(R)                # more work
    accumulate(R)                        # might just add zero

# Fast: cheap "can this contribute?" test, then skip
for layer in layers:
    if layer.optical_depth < 1e-20 or layer.albedo <= 0.0:
        continue                         # provably zero — stop here
    R = build_phase_matrix(layer)
    R = layer_doubling(R)
    accumulate(R)
```

The O2 A run visits millions of layer/Fourier combinations, so even a small skip ratio prevents phase-matrix work, layer-doubling work, and scattering-order dot products inside that repeated structure.
