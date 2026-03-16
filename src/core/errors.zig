pub const TemplateError = error{
    MissingModelFamily,
    MissingTransportRoute,
};

pub const PreparationError = TemplateError || error{
    OutOfMemory,
    CatalogNotBootstrapped,
    UnsupportedModelFamily,
    PreparedPlanLimitExceeded,
    UnsupportedDerivativeMode,
    UnsupportedExecutionMode,
    UnsupportedCapability,
    PluginPrepareFailed,
};

pub const ExecutionError = error{
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
    WorkspacePlanMismatch,
    DerivativeModeMismatch,
    PluginExecutionFailed,
};

pub const Error = PreparationError || ExecutionError;
