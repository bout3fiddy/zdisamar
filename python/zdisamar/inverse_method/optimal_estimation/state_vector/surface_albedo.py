"""Surface albedo retrieval parameter."""

from dataclasses import dataclass

SURFACE_ALBEDO = "surface_albedo"


@dataclass(frozen=True)
class SurfaceAlbedo:
    """State-vector coordinate for Lambertian surface albedo."""

    initial: float
    prior: float
    variance: float
    lower: float | None = 0.0
    upper: float | None = 1.0
    name: str = SURFACE_ALBEDO

    def write_to(self, target, value: float) -> None:
        target.surface.albedo = value
