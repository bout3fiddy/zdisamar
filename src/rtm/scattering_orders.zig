const std = @import("std");

const attenuation_mod = @import("attenuation.zig");
const controls = @import("controls.zig");
const gauss_angles = @import("gauss_angles.zig");
const CostTiming = @import("../instrumentation/cost_timing.zig");
const rows = @import("rows.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");
const Trace = @import("../instrumentation/trace.zig");

// scattering_orders.zig ------------------------------------------------------------------------------------- |
// LABOS scattering-order transport over prepared layer reflection/transmission rows.                          |
//                                                                                                             |
//   `transportToOtherLevels`, the fixed 12-direction transport variants, active-layer scanning, and the       |
//   paired Gaussian dot-product route.                                                                        |
//                                                                                                             |
// reference names                                                                                             |
//   E         : direct top-to-level attenuation field                                                         |
//   UD_fc     : accumulated transported upward/downward order fields                                          |
//   UDorde_fc : current transported scattering order                                                          |
//   UDlocal   : current untransported local source                                                            |
//                                                                                                             |
// math                                                                                                        |
//   initial D_local = T_layer * direct_solar_attenuation                                                      |
//   initial U_local = R_layer * direct_solar_attenuation                                                      |
//                                                                                                             |
//   later D_local = R_layer * U_previous + T_layer * D_previous                                               |
//   later U_local = R_layer * D_previous + T_layer * U_previous                                               |
//                                                                                                             |
//   U_level = U_local_level + attenuation(previous -> level) * U_previous_level                               |
//   D_level = D_local_level + attenuation(next     -> level) * D_next_level                                   |
//                                                                                                             |
// memory                                                                                                      |
//   OrdersWorkArrays owns no heap memory. It borrows slices allocated by a transport worker memory owner,     |
//   and every solve writes those caller-owned rows in place.                                                  |
// ------------------------------------------------------------------------------------------------------------|

// OrdersView -------------------------------------------------------------------------------------------------|
// Borrowed result returned after a workspace-backed scattering-order solve.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] ud           : []const UDField                                                                     |
// [16..31] ud_sum_local : []const UDLocal                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: both slices point into OrdersWorkArrays                                                 |
// footprint: per instance = 32 B (0.031 KiB); referenced rows are owned by caller memory                      |
pub const OrdersView = struct {
    ud: []const rows.UDField,
    ud_sum_local: []const rows.UDLocal,
};
// ------------------------------------------------------------------------------------------------------------|

// OrdersWorkArrays ------------------------------------------------------------------------------------------ |
// Borrowed row storage for one LABOS scattering-order solve.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// normal build: size 112 B (0.109 KiB), align 8                                                               |
// trace build : size 120 B (0.117 KiB), align 8                                                               |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] ud           : []UDField                                                                           |
// [16..31] ud_sum_local : []UDLocal                                                                           |
// [32..47] ud_orde      : []UDLocal                                                                           |
// [48..63] ud_local     : []UDLocal                                                                           |
// [64..79] ud_tangent_orde  : []UDLocal                                                                       |
// [80..95] ud_tangent_local : []UDLocal                                                                       |
// [96..111] rt_active       : []bool                                                                          |
// [112..119] trace build only: cost_timing_state : WorkspaceState                                             |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: all slices are borrowed from the transport worker memory owner                          |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 120 B (0.117 KiB); referenced rows are caller-owned                               |
pub const OrdersWorkArrays = struct {
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_orde: []rows.UDLocal,
    ud_local: []rows.UDLocal,
    ud_tangent_orde: []rows.UDLocal,
    ud_tangent_local: []rows.UDLocal,
    rt_active: []bool,
    cost_timing_state: CostTiming.WorkspaceState = .{},

    pub fn setCostTiming(self: *OrdersWorkArrays, active: ?CostTiming.Active) void {
        // OrdersWorkArrays.setCostTiming --------------------------------------------------------------------|
        // Attach the worker-local cost row used by enabled cost-timing builds.                                |
        // ----------------------------------------------------------------------------------------------------|
        CostTiming.setActiveWorkspaceState(&self.cost_timing_state, active);
    }

    pub fn activeCostTiming(self: *OrdersWorkArrays) ?CostTiming.Active {
        // OrdersWorkArrays.activeCostTiming -----------------------------------------------------------------|
        // Return the active cost row for order child stages.                                                  |
        // ----------------------------------------------------------------------------------------------------|
        return CostTiming.activeWorkspaceState(&self.cost_timing_state);
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn solveOrdersWithActive(
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrdersWithActive --------------------------------------------------------------------------------- |
    // Build order fields using the active-layer mask already prepared by the layer RT builder.                |
    //                                                                                                         |
    // The mask may conservatively mark a zero layer active, but it must not mark a nonzero RT row inactive.   |
    // --------------------------------------------------------------------------------------------------------|
    const result = solveOrdersInternal(
        false,
        true,
        work,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        transport_controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = &.{},
    };
}

pub fn solveOrdersWithActiveLocalSum(
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrdersWithActiveLocalSum ------------------------------------------------------------------------- |
    // Build order fields and local sums using an active-layer mask prepared by the layer RT builder.          |
    // --------------------------------------------------------------------------------------------------------|
    return solveOrdersInternal(
        true,
        true,
        work,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        transport_controls,
        num_orders_max,
    );
}

pub fn solveOrdersTangent(
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation_base: anytype,
    attenuation_tangent: anytype,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrdersTangent ------------------------------------------------------------------------------------ |
    // Propagate non-integrated derivative order fields through the LABOS scattering-order recurrence.         |
    //                                                                                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   d(T * attenuation) = dT * attenuation + T * d attenuation                                             |
    //   d(R * U) = dR * U + R * dU                                                                            |
    //                                                                                                         |
    // convergence                                                                                             |
    //   The base current order controls the same first/multiple-order stop gates as the current route.        |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;
    const level_count = end_level + 1;

    std.debug.assert(work.ud.len >= level_count);
    std.debug.assert(work.ud_orde.len >= level_count);
    std.debug.assert(work.ud_local.len >= level_count);
    std.debug.assert(work.ud_tangent_orde.len >= level_count);
    std.debug.assert(work.ud_tangent_local.len >= level_count);
    std.debug.assert(work.rt_active.len >= level_count);
    std.debug.assert(rt.len >= level_count);
    std.debug.assert(rt_tangent.len >= level_count);

    const ud_tangent = work.ud[0..level_count];
    const base_orde = work.ud_orde[0..level_count];
    const base_local = work.ud_local[0..level_count];
    const tangent_orde = work.ud_tangent_orde[0..level_count];
    const tangent_local = work.ud_tangent_local[0..level_count];
    const rt_active = work.rt_active[0..level_count];
    initializeTangentOrderBuffers(ud_tangent, base_orde, base_local, tangent_orde, tangent_local, stream_count);
    refreshActiveLayerMask(rt[0..level_count], rt_active, stream_count);

    fillInitialTangentDirectAndLocalSources(
        ud_tangent,
        base_local,
        tangent_local,
        start_level,
        end_level,
        geometry,
        attenuation_base,
        attenuation_tangent,
        rt,
        rt_tangent,
        rt_active,
    );
    transportToOtherLevels(start_level, end_level, stream_count, attenuation_base, base_local, base_orde);
    transportToOtherLevelsTangent(
        start_level,
        end_level,
        stream_count,
        attenuation_base,
        attenuation_tangent,
        tangent_local,
        base_orde,
        tangent_orde,
    );
    copyTransportedOrderIntoOutput(ud_tangent, tangent_orde, start_level, end_level);

    var max_value = maxOutgoingUpward(base_orde, end_level, gaussian_count, stream_count);
    const first_order_converged =
        max_value < transport_controls.performance_thresholds.threshold_conv_first;
    if (transport_controls.scattering != .multiple or first_order_converged) {
        return .{ .ud = ud_tangent, .ud_sum_local = &.{} };
    }

    var order_index: usize = 1;
    while (true) {
        order_index += 1;

        fillDownwardLocalSourcesTangent(
            start_level,
            end_level,
            geometry,
            rt,
            rt_tangent,
            rt_active,
            base_orde,
            tangent_orde,
            base_local,
            tangent_local,
        );
        fillUpwardLocalSourcesTangent(
            start_level,
            end_level,
            geometry,
            rt,
            rt_tangent,
            rt_active,
            base_orde,
            tangent_orde,
            base_local,
            tangent_local,
        );
        transportToOtherLevels(start_level, end_level, stream_count, attenuation_base, base_local, base_orde);
        transportToOtherLevelsTangent(
            start_level,
            end_level,
            stream_count,
            attenuation_base,
            attenuation_tangent,
            tangent_local,
            base_orde,
            tangent_orde,
        );

        max_value = maxOutgoingUpward(base_orde, end_level, gaussian_count, stream_count);
        if (max_value < transport_controls.performance_thresholds.threshold_conv_mult or
            order_index >= num_orders_max)
        {
            break;
        }

        accumulateOrderContribution(
            false,
            ud_tangent,
            work.ud_sum_local[0..0],
            tangent_orde,
            tangent_local,
            start_level,
            end_level,
            stream_count,
        );
    }

    return .{ .ud = ud_tangent, .ud_sum_local = &.{} };
}

fn solveOrdersInternal(
    comptime track_sum_local: bool,
    comptime rt_active_ready: bool,
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrdersInternal ----------------------------------------------------------------------------------- |
    // Core LABOS scattering-order recurrence. Steps:                                                          |
    //                                                                                                         |
    //   1. fill direct attenuation E and first local U/D sources                                              |
    //   2. transport the first order through all levels                                                       |
    //   3. return for single scattering or first-order convergence                                            |
    //   4. build later local sources from the previous transported order                                      |
    //   5. transport, test convergence, and accumulate retained orders                                        |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : one call per retained Fourier term                                                         |
    //   reads    : RT layer rows, attenuation rows, active-layer mask                                         |
    //   writes   : workspace U/D fields and optional local-source sums                                        |
    //                                                                                                         |
    // instrumentation                                                                                         |
    //   trace counters uses `orders.zig` names; perturbation hooks gate the same first and multiple           |
    //   convergence decisions as the current route.                                                           |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;
    const level_count = end_level + 1;

    std.debug.assert(work.ud.len >= level_count);
    if (track_sum_local) std.debug.assert(work.ud_sum_local.len >= level_count);
    std.debug.assert(work.ud_orde.len >= level_count);
    std.debug.assert(work.ud_local.len >= level_count);
    std.debug.assert(work.rt_active.len >= level_count);
    std.debug.assert(rt.len >= level_count);

    const ud = work.ud[0..level_count];
    const ud_sum_local = if (track_sum_local) work.ud_sum_local[0..level_count] else work.ud_sum_local[0..0];
    const ud_orde = work.ud_orde[0..level_count];
    const ud_local = work.ud_local[0..level_count];
    const rt_active = work.rt_active[0..level_count];
    initializeOrderBuffers(track_sum_local, ud, ud_sum_local, ud_orde, ud_local, stream_count);

    // instrumentation: trace counter: order solve ------------------------------------------------------------|
    // captures: LABOS scattering-order solver calls                                                           |
    // why: count the transport solves hidden under each Fourier term.                                         |
    Trace.plotU("orders_calls", 1);
    // end instrumentation: trace counter: order solve --------------------------------------------------------|

    if (!rt_active_ready) {
        refreshActiveLayerMask(rt[0..level_count], rt_active, stream_count);
    }

    {

        // instrumentation: trace zone: initial sources -------------------------------------------------------|
        // captures: initial local source construction wall time                                               |
        // why: separate first-order source setup from later inter-level transport.                            |
        const zone = Trace.deepStaticZone(@src(), "labos.orders.initial_sources");
        defer zone.end();
        const trace_start = CostTiming.start(work.activeCostTiming());
        defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_initial_sources");

        fillInitialDirectAndLocalSources(
            ud,
            ud_sum_local,
            ud_local,
            start_level,
            end_level,
            geometry,
            attenuation,
            rt,
            rt_active,
            track_sum_local,
        );
        // end instrumentation: trace zone: initial sources ---------------------------------------------------|

    }

    {

        // instrumentation: trace zone: initial transport -----------------------------------------------------|
        // captures: initial-order transport wall time                                                         |
        // why: isolate first scattering transport before convergence tests.                                   |
        const zone = Trace.deepStaticZone(@src(), "labos.orders.initial_transport");
        defer zone.end();
        const trace_start = CostTiming.start(work.activeCostTiming());
        defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_initial_transport");
        transportToOtherLevels(start_level, end_level, stream_count, attenuation, ud_local, ud_orde);
        // end instrumentation: trace zone: initial transport -------------------------------------------------|

    }

    copyTransportedOrderIntoOutput(ud, ud_orde, start_level, end_level);

    var max_value = maxOutgoingUpward(ud_orde, end_level, gaussian_count, stream_count);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: first-order convergence stop                                                                  |
    // Return after the first transported order when max outgoing upward light is below threshold_conv_first.  |
    // --------------------------------------------------------------------------------------------------------|
    // threshold_conv_first is 1.0e-6 by generic default and 1.5e-7 in O2 A. Lower values keep more            |
    // scattering-order work. Higher values stop earlier and drop weak multiple-scattering feedback.           |

    // instrumentation: perturbation: initial stop ------------------------------------------------------------|
    // captures: initial-order convergence decision                                                            |
    // why: test sensitivity of the single-scattering early return.                                            |
    var initial_stop = transport_controls.scattering != .multiple;
    if (!initial_stop) {
        initial_stop = Perturbation.decision(
            .orders_initial_convergence,
            .{ .order_index = 1 },
            max_value < transport_controls.performance_thresholds.threshold_conv_first,
        );
    }
    // end instrumentation: perturbation: initial stop --------------------------------------------------------|

    // end tradeoff: first-order convergence stop -------------------------------------------------------------|

    if (initial_stop) {

        // instrumentation: trace counter: initial return -----------------------------------------------------|
        // captures: initial-order early returns                                                               |
        // why: quantify single-scattering exits from the order loop.                                          |
        Trace.plotU("orders_initial_returns", 1);
        // end instrumentation: trace counter: initial return -------------------------------------------------|

        // instrumentation: calculation telemetry: initial convergence ----------------------------------------|
        // captures: initial convergence margin                                                                |
        // why: study whether single-scattering exits are safely below tolerance.                              |
        Telemetry.ordersConvergence(
            1,
            num_orders_max,
            max_value,
            transport_controls.performance_thresholds.threshold_conv_first,
            true,
            false,
        );
        // end instrumentation: calculation telemetry: initial convergence ------------------------------------|

        return .{ .ud = ud, .ud_sum_local = ud_sum_local };
    }

    var order_index: usize = 1;
    while (true) {

        // instrumentation: trace zone: multiple order --------------------------------------------------------|
        // captures: one multiple-scattering order iteration wall time                                         |
        // why: compare cost per retained scattering order.                                                    |
        const multiple_loop_zone = Trace.deepStaticZone(@src(), "labos.orders.multiple_loop");
        order_index += 1;

        // instrumentation: trace counter: multiple iterations ------------------------------------------------|
        // captures: number of multiple-scattering iterations                                                  |
        // why: tie convergence thresholds to actual order count.                                              |
        Trace.plotU("orders_multiple_iterations", 1);
        // end instrumentation: trace counter: multiple iterations --------------------------------------------|

        {

            // instrumentation: trace zone: local down --------------------------------------------------------|
            // captures: local downward source update wall time                                                |
            // why: isolate downward matrix-vector work inside each order.                                     |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.local_down");
            defer zone.end();
            const trace_start = CostTiming.start(work.activeCostTiming());
            defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_local_down");
            fillDownwardLocalSources(start_level, end_level, geometry, rt, rt_active, ud_orde, ud_local);
            // end instrumentation: trace zone: local down ----------------------------------------------------|

        }

        {

            // instrumentation: trace zone: local up ----------------------------------------------------------|
            // captures: local upward source update wall time                                                  |
            // why: isolate upward matrix-vector work inside each order.                                       |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.local_up");
            defer zone.end();
            const trace_start = CostTiming.start(work.activeCostTiming());
            defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_local_up");
            fillUpwardLocalSources(start_level, end_level, geometry, rt, rt_active, ud_orde, ud_local);
            // end instrumentation: trace zone: local up ------------------------------------------------------|

        }

        {

            // instrumentation: trace zone: order transport ---------------------------------------------------|
            // captures: inter-level transport wall time for this order                                        |
            // why: separate propagation from local source computation.                                        |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.rtm");
            defer zone.end();
            const trace_start = CostTiming.start(work.activeCostTiming());
            defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_transport");
            transportToOtherLevels(start_level, end_level, stream_count, attenuation, ud_local, ud_orde);
            // end instrumentation: trace zone: order transport -----------------------------------------------|

        }

        max_value = maxOutgoingUpward(ud_orde, end_level, gaussian_count, stream_count);

        // ----------------------------------------------------------------------------------------------------|
        // ----------------------------------------------------------------------------------------------------|
        // tradeoff: multiple-order convergence stop                                                           |
        // Stop adding scattering orders when the order field is below threshold_conv_mult or the cap is hit.  |
        // ----------------------------------------------------------------------------------------------------|
        // threshold_conv_mult is 1.0e-4 by generic default and 1.5e-9 in O2 A. num_orders_max is the hard     |
        // cap; when it is zero, the resolved cap is roughly max(scattering optical depth, 0) + 15.            |

        // instrumentation: perturbation: multiple stop -------------------------------------------------------|
        // captures: multiple-order stop margin and forced stop experiments                                    |
        // why: identify scattering orders that are safe to skip by tolerance.                                 |
        const hit_iteration_cap = order_index >= num_orders_max;
        var multiple_stop = hit_iteration_cap;
        if (!multiple_stop) {
            multiple_stop = Perturbation.decision(
                .orders_multiple_convergence,
                .{ .order_index = @intCast(order_index) },
                max_value < transport_controls.performance_thresholds.threshold_conv_mult,
            );
        }
        // end instrumentation: perturbation: multiple stop ---------------------------------------------------|

        // end tradeoff: multiple-order convergence stop ------------------------------------------------------|

        if (multiple_stop) {

            // instrumentation: calculation telemetry: multiple convergence -----------------------------------|
            // captures: multiple-order convergence margin and iteration cap status                            |
            // why: study whether later scattering orders can be safely pruned.                                |
            Telemetry.ordersConvergence(
                order_index,
                num_orders_max,
                max_value,
                transport_controls.performance_thresholds.threshold_conv_mult,
                false,
                hit_iteration_cap,
            );
            // end instrumentation: calculation telemetry: multiple convergence -------------------------------|

            multiple_loop_zone.end();
            break;
        }

        {

            // instrumentation: trace zone: accepted order accumulation ---------------------------------------|
            // captures: accepted order accumulation wall time                                                 |
            // why: separate retained-order summation from convergence testing.                                |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.accumulate");
            defer zone.end();
            const trace_start = CostTiming.start(work.activeCostTiming());
            defer CostTiming.finish(work.activeCostTiming(), trace_start, "orders_accumulate");
            accumulateOrderContribution(
                track_sum_local,
                ud,
                ud_sum_local,
                ud_orde,
                ud_local,
                start_level,
                end_level,
                stream_count,
            );
            // end instrumentation: trace zone: accepted order accumulation -----------------------------------|

        }
        multiple_loop_zone.end();
        // end instrumentation: trace zone: multiple order ----------------------------------------------------|

    }

    return .{ .ud = ud, .ud_sum_local = ud_sum_local };
}

fn fillInitialDirectAndLocalSources(
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_local: []rows.UDLocal,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    rt_active: []const bool,
    comptime track_sum_local: bool,
) void {
    // fillInitialDirectAndLocalSources ---------------------------------------------------------------------- |
    // Fill E and first-order source terms from direct solar/view attenuation and RT rows.                     |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level + 1) |level| {
        for (0..stream_count) |stream_index| {
            ud[level].E.data[stream_index] = attenuation.get(stream_index, end_level, level);
        }
    }

    for (start_level..end_level) |level| {
        for (0..2) |extra_index| {
            if (!rt_active[level + 1]) continue;

            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level + 1);
            const local_d = &ud_local[level].D.col[extra_index].data;
            const rt_t = &rt[level + 1].T;
            var rt_index = col;

            for (0..stream_count) |stream_index| {
                local_d[stream_index] = rt_t.data[rt_index] * att;
                rt_index += rt_t.n;
            }
        }
    }

    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            if (!rt_active[level]) continue;

            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level);
            const local_u = &ud_local[level].U.col[extra_index].data;
            const rt_r = &rt[level].R;
            var rt_index = col;

            for (0..stream_count) |stream_index| {
                local_u[stream_index] = rt_r.data[rt_index] * att;
                rt_index += rt_r.n;
            }
        }
    }

    if (track_sum_local) {
        for (start_level..end_level + 1) |level| {
            ud_sum_local[level].U = ud_local[level].U;
            ud_sum_local[level].D = ud_local[level].D;
        }
    }
}

fn fillInitialTangentDirectAndLocalSources(
    ud_tangent: []rows.UDField,
    base_local: []rows.UDLocal,
    tangent_local: []rows.UDLocal,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation_base: anytype,
    attenuation_tangent: anytype,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    rt_active: []const bool,
) void {
    // fillInitialTangentDirectAndLocalSources --------------------------------------------------------------- |
    // Build base and derivative first-order local sources using the non-integrated product rule.              |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level + 1) |level| {
        for (0..stream_count) |stream_index| {
            ud_tangent[level].E.data[stream_index] = 0.0;
        }
    }

    for (start_level..end_level) |level| {
        for (0..2) |extra_index| {
            const local_d = &base_local[level].D.col[extra_index].data;
            const tangent_d = &tangent_local[level].D.col[extra_index].data;
            if (!rt_active[level + 1]) {
                zeroPair(local_d, tangent_d, stream_count);
                continue;
            }

            const col = gaussian_count + extra_index;
            const attenuation_value = attenuation_base.get(col, end_level, level + 1);
            const attenuation_derivative = attenuation_tangent.get(col, end_level, level + 1);
            const rt_t = &rt[level + 1].T;
            const rt_t_derivative = &rt_tangent[level + 1].T;
            var rt_index = col;

            for (0..stream_count) |stream_index| {
                const value = attenuateTangentValue(
                    rt_t.data[rt_index],
                    rt_t_derivative.data[rt_index],
                    attenuation_value,
                    attenuation_derivative,
                );
                local_d[stream_index] = value.base;
                tangent_d[stream_index] = value.tangent;
                rt_index += rt_t.n;
            }
        }
    }
    base_local[end_level].D = rows.Vec2.zero(stream_count);
    tangent_local[end_level].D = rows.Vec2.zero(stream_count);

    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            const local_u = &base_local[level].U.col[extra_index].data;
            const tangent_u = &tangent_local[level].U.col[extra_index].data;
            if (!rt_active[level]) {
                zeroPair(local_u, tangent_u, stream_count);
                continue;
            }

            const col = gaussian_count + extra_index;
            const attenuation_value = attenuation_base.get(col, end_level, level);
            const attenuation_derivative = attenuation_tangent.get(col, end_level, level);
            const rt_r = &rt[level].R;
            const rt_r_derivative = &rt_tangent[level].R;
            var rt_index = col;

            for (0..stream_count) |stream_index| {
                const value = attenuateTangentValue(
                    rt_r.data[rt_index],
                    rt_r_derivative.data[rt_index],
                    attenuation_value,
                    attenuation_derivative,
                );
                local_u[stream_index] = value.base;
                tangent_u[stream_index] = value.tangent;
                rt_index += rt_r.n;
            }
        }
    }
}

fn fillDownwardLocalSources(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    rt: []const rows.LayerRT,
    rt_active: []const bool,
    ud_orde: []const rows.UDLocal,
    ud_local: []rows.UDLocal,
) void {
    // fillDownwardLocalSources ------------------------------------------------------------------------------ |
    // Build downward local sources for one later scattering order.                                            |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level) |level| {
        const local_d0 = &ud_local[level].D.col[0].data;
        const local_d1 = &ud_local[level].D.col[1].data;
        const active = rt_active[level + 1];

        if (!active) {
            Trace.plotU("orders_inactive_down_layers", 1);
            continue;
        }

        const prev_u0 = &ud_orde[level].U.col[0];
        const prev_u1 = &ud_orde[level].U.col[1];
        const prev_d0 = &ud_orde[level + 1].D.col[0];
        const prev_d1 = &ud_orde[level + 1].D.col[1];

        Trace.plotU("dot_gauss_pair_calls", @intCast(stream_count * 2));
        Trace.plotU("dot_gauss_pair_terms", @intCast(stream_count * 2 * gaussian_count));

        for (0..stream_count) |stream_index| {
            const local = addDotPairs(
                dotGaussPair(&rt[level + 1].R, stream_index, prev_u0, prev_u1, gaussian_count),
                dotGaussPair(&rt[level + 1].T, stream_index, prev_d0, prev_d1, gaussian_count),
            );

            local_d0[stream_index] = local.col0;
            local_d1[stream_index] = local.col1;
        }
    }
    ud_local[end_level].D = rows.Vec2.zero(stream_count);
}

fn fillDownwardLocalSourcesTangent(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    rt_active: []const bool,
    base_orde: []const rows.UDLocal,
    tangent_orde: []const rows.UDLocal,
    base_local: []rows.UDLocal,
    tangent_local: []rows.UDLocal,
) void {
    // fillDownwardLocalSourcesTangent ----------------------------------------------------------------------- |
    // Build derivative downward local sources for one later scattering order.                                 |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level) |level| {
        const local_d0 = &base_local[level].D.col[0].data;
        const local_d1 = &base_local[level].D.col[1].data;
        const tangent_d0 = &tangent_local[level].D.col[0].data;
        const tangent_d1 = &tangent_local[level].D.col[1].data;

        if (!rt_active[level + 1]) {
            zeroQuad(local_d0, local_d1, tangent_d0, tangent_d1, stream_count);
            continue;
        }

        const prev_u0 = &base_orde[level].U.col[0];
        const prev_u1 = &base_orde[level].U.col[1];
        const prev_d0 = &base_orde[level + 1].D.col[0];
        const prev_d1 = &base_orde[level + 1].D.col[1];
        const tangent_prev_u0 = &tangent_orde[level].U.col[0];
        const tangent_prev_u1 = &tangent_orde[level].U.col[1];
        const tangent_prev_d0 = &tangent_orde[level + 1].D.col[0];
        const tangent_prev_d1 = &tangent_orde[level + 1].D.col[1];

        for (0..stream_count) |stream_index| {
            const local = addDotPairs(
                dotGaussPair(&rt[level + 1].R, stream_index, prev_u0, prev_u1, gaussian_count),
                dotGaussPair(&rt[level + 1].T, stream_index, prev_d0, prev_d1, gaussian_count),
            );
            local_d0[stream_index] = local.col0;
            local_d1[stream_index] = local.col1;

            const tangent = addFourDotPairs(
                dotGaussPair(&rt_tangent[level + 1].R, stream_index, prev_u0, prev_u1, gaussian_count),
                dotGaussPair(&rt[level + 1].R, stream_index, tangent_prev_u0, tangent_prev_u1, gaussian_count),
                dotGaussPair(&rt_tangent[level + 1].T, stream_index, prev_d0, prev_d1, gaussian_count),
                dotGaussPair(&rt[level + 1].T, stream_index, tangent_prev_d0, tangent_prev_d1, gaussian_count),
            );

            tangent_d0[stream_index] = tangent.col0;
            tangent_d1[stream_index] = tangent.col1;
        }
    }
    base_local[end_level].D = rows.Vec2.zero(stream_count);
    tangent_local[end_level].D = rows.Vec2.zero(stream_count);
}

fn fillUpwardLocalSources(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    rt: []const rows.LayerRT,
    rt_active: []const bool,
    ud_orde: []const rows.UDLocal,
    ud_local: []rows.UDLocal,
) void {
    // fillUpwardLocalSources -------------------------------------------------------------------------------- |
    // Build upward local sources for one later scattering order.                                              |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;
    const local_u_start0 = &ud_local[start_level].U.col[0].data;
    const local_u_start1 = &ud_local[start_level].U.col[1].data;
    const prev_d_start0 = &ud_orde[start_level].D.col[0];
    const prev_d_start1 = &ud_orde[start_level].D.col[1];

    if (rt_active[start_level]) {
        Trace.plotU("dot_gauss_pair_calls", @intCast(stream_count));
        Trace.plotU("dot_gauss_pair_terms", @intCast(stream_count * gaussian_count));

        for (0..stream_count) |stream_index| {
            const r_dot_d = dotGaussPair(
                &rt[start_level].R,
                stream_index,
                prev_d_start0,
                prev_d_start1,
                gaussian_count,
            );
            local_u_start0[stream_index] = r_dot_d.col0;
            local_u_start1[stream_index] = r_dot_d.col1;
        }
    }

    for (start_level + 1..end_level + 1) |level| {
        const local_u0 = &ud_local[level].U.col[0].data;
        const local_u1 = &ud_local[level].U.col[1].data;
        const active = rt_active[level];

        if (!active) {
            Trace.plotU("orders_inactive_up_layers", 1);
            continue;
        }

        const prev_d0 = &ud_orde[level].D.col[0];
        const prev_d1 = &ud_orde[level].D.col[1];
        const prev_u0 = &ud_orde[level - 1].U.col[0];
        const prev_u1 = &ud_orde[level - 1].U.col[1];

        Trace.plotU("dot_gauss_pair_calls", @intCast(stream_count * 2));
        Trace.plotU("dot_gauss_pair_terms", @intCast(stream_count * 2 * gaussian_count));

        for (0..stream_count) |stream_index| {
            const local = addDotPairs(
                dotGaussPair(&rt[level].R, stream_index, prev_d0, prev_d1, gaussian_count),
                dotGaussPair(&rt[level].T, stream_index, prev_u0, prev_u1, gaussian_count),
            );

            local_u0[stream_index] = local.col0;
            local_u1[stream_index] = local.col1;
        }
    }
}

fn fillUpwardLocalSourcesTangent(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    rt_active: []const bool,
    base_orde: []const rows.UDLocal,
    tangent_orde: []const rows.UDLocal,
    base_local: []rows.UDLocal,
    tangent_local: []rows.UDLocal,
) void {
    // fillUpwardLocalSourcesTangent ------------------------------------------------------------------------- |
    // Build derivative upward local sources for one later scattering order.                                   |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const gaussian_count = geometry.n_gauss;
    const local_u_start0 = &base_local[start_level].U.col[0].data;
    const local_u_start1 = &base_local[start_level].U.col[1].data;
    const tangent_u_start0 = &tangent_local[start_level].U.col[0].data;
    const tangent_u_start1 = &tangent_local[start_level].U.col[1].data;
    const prev_d_start0 = &base_orde[start_level].D.col[0];
    const prev_d_start1 = &base_orde[start_level].D.col[1];
    const tangent_prev_d_start0 = &tangent_orde[start_level].D.col[0];
    const tangent_prev_d_start1 = &tangent_orde[start_level].D.col[1];

    if (rt_active[start_level]) {
        for (0..stream_count) |stream_index| {
            const r_dot_d =
                dotGaussPair(&rt[start_level].R, stream_index, prev_d_start0, prev_d_start1, gaussian_count);
            local_u_start0[stream_index] = r_dot_d.col0;
            local_u_start1[stream_index] = r_dot_d.col1;

            const tangent = addDotPairs(
                dotGaussPair(
                    &rt_tangent[start_level].R,
                    stream_index,
                    prev_d_start0,
                    prev_d_start1,
                    gaussian_count,
                ),
                dotGaussPair(
                    &rt[start_level].R,
                    stream_index,
                    tangent_prev_d_start0,
                    tangent_prev_d_start1,
                    gaussian_count,
                ),
            );
            tangent_u_start0[stream_index] = tangent.col0;
            tangent_u_start1[stream_index] = tangent.col1;
        }
    } else {
        zeroQuad(local_u_start0, local_u_start1, tangent_u_start0, tangent_u_start1, stream_count);
    }

    for (start_level + 1..end_level + 1) |level| {
        const local_u0 = &base_local[level].U.col[0].data;
        const local_u1 = &base_local[level].U.col[1].data;
        const tangent_u0 = &tangent_local[level].U.col[0].data;
        const tangent_u1 = &tangent_local[level].U.col[1].data;

        if (!rt_active[level]) {
            zeroQuad(local_u0, local_u1, tangent_u0, tangent_u1, stream_count);
            continue;
        }

        const prev_d0 = &base_orde[level].D.col[0];
        const prev_d1 = &base_orde[level].D.col[1];
        const prev_u0 = &base_orde[level - 1].U.col[0];
        const prev_u1 = &base_orde[level - 1].U.col[1];
        const tangent_prev_d0 = &tangent_orde[level].D.col[0];
        const tangent_prev_d1 = &tangent_orde[level].D.col[1];
        const tangent_prev_u0 = &tangent_orde[level - 1].U.col[0];
        const tangent_prev_u1 = &tangent_orde[level - 1].U.col[1];

        for (0..stream_count) |stream_index| {
            const local = addDotPairs(
                dotGaussPair(&rt[level].R, stream_index, prev_d0, prev_d1, gaussian_count),
                dotGaussPair(&rt[level].T, stream_index, prev_u0, prev_u1, gaussian_count),
            );
            local_u0[stream_index] = local.col0;
            local_u1[stream_index] = local.col1;

            const tangent = addFourDotPairs(
                dotGaussPair(&rt_tangent[level].R, stream_index, prev_d0, prev_d1, gaussian_count),
                dotGaussPair(&rt[level].R, stream_index, tangent_prev_d0, tangent_prev_d1, gaussian_count),
                dotGaussPair(&rt_tangent[level].T, stream_index, prev_u0, prev_u1, gaussian_count),
                dotGaussPair(&rt[level].T, stream_index, tangent_prev_u0, tangent_prev_u1, gaussian_count),
            );

            tangent_u0[stream_index] = tangent.col0;
            tangent_u1[stream_index] = tangent.col1;
        }
    }
}

fn transportToOtherLevels(
    start_level: usize,
    end_level: usize,
    stream_count: usize,
    attenuation: anytype,
    ud_local: []const rows.UDLocal,
    ud_orde: []rows.UDLocal,
) void {
    // transportToOtherLevels -------------------------------------------------------------------------------- |
    // Transport current local sources through the level grid.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (stream_count == rows.max_stream_count) {
        if (comptime isDynamicAttenuationPointer(@TypeOf(attenuation))) {
            transportToOtherLevelsDynamic12(start_level, end_level, attenuation, ud_local, ud_orde);
            return;
        }
        if (comptime isRuntimeAttenuationPointer(@TypeOf(attenuation))) {
            transportToOtherLevelsRuntime12(start_level, end_level, attenuation, ud_local, ud_orde);
            return;
        }
        transportToOtherLevels12(start_level, end_level, attenuation, ud_local, ud_orde);
        return;
    }

    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        const local_u0 = ud_local[level].U.col[0].data;
        const local_u1 = ud_local[level].U.col[1].data;
        const prev_u0 = ud_orde[level - 1].U.col[0].data;
        const prev_u1 = ud_orde[level - 1].U.col[1].data;
        const out_u0 = &ud_orde[level].U.col[0].data;
        const out_u1 = &ud_orde[level].U.col[1].data;

        for (0..stream_count) |stream_index| {
            const att = attenuation.get(stream_index, level - 1, level);
            out_u0[stream_index] = local_u0[stream_index] + att * prev_u0[stream_index];
            out_u1[stream_index] = local_u1[stream_index] + att * prev_u1[stream_index];
        }
    }

    ud_orde[end_level].D = rows.Vec2.zero(stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;

        const local_d0 = ud_local[level].D.col[0].data;
        const local_d1 = ud_local[level].D.col[1].data;
        const prev_d0 = ud_orde[level + 1].D.col[0].data;
        const prev_d1 = ud_orde[level + 1].D.col[1].data;
        const out_d0 = &ud_orde[level].D.col[0].data;
        const out_d1 = &ud_orde[level].D.col[1].data;

        for (0..stream_count) |stream_index| {
            const att = attenuation.get(stream_index, level + 1, level);
            out_d0[stream_index] = local_d0[stream_index] + att * prev_d0[stream_index];
            out_d1[stream_index] = local_d1[stream_index] + att * prev_d1[stream_index];
        }
    }
}

fn isDynamicAttenuationPointer(comptime T: type) bool {
    // isDynamicAttenuationPointer --------------------------------------------------------------------------- |
    // Compile-time route check for the full [direction, from_level, to_level] attenuation table.              |
    // --------------------------------------------------------------------------------------------------------|
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child == attenuation_mod.DynamicAttenuation,
        else => false,
    };
}

fn isRuntimeAttenuationPointer(comptime T: type) bool {
    // isRuntimeAttenuationPointer --------------------------------------------------------------------------- |
    // Compile-time route check for the compact runtime attenuation table used by integrated-source LABOS.     |
    // --------------------------------------------------------------------------------------------------------|
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child == attenuation_mod.RuntimeAttenuation,
        else => false,
    };
}

fn dynamicAttenuationAt(
    attenuation: *const attenuation_mod.DynamicAttenuation,
    stream_stride: usize,
    stream_index: usize,
    level_offset: usize,
) f64 {
    // dynamicAttenuationAt ---------------------------------------------------------------------------------- |
    // Direct row-major lookup for DynamicAttenuation without redoing the index decomposition in `get`.        |
    // --------------------------------------------------------------------------------------------------------|
    return attenuation.data[stream_index * stream_stride + level_offset];
}

fn transportToOtherLevelsDynamic12(
    start_level: usize,
    end_level: usize,
    attenuation: *const attenuation_mod.DynamicAttenuation,
    ud_local: []const rows.UDLocal,
    ud_orde: []rows.UDLocal,
) void {
    // transportToOtherLevelsDynamic12 ----------------------------------------------------------------------- |
    // Fixed 12-direction transport for the full dynamic attenuation table.                                    |
    // hot path: avoids generic `get` calls inside scattering-order propagation.                               |
    // --------------------------------------------------------------------------------------------------------|
    const level_count = attenuation.level_count;
    const stream_stride = level_count * level_count;

    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        const level_offset = (level - 1) * level_count + level;
        const local_u0 = ud_local[level].U.col[0].data;
        const local_u1 = ud_local[level].U.col[1].data;
        const prev_u0 = ud_orde[level - 1].U.col[0].data;
        const prev_u1 = ud_orde[level - 1].U.col[1].data;
        const out_u0 = &ud_orde[level].U.col[0].data;
        const out_u1 = &ud_orde[level].U.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = dynamicAttenuationAt(attenuation, stream_stride, stream_index, level_offset);
            out_u0[stream_index] = local_u0[stream_index] + att * prev_u0[stream_index];
            out_u1[stream_index] = local_u1[stream_index] + att * prev_u1[stream_index];
        }
    }

    ud_orde[end_level].D = rows.Vec2.zero(rows.max_stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;

        const level_offset = (level + 1) * level_count + level;
        const local_d0 = ud_local[level].D.col[0].data;
        const local_d1 = ud_local[level].D.col[1].data;
        const prev_d0 = ud_orde[level + 1].D.col[0].data;
        const prev_d1 = ud_orde[level + 1].D.col[1].data;
        const out_d0 = &ud_orde[level].D.col[0].data;
        const out_d1 = &ud_orde[level].D.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = dynamicAttenuationAt(attenuation, stream_stride, stream_index, level_offset);
            out_d0[stream_index] = local_d0[stream_index] + att * prev_d0[stream_index];
            out_d1[stream_index] = local_d1[stream_index] + att * prev_d1[stream_index];
        }
    }
}

fn transportToOtherLevelsRuntime12(
    start_level: usize,
    end_level: usize,
    attenuation: *const attenuation_mod.RuntimeAttenuation,
    ud_local: []const rows.UDLocal,
    ud_orde: []rows.UDLocal,
) void {
    // transportToOtherLevelsRuntime12 ----------------------------------------------------------------------- |
    // Fixed 12-direction transport for compact runtime attenuation.                                           |
    // hot path: integrated-source transport only needs adjacent layer transmittance here.                     |
    // --------------------------------------------------------------------------------------------------------|
    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        const local_u0 = ud_local[level].U.col[0].data;
        const local_u1 = ud_local[level].U.col[1].data;
        const prev_u0 = ud_orde[level - 1].U.col[0].data;
        const prev_u1 = ud_orde[level - 1].U.col[1].data;
        const out_u0 = &ud_orde[level].U.col[0].data;
        const out_u1 = &ud_orde[level].U.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = attenuation.adjacent(stream_index, level - 1);
            out_u0[stream_index] = local_u0[stream_index] + att * prev_u0[stream_index];
            out_u1[stream_index] = local_u1[stream_index] + att * prev_u1[stream_index];
        }
    }

    ud_orde[end_level].D = rows.Vec2.zero(rows.max_stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;

        const local_d0 = ud_local[level].D.col[0].data;
        const local_d1 = ud_local[level].D.col[1].data;
        const prev_d0 = ud_orde[level + 1].D.col[0].data;
        const prev_d1 = ud_orde[level + 1].D.col[1].data;
        const out_d0 = &ud_orde[level].D.col[0].data;
        const out_d1 = &ud_orde[level].D.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = attenuation.adjacent(stream_index, level);
            out_d0[stream_index] = local_d0[stream_index] + att * prev_d0[stream_index];
            out_d1[stream_index] = local_d1[stream_index] + att * prev_d1[stream_index];
        }
    }
}

fn transportToOtherLevels12(
    start_level: usize,
    end_level: usize,
    attenuation: anytype,
    ud_local: []const rows.UDLocal,
    ud_orde: []rows.UDLocal,
) void {
    // transportToOtherLevels12 ------------------------------------------------------------------------------ |
    // Fixed 12-direction transport for the O2 A LABOS stream shape.                                           |
    // --------------------------------------------------------------------------------------------------------|
    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        const local_u0 = ud_local[level].U.col[0].data;
        const local_u1 = ud_local[level].U.col[1].data;
        const prev_u0 = ud_orde[level - 1].U.col[0].data;
        const prev_u1 = ud_orde[level - 1].U.col[1].data;
        const out_u0 = &ud_orde[level].U.col[0].data;
        const out_u1 = &ud_orde[level].U.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = attenuation.get(stream_index, level - 1, level);
            out_u0[stream_index] = local_u0[stream_index] + att * prev_u0[stream_index];
            out_u1[stream_index] = local_u1[stream_index] + att * prev_u1[stream_index];
        }
    }

    ud_orde[end_level].D = rows.Vec2.zero(rows.max_stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;

        const local_d0 = ud_local[level].D.col[0].data;
        const local_d1 = ud_local[level].D.col[1].data;
        const prev_d0 = ud_orde[level + 1].D.col[0].data;
        const prev_d1 = ud_orde[level + 1].D.col[1].data;
        const out_d0 = &ud_orde[level].D.col[0].data;
        const out_d1 = &ud_orde[level].D.col[1].data;

        inline for (0..rows.max_stream_count) |stream_index| {
            const att = attenuation.get(stream_index, level + 1, level);
            out_d0[stream_index] = local_d0[stream_index] + att * prev_d0[stream_index];
            out_d1[stream_index] = local_d1[stream_index] + att * prev_d1[stream_index];
        }
    }
}

fn transportToOtherLevelsTangent(
    start_level: usize,
    end_level: usize,
    stream_count: usize,
    attenuation_base: anytype,
    attenuation_tangent: anytype,
    ud_local_tangent: []const rows.UDLocal,
    ud_orde_base: []const rows.UDLocal,
    ud_orde_tangent: []rows.UDLocal,
) void {
    // transportToOtherLevelsTangent ------------------------------------------------------------------------- |
    // Transport derivative U/D fields through the same level grid as the base current order.                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   d(T * U) = dT * U + T * dU                                                                            |
    // --------------------------------------------------------------------------------------------------------|
    ud_orde_tangent[start_level].U = ud_local_tangent[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        const local_du0 = ud_local_tangent[level].U.col[0].data;
        const local_du1 = ud_local_tangent[level].U.col[1].data;
        const prev_u0 = ud_orde_base[level - 1].U.col[0].data;
        const prev_u1 = ud_orde_base[level - 1].U.col[1].data;
        const prev_du0 = ud_orde_tangent[level - 1].U.col[0].data;
        const prev_du1 = ud_orde_tangent[level - 1].U.col[1].data;
        const out_u0 = &ud_orde_tangent[level].U.col[0].data;
        const out_u1 = &ud_orde_tangent[level].U.col[1].data;

        for (0..stream_count) |stream_index| {
            const attenuation_value = attenuation_base.get(stream_index, level - 1, level);
            const attenuation_derivative = attenuation_tangent.get(stream_index, level - 1, level);
            out_u0[stream_index] = propagatedTangentValue(
                local_du0[stream_index],
                prev_u0[stream_index],
                prev_du0[stream_index],
                attenuation_value,
                attenuation_derivative,
            );
            out_u1[stream_index] = propagatedTangentValue(
                local_du1[stream_index],
                prev_u1[stream_index],
                prev_du1[stream_index],
                attenuation_value,
                attenuation_derivative,
            );
        }
    }

    ud_orde_tangent[end_level].D = rows.Vec2.zero(stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;

        const local_dd0 = ud_local_tangent[level].D.col[0].data;
        const local_dd1 = ud_local_tangent[level].D.col[1].data;
        const prev_d0 = ud_orde_base[level + 1].D.col[0].data;
        const prev_d1 = ud_orde_base[level + 1].D.col[1].data;
        const prev_dd0 = ud_orde_tangent[level + 1].D.col[0].data;
        const prev_dd1 = ud_orde_tangent[level + 1].D.col[1].data;
        const out_d0 = &ud_orde_tangent[level].D.col[0].data;
        const out_d1 = &ud_orde_tangent[level].D.col[1].data;

        for (0..stream_count) |stream_index| {
            const attenuation_value = attenuation_base.get(stream_index, level + 1, level);
            const attenuation_derivative = attenuation_tangent.get(stream_index, level + 1, level);
            out_d0[stream_index] = propagatedTangentValue(
                local_dd0[stream_index],
                prev_d0[stream_index],
                prev_dd0[stream_index],
                attenuation_value,
                attenuation_derivative,
            );
            out_d1[stream_index] = propagatedTangentValue(
                local_dd1[stream_index],
                prev_d1[stream_index],
                prev_dd1[stream_index],
                attenuation_value,
                attenuation_derivative,
            );
        }
    }
}

fn initializeOrderBuffers(
    comptime track_sum_local: bool,
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_orde: []rows.UDLocal,
    ud_local: []rows.UDLocal,
    stream_count: usize,
) void {
    // initializeOrderBuffers -------------------------------------------------------------------------------- |
    // Reset all per-level fields before one order solve.                                                      |
    // --------------------------------------------------------------------------------------------------------|
    for (0..ud.len) |index| {
        ud[index] = undefined;
        if (track_sum_local) {
            ud_sum_local[index].U = rows.Vec2.zero(stream_count);
            ud_sum_local[index].D = rows.Vec2.zero(stream_count);
        }
        ud_orde[index] = undefined;
        ud_local[index].U = rows.Vec2.zero(stream_count);
        ud_local[index].D = rows.Vec2.zero(stream_count);
    }
}

fn initializeTangentOrderBuffers(
    ud_tangent: []rows.UDField,
    base_orde: []rows.UDLocal,
    base_local: []rows.UDLocal,
    tangent_orde: []rows.UDLocal,
    tangent_local: []rows.UDLocal,
    stream_count: usize,
) void {
    // initializeTangentOrderBuffers ------------------------------------------------------------------------- |
    // Reset base and derivative rows needed by one non-integrated tangent order solve.                        |
    // --------------------------------------------------------------------------------------------------------|
    for (0..ud_tangent.len) |index| {
        ud_tangent[index] = .{
            .E = rows.Vec.zero(stream_count),
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        base_orde[index] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        base_local[index] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        tangent_orde[index] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        tangent_local[index] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
    }
}

fn accumulateOrderContribution(
    comptime track_sum_local: bool,
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_orde: []const rows.UDLocal,
    ud_local: []const rows.UDLocal,
    start_level: usize,
    end_level: usize,
    stream_count: usize,
) void {
    // accumulateOrderContribution --------------------------------------------------------------------------- |
    // Add a retained transported order into UD_fc and optional local-source sums.                             |
    // --------------------------------------------------------------------------------------------------------|
    if (stream_count == rows.max_stream_count) {
        accumulateOrderContribution12(
            track_sum_local,
            ud,
            ud_sum_local,
            ud_orde,
            ud_local,
            start_level,
            end_level,
        );
        return;
    }

    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            const order_u = ud_orde[level].U.col[extra_index].data;
            const order_d = ud_orde[level].D.col[extra_index].data;
            const out_u = &ud[level].U.col[extra_index].data;
            const out_d = &ud[level].D.col[extra_index].data;

            if (track_sum_local) {
                const local_u = ud_local[level].U.col[extra_index].data;
                const local_d = ud_local[level].D.col[extra_index].data;
                const sum_u = &ud_sum_local[level].U.col[extra_index].data;
                const sum_d = &ud_sum_local[level].D.col[extra_index].data;

                for (0..stream_count) |stream_index| {
                    out_u[stream_index] += order_u[stream_index];
                    out_d[stream_index] += order_d[stream_index];
                    sum_u[stream_index] += local_u[stream_index];
                    sum_d[stream_index] += local_d[stream_index];
                }
            } else {
                for (0..stream_count) |stream_index| {
                    out_u[stream_index] += order_u[stream_index];
                    out_d[stream_index] += order_d[stream_index];
                }
            }
        }
    }
}

fn accumulateOrderContribution12(
    comptime track_sum_local: bool,
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_orde: []const rows.UDLocal,
    ud_local: []const rows.UDLocal,
    start_level: usize,
    end_level: usize,
) void {
    // accumulateOrderContribution12 ------------------------------------------------------------------------- |
    // Fixed 12-direction retained-order accumulation.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            const order_u = ud_orde[level].U.col[extra_index].data;
            const order_d = ud_orde[level].D.col[extra_index].data;
            const out_u = &ud[level].U.col[extra_index].data;
            const out_d = &ud[level].D.col[extra_index].data;

            if (track_sum_local) {
                const local_u = ud_local[level].U.col[extra_index].data;
                const local_d = ud_local[level].D.col[extra_index].data;
                const sum_u = &ud_sum_local[level].U.col[extra_index].data;
                const sum_d = &ud_sum_local[level].D.col[extra_index].data;

                inline for (0..rows.max_stream_count) |stream_index| {
                    out_u[stream_index] += order_u[stream_index];
                    out_d[stream_index] += order_d[stream_index];
                    sum_u[stream_index] += local_u[stream_index];
                    sum_d[stream_index] += local_d[stream_index];
                }
            } else {
                inline for (0..rows.max_stream_count) |stream_index| {
                    out_u[stream_index] += order_u[stream_index];
                    out_d[stream_index] += order_d[stream_index];
                }
            }
        }
    }
}

fn copyTransportedOrderIntoOutput(
    ud: []rows.UDField,
    ud_orde: []const rows.UDLocal,
    start_level: usize,
    end_level: usize,
) void {
    // copyTransportedOrderIntoOutput ------------------------------------------------------------------------ |
    // Copy the first transported order into accumulated UD_fc storage.                                        |
    // --------------------------------------------------------------------------------------------------------|
    for (start_level..end_level + 1) |level| {
        ud[level].U = ud_orde[level].U;
        ud[level].D = ud_orde[level].D;
    }
}

fn maxOutgoingUpward(
    ud_orde: []const rows.UDLocal,
    end_level: usize,
    gaussian_count: usize,
    stream_count: usize,
) f64 {
    // maxOutgoingUpward ------------------------------------------------------------------------------------- |
    // Return the largest outgoing upward source at the top boundary.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var max_value: f64 = 0.0;
    for (0..2) |extra_index| {
        const top_u = ud_orde[end_level].U.col[extra_index].data;
        for (gaussian_count..stream_count) |stream_index| {
            max_value = @max(max_value, @abs(top_u[stream_index]));
        }
    }
    return max_value;
}

fn refreshActiveLayerMask(
    rt: []const rows.LayerRT,
    rt_active: []bool,
    stream_count: usize,
) void {
    // refreshActiveLayerMask -------------------------------------------------------------------------------- |
    // Rebuild the active-layer mask from layer RT matrix signal.                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (rt, rt_active) |*layer_rt, *active| {
        active.* = rtLayerHasSignal(layer_rt, stream_count);
    }
}

fn rtLayerHasSignal(rt: *const rows.LayerRT, stream_count: usize) bool {
    // rtLayerHasSignal -------------------------------------------------------------------------------------- |
    // Detect whether a layer RT row can contribute to scattering-order updates.                               |
    // --------------------------------------------------------------------------------------------------------|
    const count = stream_count * stream_count;
    for (rt.R.data[0..count]) |value| {
        if (value != 0.0) return true;
    }

    for (rt.T.data[0..count]) |value| {
        if (value != 0.0) return true;
    }

    return false;
}

fn zeroPair(a: *[rows.max_stream_count]f64, b: *[rows.max_stream_count]f64, stream_count: usize) void {
    // zeroPair ---------------------------------------------------------------------------------------------- |
    // Clear two active stream rows without touching inactive fixed-capacity storage.                          |
    // --------------------------------------------------------------------------------------------------------|
    for (0..stream_count) |stream_index| {
        a[stream_index] = 0.0;
        b[stream_index] = 0.0;
    }
}

fn zeroQuad(
    a: *[rows.max_stream_count]f64,
    b: *[rows.max_stream_count]f64,
    c: *[rows.max_stream_count]f64,
    d: *[rows.max_stream_count]f64,
    stream_count: usize,
) void {
    // zeroQuad ---------------------------------------------------------------------------------------------- |
    // Clear four active stream rows used by base/tangent local source pairs.                                  |
    // --------------------------------------------------------------------------------------------------------|
    for (0..stream_count) |stream_index| {
        a[stream_index] = 0.0;
        b[stream_index] = 0.0;
        c[stream_index] = 0.0;
        d[stream_index] = 0.0;
    }
}

// AttenuatedValue --------------------------------------------------------------------------------------------|
// Carries one base value and its derivative through the local product-rule helpers.                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] base    : f64                                                                                      |
// [ 8..15] tangent : f64                                                                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); stack value in tangent source and transport loops               |
const AttenuatedValue = struct {
    base: f64,
    tangent: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// DotPair ----------------------------------------------------------------------------------------------------|
// Two Gaussian dot products returned from one pass over the same matrix row.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] col0 : f64                                                                                         |
// [ 8..15] col1 : f64                                                                                         |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B (0.016 KiB); stack row for paired dot reductions                             |
const DotPair = struct {
    col0: f64,
    col1: f64,
};
// ------------------------------------------------------------------------------------------------------------|

inline fn attenuateTangentValue(
    base_value: f64,
    tangent_value: f64,
    attenuation_value: f64,
    attenuation_derivative: f64,
) AttenuatedValue {
    // attenuateTangentValue --------------------------------------------------------------------------------- |
    // Apply the first-order product rule to one RT-matrix value multiplied by direct attenuation.             |
    //                                                                                                         |
    // math                                                                                                    |
    //   base    = RT * E                                                                                      |
    //   tangent = dRT * E + RT * dE                                                                           |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .base = base_value * attenuation_value,
        .tangent = tangent_value * attenuation_value + base_value * attenuation_derivative,
    };
}

inline fn propagatedTangentValue(
    local_tangent: f64,
    previous_base: f64,
    previous_tangent: f64,
    attenuation_value: f64,
    attenuation_derivative: f64,
) f64 {
    // propagatedTangentValue -------------------------------------------------------------------------------- |
    // Propagate a derivative field through one attenuation hop.                                               |
    //                                                                                                         |
    // math                                                                                                    |
    //   tangent_out = local_tangent + dE * previous_base + E * previous_tangent                               |
    // --------------------------------------------------------------------------------------------------------|
    return local_tangent + attenuation_derivative * previous_base + attenuation_value * previous_tangent;
}

inline fn addDotPairs(a: DotPair, b: DotPair) DotPair {
    // addDotPairs ------------------------------------------------------------------------------------------- |
    // Add two paired Gaussian dot products without changing the source loop order.                            |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .col0 = a.col0 + b.col0,
        .col1 = a.col1 + b.col1,
    };
}

inline fn addFourDotPairs(a: DotPair, b: DotPair, c: DotPair, d: DotPair) DotPair {
    // addFourDotPairs --------------------------------------------------------------------------------------- |
    // Add the four first-order tangent dot terms: dR*x, R*dx, dT*y, and T*dy.                                 |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .col0 = a.col0 + b.col0 + c.col0 + d.col0,
        .col1 = a.col1 + b.col1 + c.col1 + d.col1,
    };
}

fn dotGaussPair(
    matrix: *const rows.Mat,
    row: usize,
    vector0: *const rows.Vec,
    vector1: *const rows.Vec,
    gaussian_count: usize,
) DotPair {
    // dotGaussPair ------------------------------------------------------------------------------------------ |
    // Dot one RT matrix row with both source columns.                                                         |
    // --------------------------------------------------------------------------------------------------------|
    const row_offset = row * matrix.n;
    if (gaussian_count == rows.max_gauss) {
        const data = matrix.data[row_offset..];
        const vec0 = vector0.data;
        const vec1 = vector1.data;
        return dotGaussPair10(data, &vec0, &vec1);
    }

    var sum0: f64 = 0.0;
    var sum1: f64 = 0.0;
    for (0..gaussian_count) |col| {
        const value = matrix.data[row_offset + col];
        sum0 += value * vector0.data[col];
        sum1 += value * vector1.data[col];
    }
    return .{ .col0 = sum0, .col1 = sum1 };
}

fn dotGaussPair10(
    data: []const f64,
    vector0: *const [rows.max_stream_count]f64,
    vector1: *const [rows.max_stream_count]f64,
) DotPair {
    // dotGaussPair10 ---------------------------------------------------------------------------------------- |
    // Fixed 10-Gauss paired dot product used by the common 12-direction LABOS route.                          |
    // --------------------------------------------------------------------------------------------------------|
    const Vec2 = @Vector(2, f64);
    var sum0: Vec2 = @as(Vec2, .{ data[0], data[1] }) * @as(Vec2, .{ vector0[0], vector0[1] });
    var sum1: Vec2 = @as(Vec2, .{ data[0], data[1] }) * @as(Vec2, .{ vector1[0], vector1[1] });
    const data2: Vec2 = @as(Vec2, .{ data[2], data[3] });
    sum0 += data2 * @as(Vec2, .{ vector0[2], vector0[3] });
    sum1 += data2 * @as(Vec2, .{ vector1[2], vector1[3] });
    const data4: Vec2 = @as(Vec2, .{ data[4], data[5] });
    sum0 += data4 * @as(Vec2, .{ vector0[4], vector0[5] });
    sum1 += data4 * @as(Vec2, .{ vector1[4], vector1[5] });
    const data6: Vec2 = @as(Vec2, .{ data[6], data[7] });
    sum0 += data6 * @as(Vec2, .{ vector0[6], vector0[7] });
    sum1 += data6 * @as(Vec2, .{ vector1[6], vector1[7] });
    const data8: Vec2 = @as(Vec2, .{ data[8], data[9] });
    sum0 += data8 * @as(Vec2, .{ vector0[8], vector0[9] });
    sum1 += data8 * @as(Vec2, .{ vector1[8], vector1[9] });
    return .{
        .col0 = @reduce(.Add, sum0),
        .col1 = @reduce(.Add, sum1),
    };
}
