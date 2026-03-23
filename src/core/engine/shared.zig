//! Purpose:
//!   Hold small shared helpers used across engine execution phases.
//!
//! Physics:
//!   This file does not compute a scientific quantity directly; it preserves the typed
//!   provider wiring that measurement-space evaluation consumes downstream.
//!
//! Vendor:
//!   `engine provider binding handoff`
//!
//! Design:
//!   Common wiring helpers live in one place so forward and retrieval code can share the
//!   same measurement-space provider view without duplicating field mapping logic.
//!
//! Invariants:
//!   Returned provider bindings must reflect the prepared plan exactly and must not
//!   outlive the plan snapshot they reference.
//!
//! Validation:
//!   Covered indirectly by forward and retrieval execution tests that exercise
//!   measurement-space simulation through prepared plans.
const PreparedPlan = @import("../Plan.zig").PreparedPlan;
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");

/// Purpose:
///   Project the prepared-plan provider set into the measurement-space binding shape.
///
/// Outputs:
///   Returns a borrowed view of the transport, surface, instrument, and noise providers
///   required by measurement-space simulation.
///
/// Assumptions:
///   The returned view is only valid while `plan` remains alive.
pub fn measurementProviders(plan: *const PreparedPlan) MeasurementSpace.ProviderBindings {
    // DECISION:
    //   This helper keeps the provider-field mapping centralized so forward and retrieval
    //   phases cannot silently diverge in which prepared providers they expose.
    return .{
        .transport = plan.providers.transport,
        .surface = plan.providers.surface,
        .instrument = plan.providers.instrument,
        .noise = plan.providers.noise,
    };
}
