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
    LineByLine,
    Optimisation,
    OxygenCollisionInducedAbsorption,
    RadiativeTransferControls,
    RadiativeTransferPerformanceThresholds,
    ReferenceAsset,
    ReferenceAssets,
    SpectralGrid,
    Surface,
    VerticalInterval,
)
from ..input.wavelength_band.o2a import Scene as Scene


def reference_scene() -> Scene:
    """Return the packaged DISAMAR-family O2 A reference case."""

    from ..rtm.run import reference_scene

    return reference_scene()


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
    "Scene",
    "Optimisation",
    "LineByLine",
    "OxygenCollisionInducedAbsorption",
    "RadiativeTransferControls",
    "RadiativeTransferPerformanceThresholds",
    "ReferenceAsset",
    "ReferenceAssets",
    "SpectralGrid",
    "Surface",
    "VerticalInterval",
    "reference_scene",
]
