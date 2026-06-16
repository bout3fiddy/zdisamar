"""Wavelength-band scene API."""

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
from ..input.wavelength_band.o2a_default import default_o2a_scene as default_o2a_scene


def reference_scene() -> Scene:
    """Return the packaged DISAMAR-family reference scene."""

    return default_o2a_scene()


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
    "default_o2a_scene",
    "reference_scene",
]
