#!/usr/bin/env -S uv run

from __future__ import annotations

from pathlib import Path
import sys

import numpy as np
import pandas as pd


REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUT_DIR = REPO_ROOT / "out" / "plots" / "python_plotting"


class DemoSpectrum:
    def __init__(self, wavelength_nm, radiance, irradiance, reflectance):
        self.wavelength_nm = wavelength_nm
        self.radiance = radiance
        self.irradiance = irradiance
        self.reflectance = reflectance


def import_plotting():
    sys.path.insert(0, str(PYTHON_ROOT))
    import zdisamar.plot as zp

    return zp


def demo_spectrum() -> DemoSpectrum:
    wavelength_nm = np.linspace(755.0, 776.0, 241)
    trough = np.exp(-0.5 * ((wavelength_nm - 760.76) / 1.35) ** 2)
    fine_structure = 0.015 * np.sin((wavelength_nm - 755.0) * 4.8)
    reflectance = 0.82 - 0.45 * trough + fine_structure
    irradiance = 1.0 + 0.025 * np.cos((wavelength_nm - 755.0) * 0.7)
    radiance = reflectance * irradiance * 0.15
    return DemoSpectrum(wavelength_nm, radiance, irradiance, reflectance)


def load_csv_frame(path: Path) -> pd.DataFrame:
    return pd.read_csv(path)


def spectrum_input():
    generated = REPO_ROOT / "validation" / "generated_spectrum.csv"
    if generated.exists():
        return load_csv_frame(generated)
    return demo_spectrum()


def reference_input(spectrum) -> pd.DataFrame:
    reference = REPO_ROOT / "validation" / "o2a_with_cia_disamar_reference.csv"
    if reference.exists():
        return load_csv_frame(reference)
    if isinstance(spectrum, DemoSpectrum):
        return reference_frame(spectrum)
    raise FileNotFoundError(reference)


def reference_frame(spectrum: DemoSpectrum) -> pd.DataFrame:
    wavelength_nm = spectrum.wavelength_nm
    return pd.DataFrame(
        {
            "wavelength_nm": wavelength_nm,
            "reflectance": spectrum.reflectance * (1.0 + 0.002 * np.sin(wavelength_nm)),
            "radiance": spectrum.radiance * (1.0 - 0.0015 * np.cos(wavelength_nm * 0.5)),
            "irradiance": spectrum.irradiance * (1.0 + 0.001 * np.sin(wavelength_nm * 0.25)),
        }
    )


def save_inspection_png(zp, chart, stem: str, outputs: list[str]) -> None:
    png = OUT_DIR / f"{stem}.png"
    zp.save(chart, png, scale=1.3853)
    outputs.append(str(png))


def with_context(zp, chart, spectrum: DemoSpectrum, markers_nm):
    return zp.spectrum.with_full_sample_spectrum(chart, spectrum, markers_nm=markers_nm)


def main() -> int:
    zp = import_plotting()
    zp.use_theme("validation")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for existing in OUT_DIR.iterdir():
        if existing.is_file():
            existing.unlink()

    spectrum = spectrum_input()
    reference = reference_input(spectrum)
    markers_nm = [755.0, 760.76, 776.0]
    residual_threshold = 5.0e-14

    charts = {
        "reflectance_spectrum": zp.spectrum.reflectance(spectrum, markers_nm=markers_nm),
        "radiance_spectrum": zp.spectrum.radiance(spectrum, markers_nm=markers_nm),
        "irradiance_spectrum": zp.spectrum.irradiance(spectrum, markers_nm=markers_nm),
        "spectrum_triplet": zp.spectrum.triplet(spectrum, markers_nm=markers_nm),
        "model_reference_overlay": zp.validation.overlay(spectrum, reference, quantity=zp.fields.REFLECTANCE),
        "radiance_against_reference": zp.validation.overlay(spectrum, reference, quantity=zp.fields.RADIANCE),
        "spectral_residual": with_context(
            zp,
            zp.validation.residual(
                spectrum,
                reference,
                quantity=zp.fields.REFLECTANCE,
                tolerance=residual_threshold,
            ),
            spectrum,
            markers_nm,
        ),
        "reflectance_residual_report": zp.validation.residual_histogram_report(
            spectrum,
            reference,
            quantity=zp.fields.REFLECTANCE,
            residual_threshold=residual_threshold,
        ),
        "validation_metrics_bar": with_context(zp, zp.validation.metrics_bar(spectrum, reference), spectrum, markers_nm),
        "o2a_forward_summary": zp.bundles.o2a_forward_summary(spectrum, markers_nm=markers_nm),
        "validation_against_reference": zp.bundles.validation_against_reference(spectrum, reference),
    }
    inspection_stems = {
        "reflectance_residual_report",
        "radiance_against_reference",
        "validation_metrics_bar",
    }

    outputs: list[str] = []
    for stem, chart in charts.items():
        chart.to_dict()
        if stem in inspection_stems:
            save_inspection_png(zp, chart, stem, outputs)

    print(f"wrote {len(outputs)} inspection plot files under {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
