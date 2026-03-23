//! Purpose:
//!   Centralize the typed error surfaces shared by plan preparation and request
//!   execution so engine callers can reason about failure classes explicitly.
//!
//! Physics:
//!   This file does not implement physics; it names the failure boundaries around
//!   scientific preparation and evaluation stages.
//!
//! Vendor:
//!   `engine prepare/execute error boundary`
//!
//! Design:
//!   Zig error sets replace string-keyed status codes and keep shared failure categories
//!   stable across the engine pipeline.
//!
//! Invariants:
//!   Template errors are a strict subset of preparation errors, and the top-level engine
//!   error set is the union of preparation and execution failures.
//!
//! Validation:
//!   Compile-time references across `src/core` and the API wrappers ensure the named
//!   failure surface stays in sync.
/// Purpose:
///   Errors raised while validating a request template before provider resolution.
pub const TemplateError = error{
    MissingModelFamily,
    MissingTransportRoute,
};

/// Purpose:
///   Errors raised while turning a validated template into a prepared plan.
pub const PreparationError = TemplateError || error{
    OutOfMemory,
    CatalogNotBootstrapped,
    UnsupportedModelFamily,
    PreparedPlanLimitExceeded,
    UnsupportedDerivativeMode,
    UnsupportedExecutionMode,
    UnsupportedRtmControls,
    UnsupportedCapability,
    MissingNativeSource,
    MissingPrepareHook,
    PluginEntryIncompatibleAbi,
    PluginPrepareRejected,
    PluginPrepareFailed,
};

/// Purpose:
///   Errors raised while executing a prepared plan against a concrete request.
pub const ExecutionError = error{
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
    WorkspacePlanMismatch,
    DerivativeModeMismatch,
    MissingExecuteHook,
    PluginEntryIncompatibleAbi,
    PluginExecutionFailed,
};

/// Purpose:
///   Union of the preparation and execution failure surfaces exposed by the engine.
pub const Error = PreparationError || ExecutionError;
