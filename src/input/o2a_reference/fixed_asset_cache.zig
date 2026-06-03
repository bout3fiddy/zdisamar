const std = @import("std");
const ReferenceData = @import("../../input/ReferenceData.zig");
const reference_types = @import("types.zig");

const Allocator = std.mem.Allocator;
const LineGasSpec = reference_types.LineGasSpec;
const ExternalAsset = reference_types.ExternalAsset;
const ReferenceSample = reference_types.ReferenceSample;
const SolarSpectrumSample = reference_types.SolarSpectrumSample;

const ClimatologyProfile = ReferenceData.ClimatologyProfile;
const CollisionInducedAbsorptionTable = ReferenceData.CollisionInducedAbsorptionTable;
const AirmassFactorLut = ReferenceData.AirmassFactorLut;

const LineListEntry = struct {
    key: u64,
    line_list: ReferenceData.SpectroscopyLineList,

    fn deinit(self: *LineListEntry, allocator: Allocator) void {
        self.line_list.deinit(allocator);
        self.* = undefined;
    }
};

const ProfileEntry = struct {
    key: u64,
    profile: ClimatologyProfile,

    fn deinit(self: *ProfileEntry, allocator: Allocator) void {
        self.profile.deinit(allocator);
        self.* = undefined;
    }
};

const CiaEntry = struct {
    key: u64,
    table: CollisionInducedAbsorptionTable,

    fn deinit(self: *CiaEntry, allocator: Allocator) void {
        self.table.deinit(allocator);
        self.* = undefined;
    }
};

const AirmassLutEntry = struct {
    key: u64,
    lut: AirmassFactorLut,

    fn deinit(self: *AirmassLutEntry, allocator: Allocator) void {
        self.lut.deinit(allocator);
        self.* = undefined;
    }
};

const ReferenceEntry = struct {
    key: u64,
    samples: []ReferenceSample,

    fn deinit(self: *ReferenceEntry, allocator: Allocator) void {
        allocator.free(self.samples);
        self.* = undefined;
    }
};

const SolarEntry = struct {
    key: u64,
    samples: []SolarSpectrumSample,

    fn deinit(self: *SolarEntry, allocator: Allocator) void {
        allocator.free(self.samples);
        self.* = undefined;
    }
};

var mutex = std.Thread.Mutex{};
var cached_line_list: ?LineListEntry = null;
var cached_profile: ?ProfileEntry = null;
var cached_cia: ?CiaEntry = null;
var cached_airmass_lut: ?AirmassLutEntry = null;
var cached_reference: ?ReferenceEntry = null;
var cached_solar: ?SolarEntry = null;

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

pub fn loadProfile(allocator: Allocator, asset: ExternalAsset) !?ClimatologyProfile {
    const key = assetKey(asset);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_profile orelse return null;
    if (entry.key != key) return null;
    return try cloneProfile(allocator, entry.profile);
}

pub fn storeProfile(asset: ExternalAsset, profile: ClimatologyProfile) !void {
    const allocator = std.heap.smp_allocator;
    const entry = ProfileEntry{
        .key = assetKey(asset),
        .profile = try cloneProfile(allocator, profile),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_profile) |*old| old.deinit(allocator);
    cached_profile = entry;
}

pub fn loadCia(allocator: Allocator, asset: ExternalAsset) !?CollisionInducedAbsorptionTable {
    const key = assetKey(asset);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_cia orelse return null;
    if (entry.key != key) return null;
    return try entry.table.clone(allocator);
}

pub fn storeCia(asset: ExternalAsset, table: CollisionInducedAbsorptionTable) !void {
    const allocator = std.heap.smp_allocator;
    const entry = CiaEntry{
        .key = assetKey(asset),
        .table = try table.clone(allocator),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_cia) |*old| old.deinit(allocator);
    cached_cia = entry;
}

pub fn loadAirmassLut(allocator: Allocator, asset: ExternalAsset) !?AirmassFactorLut {
    const key = assetKey(asset);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_airmass_lut orelse return null;
    if (entry.key != key) return null;
    return try cloneAirmassLut(allocator, entry.lut);
}

pub fn storeAirmassLut(asset: ExternalAsset, lut: AirmassFactorLut) !void {
    const allocator = std.heap.smp_allocator;
    const entry = AirmassLutEntry{
        .key = assetKey(asset),
        .lut = try cloneAirmassLut(allocator, lut),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_airmass_lut) |*old| old.deinit(allocator);
    cached_airmass_lut = entry;
}

pub fn loadReferenceSamples(allocator: Allocator, asset: ExternalAsset) !?[]ReferenceSample {
    const key = assetKey(asset);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_reference orelse return null;
    if (entry.key != key) return null;
    return try allocator.dupe(ReferenceSample, entry.samples);
}

pub fn storeReferenceSamples(asset: ExternalAsset, samples: []const ReferenceSample) !void {
    const allocator = std.heap.smp_allocator;
    const entry = ReferenceEntry{
        .key = assetKey(asset),
        .samples = try allocator.dupe(ReferenceSample, samples),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_reference) |*old| old.deinit(allocator);
    cached_reference = entry;
}

pub fn loadSolarSamples(allocator: Allocator, asset: ExternalAsset) !?[]SolarSpectrumSample {
    const key = assetKey(asset);
    mutex.lock();
    defer mutex.unlock();

    const entry = cached_solar orelse return null;
    if (entry.key != key) return null;
    return try allocator.dupe(SolarSpectrumSample, entry.samples);
}

pub fn storeSolarSamples(asset: ExternalAsset, samples: []const SolarSpectrumSample) !void {
    const allocator = std.heap.smp_allocator;
    const entry = SolarEntry{
        .key = assetKey(asset),
        .samples = try allocator.dupe(SolarSpectrumSample, samples),
    };
    mutex.lock();
    defer mutex.unlock();
    if (cached_solar) |*old| old.deinit(allocator);
    cached_solar = entry;
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

fn assetKey(asset: ExternalAsset) u64 {
    var hash = std.hash.Wyhash.init(0);
    updateAsset(&hash, asset);
    return hash.final();
}

fn cloneProfile(allocator: Allocator, profile: ClimatologyProfile) !ClimatologyProfile {
    return .{ .rows = try allocator.dupe(ReferenceData.ClimatologyPoint, profile.rows) };
}

fn cloneAirmassLut(allocator: Allocator, lut: AirmassFactorLut) !AirmassFactorLut {
    return .{ .points = try allocator.dupe(ReferenceData.AirmassFactorPoint, lut.points) };
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
