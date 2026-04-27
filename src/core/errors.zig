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
    UnsupportedRadiativeTransferControls,
    UnsupportedCapability,
    MissingNativeSource,
    MissingPrepareHook,
    PluginEntryIncompatibleAbi,
    PluginPrepareRejected,
    PluginPrepareFailed,
};

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

pub const Error = PreparationError || ExecutionError;
