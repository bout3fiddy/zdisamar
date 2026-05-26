"""Wavelength-band-specific input objects."""

from .o2a import O2AInput
from .optimisation import (
    FastModeAdaptiveReferenceGrid,
    FastModeFinalCorrection,
    FastModeOe,
    FastModeOeControls,
    FastModeOptimisation,
    FastModeRadiativeTransfer,
    O2AOptimisation,
)

__all__ = [
    "FastModeAdaptiveReferenceGrid",
    "FastModeFinalCorrection",
    "FastModeOe",
    "FastModeOeControls",
    "FastModeOptimisation",
    "FastModeRadiativeTransfer",
    "O2AInput",
    "O2AOptimisation",
]
