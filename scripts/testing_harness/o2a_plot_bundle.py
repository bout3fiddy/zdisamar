#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "matplotlib>=3.10",
#   "numpy>=2.2",
# ]
# ///

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
from typing import Any

import matplotlib.pyplot as plt
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Materialize a tracked O2A comparison bundle from a fresh zdisamar profile run."
    )
    parser.add_argument(
        "--current-spectrum",
        required=True,
        help="Generated zdisamar spectrum CSV from the O2A profile workflow.",
    )
    parser.add_argument(
        "--profile-summary",
        required=True,
        help="Raw profile summary JSON from the O2A profile workflow.",
    )
    parser.add_argument(
        "--vendor-reference",
        default="validation/reference/o2a_with_cia_disamar_reference.csv",
        help="Tracked vendor reference CSV.",
    )
    parser.add_argument(
        "--output-dir",
        default="validation/compatibility/o2a_plots",
        help="Tracked bundle output directory.",
    )
    parser.add_argument(
        "--canonical-command",
        default="zig build o2a-plot-bundle",
        help="Canonical regeneration command recorded in the bundle manifest.",
    )
    return parser.parse_args()


def load_csv(path: Path) -> dict[str, np.ndarray]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"{path} is empty")
    return {
        key: np.array([float(row[key]) for row in rows], dtype=float)
        for key in rows[0].keys()
    }


def stable_repo_path(path: Path) -> str:
    resolved = path.resolve()
    cwd = Path.cwd().resolve()
    try:
        return resolved.relative_to(cwd).as_posix()
    except ValueError:
        return path.as_posix() if not path.is_absolute() else path.name


def write_csv_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def sanitize_profile_summary(raw_summary: dict[str, Any], output_dir: Path) -> dict[str, Any]:
    sanitized = dict(raw_summary)
    summary_path = output_dir / "profile_summary.json"
    spectrum_path = output_dir / "generated_spectrum.csv"
    sanitized["summary_path"] = stable_repo_path(summary_path)
    sanitized["spectrum_path"] = stable_repo_path(spectrum_path)
    return sanitized


def metric_block(wavelength_nm: np.ndarray, current: np.ndarray, vendor: np.ndarray) -> dict[str, float]:
    residual = current - vendor
    return {
        "mae": float(np.mean(np.abs(residual))),
        "rmse": float(np.sqrt(np.mean(residual**2))),
        "max_abs": float(np.max(np.abs(residual))),
        "max_abs_wavelength_nm": float(wavelength_nm[np.argmax(np.abs(residual))]),
        "correlation": float(np.corrcoef(current, vendor)[0, 1]),
        "mean_signed": float(np.mean(residual)),
    }


def write_comparison_metrics(
    output_path: Path,
    wavelength_nm: np.ndarray,
    current: dict[str, np.ndarray],
    vendor: dict[str, np.ndarray],
    vendor_reference_path: Path,
    generated_spectrum_path: Path,
    profile_summary_path: Path,
) -> None:
    metrics = {
        "sample_count": int(len(wavelength_nm)),
        "wavelength_min_nm": float(wavelength_nm.min()),
        "wavelength_max_nm": float(wavelength_nm.max()),
        "vendor_reference_path": stable_repo_path(vendor_reference_path),
        "generated_spectrum_path": stable_repo_path(generated_spectrum_path),
        "profile_summary_path": stable_repo_path(profile_summary_path),
        "reflectance": metric_block(wavelength_nm, current["reflectance"], vendor["reflectance"]),
        "radiance": metric_block(wavelength_nm, current["radiance"], vendor["radiance"]),
        "irradiance": metric_block(wavelength_nm, current["irradiance"], vendor["irradiance"]),
    }
    output_path.write_text(json.dumps(metrics, indent=2) + "\n")


def write_manifest(
    output_path: Path,
    canonical_command: str,
    vendor_reference_path: Path,
    output_dir: Path,
) -> None:
    tracked_outputs = [
        "bundle_manifest.json",
        "comparison_metrics.json",
        "current_vs_vendor_overlay.png",
        "current_vs_vendor_residuals.png",
        "generated_spectrum.csv",
        "profile_summary.json",
    ]
    manifest = {
        "schema_version": 1,
        "canonical_command": canonical_command,
        "tracked_output_dir": stable_repo_path(output_dir),
        "vendor_reference_path": stable_repo_path(vendor_reference_path),
        "tracked_outputs": [f"{stable_repo_path(output_dir)}/{name}" for name in tracked_outputs],
        "policy": {
            "default_vendor_refresh": "use_committed_vendor_reference",
            "note": "The default O2A plot refresh uses the committed vendor reference and does not rerun vendored DISAMAR.",
        },
    }
    output_path.write_text(json.dumps(manifest, indent=2) + "\n")


def create_plots(
    output_dir: Path,
    wavelength_nm: np.ndarray,
    current: dict[str, np.ndarray],
    vendor: dict[str, np.ndarray],
) -> None:
    reflectance_residual = current["reflectance"] - vendor["reflectance"]
    radiance_residual = current["radiance"] - vendor["radiance"]
    irradiance_residual = current["irradiance"] - vendor["irradiance"]
    reflectance_ratio = np.divide(
        current["reflectance"],
        vendor["reflectance"],
        out=np.full_like(current["reflectance"], np.nan),
        where=np.abs(vendor["reflectance"]) > 1.0e-30,
    )

    overlay_path = output_dir / "current_vs_vendor_overlay.png"
    fig, axes = plt.subplots(3, 1, figsize=(12, 12), sharex=True, constrained_layout=True)

    axes[0].plot(wavelength_nm, vendor["reflectance"], label="Vendored DISAMAR reference", linewidth=1.8)
    axes[0].plot(wavelength_nm, current["reflectance"], label="Current zdisamar", linewidth=1.4)
    axes[0].set_ylabel("Reflectance")
    axes[0].set_title("O2A reflectance: current zdisamar vs vendored DISAMAR reference")
    axes[0].grid(True, alpha=0.25)
    axes[0].legend(loc="best")

    axes[1].plot(wavelength_nm, vendor["radiance"], label="Vendored DISAMAR reference", linewidth=1.8)
    axes[1].plot(wavelength_nm, current["radiance"], label="Current zdisamar", linewidth=1.4)
    axes[1].set_ylabel("Radiance")
    axes[1].grid(True, alpha=0.25)
    axes[1].legend(loc="best")

    axes[2].plot(wavelength_nm, vendor["irradiance"], label="Vendored DISAMAR reference", linewidth=1.8)
    axes[2].plot(wavelength_nm, current["irradiance"], label="Current zdisamar", linewidth=1.4)
    axes[2].set_ylabel("Irradiance")
    axes[2].set_xlabel("Wavelength (nm)")
    axes[2].grid(True, alpha=0.25)
    axes[2].legend(loc="best")

    fig.savefig(overlay_path, dpi=160)
    plt.close(fig)

    residual_path = output_dir / "current_vs_vendor_residuals.png"
    fig, axes = plt.subplots(4, 1, figsize=(12, 13), sharex=True, constrained_layout=True)

    axes[0].plot(wavelength_nm, reflectance_residual, color="tab:red", linewidth=1.3)
    axes[0].axhline(0.0, color="black", linewidth=0.8, alpha=0.7)
    axes[0].set_ylabel("Reflectance\nresidual")
    axes[0].set_title("O2A residuals: current zdisamar minus vendored DISAMAR reference")
    axes[0].grid(True, alpha=0.25)

    axes[1].plot(wavelength_nm, reflectance_ratio, color="tab:green", linewidth=1.3)
    axes[1].axhline(1.0, color="black", linewidth=0.8, alpha=0.7)
    axes[1].set_ylabel("Reflectance\nratio")
    axes[1].grid(True, alpha=0.25)

    axes[2].plot(wavelength_nm, radiance_residual, color="tab:orange", linewidth=1.3)
    axes[2].axhline(0.0, color="black", linewidth=0.8, alpha=0.7)
    axes[2].set_ylabel("Radiance\nresidual")
    axes[2].grid(True, alpha=0.25)

    axes[3].plot(wavelength_nm, irradiance_residual, color="tab:blue", linewidth=1.3)
    axes[3].axhline(0.0, color="black", linewidth=0.8, alpha=0.7)
    axes[3].set_ylabel("Irradiance\nresidual")
    axes[3].set_xlabel("Wavelength (nm)")
    axes[3].grid(True, alpha=0.25)

    fig.savefig(residual_path, dpi=160)
    plt.close(fig)


def build_bundle(
    current_spectrum_path: Path,
    profile_summary_path: Path,
    vendor_reference_path: Path,
    output_dir: Path,
    canonical_command: str,
) -> None:
    current = load_csv(current_spectrum_path)
    vendor = load_csv(vendor_reference_path)
    wavelength_nm = vendor["wavelength_nm"]
    if len(current["wavelength_nm"]) != len(wavelength_nm) or not np.allclose(
        current["wavelength_nm"], wavelength_nm, rtol=0.0, atol=1.0e-12
    ):
        raise ValueError("Current spectrum grid does not match the tracked vendor reference grid")

    output_dir.mkdir(parents=True, exist_ok=True)

    generated_spectrum_path = output_dir / "generated_spectrum.csv"
    write_csv_copy(current_spectrum_path, generated_spectrum_path)

    raw_summary = json.loads(profile_summary_path.read_text())
    sanitized_summary = sanitize_profile_summary(raw_summary, output_dir)
    tracked_summary_path = output_dir / "profile_summary.json"
    tracked_summary_path.write_text(json.dumps(sanitized_summary, indent=2) + "\n")

    write_comparison_metrics(
        output_dir / "comparison_metrics.json",
        wavelength_nm,
        current,
        vendor,
        vendor_reference_path,
        generated_spectrum_path,
        tracked_summary_path,
    )
    create_plots(output_dir, wavelength_nm, current, vendor)
    write_manifest(output_dir / "bundle_manifest.json", canonical_command, vendor_reference_path, output_dir)


def main() -> None:
    args = parse_args()
    build_bundle(
        Path(args.current_spectrum),
        Path(args.profile_summary),
        Path(args.vendor_reference),
        Path(args.output_dir),
        args.canonical_command,
    )


if __name__ == "__main__":
    main()
