"""Typed input objects."""

from .aerosol import Aerosol, AerosolPlacement, AerosolProfileLayer
from .assets import ReferenceAsset, ReferenceAssets
from .atmosphere import Atmosphere, VerticalInterval
from .geometry import Geometry, Surface
from .instrument import InstrumentResponse, SpectralGrid
from .radiative_transfer import RadiativeTransferControls, RadiativeTransferPerformanceThresholds
from .spectroscopy import LineByLine, OxygenCollisionInducedAbsorption
from .wavelength_band import (
    FastModeAdaptiveReferenceGrid,
    FastModeFastStageSampling,
    FastModeFinalCorrection,
    FastModeOe,
    FastModeOeControls,
    FastModeOptimisation,
    FastModeRadiativeTransfer,
    FastModeWavelengthWindow,
    Optimisation,
    Scene,
)

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
]
