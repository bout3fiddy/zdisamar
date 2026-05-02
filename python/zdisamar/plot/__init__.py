"""Altair plotting helpers for zdisamar outputs and diagnostics."""

from . import bundles, fields, spectrum, validation
from .data import comparison_frame, metric_frame, to_dataframe
from .io import save
from .spectrum import with_full_sample_spectrum
from .theme import SEMANTIC_COLORS, use_theme

__all__ = [
    "SEMANTIC_COLORS",
    "bundles",
    "comparison_frame",
    "fields",
    "metric_frame",
    "save",
    "spectrum",
    "to_dataframe",
    "use_theme",
    "validation",
    "with_full_sample_spectrum",
]

use_theme("validation")
