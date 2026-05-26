"""O2 A wavelength-band case API."""

from ..input import (
    Aerosol,
    AerosolPlacement,
    AerosolProfileLayer,
    Atmosphere,
    FastModeAdaptiveReferenceGrid,
    FastModeFastStageSampling,
    FastModeFinalCorrection,
    FastModeOe,
    FastModeOeControls,
    FastModeOptimisation,
    FastModeRadiativeTransfer,
    FastModeWavelengthWindow,
    Geometry,
    InstrumentResponse,
    O2AOptimisation,
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
from ..input.wavelength_band.o2a import O2AInput as O2ACase


def reference_case() -> O2ACase:
    """Return the packaged DISAMAR-family O2 A reference case."""

    from ..rtm.run import o2a_reference_case

    return o2a_reference_case()


__all__ = [
    "Aerosol",
    "AerosolPlacement",
    "AerosolProfileLayer",
    "Atmosphere",
    "FastModeAdaptiveReferenceGrid",
    "FastModeFastStageSampling",
    "FastModeFinalCorrection",
    "FastModeOe",
    "FastModeOeControls",
    "FastModeOptimisation",
    "FastModeRadiativeTransfer",
    "FastModeWavelengthWindow",
    "Geometry",
    "InstrumentResponse",
    "O2ACase",
    "O2AOptimisation",
    "O2LineByLine",
    "OxygenCollisionInducedAbsorption",
    "RadiativeTransferControls",
    "RadiativeTransferPerformanceThresholds",
    "ReferenceAsset",
    "ReferenceAssets",
    "SpectralGrid",
    "Surface",
    "VerticalInterval",
    "reference_case",
]
