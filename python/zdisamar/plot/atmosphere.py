"""Atmospheric-budget plot accessor."""

from pathlib import Path

from . import fields
from .axes import label
from .profiles import profile_figure
from .properties import PlotAccessor


class BudgetPlot(PlotAccessor):
    """Plots for atmospheric optical-depth budgets."""

    def __init__(self, budget):

        super().__init__(budget)

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
    budget,
    *,
    wavelength_nm: float | None,
):

    quantity = fields.TOTAL_OPTICAL_DEPTH

    return profile_figure(
        budget,
        quantity=quantity,
        title=f"{label(quantity)} profile",
        color_key=quantity,
        wavelength_nm=wavelength_nm,
    )
