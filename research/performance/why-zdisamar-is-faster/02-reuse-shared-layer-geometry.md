# 02. Reuse Shared Layer Geometry

Measured forward-time saving: included in `511061b -> e23035b`, 79.767901 s to 11.890893 s for one spectrum. The checkpoint does not split this geometry reuse from the unique-wavelength change.

## Why This Step Exists

The atmospheric grid has layer boundaries, altitudes, thicknesses, source-function levels, and other geometry values. RTM here means the radiative-transfer model layer layout that LABOS receives. Those geometry values do not change when the wavelength changes. The absorption and scattering values change with wavelength, but the vertical layout of the atmosphere does not.

If the geometry is rebuilt for each high-resolution wavelength, we pay for the same layer layout thousands of times.

## What DISAMAR Does

DISAMAR carries a general wavelength, pressure, and geometry table flow. It copies the geometry table inside the same broad loop that handles bands and Fourier terms. That keeps the executable general, but it is heavier than the O2 A case needs.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/DISAMARModule.f90#L2734-L2744)

Excerpt:

```fortran
! SLOW: this geometry copy lives inside the band x Fourier loop, so the
!       same vertical layout is re-copied for every Fourier term — even
!       though geometry never changes with wavelength or Fourier index.
! geometry (mu = cos(theta) with theta the polar angle
do imu = 1, globalS%createLUTSimS(iFourier,iband)%nmu
  globalS%createLUTSimS(iFourier,iband)%mu(imu) = &
  globalS%geometrySimS%u(imu)
end do ! imu
do imu = 1, globalS%createLUTRetrS(iFourier,iband)%nmu
  globalS%createLUTRetrS(iFourier,iband)%mu(imu) = &
  globalS%geometryRetrS%u(imu)
end do ! imu
```

DISAMAR then passes wavelength-specific layer arrays into LABOS. LABOS is designed to accept those arrays for a broad set of configurations.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L472-L483)

```fortran
! SLOW: geometryS is passed in per call, so each high-resolution wavelength
!       hands LABOS a full geometry record instead of reusing a cached one.
! INPUT
type(errorType), intent(inout) :: errS
integer,                     intent(in)   :: iFourier, maxFourierTermLUT, dimSV, dimSV_fc
type(optPropRTMGridType),    intent(in)   :: optPropRTMGridS
type(RRS_RingType),          intent(in)   :: RRS_RingS
type(controlType),           intent(in)   :: controlS
type(createLUTType),         intent(inout):: createLUTS
type(geometryType),          intent(in)   :: geometryS

integer,                     intent(in)   :: RTMnlevelCloud, iwave
type(wavelHRType),           intent(in)   :: wavelMRS   ! instr - high resolution wavelength grid
```

Inside LABOS, the Fourier work then uses both `geometryS` and `optPropRTMGridS`.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/LabosModule.f90#L245-L255)

```fortran
bsca = sum(optPropRTMGridS%opticalThicknLay(:) * optPropRTMGridS%ssaLay(:) )
babs = sum(optPropRTMGridS%opticalThicknLay(:) * (1.0d0 - optPropRTMGridS%ssaLay(:)) )

if ( controlS%numOrdersMax == 0 ) then
  numOrdersMax = int(bsca + 15.0d0)
else
  numOrdersMax = controlS%numOrdersMax
end if

call fillAttenuation (errS, optPropRTMGridS, controlS, geometryS, nmutot, RTMnlayer, atten)
```

## What zdisamar Does

zdisamar builds the shared vertical geometry once during preparation. Later, each wavelength fills only the wavelength-dependent optical values into that prepared shape.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/prepared_state.zig#L149-L156)

Excerpt:

```zig
pub fn ensureSharedRtmGeometryCache(
    self: *PreparedOpticalState,
    allocator: Allocator,
) !void {
    // FAST: build the shared layer geometry exactly once during preparation,
    //       then reuse it across every wavelength. The early-return below is
    //       what makes repeated calls free.
    if (self.shared_rtm_geometry.isValidFor(self.transportLayerCount())) return;
    self.shared_rtm_geometry.deinit(allocator);
    self.shared_rtm_geometry = try @import("transport.zig").buildSharedRtmGeometry(allocator, self);
}
```

The shared geometry stores the layer heights and thicknesses.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/shared_geometry.zig#L127-L150)

```zig
pub fn buildSharedRtmGeometry(
    allocator: std.mem.Allocator,
    self: *const PreparedOpticalState,
) !SharedRtmGeometry {
    const transport_layer_count = self.transportLayerCount();
    if (!usesSharedRtmGrid(self, transport_layer_count)) return .{};
    const sublayers = self.sublayers orelse return .{};

    const layers = try allocator.alloc(SharedRtmLayerGeometry, transport_layer_count);
    errdefer allocator.free(layers);
    const levels = try allocator.alloc(SharedRtmLevelGeometry, transport_layer_count + 1);
    errdefer allocator.free(levels);
    @memset(layers, .{});
    @memset(levels, .{});

    for (self.layers, 0..) |layer, layer_index| {
        layers[layer_index] = .{
            .lower_altitude_km = layer.bottom_altitude_km,
            .upper_altitude_km = layer.top_altitude_km,
            .midpoint_altitude_km = 0.5 * (layer.bottom_altitude_km + layer.top_altitude_km),
            .thickness_km = @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0),
        };
```

During the forward calculation, zdisamar creates one per-wavelength cache and uses it to fill layers, source interfaces, and source-function quadrature without rebuilding the shared layer geometry.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L53)

```zig
// FAST: only the wavelength-dependent optical values are filled per call.
//       The shared layer geometry is read straight out of `prepared` —
//       no rebuild, no copy.
var wavelength_cache = CarrierEval.WavelengthCarrierCache.init(
    prepared,
    wavelength_nm,
    support_carrier_valid,
    support_carriers,
);
const optical_depths = OpticsPreparation.transport.fillForwardLayersAtWavelengthWithCarrierCache(
    prepared,
    scene,
    wavelength_nm,
    layer_inputs,
    &wavelength_cache,
);
var input = OpticsPreparation.transport.forwardInputFromOpticalDepths(
    prepared,
    scene,
    wavelength_nm,
    optical_depths,
    layer_inputs,
);
const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];
var has_rtm_quadrature = false;
if (route.rtm_controls.integrate_source_function) {
    has_rtm_quadrature = OpticsPreparation.transport.fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
        prepared,
        wavelength_nm,
        input.layers,
        rtm_quadrature_levels[0 .. input.layers.len + 1],
        &wavelength_cache,
    );
```

## Why It Matters

The vertical layout of the atmosphere (layer heights, thicknesses, midpoints) does not change with wavelength. Only the absorption and scattering numbers do. So rebuilding the layout for every wavelength is paying for the same answer thousands of times.

The classic fix is to hoist work that does not depend on the loop variable out of the loop:

```python
# Slow: rebuild the part that never changes
for wavelength in wavelengths:
    layers = build_layer_geometry(profile)   # same answer every time
    optics = build_optics(profile, wavelength)
    run(layers, optics)

# Fast: build once, reuse on every iteration
layers = build_layer_geometry(profile)
for wavelength in wavelengths:
    optics = build_optics(profile, wavelength)
    run(layers, optics)
```

The timing table does not isolate this from the unique-wavelength change, so the honest measured statement is that both changes together produced the 67.88 s early checkpoint saving.
