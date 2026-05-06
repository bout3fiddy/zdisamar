# 10. Carry Layer Activity Into Scattering Orders

Measured forward-time saving: `c423f4a -> f295ace`, 2.025331 s to 1.980342 s, saving 0.044989 s for one spectrum.

## Why This Step Exists

LABOS first builds reflection and transmission matrices for every atmospheric layer. It then uses those layer matrices again while summing successive scattering orders. If a layer matrix is zero, the later scattering-order dot products will also return zero.

The speedup is simple: remember which layer matrices are zero, then skip their later dot products.

## What DISAMAR Does

DISAMAR computes local up/down fields for every layer in the scattering-order loop. If a layer's reflection/transmission matrix is zero, the dot products still run and produce zero.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L2360-L2396)

Excerpt:

```fortran
do ilevel = startLevel, endLevel - 1
  do imu0 = 1, 2
    do imu = 1, dimSV_fc * nmutot
      ! DISAMAR reaches this dot product for each layer in each order.
      ! A zero RT_fc layer still pays for the multiply-and-sum work.
      UDLocal_fc(ilevel)%D(imu,imu0) = &
      dot_product(RT_fc(ilevel+1)%Rst(imu,1:dimSV_fc*nGauss),        &
                  UDorde_fc(ilevel  )%U(1:dimSV_fc*nGauss,imu0) ) +  &
      dot_product(RT_fc(ilevel+1)%T  (imu,1:dimSV_fc*nGauss),        &
                  UDorde_fc(ilevel+1)%D(1:dimSV_fc*nGauss,imu0) )
    end do
  end do
end do

do ilevel = startLevel + 1, endLevel
  do imu0 = 1, 2
    do imu = 1, dimSV_fc * nmutot
      UDLocal_fc(ilevel)%U(imu,imu0) = &
      dot_product(RT_fc(ilevel)%R(imu,1:dimSV_fc * nGauss),          &
                  UDorde_fc(ilevel)%D(1:dimSV_fc * nGauss,imu0) ) +  &
      dot_product(RT_fc(ilevel)%Tst(imu,1:dimSV_fc *nGauss),         &
                  UDorde_fc(ilevel-1)%U(1:dimSV_fc * nGauss,imu0) )
    end do
  end do
end do
```

## What zdisamar Does

zdisamar records whether each layer can contribute while it builds the layer reflection/transmission matrices.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L321-L344)

Excerpt:

```zig
if (i_fourier > max_phase_index) {
    rt[rt_idx] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[rt_idx] = false;
    continue;
}

if (layer.optical_depth < 1.0e-20 or
    layer.scattering_optical_depth <= 0.0 or
    layer.single_scatter_albedo <= 0.0)
{
    // This layer cannot scatter for this Fourier term. Mark it now so
    // the later scattering-order loop does not multiply by a zero matrix.
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
    if (!rt_active_view[ilevel + 1]) {
        for (0..nmutot) |imu| {
            local_d0[imu] = 0.0;
            local_d1[imu] = 0.0;
        }
        continue;
    }

    // Only active layers reach the dot products.
    for (0..nmutot) |imu| {
        const rst_dot_u = dotGaussPair(&rt[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
        const t_dot_d = dotGaussPair(&rt[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
        local_d0[imu] = rst_dot_u.col0 + t_dot_d.col0;
        local_d1[imu] = rst_dot_u.col1 + t_dot_d.col1;
    }
}
```

## Why It Matters

The O2 A run has millions of layer/Fourier visits. A zero layer is cheap when it is recognized once. It is expensive when the scattering-order loop rediscovers that zero through dot products.

This change is smaller than the fixed matrix-shape work, but it removes repeated work in the part of LABOS that runs after every layer matrix has been built.
