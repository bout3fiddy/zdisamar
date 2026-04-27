const std = @import("std");
const o2a = @import("o2a.zig");

pub const Case = o2a.Case;
pub const Data = o2a.Data;
pub const Optics = o2a.Optics;
pub const Method = o2a.Method;
pub const RunStorage = o2a.RunStorage;
pub const Result = o2a.Result;
pub const Report = o2a.Report;
pub const RadiativeTransferControls = o2a.RadiativeTransferControls;
pub const Prepared = o2a.Prepared;
pub const parity = o2a.parity;
pub const report = o2a.report;

pub const prepare = o2a.prepare;
pub const run = o2a.run;
pub const writeReport = o2a.writeReport;

test "public root exposes the O2A forward lab surface" {
    try std.testing.expect(@hasDecl(@This(), "Case"));
    try std.testing.expect(@hasDecl(@This(), "Data"));
    try std.testing.expect(@hasDecl(@This(), "Optics"));
    try std.testing.expect(@hasDecl(@This(), "Method"));
    try std.testing.expect(@hasDecl(@This(), "RunStorage"));
    try std.testing.expect(@hasDecl(@This(), "Result"));
    try std.testing.expect(@hasDecl(@This(), "Report"));
    try std.testing.expect(@hasDecl(@This(), "Prepared"));
    try std.testing.expect(@hasDecl(@This(), "parity"));
    try std.testing.expect(@hasDecl(@This(), "prepare"));
    try std.testing.expect(@hasDecl(@This(), "run"));
    try std.testing.expect(@hasDecl(@This(), "writeReport"));
}

test "public root no longer exposes removed framework scaffolding" {
    try std.testing.expect(!@hasDecl(@This(), "Engine"));
    try std.testing.expect(!@hasDecl(@This(), "PreparedPlan"));
    try std.testing.expect(!@hasDecl(@This(), "Workspace"));
    try std.testing.expect(!@hasDecl(@This(), "Request"));
    try std.testing.expect(!@hasDecl(@This(), "canonical_config"));
    try std.testing.expect(!@hasDecl(@This(), "mission_s5p"));
    try std.testing.expect(!@hasDecl(@This(), "exporters"));
    try std.testing.expect(!@hasDecl(@This(), "test_support"));
    try std.testing.expect(!@hasDecl(@This(), "vendor_case"));
    try std.testing.expect(!@hasDecl(@This(), "loadData"));
    try std.testing.expect(!@hasDecl(@This(), "buildOptics"));
    try std.testing.expect(!@hasDecl(@This(), "runSpectrum"));
}
