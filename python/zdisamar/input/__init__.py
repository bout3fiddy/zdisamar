"""Typed input objects."""

from .aerosol import Aerosol, AerosolPlacement, AerosolProfileLayer
from .assets import ReferenceAsset, ReferenceAssets
from .atmosphere import Atmosphere, VerticalInterval
from .geometry import Geometry, Surface
from .instrument import InstrumentResponse, SpectralGrid
from .radiative_transfer import RadiativeTransferControls, RadiativeTransferPerformanceThresholds
from .spectroscopy import O2LineByLine, OxygenCollisionInducedAbsorption
from .wavelength_band import O2AInput

__all__ = [
    "Aerosol",
    "AerosolPlacement",
    "AerosolProfileLayer",
    "Atmosphere",
    "Geometry",
    "InstrumentResponse",
    "O2AInput",
    "O2LineByLine",
    "OxygenCollisionInducedAbsorption",
    "RadiativeTransferControls",
    "RadiativeTransferPerformanceThresholds",
    "ReferenceAsset",
    "ReferenceAssets",
    "SpectralGrid",
    "Surface",
    "VerticalInterval",
]
