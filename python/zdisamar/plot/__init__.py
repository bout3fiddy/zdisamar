"""Altair plotting helpers for zdisamar outputs and diagnostics."""

from . import (
    aerosol,
    atmosphere,
    bound,
    bundles,
    cloud,
    collision_induced_absorption,
    fields,
    instrument_response,
    o2_lines,
    perturbation,
    radiative_transfer,
    spectrum,
    validation,
)
from .bound import for_prepared
from .data import comparison_frame, metric_frame, to_dataframe
from .io import save
from .spectrum import with_full_sample_spectrum
from .theme import SEMANTIC_COLORS, use_theme

__all__ = [
    "SEMANTIC_COLORS",
    "aerosol",
    "atmosphere",
    "bound",
    "bundles",
    "cloud",
    "collision_induced_absorption",
    "comparison_frame",
    "fields",
    "for_prepared",
    "instrument_response",
    "metric_frame",
    "o2_lines",
    "perturbation",
    "radiative_transfer",
    "save",
    "spectrum",
    "to_dataframe",
    "use_theme",
    "validation",
    "with_full_sample_spectrum",
]

use_theme("validation")
