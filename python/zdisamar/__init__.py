"""Python wrapper for the native zdisamar O2A C ABI."""

from importlib import import_module

from . import reference_data
from .api import (
    AtmosphereDiagnostics,
    AtmosphericBudget,
    Context,
    DiagnosticReport,
    InstrumentResponseTable,
    O2AForwardSession,
    OxygenCollisionInducedAbsorptionDiagnosticTable,
    PreparedDefaultO2A,
    PreparedO2A,
    Spectrum,
    forward,
    o2a_disamar_reference_input,
    o2a_forward_session,
    prepare,
    prepare_default_o2a,
)
from .types import (
    Aerosol,
    AerosolPlacement,
    Atmosphere,
    Geometry,
    InstrumentResponse,
    O2AInput,
    O2LineByLine,
    OxygenCollisionInducedAbsorption,
    RadiativeTransferControls,
    RadiativeTransferPerformanceThresholds,
    ReferenceAsset,
    ReferenceAssets,
    SpectralGrid,
    Surface,
    VerticalInterval,
)


def __getattr__(name: str):

    if name == "inverse_method":
        module = import_module(".inverse_method", __name__)
        globals()[name] = module

        return module

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__all__ = [
    "Aerosol",
    "AerosolPlacement",
    "Atmosphere",
    "AtmosphereDiagnostics",
    "AtmosphericBudget",
    "Context",
    "DiagnosticReport",
    "Geometry",
    "InstrumentResponse",
    "InstrumentResponseTable",
    "O2AInput",
    "O2LineByLine",
    "O2AForwardSession",
    "OxygenCollisionInducedAbsorptionDiagnosticTable",
    "OxygenCollisionInducedAbsorption",
    "PreparedO2A",
    "PreparedDefaultO2A",
    "RadiativeTransferControls",
    "RadiativeTransferPerformanceThresholds",
    "ReferenceAsset",
    "ReferenceAssets",
    "SpectralGrid",
    "Spectrum",
    "Surface",
    "VerticalInterval",
    "forward",
    "o2a_forward_session",
    "o2a_disamar_reference_input",
    "reference_data",
    "prepare",
    "prepare_default_o2a",
]
