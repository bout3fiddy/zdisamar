# 02. LABOS Top Level

Each high-resolution radiance sample has two major worker-local phases. First, zdisamar builds wavelength-specific optical input: layer optical depths, scattering properties, and related prepared values for that wavelength. Across all workers, that accounts for `3.927454 s` of aggregate CPU.

Then zdisamar executes LABOS transport. That is the larger cost: `11.484103 s` of aggregate worker CPU. This number is larger than the `1.958912 s` caller wall because the work is spread over 10 workers; it is CPU time summed across workers, not elapsed wall time.

The source split is visible in [spectral_forward.zig](../../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L239-L263):

```zig
// Per high-resolution wavelength: build the optical input first.
const input = try ForwardInput.configuredForwardInput(
    scene,
    route,
    prepared,
    wavelength_nm,
    layer_inputs,
    pseudo_spherical_layers,
    source_interfaces,
    rtm_quadrature_levels,
    pseudo_spherical_samples,
    pseudo_spherical_level_starts,
    pseudo_spherical_level_altitudes,
    support_carrier_valid,
    support_carriers,
);

// Then run LABOS transport for that wavelength.
const forward = if (implementations.transport.executePreparedWithLabosWorkspace) |execute_with_workspace|
    try execute_with_workspace(allocator, effective_route, input, labos_workspace)
else
    try implementations.transport.executePrepared(allocator, effective_route, input);
```

Inside LABOS, `11.080734 s` of the `11.484103 s` LABOS CPU is inside the Fourier loop. That means `96.488%` of LABOS CPU is spent repeatedly evaluating Fourier terms. The remaining `0.403369 s` is non-Fourier LABOS overhead.

The Fourier loop is a parent scope. Its children are RT-layer construction (`8.026027 s`), scattering orders (`2.826031 s`), reflectance integration (`0.190831 s`), PLM basis lookup/build (`0.006664 s`), and a small amount of loop/tail overhead (`0.031181 s`). Those child costs are inside the Fourier loop; they should not be added to the parent.

The parent loop is in [execute.zig](../../../src/forward_model/radiative_transfer/labos/execute.zig#L250-L350):

```zig
for (0..fourier_max + 1) |i_fourier| {
    // Basis for this Fourier order. Usually cheap because workspace caching
    // has already removed most repeated basis construction.
    const plm_basis = if (workspace) |scratch|
        try scratch.fourierPlmBasis(i_fourier, phase_max, geo)
    else
        &owned_plm_basis;

    // Largest child: build layer reflection/transmission matrices.
    calcRTlayersIntoWithBasis(
        rt,
        input.layers,
        i_fourier,
        geo,
        controls,
        plm_basis,
        layer_phase_max_indices,
        layer_phase_kernels,
        layer_phase_kernel_valid,
        if (workspace != null) orders_workspace.rt_active else null,
        trace,
    );

    // Second largest child: propagate successive scattering orders.
    const orders_result = if (use_integrated_source)
        orders_mod.ordersScatIntoWithActive(
            orders_workspace,
            0,
            nlayer,
            geo,
            &atten,
            rt,
            controls,
            num_orders_max,
        )
    else
        orders_mod.ordersScatTransportInto(
            orders_workspace,
            0,
            nlayer,
            geo,
            &atten,
            rt,
            controls,
            num_orders_max,
        );

    // Small child: turn the current Fourier term into reflectance.
    const refl_fc = if (use_integrated_source)
        calcIntegratedReflectanceWithBasis(
            input.layers,
            input.source_interfaces,
            input.rtm_quadrature,
            orders_result.ud,
            nlayer,
            i_fourier,
            geo,
            plm_basis,
            adjacent_layer_phase_max_indices,
            layer_phase_kernels,
            layer_phase_kernel_valid,
        )
    else
        calcReflectance(orders_result.ud, nlayer, geo);
}
```

The important result is that the remaining wall is not setup, allocation, or output-grid assembly. It is the exact LABOS Fourier transport calculation, dominated by RT-layer construction and scattering orders.

## Simple Python Shape

The timing hierarchy is nested:

```python
def high_resolution_sample(wavelength):
    input_state = build_wavelength_specific_input(wavelength)
    return labos_execute(input_state)


def labos_execute(input_state):
    total = 0.0
    for fourier in active_fourier_terms(input_state):
        rt_layers = build_rt_layers(input_state, fourier)   # largest child
        orders = propagate_scattering_orders(rt_layers)     # second largest child
        total += integrate_reflectance(orders, fourier)
    return total
```

`labos_execute` contains the Fourier loop, and the Fourier loop contains RT-layer construction and scattering orders. The percentages are nested, not sibling rows that should sum independently.
