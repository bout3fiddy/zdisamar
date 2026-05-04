const std = @import("std");
const ReferenceData = @import("../../input/ReferenceData.zig");
const reference_types = @import("types.zig");

const Allocator = std.mem.Allocator;
const LineGasSpec = reference_types.LineGasSpec;

const LineListEntry = struct {
    key: u64,
    line_list: ReferenceData.SpectroscopyLineList,

    fn deinit(self: *LineListEntry, allocator: Allocator) void {
        self.line_list.deinit(allocator);
        self.* = undefined;
    }
};

var mutex = std.Thread.Mutex{};
var cached_line_list: ?LineListEntry = null;

pub fn loadLineList(allocator: Allocator, spec: LineGasSpec) !?ReferenceData.SpectroscopyLineList {
    const key = lineListKey(spec);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_line_list orelse return null;
    if (entry.key != key) return null;
    return try entry.line_list.clone(allocator);
}

pub fn storeLineList(spec: LineGasSpec, line_list: ReferenceData.SpectroscopyLineList) !void {
    const allocator = std.heap.smp_allocator;
    const entry = LineListEntry{
        .key = lineListKey(spec),
        .line_list = try line_list.clone(allocator),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_line_list) |*old| old.deinit(allocator);
    cached_line_list = entry;
}

fn lineListKey(spec: LineGasSpec) u64 {
    var hash = std.hash.Wyhash.init(0);
    updateAsset(&hash, spec.line_list_asset);
    updateAsset(&hash, spec.line_mixing_asset);
    updateAsset(&hash, spec.strong_lines_asset);
    updateOptionalFloat(&hash, spec.line_mixing_factor);
    hash.update(spec.isotopes_sim);
    updateOptionalFloat(&hash, spec.threshold_line_sim);
    updateOptionalFloat(&hash, spec.cutoff_sim_cm1);
    return hash.final();
}

fn updateAsset(hash: *std.hash.Wyhash, asset: reference_types.ExternalAsset) void {
    hash.update(asset.id);
    hash.update(&.{0});
    hash.update(asset.path);
    hash.update(&.{0});
    hash.update(asset.format);
    hash.update(&.{0});
}

fn updateOptionalFloat(hash: *std.hash.Wyhash, value: ?f64) void {
    updateInt(hash, value != null);
    if (value) |payload| updateFloat(hash, payload);
}

fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}
