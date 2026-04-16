//! Purpose:
//!   Public Zig entrypoint for the O2A forward-model lab.
//!
//! Physics:
//!   Re-exports the O2A case, data, optics, solver controls, spectral runner,
//!   and reporting surface used by the exact scalar forward path.
//!
//! Design:
//!   Keep the shipped surface small and literal: case, data, optics, spectrum,
//!   and report. Generic engine, plugin, retrieval, and ABI layers are not
//!   part of the public library anymore.
//!
//! Invariants:
//!   Public consumers do not gain access to engine-plan-workspace scaffolding
//!   or plugin/provider resolution APIs.
//!
//! Validation:
//!   The root-level tests in this file verify the intended O2A-only export
//!   surface.

const std = @import("std");
const o2a = @import("o2a.zig");

pub const Case = o2a.Case;
pub const Data = o2a.Data;
pub const Optics = o2a.Optics;
pub const Method = o2a.Method;
pub const Work = o2a.Work;
pub const Result = o2a.Result;
pub const Report = o2a.Report;
pub const ForwardProfile = o2a.ForwardProfile;
pub const RtmControls = o2a.RtmControls;
pub const parity = o2a.parity;
pub const profile = o2a.profile;

pub const loadData = o2a.loadData;
pub const buildOptics = o2a.buildOptics;
pub const runSpectrum = o2a.runSpectrum;
pub const writeReport = o2a.writeReport;

test "public root exposes the O2A forward lab surface" {
    try std.testing.expect(@hasDecl(@This(), "Case"));
    try std.testing.expect(@hasDecl(@This(), "Data"));
    try std.testing.expect(@hasDecl(@This(), "Optics"));
    try std.testing.expect(@hasDecl(@This(), "Method"));
    try std.testing.expect(@hasDecl(@This(), "Work"));
    try std.testing.expect(@hasDecl(@This(), "Result"));
    try std.testing.expect(@hasDecl(@This(), "Report"));
    try std.testing.expect(@hasDecl(@This(), "parity"));
    try std.testing.expect(@hasDecl(@This(), "loadData"));
    try std.testing.expect(@hasDecl(@This(), "buildOptics"));
    try std.testing.expect(@hasDecl(@This(), "runSpectrum"));
    try std.testing.expect(@hasDecl(@This(), "writeReport"));
}

test "public root no longer exposes engine or plugin scaffolding" {
    try std.testing.expect(!@hasDecl(@This(), "Engine"));
    try std.testing.expect(!@hasDecl(@This(), "PreparedPlan"));
    try std.testing.expect(!@hasDecl(@This(), "Workspace"));
    try std.testing.expect(!@hasDecl(@This(), "Request"));
    try std.testing.expect(!@hasDecl(@This(), "canonical_config"));
    try std.testing.expect(!@hasDecl(@This(), "mission_s5p"));
    try std.testing.expect(!@hasDecl(@This(), "exporters"));
    try std.testing.expect(!@hasDecl(@This(), "test_support"));
    try std.testing.expect(!@hasDecl(@This(), "vendor_case"));
}
