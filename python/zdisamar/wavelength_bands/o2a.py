"""O2 A wavelength-band case API."""

from ..input import (
    Aerosol,
    AerosolPlacement,
    Atmosphere,
    Geometry,
    InstrumentResponse,
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
from ..rtm.run import o2a_reference_case


def reference_case() -> O2ACase:
    """Return the packaged DISAMAR-family O2 A reference case."""

    return o2a_reference_case()


__all__ = [
    "Aerosol",
    "AerosolPlacement",
    "Atmosphere",
    "Geometry",
    "InstrumentResponse",
    "O2ACase",
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
