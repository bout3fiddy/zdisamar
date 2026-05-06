from __future__ import annotations

import csv
from pathlib import Path

import numpy as np


def load_spectrum_csv(path: Path) -> dict[str, np.ndarray]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"{path} is empty")
    return {key: np.array([float(row[key]) for row in rows], dtype=float) for key in rows[0]}


def interpolate_to_grid(
    wavelength_nm: np.ndarray,
    reference: dict[str, np.ndarray],
) -> dict[str, np.ndarray]:
    reference_wavelength_nm = reference["wavelength_nm"]
    if (
        wavelength_nm[0] < reference_wavelength_nm[0]
        or wavelength_nm[-1] > reference_wavelength_nm[-1]
    ):
        raise ValueError(
            "current spectrum grid extends outside the vendored DISAMAR reference grid"
        )
    return {
        key: wavelength_nm
        if key == "wavelength_nm"
        else np.interp(wavelength_nm, reference_wavelength_nm, values)
        for key, values in reference.items()
    }


def write_spectrum_plot(
    output_path: Path,
    wavelength_nm: np.ndarray,
    radiance: np.ndarray,
    irradiance: np.ndarray,
    reflectance: np.ndarray,
    vendor: dict[str, np.ndarray],
    min_reflectance_index: int,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(4, 1, figsize=(12, 11), sharex=True, constrained_layout=True)
    fig.suptitle("DISAMAR O2 A parity route spectrum")

    axes[0].plot(
        wavelength_nm,
        vendor["reflectance"],
        label="Vendored DISAMAR reference",
        linewidth=1.8,
    )
    axes[0].plot(wavelength_nm, reflectance, label="Python parity route", linewidth=1.4)
    axes[0].scatter(
        [wavelength_nm[min_reflectance_index]],
        [reflectance[min_reflectance_index]],
        color="#d62728",
        s=24,
        zorder=3,
        label="minimum reflectance",
    )
    axes[0].set_ylabel("reflectance")
    axes[0].legend(loc="best")

    axes[1].plot(
        wavelength_nm,
        vendor["radiance"],
        label="Vendored DISAMAR reference",
        linewidth=1.8,
    )
    axes[1].plot(wavelength_nm, radiance, label="Python parity route", linewidth=1.4)
    axes[1].set_ylabel("radiance")
    axes[1].legend(loc="best")

    axes[2].plot(
        wavelength_nm,
        vendor["irradiance"],
        label="Vendored DISAMAR reference",
        linewidth=1.8,
    )
    axes[2].plot(wavelength_nm, irradiance, label="Python parity route", linewidth=1.4)
    axes[2].set_ylabel("irradiance")
    axes[2].legend(loc="best")

    reflectance_residual = reflectance - vendor["reflectance"]
    axes[3].plot(wavelength_nm, reflectance_residual, color="tab:red", linewidth=1.3)
    axes[3].axhline(0.0, color="black", linewidth=0.8, alpha=0.7)
    axes[3].set_ylabel("reflectance\nresidual")
    axes[3].set_xlabel("wavelength (nm)")

    for axis in axes:
        axis.grid(True, alpha=0.25)
        axis.ticklabel_format(axis="y", style="sci", scilimits=(-2, 3))

    fig.savefig(output_path, dpi=160)
    plt.close(fig)
