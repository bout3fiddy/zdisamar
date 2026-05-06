# 10. Carry Layer Activity Into Scattering Orders

Measured forward-time saving: `c423f4a -> f295ace`, 2.025331 s to 1.980342 s, saving 0.044989 s for one spectrum.

## Why This Step Exists

LABOS first builds reflection and transmission matrices for every atmospheric layer. It then uses those layer matrices again while summing successive scattering orders. If a layer matrix is zero, the later scattering-order dot products will also return zero.

The speedup is simple: remember which layer matrices are zero, then skip their later dot products.

## What DISAMAR Does

DISAMAR computes local up/down fields for every layer in the scattering-order loop. If a layer's reflection/transmission matrix is zero, the dot products still run and produce zero.

Source link: [DISAMAR GitLab source](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L2360-L2396)

Excerpt:

```fortran
do ilevel = startLevel, endLevel - 1
  do imu0 = 1, 2
    do imu = 1, dimSV_fc * nmutot
      ! SLOW: the dot products run for every layer at every order. If
      !       RT_fc(ilevel+1) is the zero matrix, we still pay for two
      !       full dot products per (imu, imu0) just to get zero back.
      UDLocal_fc(ilevel)%D(imu,imu0) = &
      dot_product(RT_fc(ilevel+1)%Rst(imu,1:dimSV_fc*nGauss),        &
                  UDorde_fc(ilevel  )%U(1:dimSV_fc*nGauss,imu0) ) +  &
      dot_product(RT_fc(ilevel+1)%T  (imu,1:dimSV_fc*nGauss),        &
                  UDorde_fc(ilevel+1)%D(1:dimSV_fc*nGauss,imu0) )
    end do ! imu
  end do ! imu0
end do ! ilevel

do ilevel = startLevel + 1, endLevel
  do imu0 = 1, 2
    do imu = 1, dimSV_fc * nmutot
      UDLocal_fc(ilevel)%U(imu,imu0) = &
      dot_product(RT_fc(ilevel)%R(imu,1:dimSV_fc * nGauss),          &
                  UDorde_fc(ilevel)%D(1:dimSV_fc * nGauss,imu0) ) +  &
      dot_product(RT_fc(ilevel)%Tst(imu,1:dimSV_fc *nGauss),         &
                  UDorde_fc(ilevel-1)%U(1:dimSV_fc * nGauss,imu0) )
    end do ! imu
  end do ! imu0
end do ! ilevel
```

## What zdisamar Does

zdisamar records whether each layer can contribute while it builds the layer reflection/transmission matrices.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L335-L344)

Excerpt:

```zig
// FAST: while building layer matrices, also write down whether the
//       layer can contribute. `rt_active[rt_idx] = false` is the flag
//       the scattering-order loop will check later instead of
//       re-discovering the zero through expensive dot products.
if (i_fourier > max_phase_index) {
    rt[rt_idx] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[rt_idx] = false;
    continue;
}

if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0 or layer.single_scatter_albedo <= 0.0) {
    // FAST: same idea — the layer is provably inactive for this Fourier
    //       term. Record it and skip the heavy build entirely.
    rt[rt_idx] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[rt_idx] = false;
    continue;
}
```

The scattering-order loop then uses that flag before the dot products.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/orders.zig#L432-L490)

```zig
for (start_level..end_level) |ilevel| {
    const local_d0 = &ud_local_view[ilevel].D.col[0].data;
    const local_d1 = &ud_local_view[ilevel].D.col[1].data;
    // FAST: this is the payoff. Reading the precomputed rt_active flag
    //       is one bool. If the layer was zero, write zeros into D and
    //       move on — no dot products at all.
    if (!rt_active_view[ilevel + 1]) {
        for (0..nmutot) |imu| {
            local_d0[imu] = 0.0;
            local_d1[imu] = 0.0;
        }
        continue;
    }

    // FAST: only active layers reach the dot products below.
    for (0..nmutot) |imu| {
        const rst_dot_u = dotGaussPair(&rt[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
        const t_dot_d = dotGaussPair(&rt[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
        local_d0[imu] = rst_dot_u.col0 + t_dot_d.col0;
        local_d1[imu] = rst_dot_u.col1 + t_dot_d.col1;
    }
}
```

## Why It Matters

The layer-build pass already discovered which layers cannot contribute (zero optical depth, Fourier term out of range). Without remembering that, the scattering-order pass walks every layer and rediscovers the same zeros — by paying for the dot products and getting zero back.

The fix is to write down the answer once and check the flag later:

```python
# Slow: scattering-order loop does dot products for every layer
for layer in layers:
    for order in orders:
        result = dot(layer.R, prev) + dot(layer.T, prev_d)   # zero if R, T are zero

# Fast: remember which layers were zero, then skip those dot products
active = [l.contributes() for l in layers]                   # decided once
for layer, ok in zip(layers, active):
    for order in orders:
        if not ok:
            continue                                          # no math, no zero result
        result = dot(layer.R, prev) + dot(layer.T, prev_d)
```

A zero layer is cheap when it is recognized once. It is expensive when the scattering-order loop rediscovers that zero through dot products. The O2 A run has millions of layer/Fourier visits, so the saving compounds even though each individual skip is small.
