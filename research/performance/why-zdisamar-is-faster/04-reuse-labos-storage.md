# 04. Reuse LABOS Storage

Measured forward-time saving: `5ef6c71 -> b0a9e0f`, 8.432518 s to 7.020602 s, saving 1.411916 s for one spectrum.

## What DISAMAR Does

DISAMAR allocates and frees several LABOS objects inside the Fourier loop. That is a reasonable design for a broad executable because each Fourier term can have the storage shape it needs. It is not ideal for one repeated O2 A spectrum because the shapes are stable and the loop is repeated many times.

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

    ! These objects are allocated inside the repeated Fourier work.
    call allocCoef(errS, fcCoef, nmutot, dimSV_fc, maxExpCoef)
    call allocateReflTransInternalField(errS, RTMnlayer, dimSV_fc, nmutot, nmuextra, RT_fc,  &
                                        UDorde_fc, UDLocal_fc, UDsumLocal_fc, UD_fc)
  end if

  call fillPlmVector(errS, fcCoef, iFourier, dimSV_fc, nmutot, maxExpCoef, geometryS)
  call CalcRTlayers(errS, fcCoef, iFourier, maxExpCoef, RTMnlevelCloud, RTMnlayer, dimSV, dimSV_fc, nmutot, &
                    nGauss, controlS, geometryS, optPropRTMGridS, RT_fc)
```

Cleanup is also inside the Fourier loop.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L421-L425)

```fortran
if ( .not. controlS%aerosolLayerHeight ) then
  call deallocCoef(errS, fcCoef, maxExpCoef)
  call deallocateReflTransIntField(errS, RTMnlayer, RT_fc, UDorde_fc, UDLocal_fc, UDsumLocal_fc, UD_fc)
end if
```

## What zdisamar Does

zdisamar keeps reusable LABOS storage. Each high-resolution wavelength then reuses the arrays that hold attenuation values, layer reflection/transmission values, scattering-order values, phase matrices, and Fourier basis values.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/workspace.zig#L46-L140)

Excerpt:

```zig
pub fn attenuation(
    self: *Workspace,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) !attenuation_mod.DynamicAttenArray {
    const nlevel = layers.len + 1;
    const required_len = geo.nmutot * nlevel * nlevel;
    try ensureCapacity(f64, self.allocator, &self.attenuation_data, required_len);
    try ensureCapacity(f64, self.allocator, &self.attenuation_layer_transmittance, geo.nmutot * layers.len);
    return attenuation_mod.fillAttenuationDynamicWithGridInBufferAndLayerCache(
        self.allocator,
        self.attenuation_data,
        self.attenuation_layer_transmittance,
        layers,
        pseudo_spherical_grid,
        geo,
        use_spherical_correction,
    );
}

pub fn layerRt(self: *Workspace, nlevel: usize) ![]basis.LayerRT {
    try ensureCapacity(basis.LayerRT, self.allocator, &self.rt_layers, nlevel);
    return self.rt_layers[0..nlevel];
}

pub fn ordersWorkspace(self: *Workspace, nlevel: usize) !*orders_mod.OrdersWorkspace {
    if (self.orders) |*orders| {
        if (orders.ud.len >= nlevel) return orders;
        orders.deinit();
        self.orders = null;
    }
    self.orders = try orders_mod.OrdersWorkspace.init(self.allocator, nlevel);
    return &(self.orders.?);
}
```

## Why It Matters

LABOS needs scratch arrays to hold attenuation, layer reflection/transmission, scattering orders, and Fourier basis values. Each high-resolution wavelength uses arrays of the same shape. Allocating fresh arrays inside the inner loop, then freeing them, is paying for memory bookkeeping over and over.

The fix is to allocate once outside the loop and pass the same buffer in:

```python
# Slow: allocate (and free) inside the hot loop
for wavelength in wavelengths:
    buf = [0.0] * 12000      # fresh allocation every iteration
    fill_with_results(buf, wavelength)
    use(buf)
    # buf goes away here, only to be re-created next iteration

# Fast: allocate once, reuse the same buffer
buf = [0.0] * 12000
for wavelength in wavelengths:
    fill_with_results(buf, wavelength)
    use(buf)
```

The science is identical; only the storage handling changes. That saved about 1.41 s in the checkpoint table.
