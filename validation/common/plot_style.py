"""Shared plotting style for retained validation figures."""

from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter
from zdisamar.plot.properties import PLOT

MONOSPACE_FONTS = [
    "Menlo",
    "Monaco",
    "Consolas",
    "Liberation Mono",
    "DejaVu Sans Mono",
    "monospace",
]


def prepare_matplotlib() -> None:
    """Apply the repository validation plot policy to Matplotlib figures."""

    PLOT.prepare()
    plt.rcParams.update(
        {
            "axes.edgecolor": "black",
            "axes.grid": True,
            "axes.linewidth": 0.8,
            "figure.facecolor": "white",
            "font.family": "monospace",
            "font.monospace": MONOSPACE_FONTS,
            "grid.alpha": 0.25,
            "grid.color": PLOT.colors["grid"],
            "grid.linewidth": 0.65,
            "legend.framealpha": 1.0,
            "legend.facecolor": "white",
            "legend.edgecolor": "#cccccc",
            "mathtext.fontset": "dejavusans",
            "savefig.facecolor": "white",
        }
    )


def scientific_formatter() -> ScalarFormatter:
    formatter = ScalarFormatter(useMathText=True)
    formatter.set_powerlimits((-2, 2))
    return formatter


def style_axis(axis: Any, *, scientific_y: bool = False) -> None:
    axis.grid(True, color=PLOT.colors["grid"], linewidth=0.65, alpha=0.25)
    axis.tick_params(axis="both", colors="black", direction="out", length=4.0, width=0.8)
    if scientific_y:
        axis.ticklabel_format(axis="y", style="sci", scilimits=(-2, 2), useMathText=True)
        axis.yaxis.set_major_formatter(scientific_formatter())
    for spine in axis.spines.values():
        spine.set_visible(True)
        spine.set_color("black")
        spine.set_linewidth(0.8)


def style_legend(legend: Any) -> None:
    legend.get_frame().set_facecolor("white")
    legend.get_frame().set_edgecolor("#cccccc")
    legend.get_frame().set_linewidth(0.8)


def save_figure(fig: Any, path: Path, *, dpi: int = 180) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)
