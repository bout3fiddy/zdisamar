# 06. Scattering Orders

Scattering orders are the second major LABOS block after RT-layer construction. They cost `2.826031 s`, or `24.608%` of aggregate LABOS CPU. There is one orders call for each Fourier term, so the trace counted `120,390` orders calls.

What that means: after LABOS builds layer reflection/transmission matrices, it propagates successive scattering orders upward and downward through the atmosphere. Some calls return after the initial source/transport stage; the trace counted `66,429` initial-return calls. The remaining calls enter the multiple-scattering loop, which ran `258,796` iterations across the spectrum.

The multiple-order loop is in [orders.zig](../../../src/forward_model/radiative_transfer/labos/orders.zig#L439-L558):

```zig
while (true) {
    num_orders += 1;

    // Downward local field for this scattering order.
    for (start_level..end_level) |ilevel| {
        if (!rt_active_view[ilevel + 1]) {
            // This layer was marked inactive during RT-layer construction.
            // Skip the dot products and write zeros.
            for (0..nmutot) |imu| {
                local_d0[imu] = 0.0;
                local_d1[imu] = 0.0;
            }
            continue;
        }

        for (0..nmutot) |imu| {
            const rst_dot_u = dotGaussPair(&rt[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
            const t_dot_d = dotGaussPair(&rt[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
            local_d0[imu] = rst_dot_u.col0 + t_dot_d.col0;
            local_d1[imu] = rst_dot_u.col1 + t_dot_d.col1;
        }
    }

    // Upward local field has the same shape: skip inactive layers, otherwise
    // run paired Gauss dot products through R and T.
    for (start_level + 1..end_level + 1) |ilevel| {
        const r_dot_d = dotGaussPair(&rt[ilevel].R, imu, prev_d0, prev_d1, n_gauss);
        const tst_dot_u = dotGaussPair(&rt[ilevel].T, imu, prev_u0, prev_u1, n_gauss);
    }

    if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) break;
    // If this order is still large enough, add it to the accumulated field.
    accumulateOrderContribution(
        track_sum_local,
        ud_view,
        ud_sum_local_view,
        ud_orde_view,
        ud_local_view,
        start_level,
        end_level,
        nmutot,
    );
}
```

The split tells us where that `2.826031 s` goes: initial source setup costs `0.130322 s`; initial transport costs `0.324308 s`; the multiple-order loop costs `2.198735 s`; local downward propagation costs `0.623497 s`; local upward propagation costs `0.609598 s`; transport to other levels costs `0.663621 s`; and accumulation costs `0.277443 s`.

The hot primitive in the multiple-order loop is the paired Gauss dot product in [orders.zig](../../../src/forward_model/radiative_transfer/labos/orders.zig#L186-L218):

```zig
fn dotGaussPair(
    mat: *const basis.Mat,
    row: usize,
    vec_col0: *const basis.Vec,
    vec_col1: *const basis.Vec,
    n_gauss: usize,
) DotPair {
    if (n_gauss == 10) {
        // One call computes two 10-term dot products from the same matrix row.
        var s0 = data[0] * vec0[0];
        var s1 = data[0] * vec1[0];
        s0 += data[1] * vec0[1];
        s1 += data[1] * vec1[1];
        // ... repeated through Gauss term 9 ...
        return .{ .col0 = s0, .col1 = s1 };
    }
}
```

The trace counted `295,581,240` `dotGaussPair` calls, representing `2,955,812,400` multiply-add terms. The [inactive-layer skip is already doing useful work](../why-zdisamar-is-faster/10-carry-layer-activity-into-orders.md): it skipped `5,499,208` down-layer cases and `5,499,208` up-layer cases. The remaining orders cost is the active multiple-scattering propagation that LABOS still has to perform until the order contribution falls below the convergence threshold.

## Simple Python Shape

Scattering orders repeat until the next order is small enough:

```python
order = initial_source()
total = order

while True:
    local_down = []
    local_up = []

    for layer in layers:
        if not layer.active:
            local_down.append(0.0)
            local_up.append(0.0)
            continue

        down = dot(layer.R, order.up) + dot(layer.T, order.down)
        up = dot(layer.R, order.down) + dot(layer.T, order.up)
        local_down.append(down)
        local_up.append(up)

    order = transport_to_other_levels(local_down, local_up)
    if max_abs(order) < convergence_threshold:
        break
    total += order
```

The inactive-layer check prevents some dot products. The active layers still have to propagate upward and downward orders until convergence.
