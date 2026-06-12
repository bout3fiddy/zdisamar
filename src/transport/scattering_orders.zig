const std = @import("std");

const controls = @import("controls.zig");
const gauss_angles = @import("gauss_angles.zig");
const phase_timing = @import("phase_timing.zig");
const rows = @import("rows.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");
const Trace = @import("../instrumentation/trace.zig");

// scattering_orders.zig ------------------------------------------------------------------------------------- |
// LABOS scattering-order transport over prepared layer reflection/transmission rows.                          |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/orders.zig` `ordersScatInternal`,                  |
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
// normal build: size 80 B (0.078 KiB), align 8                                                                |
// trace build : size 88 B (0.086 KiB), align 8                                                                |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] ud           : []UDField                                                                           |
// [16..31] ud_sum_local : []UDLocal                                                                           |
// [32..47] ud_orde      : []UDLocal                                                                           |
// [48..63] ud_local     : []UDLocal                                                                           |
// [64..79] rt_active    : []bool                                                                              |
// [80..87] trace build only: trace_phase : WorkspaceState                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: all slices are borrowed from the transport worker memory owner                          |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 88 B (0.086 KiB); referenced rows are caller-owned                                |
pub const OrdersWorkArrays = struct {
    ud: []rows.UDField,
    ud_sum_local: []rows.UDLocal,
    ud_orde: []rows.UDLocal,
    ud_local: []rows.UDLocal,
    rt_active: []bool,
    trace_phase: phase_timing.WorkspaceState = .{},

    pub fn setTracePhaseTiming(self: *OrdersWorkArrays, active: ?phase_timing.Active) void {
        // OrdersWorkArrays.setTracePhaseTiming -------------------------------------------------------------- |
        // Attach the worker-local LABOS phase sink used by trace builds.                                      |
        // ----------------------------------------------------------------------------------------------------|
        phase_timing.setActiveWorkspaceState(&self.trace_phase, active);
    }

    pub fn activeTracePhaseTiming(self: *OrdersWorkArrays) ?phase_timing.Active {
        // OrdersWorkArrays.activeTracePhaseTiming ----------------------------------------------------------- |
        // Return the active timing sink for order child phases.                                               |
        // ----------------------------------------------------------------------------------------------------|
        return phase_timing.activeWorkspaceState(&self.trace_phase);
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn solveOrders(
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrders ------------------------------------------------------------------------------------------- |
    // Build transported LABOS scattering-order fields using a caller-owned workspace.                         |
    //                                                                                                         |
    // used by                                                                                                 |
    //   Later `solveReflectance` orchestration calls this after layer RT rows and attenuation are ready.      |
    // --------------------------------------------------------------------------------------------------------|
    const result = solveOrdersInternal(
        false,
        false,
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

pub fn solveOrdersWithLocalSum(
    work: *OrdersWorkArrays,
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: anytype,
    rt: []const rows.LayerRT,
    transport_controls: controls.TransportControls,
    num_orders_max: usize,
) OrdersView {
    // solveOrdersWithLocalSum ------------------------------------------------------------------------------- |
    // Build transported order fields and local-source sums for integrated-source Jacobian weighting.          |
    // --------------------------------------------------------------------------------------------------------|
    return solveOrdersInternal(
        true,
        false,
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
    //   trace counters mirror old `orders.zig` names; perturbation hooks gate the same first and multiple     |
    //   convergence decisions as the old route.                                                               |
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
        const trace_start = phase_timing.start(work.activeTracePhaseTiming());
        defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_initial_sources");

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
        const trace_start = phase_timing.start(work.activeTracePhaseTiming());
        defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_initial_transport");
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
            const trace_start = phase_timing.start(work.activeTracePhaseTiming());
            defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_local_down");
            fillDownwardLocalSources(start_level, end_level, geometry, rt, rt_active, ud_orde, ud_local);
            // end instrumentation: trace zone: local down ----------------------------------------------------|

        }

        {

            // instrumentation: trace zone: local up ----------------------------------------------------------|
            // captures: local upward source update wall time                                                  |
            // why: isolate upward matrix-vector work inside each order.                                       |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.local_up");
            defer zone.end();
            const trace_start = phase_timing.start(work.activeTracePhaseTiming());
            defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_local_up");
            fillUpwardLocalSources(start_level, end_level, geometry, rt, rt_active, ud_orde, ud_local);
            // end instrumentation: trace zone: local up ------------------------------------------------------|

        }

        {

            // instrumentation: trace zone: order transport ---------------------------------------------------|
            // captures: inter-level transport wall time for this order                                        |
            // why: separate propagation from local source computation.                                        |
            const zone = Trace.deepStaticZone(@src(), "labos.orders.transport");
            defer zone.end();
            const trace_start = phase_timing.start(work.activeTracePhaseTiming());
            defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_transport");
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
            const trace_start = phase_timing.start(work.activeTracePhaseTiming());
            defer phase_timing.finish(work.activeTracePhaseTiming(), trace_start, "orders_accumulate");
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

        if (!rt_active[level + 1]) {
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
            const rst_dot_u = dotGaussPair(&rt[level + 1].R, stream_index, prev_u0, prev_u1, gaussian_count);
            const t_dot_d = dotGaussPair(&rt[level + 1].T, stream_index, prev_d0, prev_d1, gaussian_count);

            local_d0[stream_index] = rst_dot_u.col0 + t_dot_d.col0;
            local_d1[stream_index] = rst_dot_u.col1 + t_dot_d.col1;
        }
    }
    ud_local[end_level].D = rows.Vec2.zero(stream_count);
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

        if (!rt_active[level]) {
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
            const r_dot_d = dotGaussPair(&rt[level].R, stream_index, prev_d0, prev_d1, gaussian_count);
            const tst_dot_u = dotGaussPair(&rt[level].T, stream_index, prev_u0, prev_u1, gaussian_count);

            local_u0[stream_index] = r_dot_d.col0 + tst_dot_u.col0;
            local_u1[stream_index] = r_dot_d.col1 + tst_dot_u.col1;
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

pub fn dotGauss(
    matrix: *const rows.Mat,
    row: usize,
    vector: *const rows.Vec,
    gaussian_count: usize,
) f64 {
    // dotGauss ---------------------------------------------------------------------------------------------- |
    // Dot one RT matrix row with one Gaussian-stream vector.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    const row_offset = row * matrix.n;
    if (gaussian_count == rows.max_gauss) {
        const data = matrix.data[row_offset..];
        const vec_data = vector.data;
        var sum = data[0] * vec_data[0];
        sum += data[1] * vec_data[1];
        sum += data[2] * vec_data[2];
        sum += data[3] * vec_data[3];
        sum += data[4] * vec_data[4];
        sum += data[5] * vec_data[5];
        sum += data[6] * vec_data[6];
        sum += data[7] * vec_data[7];
        sum += data[8] * vec_data[8];
        sum += data[9] * vec_data[9];
        return sum;
    }

    var sum: f64 = 0.0;
    for (0..gaussian_count) |col| {
        sum += matrix.data[row_offset + col] * vector.data[col];
    }
    return sum;
}

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
