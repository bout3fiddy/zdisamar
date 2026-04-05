#!/usr/bin/env python3

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plot the current zdisamar vs DISAMAR O2A vendor comparison."
    )
    parser.add_argument(
        "--csv",
        default="out/analysis/o2a/fresh_vendor_plot/vendor_o2a_comparison.csv",
        help="Input comparison CSV",
    )
    parser.add_argument(
        "--plot",
        default="out/analysis/o2a/fresh_vendor_plot/vendor_o2a_comparison.png",
        help="Output PNG path",
    )
    return parser.parse_args()


def load_rows(path: Path) -> dict[str, list[float]]:
    columns: dict[str, list[float]] = {}
    with path.open() as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            for key, value in row.items():
                columns.setdefault(key, []).append(float(value))
    return columns


def main() -> None:
    args = parse_args()
    csv_path = Path(args.csv)
    plot_path = Path(args.plot)
    plot_path.parent.mkdir(parents=True, exist_ok=True)

    data = load_rows(csv_path)
    wavelength = data["wavelength_nm"]

    fig, axes = plt.subplots(4, 1, figsize=(12, 13), sharex=True, constrained_layout=True)

    axes[0].plot(wavelength, data["fortran_reflectance"], label="DISAMAR", linewidth=1.8)
    axes[0].plot(wavelength, data["zdisamar_reflectance"], label="zdisamar", linewidth=1.4)
    axes[0].set_ylabel("Reflectance")
    axes[0].set_title("O2A vendor comparison: current zdisamar vs stored DISAMAR reference")
    axes[0].grid(True, alpha=0.25)
    axes[0].legend(loc="best")

    axes[1].plot(wavelength, data["reflectance_residual"], color="tab:red", linewidth=1.3)
    axes[1].axhline(0.0, color="black", linewidth=0.8, alpha=0.7)
    axes[1].set_ylabel("Reflectance\nresidual")
    axes[1].grid(True, alpha=0.25)

    axes[2].plot(wavelength, data["fortran_radiance"], label="DISAMAR", linewidth=1.8)
    axes[2].plot(wavelength, data["zdisamar_radiance"], label="zdisamar", linewidth=1.4)
    axes[2].set_ylabel("Radiance")
    axes[2].grid(True, alpha=0.25)
    axes[2].legend(loc="best")

    axes[3].plot(wavelength, data["reflectance_ratio"], color="tab:green", linewidth=1.3)
    axes[3].axhline(1.0, color="black", linewidth=0.8, alpha=0.7)
    axes[3].set_ylabel("Reflectance\nratio")
    axes[3].set_xlabel("Wavelength (nm)")
    axes[3].grid(True, alpha=0.25)

    fig.savefig(plot_path, dpi=160)
    print(f"wrote {plot_path}")


if __name__ == "__main__":
    main()
