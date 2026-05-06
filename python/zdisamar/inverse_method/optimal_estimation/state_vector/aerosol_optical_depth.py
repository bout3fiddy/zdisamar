"""Aerosol optical-depth retrieval parameter."""

from __future__ import annotations

from dataclasses import dataclass

AEROSOL_OPTICAL_DEPTH = "aerosol_optical_depth"


@dataclass(frozen=True)
class AerosolOpticalDepth:
    """State-vector coordinate for total aerosol optical depth at 550 nm."""

    initial: float
    prior: float
    variance: float
    lower: float | None = 0.0
    upper: float | None = None
    name: str = AEROSOL_OPTICAL_DEPTH

    def write_to(self, target, value: float) -> None:
        target.aerosol.optical_depth_550_nm = value
