const std = @import("std");

// instrumentation: perturbation sink
// captures: changed hook counts and replacements
// why: run ablation sweeps outside the product build.
pub const available = true;

pub const max_channel_count: usize = 16;
pub const any_index: i32 = -1;

const AtomicU64 = std.atomic.Value(u64);

pub const Mode = enum(u8) {
    baseline,
    zero,
    scale,
    force_true,
    force_false,
};

// instrumentation: perturbation plan
// captures: active channel/filter/mode
// why: select one ablation while hooks stay allocation-free.
pub const Plan = struct {
    experiment_id: u32 = 0,
    channel_id: u8 = 0,
    mode: Mode = .baseline,
    scale: f64 = 1.0,
    min_layer: i32 = any_index,
    max_layer: i32 = any_index,
    min_fourier: i32 = any_index,
    max_fourier: i32 = any_index,
    min_order: i32 = any_index,
    max_order: i32 = any_index,
    state_filter: i32 = any_index,
    branch_filter: i32 = any_index,
    active: bool = false,
};

pub const CounterSnapshot = struct {
    hit_count: u64,
    changed_count: u64,
};

var active_plan: Plan = .{};
var hit_counts: [max_channel_count]AtomicU64 = atomicArray();
var changed_counts: [max_channel_count]AtomicU64 = atomicArray();

fn atomicArray() [max_channel_count]AtomicU64 {
    return [_]AtomicU64{AtomicU64.init(0)} ** max_channel_count;
}

// instrumentation: perturbation activation
// captures: plan setup/reset
// why: isolate counters for each paired experiment.
pub fn setPlan(plan: Plan) void {
    active_plan = plan;
}

pub fn clearPlan() void {
    active_plan = .{};
}

pub fn resetCounters() void {
    for (&hit_counts) |*counter| counter.store(0, .monotonic);
    for (&changed_counts) |*counter| counter.store(0, .monotonic);
}

// instrumentation: perturbation counters
// captures: hook hits and changed values
// why: estimate skipped work without storing event rows.
pub fn snapshot(channel_id: u8) CounterSnapshot {
    const index = channelIndex(channel_id);
    return .{
        .hit_count = hit_counts[index].load(.monotonic),
        .changed_count = changed_counts[index].load(.monotonic),
    };
}

// instrumentation: perturbation scalar
// captures: zero/scale replacements
// why: measure final-output sensitivity to removing scalar terms.
pub fn scalar(
    channel_id: u8,
    layer_index: i32,
    fourier_index: i32,
    order_index: i32,
    state_index: i32,
    branch: i32,
    baseline: f64,
) f64 {
    recordHit(channel_id);
    const plan = active_plan;
    if (!matches(plan, channel_id, layer_index, fourier_index, order_index, state_index, branch)) {
        return baseline;
    }

    const perturbed = switch (plan.mode) {
        .zero => 0.0,
        .scale => baseline * plan.scale,
        else => baseline,
    };
    if (perturbed != baseline) recordChanged(channel_id);
    return perturbed;
}

// instrumentation: perturbation decision
// captures: forced branch outcomes
// why: measure final-output sensitivity to skipping or extending work.
pub fn decision(
    channel_id: u8,
    layer_index: i32,
    fourier_index: i32,
    order_index: i32,
    state_index: i32,
    branch: i32,
    baseline: bool,
) bool {
    recordHit(channel_id);
    const plan = active_plan;
    if (!matches(plan, channel_id, layer_index, fourier_index, order_index, state_index, branch)) {
        return baseline;
    }

    const perturbed = switch (plan.mode) {
        .force_true => true,
        .force_false => false,
        else => baseline,
    };
    if (perturbed != baseline) recordChanged(channel_id);
    return perturbed;
}

fn recordHit(channel_id: u8) void {
    _ = hit_counts[channelIndex(channel_id)].fetchAdd(1, .monotonic);
}

fn recordChanged(channel_id: u8) void {
    _ = changed_counts[channelIndex(channel_id)].fetchAdd(1, .monotonic);
}

fn channelIndex(channel_id: u8) usize {
    const index: usize = @intCast(channel_id);
    return if (index < max_channel_count) index else max_channel_count - 1;
}

fn matches(
    plan: Plan,
    channel_id: u8,
    layer_index: i32,
    fourier_index: i32,
    order_index: i32,
    state_index: i32,
    branch: i32,
) bool {
    if (!plan.active or plan.mode == .baseline or plan.channel_id != channel_id) return false;
    if (!matchesRange(layer_index, plan.min_layer, plan.max_layer)) return false;
    if (!matchesRange(fourier_index, plan.min_fourier, plan.max_fourier)) return false;
    if (!matchesRange(order_index, plan.min_order, plan.max_order)) return false;
    if (plan.state_filter != any_index and plan.state_filter != state_index) return false;
    if (plan.branch_filter != any_index and plan.branch_filter != branch) return false;
    return true;
}

fn matchesRange(value: i32, min_value: i32, max_value: i32) bool {
    if (min_value != any_index and value < min_value) return false;
    if (max_value != any_index and value > max_value) return false;
    return true;
}
