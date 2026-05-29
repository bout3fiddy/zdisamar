"""O2-O2 collision-induced absorption plot accessor."""

from pathlib import Path

from . import fields
from .profiles import profile_figure
from .properties import PlotAccessor


class CollisionInducedAbsorptionPlot(PlotAccessor):
    """Plots for O2-O2 collision-induced absorption by layer."""

    def __init__(self, table):

        super().__init__(table)

    def optical_depth(
        self,
        wavelength_nm: float | None = None,
        save: str | Path | None = None,
    ):

        return self.finish_plot(
            optical_depth_profile(self.target, wavelength_nm=wavelength_nm),
            save=save,
        )


def optical_depth_profile(
    table,
    *,
    wavelength_nm: float | None,
):

    return profile_figure(
        table,
        quantity=fields.COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH,
        title="O2-O2 collision-induced absorption optical depth profile",
        color_key="collision_induced_absorption",
        wavelength_nm=wavelength_nm,
    )
