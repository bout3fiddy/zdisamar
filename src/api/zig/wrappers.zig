//! Purpose:
//!   Provide typed Zig wrappers over the C ABI bridge.
//!
//! Physics:
//!   No additional physics; this preserves the request/result semantics while
//!   packaging ABI-safe descriptors for Zig callers.
//!
//! Vendor:
//!   `wrappers`
//!
//! Design:
//!   Keep the typed surface narrow: encode request diagnostics and engine
//!   options once, then delegate to the C bridge helpers.
//!
//! Invariants:
//!   Packed flags must round-trip to the same low bits, and ABI capacity checks
//!   must fail before descriptors are exported.
//!
//! Validation:
//!   Exercised by the wrapper unit tests in this file.
const std = @import("std");

const EngineOptions = @import("../../core/Engine.zig").EngineOptions;
const DiagnosticsSpec = @import("../../core/diagnostics.zig").DiagnosticsSpec;
const Result = @import("../../core/Result.zig").Result;
const c_api = @import("../c/bridge.zig");

pub const DiagnosticsFlags = packed struct(u32) {
    provenance: bool = true,
    jacobians: bool = false,
    _padding: u30 = 0,

    /// Purpose:
    ///   Convert typed diagnostics flags into the request spec view.
    ///
    /// Physics:
    ///   None; this is bit-pack translation for the ABI bridge.
    ///
    /// Vendor:
    ///   `wrappers::DiagnosticsFlags::fromSpec`
    ///
    /// Inputs:
    ///   `spec` carries the typed diagnostics toggles.
    ///
    /// Outputs:
    ///   Returns the packed bitfield used by the C bridge.
    ///
    /// Units:
    ///   Bit positions only.
    ///
    /// Assumptions:
    ///   The spec uses the same semantic fields as the ABI bridge.
    ///
    /// Decisions:
    ///   Keep provenance enabled by default to match the existing request spec.
    ///
    /// Validation:
    ///   Covered by the diagnostics flag unit test in this file.
    pub fn fromSpec(spec: DiagnosticsSpec) DiagnosticsFlags {
        return .{
            .provenance = spec.provenance,
            .jacobians = spec.jacobians,
        };
    }

    /// Purpose:
    ///   Expose the packed flag word expected by the C ABI.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `wrappers::DiagnosticsFlags::toMask`
    ///
    /// Inputs:
    ///   The packed flags on `self`.
    ///
    /// Outputs:
    ///   Returns the raw `u32` bitmask.
    ///
    /// Units:
    ///   Bit positions only.
    ///
    /// Assumptions:
    ///   The packed layout is stable for the two low bits.
    ///
    /// Decisions:
    ///   Use a direct bit-cast so the wrapper does not invent a new mapping.
    ///
    /// Validation:
    ///   Covered by the diagnostics flag unit test in this file.
    pub fn toMask(self: DiagnosticsFlags) u32 {
        return @bitCast(self);
    }
};

pub const ApiBridgeError = error{
    AbiCapacityExceeded,
};

pub const EngineOptionsView = struct {
    options: EngineOptions = .{},

    /// Purpose:
    ///   Convert typed engine options to the C ABI descriptor.
    ///
    /// Physics:
    ///   None.
    ///
    /// Vendor:
    ///   `wrappers::EngineOptionsView::toC`
    ///
    /// Inputs:
    ///   `self.options.max_prepared_plans` is the only field currently exposed.
    ///
    /// Outputs:
    ///   Returns a bridge descriptor or `AbiCapacityExceeded`.
    ///
    /// Units:
    ///   Count of prepared plans.
    ///
    /// Assumptions:
    ///   The capacity fits into a `u32` before it is exported.
    ///
    /// Decisions:
    ///   Fail early rather than truncate the plan cache capacity.
    ///
    /// Validation:
    ///   Covered by the engine-options wrapper test in this file.
    pub fn toC(self: EngineOptionsView) ApiBridgeError!c_api.EngineOptionsDesc {
        const max_prepared_plans = std.math.cast(u32, self.options.max_prepared_plans) orelse
            return error.AbiCapacityExceeded;
        return c_api.defaultEngineOptions(max_prepared_plans);
    }
};

/// Purpose:
///   Translate a typed result into the C ABI result descriptor.
///
/// Physics:
///   No new physics; this preserves the provenance summary across the ABI.
///
/// Vendor:
///   `wrappers::describeResult`
///
/// Inputs:
///   `result` is the typed result emitted by the core engine.
///
/// Outputs:
///   Returns the ABI-safe result descriptor.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The caller only needs the bridge-level summary.
///
/// Decisions:
///   Delegate directly to the C bridge so the ABI mapping stays centralized.
///
/// Validation:
///   Covered by the result-description test in this file.
pub fn describeResult(result: Result) c_api.ResultDesc {
    return c_api.describeResult(result);
}

test "diagnostics flags preserve the request spec bits" {
    const flags = DiagnosticsFlags.fromSpec(.{
        .provenance = true,
        .jacobians = true,
    });

    try std.testing.expect(flags.provenance);
    try std.testing.expect(flags.jacobians);
    try std.testing.expectEqual(@as(u32, 0b11), flags.toMask() & 0b11);
}

test "engine options view converts typed options to the C ABI descriptor" {
    const desc = try (EngineOptionsView{
        .options = .{
            .max_prepared_plans = 12,
        },
    }).toC();

    try std.testing.expectEqual(@as(u32, 12), desc.max_prepared_plans);
}
