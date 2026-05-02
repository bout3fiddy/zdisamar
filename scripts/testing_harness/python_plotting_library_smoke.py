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


class DemoContext:
    def __init__(self, value):
        self.value = value

    def __enter__(self):
        return self.value

    def __exit__(self, *_exc):
        return None


class DemoSummary:
    def __init__(self, label, max_abs, max_wavelength, mean_abs):
        self.label = label
        self.parameter_path = label
        self.max_abs_delta_reflectance = max_abs
        self.max_abs_delta_wavelength_nm = max_wavelength
        self.mean_abs_delta_reflectance = mean_abs


class DemoPerturbation:
    def __init__(self, table, summary):
        self.table = table
        self.summary = summary


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


def demo_budget() -> pd.DataFrame:
    rows = []
    wavelengths = np.array([755.0, 760.76, 776.0])
    altitudes = np.linspace(0.5, 14.0, 10)
    for wavelength in wavelengths:
        for layer_index, altitude in enumerate(altitudes):
            pressure = 1013.25 * np.exp(-altitude / 7.2)
            gas_abs = 0.02 * np.exp(-altitude / 8.0) * (1.0 + 0.25 * np.cos(wavelength))
            gas_scat = 0.004 * np.exp(-altitude / 12.0)
            cia_tau = 0.003 * np.exp(-altitude / 5.5) * (1.0 + 0.2 * np.sin(wavelength))
            aerosol_tau = 0.002 * np.exp(-((altitude - 3.0) ** 2) / 8.0)
            cloud_tau = 0.001 * np.exp(-((altitude - 7.0) ** 2) / 4.0)
            total_abs = gas_abs + cia_tau + 0.35 * aerosol_tau + 0.25 * cloud_tau
            total_scat = gas_scat + 0.65 * aerosol_tau + 0.75 * cloud_tau
            total = total_abs + total_scat
            rows.append(
                {
                    "wavelength_nm": wavelength,
                    "layer_index": layer_index,
                    "sublayer_index": 0,
                    "global_sublayer_index": layer_index,
                    "interval_index_1based": layer_index + 1,
                    "altitude_km": altitude,
                    "pressure_hpa": pressure,
                    "temperature_k": 288.0 - 6.0 * altitude,
                    "oxygen_number_density_cm3": 5.0e18 * np.exp(-altitude / 7.2),
                    "path_length_cm": 1.0e5,
                    "gas_absorption_optical_depth": gas_abs,
                    "gas_scattering_optical_depth": gas_scat,
                    "cia_optical_depth": cia_tau,
                    "aerosol_optical_depth": aerosol_tau,
                    "aerosol_scattering_optical_depth": 0.65 * aerosol_tau,
                    "aerosol_absorption_optical_depth": 0.35 * aerosol_tau,
                    "cloud_optical_depth": cloud_tau,
                    "cloud_scattering_optical_depth": 0.75 * cloud_tau,
                    "cloud_absorption_optical_depth": 0.25 * cloud_tau,
                    "total_absorption_optical_depth": total_abs,
                    "total_scattering_optical_depth": total_scat,
                    "total_optical_depth": total,
                    "single_scatter_albedo": total_scat / total,
                }
            )
    return pd.DataFrame.from_records(rows)


def demo_cia(budget: pd.DataFrame) -> pd.DataFrame:
    cia = budget.copy()
    pair_path = np.square(cia["oxygen_number_density_cm3"]) * cia["path_length_cm"]
    cia["cia_cross_section_cm5_per_molecule2"] = cia["cia_optical_depth"] / pair_path
    cia["cia_share_of_total_absorption"] = cia["cia_optical_depth"] / cia["total_absorption_optical_depth"]
    cia["cia_share_of_total_optical_depth"] = cia["cia_optical_depth"] / cia["total_optical_depth"]
    return cia


def demo_lines() -> pd.DataFrame:
    rows = []
    for sample in [760.76, 761.2]:
        centers = sample + np.linspace(-0.35, 0.35, 24)
        for line_index, center in enumerate(centers):
            for altitude in [0.5, 5.0, 10.0]:
                strength = 1.0e-24 * (1 + line_index % 6) * np.exp(-altitude / 18.0)
                rows.append(
                    {
                        "wavelength_nm": sample,
                        "profile_node_index": int(altitude * 10),
                        "altitude_km": altitude,
                        "pressure_hpa": 1013.25 * np.exp(-altitude / 7.2),
                        "temperature_k": 288.0 - 6.0 * altitude,
                        "row_kind": line_index % 2,
                        "row_kind_label": "strong_line" if line_index % 2 else "weak_line",
                        "status": line_index % 4,
                        "status_label": ["weak_included", "weak_excluded_by_strong_line", "strong_sidecar", "weak_zero_after_cutoff"][line_index % 4],
                        "line_index": line_index,
                        "isotope_number": 1 + (line_index % 3),
                        "isotopologue_code": 66 + (line_index % 3),
                        "center_wavelength_nm": center,
                        "center_wavenumber_cm1": 1.0e7 / center,
                        "line_strength_cm2_per_molecule": strength,
                        "weak_line_sigma_cm2_per_molecule": strength * (0.4 if line_index % 2 == 0 else 0.05),
                        "strong_line_sigma_cm2_per_molecule": strength * (0.6 if line_index % 2 else 0.05),
                        "line_mixing_sigma_cm2_per_molecule": strength * 0.08,
                        "total_sigma_cm2_per_molecule": strength,
                        "abs_total_sigma_cm2_per_molecule": abs(strength),
                    }
                )
    return pd.DataFrame.from_records(rows)


def demo_response() -> pd.DataFrame:
    rows = []
    offsets = np.linspace(-0.12, 0.12, 17)
    weights = np.exp(-0.5 * (offsets / 0.045) ** 2)
    weights /= weights.sum()
    for nominal_index, nominal in enumerate([755.0, 760.76, 776.0]):
        for channel, channel_label in [(0, "radiance"), (1, "irradiance")]:
            for sample_index, (offset, weight) in enumerate(zip(offsets, weights, strict=True)):
                rows.append(
                    {
                        "nominal_index": nominal_index,
                        "nominal_wavelength_nm": nominal,
                        "channel": channel,
                        "channel_label": channel_label,
                        "sample_index": sample_index,
                        "support_count": offsets.size,
                        "offset_nm": offset,
                        "support_wavelength_nm": nominal + offset,
                        "weight": weight,
                        "raw_response_weight": weight,
                        "support_width_nm": offsets[-1] - offsets[0],
                    }
                )
    return pd.DataFrame.from_records(rows)


def demo_rt(budget: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for wavelength, group in budget.groupby("wavelength_nm"):
        cumulative = 0.0
        for _, row in group.sort_values("altitude_km", ascending=False).iterrows():
            total = row["total_optical_depth"]
            transmission = np.exp(-2.0 * (cumulative + 0.5 * total))
            rows.append(
                {
                    "wavelength_nm": wavelength,
                    "altitude_km": row["altitude_km"],
                    "total_optical_depth": total,
                    "total_absorption_optical_depth": row["total_absorption_optical_depth"],
                    "total_scattering_optical_depth": row["total_scattering_optical_depth"],
                    "single_scatter_albedo": row["single_scatter_albedo"],
                    "cumulative_optical_depth_above": cumulative,
                    "mid_layer_transmission_proxy": transmission,
                    "direct_surface_transmission_proxy": np.exp(-2.0 * (cumulative + total)),
                    "atmospheric_scattering_source_proxy": row["total_scattering_optical_depth"] * transmission,
                    "absorption_loss_proxy": row["total_absorption_optical_depth"] * transmission,
                    "pseudo_spherical_airmass_factor": 2.0,
                }
            )
            cumulative += total
    return pd.DataFrame.from_records(rows)


def demo_perturbations(spectrum) -> list[DemoPerturbation]:
    if isinstance(spectrum, pd.DataFrame):
        frame = spectrum
    else:
        frame = pd.DataFrame(
            {
                "wavelength_nm": spectrum.wavelength_nm,
                "reflectance": spectrum.reflectance,
            }
        )
    results = []
    for label, scale in [("surface albedo +1%", 0.01), ("aerosol optical depth +10%", -0.006)]:
        table = pd.DataFrame(
            {
                "wavelength_nm": frame["wavelength_nm"],
                "baseline_reflectance": frame["reflectance"],
                "perturbed_reflectance": frame["reflectance"] + scale * np.sin(frame["wavelength_nm"] * 3.0),
                "delta_reflectance": scale * np.sin(frame["wavelength_nm"] * 3.0),
                "abs_delta_reflectance": np.abs(scale * np.sin(frame["wavelength_nm"] * 3.0)),
            }
        )
        max_index = table["abs_delta_reflectance"].idxmax()
        summary = DemoSummary(
            label,
            float(table.loc[max_index, "abs_delta_reflectance"]),
            float(table.loc[max_index, "wavelength_nm"]),
            float(table["abs_delta_reflectance"].mean()),
        )
        results.append(DemoPerturbation(table, summary))
    return results


class FakePrepared:
    def __init__(self, spectrum, budget, lines, cia, response, rt, perturbations):
        self._spectrum = spectrum
        self.atmosphere = FakeAtmosphere(budget)
        self.o2_lines = FakeO2Lines(lines)
        self.o2_o2_cia = FakeCIA(cia)
        self.instrument_response = FakeInstrumentResponse(response)
        self.radiative_transfer = FakeRT(rt)
        self.perturbations = FakePerturbations(perturbations)

    def forward_model(self):
        return DemoContext(self._spectrum)


class FakeAtmosphere:
    def __init__(self, budget):
        self._budget = budget

    def budget(self, wavelengths_nm):
        _ = wavelengths_nm
        return DemoContext(self._budget)


class FakeO2Lines:
    def __init__(self, lines):
        self._lines = lines

    def contributions(self, wavelengths_nm, max_rows=50_000):
        _ = wavelengths_nm, max_rows
        return DemoContext(self._lines)


class FakeCIA:
    def __init__(self, cia):
        self._cia = cia

    def diagnostics(self, wavelengths_nm):
        _ = wavelengths_nm
        return self._cia


class FakeInstrumentResponse:
    def __init__(self, response):
        self._response = response

    def sampling_table(self, wavelengths_nm=None, channels=("radiance", "irradiance")):
        data = self._response
        if wavelengths_nm is not None:
            data = data[data["nominal_wavelength_nm"].isin(wavelengths_nm)]
        if channels is not None:
            data = data[data["channel_label"].isin(channels)]
        return data


class FakeRT:
    def __init__(self, rt):
        self._rt = rt

    def diagnostics(self, wavelengths_nm, spectrum=None):
        _ = wavelengths_nm, spectrum
        return self._rt


class FakePerturbations:
    def __init__(self, perturbations):
        self._perturbations = perturbations

    def spectrum_delta(self, parameter_path, value, label=None):
        _ = parameter_path, value, label
        return self._perturbations[0]


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
    spectrum_frame = zp.to_dataframe(spectrum)
    reference = reference_input(spectrum)
    markers_nm = [755.0, 760.76, 776.0]
    residual_threshold = 1.0e-14
    budget = demo_budget()
    cia_table = demo_cia(budget)
    lines = demo_lines()
    response = demo_response()
    rt = demo_rt(budget)
    perturbations = demo_perturbations(spectrum)
    fake_prepared = FakePrepared(spectrum, budget, lines, cia_table, response, rt, perturbations)
    bound = zp.for_prepared(fake_prepared)

    charts = {
        "reflectance_spectrum": zp.spectrum.reflectance(spectrum, markers_nm=markers_nm),
        "radiance_spectrum": zp.spectrum.radiance(spectrum, markers_nm=markers_nm),
        "irradiance_spectrum": zp.spectrum.irradiance(spectrum, markers_nm=markers_nm),
        "spectrum_triplet": zp.spectrum.triplet(spectrum, markers_nm=markers_nm),
        "micro_window_marker_spectrum": zp.spectrum.micro_window_marker_spectrum(spectrum),
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
        "one_to_one_scatter": zp.validation.one_to_one(
            pd.DataFrame(
                {
                    "reference": reference["reflectance"].head(80),
                    "current": spectrum_frame["reflectance"].head(80),
                }
            )
        ),
        "o2_line_window": zp.o2_lines.window(spectrum, lines),
        "o2_line_contribution_stems": zp.o2_lines.contribution_stems(lines),
        "o2_line_partition_bar": zp.o2_lines.partition_bar(lines),
        "o2_line_status_counts": zp.o2_lines.status_counts(lines),
        "o2_isotope_contribution_bar": zp.o2_lines.isotope_bar(lines),
        "o2_cross_section_profile": zp.o2_lines.cross_section_profile(lines),
        "optical_depth_profile": zp.atmosphere.optical_depth_profile(budget, wavelengths_nm=markers_nm),
        "optical_depth_heatmap": zp.atmosphere.optical_depth_heatmap(budget, markers_nm=markers_nm),
        "optical_depth_component_stack": zp.atmosphere.component_stack(budget),
        "single_scatter_albedo_profile": zp.atmosphere.single_scatter_albedo_profile(budget, wavelengths_nm=markers_nm),
        "aerosol_share_spectrum": zp.aerosol.share_spectrum(budget),
        "aerosol_optical_depth_profile": zp.aerosol.optical_depth_profile(budget, wavelengths_nm=markers_nm),
        "cloud_share_spectrum": zp.cloud.share_spectrum(budget),
        "cloud_optical_depth_profile": zp.cloud.optical_depth_profile(budget, wavelengths_nm=markers_nm),
        "cia_share_profile": zp.cia.share_profile(cia_table),
        "cia_share_spectrum": zp.cia.share_spectrum(cia_table),
        "cia_cross_section_temperature": zp.cia.cross_section_temperature(cia_table),
        "instrument_response_kernel": zp.instrument_response.kernel(response, nominal_wavelength_nm=760.76),
        "instrument_response_matrix": zp.instrument_response.matrix(response),
        "instrument_support_width": zp.instrument_response.support_width(response),
        "instrument_weight_rank": zp.instrument_response.weight_rank(response, nominal_wavelength_nm=760.76),
        "rt_source_profile": zp.radiative_transfer.source_profile(rt),
        "rt_cumulative_transmission": zp.radiative_transfer.cumulative_transmission(rt),
        "rt_proxy_share_bar": zp.radiative_transfer.proxy_share_bar(rt),
        "pseudo_spherical_airmass_profile": zp.radiative_transfer.pseudo_spherical_airmass_profile(rt),
        "perturbation_delta_reflectance": zp.perturbation.delta_reflectance(perturbations),
        "perturbation_abs_delta_reflectance": zp.perturbation.abs_delta_reflectance(perturbations),
        "perturbation_delta_heatmap": zp.perturbation.delta_heatmap(perturbations),
        "perturbation_summary_bar": zp.perturbation.summary_bar(perturbations),
        "o2_line_window_bundle": zp.bundles.o2_line_window(spectrum, lines),
        "atmospheric_budget_bundle": zp.bundles.atmospheric_budget(budget),
        "cia_budget_bundle": zp.bundles.cia_budget(cia_table),
        "instrument_response_bundle": zp.bundles.instrument_response(response),
        "radiative_transfer_budget_bundle": zp.bundles.radiative_transfer_budget(rt),
        "perturbation_sensitivity_bundle": zp.bundles.perturbation_sensitivity(perturbations),
        "bound_spectrum_reflectance": bound.spectrum.reflectance(markers_nm=markers_nm, run_forward=True),
        "bound_atmosphere_heatmap": bound.atmosphere.optical_depth_heatmap(wavelengths_nm=markers_nm),
        "bound_o2_line_window": bound.o2_lines.window(wavelengths_nm=(760.76,), run_forward=True),
        "bound_cia_budget": bound.cia.budget(wavelengths_nm=markers_nm),
        "bound_instrument_kernel": bound.instrument_response.kernel(wavelengths_nm=(760.76,)),
        "bound_radiative_transfer_budget": bound.radiative_transfer.budget(wavelengths_nm=markers_nm, run_forward=True),
        "bound_perturbation_delta": bound.perturbation.delta_reflectance("surface.albedo", 0.4),
        "bound_validation_report": bound.validation.reflectance_residual_report(
            reference,
            residual_threshold=1.0e-14,
            run_forward=True,
        ),
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
